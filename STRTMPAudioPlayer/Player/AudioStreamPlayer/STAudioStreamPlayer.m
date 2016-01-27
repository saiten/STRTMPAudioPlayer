//
//  STAudioStreamPlayer.m
//  STRTMPAudioPlayer
//
//  Created by saiten on 2013/12/12.
//  Copyright (c) 2013 saiten. All rights reserved.
//

#import "STAudioStreamPlayer.h"
#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>
#import <pthread.h>
#import <Accelerate/Accelerate.h>

NSString * const STAudioStreamPlayerErrorDomain = @"STAudioStreamPlayerErrorDomain";

#define RDKAudioStreamPlayerBitRateEstimationMaxPackets     (5000)
#define RDKAudioStreamPlayerBitRateEstimationMinPackets     (50)

@interface STAudioStreamPlayer()
@property (nonatomic, readwrite) STAudioStreamPlayerState playerState;
@end

@implementation STAudioStreamPlayer {
    AudioQueueRef _audioQueue;
    AudioQueueBufferRef _audioQueueBuffers[STAudioStreamPlayerAQNumberOfBuffers];
    AudioStreamPacketDescription _packetDescriptions[STAudioStreamPlayerAQMaxPacketDescriptions];
    
    AudioQueueProcessingTapRef _audioQueueProcessingTap;

    BOOL _usedBuffer[STAudioStreamPlayerAQNumberOfBuffers];
    unsigned int _fillBufferIndex;
    UInt32 _packetBufferSize;
    size_t _bytesFilled;
    size_t _packetsFilled;
    NSInteger _buffersUsed;
    
    UInt64 _processedPacketsCount;
    UInt64 _processedPacketsSizeTotal;

    OSStatus _errorStatus;

    AudioFileStreamID _audioFileStream;
    AudioStreamBasicDescription _audioStreamBasicDescription;

    BOOL _discontinuous;

    STAudioStreamPlayerState _lastPlayerState;

    NSThread *_playerThread;
    pthread_mutex_t _queueBuffersMutex;
    pthread_cond_t _queueBufferReadyCondition;
}

static void RDKAudioStreamPlayerPropertyListenerProc(void *inClientData,
                                                     AudioFileStreamID inAudioFileStream,
                                                     AudioFileStreamPropertyID inPropertyID,
                                                     UInt32 *ioFlags)
{
    STAudioStreamPlayer *audioStreamPlayer = (__bridge STAudioStreamPlayer*)inClientData;
    [audioStreamPlayer _handlePropertyChangeForAudioFileStream:inAudioFileStream
                                     audioFileStreamPropertyID:inPropertyID
                                                       ioFlags:ioFlags];
}

static void RDKAudioStreamPlayerPacketsProc(void *inClientData,
                                            UInt32 inNumberBytes,
                                            UInt32 inNumberPackets,
                                            const void *inInputData,
                                            AudioStreamPacketDescription *inPacketDescriptions)
{
    STAudioStreamPlayer *audioStreamPlayer = (__bridge STAudioStreamPlayer*)inClientData;
    [audioStreamPlayer _handleAudioPackets:inInputData
                               numberBytes:inNumberBytes
                             numberPackets:inNumberPackets
                        packetDescriptions:inPacketDescriptions];
}

static void RDKAudioStreamPlayerAudioQueueOutputCallback(void *inClientData,
                                                         AudioQueueRef inAQ,
                                                         AudioQueueBufferRef inBuffer)
{
    STAudioStreamPlayer *audioStreamPlayer = (__bridge STAudioStreamPlayer*)inClientData;
    [audioStreamPlayer _handleBufferCompleteForAudioQueue:inAQ buffer:inBuffer];
}

static void RDKAudioStreamPlayerAudioQueueIsRunningCallback(void *inClientData, AudioQueueRef inAQ, AudioQueuePropertyID inID)
{
    STAudioStreamPlayer *audioStreamPlayer = (__bridge STAudioStreamPlayer*)inClientData;
    [audioStreamPlayer _handlePropertyChangeForAudioQueue:inAQ propertyID:inID];
}

static void RDKAudioStreamPlayerAudioQueueProcessingTapCallback(void *inClientData,
                                                                AudioQueueProcessingTapRef inAudioQueueTap,
                                                                UInt32 inNumberFrames,
                                                                AudioTimeStamp *ioTimeStamp,
                                                                UInt32 *ioFlags,
                                                                UInt32 *outNumberFrames,
                                                                AudioBufferList *ioData)
{
    STAudioStreamPlayer *audioStreamPlayer = (__bridge STAudioStreamPlayer*)inClientData;
    [audioStreamPlayer _handleProcessingTap:inAudioQueueTap
                          inputNumberFrames:inNumberFrames
                                ioTimeStamp:ioTimeStamp
                                    ioFlags:ioFlags
                         outputNumberFrames:outNumberFrames
                                     ioData:ioData];
}

#pragma mark - lifecycle

- (id)initWithDelegate:(id<STAudioStreamPlayerDelegate>)delegate blockingQueue:(STBlockingQueue *)queue
{
    self = [super init];
    if(self) {
        _playerState = STAudioStreamPlayerStateInitialized;
        _delegate = delegate;
        _blockingQueue = queue;
        
        NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
        [center addObserver:self selector:@selector(audioSessionDidInterrupt:) name:AVAudioSessionInterruptionNotification object:nil];
        [center addObserver:self selector:@selector(audioSessionRouteDidChange:) name:AVAudioSessionRouteChangeNotification object:nil];
    }
    
    return self;
}

- (void)dealloc
{
    [self stop];
    
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center removeObserver:self name:AVAudioSessionInterruptionNotification object:nil];
    [center removeObserver:self name:AVAudioSessionRouteChangeNotification object:nil];
}

#pragma mark - public methods

- (void)start
{
    @synchronized(self) {
        if(_playerState == STAudioStreamPlayerStateInitialized) {
            self.playerState = STAudioStreamPlayerStateStartingThread;
            
            _playerThread = [[NSThread alloc] initWithTarget:self selector:@selector(_main) object:nil];
            _playerThread.name = @"co.saiten.RDKAudioStreamPlayer";
            [_playerThread start];
        }
    }
}

- (void)pause
{
    @synchronized(self) {
        if(_playerState == STAudioStreamPlayerStatePlaying || _playerState == STAudioStreamPlayerStateStopping) {
            _errorStatus = AudioQueuePause(_audioQueue);
            if(_errorStatus) {
                [self _failWithErrorMessage:@"failed AudioQueuePause"];
                return;
            }
            _lastPlayerState = _playerState;
            self.playerState = STAudioStreamPlayerStatePaused;
        }
        else if(_playerState == STAudioStreamPlayerStatePaused) {
            _errorStatus = AudioQueueStart(_audioQueue, NULL);
            if(_errorStatus) {
                [self _failWithErrorMessage:@"failed AudioQueueStart"];
                return;
            }
            self.playerState = _lastPlayerState;
        }
    }
}

- (void)stop
{
    @synchronized(self) {
        if(_audioQueue &&
           (_playerState == STAudioStreamPlayerStatePlaying || _playerState == STAudioStreamPlayerStatePaused ||
            _playerState == STAudioStreamPlayerStateBuffering || _playerState == STAudioStreamPlayerStateWaitingForQueueToStart))
        {
            self.playerState = STAudioStreamPlayerStateStopping;
            _stopReason = STAudioStreamPlayerStopReasonUserAction;
            _errorStatus = AudioQueueStop(_audioQueue, true);
            if(_errorStatus) {
                [self _failWithErrorMessage:@"failed AudioQueueStop"];
                return;
            }
        }
        else if(_playerState != STAudioStreamPlayerStateInitialized) {
            self.playerState = STAudioStreamPlayerStateStopped;
            _stopReason = STAudioStreamPlayerStopReasonUserAction;
        }
    }
    
    while(_playerState != STAudioStreamPlayerStateInitialized) {
        [NSThread sleepForTimeInterval:0.1];
    }
}

#pragma mark - property

- (void)setPlayerState:(STAudioStreamPlayerState)playerState
{
    if(_playerState == playerState) {
        return;
    }
    
    _playerState = playerState;
    
    if(self.delegate && [self.delegate respondsToSelector:@selector(audioStreamPlayer:didChangePlayerState:)]) {
        [self.delegate audioStreamPlayer:self didChangePlayerState:playerState];
    }
}

#pragma mark - private methods

- (void)_main
{
    @autoreleasepool {
        @synchronized(self) {
            if(!_blockingQueue) {
                return;
            }
            
            NSError *error = nil;
            AVAudioSession *audioSession = [AVAudioSession sharedInstance];
            [audioSession setCategory:AVAudioSessionCategoryPlayback error:&error];
            if(error) {
                return;
            }
            [audioSession setActive:YES error:&error];
            if(error) {
                return;
            }
            
            pthread_mutex_init(&_queueBuffersMutex, NULL);
            pthread_cond_init(&_queueBufferReadyCondition, NULL);
            
            _errorStatus = AudioFileStreamOpen((__bridge void*)self,
                                               RDKAudioStreamPlayerPropertyListenerProc,
                                               RDKAudioStreamPlayerPacketsProc,
                                               0, &_audioFileStream);
            if(_errorStatus) {
                [self _failWithErrorMessage:@"fauled AudioFileStreamOpen"];
                goto cleanup;
            }
        }
        
        self.playerState = STAudioStreamPlayerStateWaitingForData;
        
        [self _readBlockingQueue];
        
    cleanup:
        @synchronized(self) {
            if(_audioFileStream) {
                _errorStatus = AudioFileStreamClose(_audioFileStream);
                _audioFileStream = nil;
                if(_errorStatus) {
                    [self _failWithErrorMessage:@"failed AudioFileStreamClose"];
                }
            }
            
            if(_audioQueue) {
                _errorStatus = AudioQueueDispose(_audioQueue, true);
                _audioQueue = nil;
                if(_errorStatus) {
                    [self _failWithErrorMessage:@"failed AudioQueueDipose"];
                }
            }
            
            pthread_mutex_destroy(&_queueBuffersMutex);
            pthread_cond_destroy(&_queueBufferReadyCondition);
            
            [[AVAudioSession sharedInstance] setActive:NO error:nil];
            
            self.playerState = STAudioStreamPlayerStateInitialized;
            _playerThread = nil;
        }
    }
}

- (void)_readBlockingQueue
{
    int32_t bufferSize = MIN(_blockingQueue.capacity/4, 1024);
    int8_t buffer[bufferSize];
    
    int32_t readBytes;
    BOOL discontinuity;
    while(![self _isFinishing] && (readBytes = [_blockingQueue popWithBytes:buffer size:bufferSize discontinuity:&discontinuity]) > 0) {
        @autoreleasepool {
            _errorStatus = AudioFileStreamParseBytes(_audioFileStream,
                                                     readBytes,
                                                     buffer,
                                                     _discontinuous ? kAudioFileStreamParseFlag_Discontinuity : 0);
            if(_errorStatus) {
                [self _failWithErrorMessage:@"failed AudioFileStreamParseBytes"];
                break;
            }

            // next discontinuity stream
            _discontinuous = discontinuity;
        }
    }
    
    if(_bytesFilled) {
        if(_playerState == STAudioStreamPlayerStateWaitingForData) {
            self.playerState = STAudioStreamPlayerStateFlushingEOS;
        }
        [self _enqueueBuffer];
    }
    
    @synchronized(self) {
        if(_playerState == STAudioStreamPlayerStateWaitingForData) {
            [self _failWithErrorMessage:@"data not found"];
        }
        else if(![self _isFinishing]) {
            if(_audioQueue) {
                _errorStatus = AudioQueueFlush(_audioQueue);
                if(_errorStatus) {
                    [self _failWithErrorMessage:@"failed AudioQueueFlush"];
                    return;
                }
                
                self.playerState = STAudioStreamPlayerStateStopping;
                _stopReason = STAudioStreamPlayerStopReasonEndOfStream;
                
                _errorStatus = AudioQueueStop(_audioQueue, false);
                if(_errorStatus) {
                    [self _failWithErrorMessage:@"failed AudioQueueStop"];
                    return;
                }
            } else {
                self.playerState = STAudioStreamPlayerStateStopped;
                _stopReason = STAudioStreamPlayerStopReasonEndOfStream;
            }
        }
    }
}

- (void)_enqueueBuffer
{
    @synchronized(self) {
        if([self _isFinishing]) {
            return;
        }
        _usedBuffer[_fillBufferIndex] = YES;
        _buffersUsed++;
        
        AudioQueueBufferRef fillBuffer = _audioQueueBuffers[_fillBufferIndex];
        fillBuffer->mAudioDataByteSize = _bytesFilled;
        
        if(_packetsFilled) {
            _errorStatus = AudioQueueEnqueueBuffer(_audioQueue, fillBuffer, _packetsFilled, _packetDescriptions);
        } else {
            _errorStatus = AudioQueueEnqueueBuffer(_audioQueue, fillBuffer, 0, NULL);
        }
        
        if(_errorStatus) {
            [self _failWithErrorMessage:@"failed AudioQueueEnqueueBuffer"];
            return;
        }
        
        if(_playerState == STAudioStreamPlayerStateBuffering ||
           _playerState == STAudioStreamPlayerStateWaitingForData ||
           _playerState == STAudioStreamPlayerStateFlushingEOS ||
           (_playerState == STAudioStreamPlayerStateStopped && _stopReason == STAudioStreamPlayerStopReasonTemporarily))
        {
            if(_playerState == STAudioStreamPlayerStateFlushingEOS ||
               _buffersUsed == STAudioStreamPlayerAQNumberOfBuffers - 1) {
                
                if(_playerState == STAudioStreamPlayerStateBuffering) {
                    _errorStatus = AudioQueueStart(_audioQueue, NULL);
                    if(_errorStatus) {
                        [self _failWithErrorMessage:@"failed AudioQueueStart"];
                        return;
                    }
                    self.playerState = STAudioStreamPlayerStatePlaying;
                } else {
                    self.playerState = STAudioStreamPlayerStateWaitingForQueueToStart;
                    
                    _errorStatus = AudioQueueStart(_audioQueue, NULL);
                    if(_errorStatus) {
                        [self _failWithErrorMessage:@"failed AudioQueueStart"];
                        return;
                    }
                }
            }
        }
        
        if(++_fillBufferIndex >= STAudioStreamPlayerAQNumberOfBuffers) {
            _fillBufferIndex = 0;
        }
        _bytesFilled = 0;
        _packetsFilled = 0;
    }
    
    pthread_mutex_lock(&_queueBuffersMutex);
    while(_usedBuffer[_fillBufferIndex]) {
        pthread_cond_wait(&_queueBufferReadyCondition, &_queueBuffersMutex);
    }
    pthread_mutex_unlock(&_queueBuffersMutex);
}

- (void)_createAudioQueue
{
    _errorStatus = AudioQueueNewOutput(&_audioStreamBasicDescription,
                                       RDKAudioStreamPlayerAudioQueueOutputCallback,
                                       (__bridge void*)self, NULL, NULL, 0, &_audioQueue);
    if(_errorStatus) {
        [self _failWithErrorMessage:@"failed AudioQueueNewOutput"];
        return;
    }
    
    _errorStatus = AudioQueueAddPropertyListener(_audioQueue, kAudioQueueProperty_IsRunning,
                                                 RDKAudioStreamPlayerAudioQueueIsRunningCallback, (__bridge void*)self);
    if(_errorStatus) {
        [self _failWithErrorMessage:@"failed AudioQueueAddPropertyListener"];
        return;
    }
    
    UInt32 sizeOfUInt32 = sizeof(UInt32);
    _errorStatus = AudioFileStreamGetProperty(_audioFileStream, kAudioFileStreamProperty_PacketSizeUpperBound, &sizeOfUInt32, &_packetBufferSize);
    if(_errorStatus || _packetBufferSize == 0) {
        _errorStatus = AudioFileStreamGetProperty(_audioFileStream, kAudioFileStreamProperty_MaximumPacketSize, &sizeOfUInt32, &_packetBufferSize);
        if(_errorStatus || _packetBufferSize == 0) {
            _packetBufferSize = STAudioStreamPlayerAQDefaultBufferSize;
        }
    }
    
    for(unsigned int i = 0; i < STAudioStreamPlayerAQNumberOfBuffers; i++) {
        _errorStatus = AudioQueueAllocateBuffer(_audioQueue, _packetBufferSize, &_audioQueueBuffers[i]);
        if(_errorStatus) {
            [self _failWithErrorMessage:@"failed AudioQueueAllocateBuffer"];
            return;
        }
    }
    
    UInt32 cookieSize;
    Boolean writable;
    OSStatus ignorableErrorStatus;
    ignorableErrorStatus = AudioFileStreamGetPropertyInfo(_audioFileStream, kAudioFileStreamProperty_MagicCookieData, &cookieSize, &writable);
    if(ignorableErrorStatus) {
        return;
    }
    
    void *cookieData = calloc(1, cookieSize);
    ignorableErrorStatus = AudioFileStreamGetProperty(_audioFileStream, kAudioFileStreamProperty_MagicCookieData, &cookieSize, cookieData);
    if(ignorableErrorStatus) {
        return;
    }
    
    ignorableErrorStatus = AudioQueueSetProperty(_audioQueue, kAudioQueueProperty_MagicCookie, cookieData, cookieSize);
    free(cookieData);
    if(ignorableErrorStatus) {
        return;
    }
    
    UInt32 processingMaxFrames;
    AudioStreamBasicDescription processingFormat;
    ignorableErrorStatus = AudioQueueProcessingTapNew(_audioQueue,
                                                      RDKAudioStreamPlayerAudioQueueProcessingTapCallback,
                                                      (__bridge void*)self,
                                                      kAudioQueueProcessingTap_PostEffects,
                                                      &processingMaxFrames,
                                                      &processingFormat,
                                                      &_audioQueueProcessingTap);
    if(ignorableErrorStatus) {
        return;
    }
}

- (BOOL)_isFinishing
{
    return NO;
}

- (void)_failWithErrorMessage:(NSString*)errorMessage
{
    NSError *error = nil;
    if(_errorStatus) {
        char *errChars = (char *)&_errorStatus;
        NSString *description = [NSString stringWithFormat:@"%@ [code: %c%c%c%c %d]",
                                 errorMessage, errChars[3], errChars[2], errChars[1], errChars[0], (int)_errorStatus];
        
        error = [NSError errorWithDomain:STAudioStreamPlayerErrorDomain
                                    code:_errorStatus
                                userInfo:@{NSLocalizedDescriptionKey: description}];
        
        DLog(@"%@\n", description);
    } else {
        error = [NSError errorWithDomain:STAudioStreamPlayerErrorDomain
                                    code:0
                                userInfo:@{NSLocalizedDescriptionKey: errorMessage}];

        DLog(@"%@\n", errorMessage);
    }
    
    if(self.delegate && [self.delegate respondsToSelector:@selector(audioStreamPlayer:didFailWithError:)]) {
        [self.delegate audioStreamPlayer:self didFailWithError:error];
    }
}

#pragma mark - AudioFileStream Handler

- (void)_handlePropertyChangeForAudioFileStream:(AudioFileStreamID)inAudioFileStream
                      audioFileStreamPropertyID:(AudioFileStreamPropertyID)inPropertyID
                                        ioFlags:(UInt32*)ioFlags
{
    @synchronized(self) {
        if([self _isFinishing]) {
            return;
        }
        
        if(inPropertyID == kAudioFileStreamProperty_ReadyToProducePackets) {
            _discontinuous = YES;
        }
        else if(inPropertyID == kAudioFileStreamProperty_DataFormat) {
            if(_audioStreamBasicDescription.mSampleRate == 0) {
                UInt32 asbdSize = sizeof(_audioStreamBasicDescription);
                
                _errorStatus = AudioFileStreamGetProperty(inAudioFileStream, kAudioFileStreamProperty_DataFormat, &asbdSize, &_audioStreamBasicDescription);
                if(_errorStatus) {
                    [self _failWithErrorMessage:@"failed AudioFileStreamGetProperty(DataFormat)"];
                    return;
                }
            }
        }
        else if(inPropertyID == kAudioFileStreamProperty_FormatList) {
            Boolean writable;
            UInt32 formatListSize;
            _errorStatus = AudioFileStreamGetPropertyInfo(inAudioFileStream, kAudioFileStreamProperty_FormatList, &formatListSize, &writable);
            if(_errorStatus) {
                [self _failWithErrorMessage:@"failed AudioFileStreamGetProperty(FormatList)"];
                return;
            }
            
            AudioFormatListItem *formatList = malloc(formatListSize);
            _errorStatus = AudioFileStreamGetProperty(inAudioFileStream, kAudioFileStreamProperty_FormatList, &formatListSize, formatList);
            for(int i = 0; i * sizeof(AudioFormatListItem) < formatListSize; i += sizeof(AudioFormatListItem)) {
                AudioStreamBasicDescription pasbd = formatList[i].mASBD;
                if(pasbd.mFormatID == kAudioFormatMPEG4AAC_HE ||
                   pasbd.mFormatID == kAudioFormatMPEG4AAC_HE_V2) {
#if !TARGET_IPHONE_SIMULATOR
                    _audioStreamBasicDescription = pasbd;
#endif
                    break;
                }
            }
            free(formatList);
        }
        else {
            //			DLog(@"Property is %c%c%c%c",
            //			 	((char *)&inPropertyID)[3],
            //				((char *)&inPropertyID)[2],
            //				((char *)&inPropertyID)[1],
            //				((char *)&inPropertyID)[0]);
        }
    }
    
    if(self.delegate && [self.delegate respondsToSelector:@selector(audioStreamPlayer:didChangeAudioFileFormat:)]) {
        [self.delegate audioStreamPlayer:self didChangeAudioFileFormat:&_audioStreamBasicDescription];
    }
}

- (void)_handleAudioPackets:(const void *)inInputData
                numberBytes:(UInt32)inNumberBytes
              numberPackets:(UInt32)inNumberPackets
         packetDescriptions:(AudioStreamPacketDescription *)inPacketDescriptions
{
    @synchronized(self) {
        if([self _isFinishing]) {
            return;
        }
        
        
        if(_discontinuous) {
            _discontinuous = NO;
        }
        
        if(!_audioQueue) {
            [self _createAudioQueue];
        }
    }
    
    // for VBR
    if(inPacketDescriptions) {
        for(int i = 0; i < inNumberPackets; i++) {
            SInt64 packetOffset = inPacketDescriptions[i].mStartOffset;
            SInt64 packetSize   = inPacketDescriptions[i].mDataByteSize;
            size_t bufSpaceRemaining;
            
            if(_processedPacketsCount < RDKAudioStreamPlayerBitRateEstimationMaxPackets) {
                _processedPacketsSizeTotal += packetSize;
                _processedPacketsCount++;
            }
            
            @synchronized(self) {
                if([self _isFinishing]) {
                    return;
                }
                
                if(packetSize > _packetBufferSize) {
                    [self _failWithErrorMessage:@"packet overflow"];
                    return;
                }
                
                bufSpaceRemaining = _packetBufferSize - _bytesFilled;
            }
            
            if(bufSpaceRemaining < packetSize) {
                [self _enqueueBuffer];
            }
            
            @synchronized(self) {
                if([self _isFinishing]) {
                    return;
                }
                
                if(_bytesFilled + packetSize > _packetBufferSize) {
                    return;
                }
                
                AudioQueueBufferRef fillBuffer = _audioQueueBuffers[_fillBufferIndex];
                memcpy((char*)fillBuffer->mAudioData + _bytesFilled, (const char*)inInputData + packetOffset, packetSize);
                
                _packetDescriptions[_packetsFilled] = inPacketDescriptions[i];
                _packetDescriptions[_packetsFilled].mStartOffset = _bytesFilled;
                _bytesFilled += packetSize;
                _packetsFilled++;
            }
        }
    }
    // for CBR
    else {
        size_t offset = 0;
        while(inNumberBytes) {
            size_t bufSpaceRemaining = STAudioStreamPlayerAQDefaultBufferSize - _bytesFilled;
            if(bufSpaceRemaining < inNumberBytes) {
                [self _enqueueBuffer];
            }
            
            @synchronized(self) {
                if([self _isFinishing]) {
                    return;
                }
                
                bufSpaceRemaining = STAudioStreamPlayerAQDefaultBufferSize - _bytesFilled;
                size_t copySize;
                if(bufSpaceRemaining < inNumberBytes) {
                    copySize = bufSpaceRemaining;
                } else {
                    copySize = inNumberBytes;
                }
                
                if(_bytesFilled > _packetBufferSize) {
                    return;
                }
                
                AudioQueueBufferRef fillBuffer = _audioQueueBuffers[_fillBufferIndex];
                memcpy((char*)fillBuffer->mAudioData + _bytesFilled, (const char*)(inInputData + offset), copySize);
                
                _bytesFilled += copySize;
                _packetsFilled = 0;
                inNumberBytes -= copySize;
                offset += copySize;
            }
        }
    }
}

#pragma mark - AudioQueueOutput Handler

- (void)_handleBufferCompleteForAudioQueue:(AudioQueueRef)inAQ buffer:(AudioQueueBufferRef)inBuffer
{
    unsigned int bufferIndex = -1;
    for(unsigned int i = 0; i < STAudioStreamPlayerAQNumberOfBuffers; i++) {
        if(inBuffer == _audioQueueBuffers[i]) {
            bufferIndex = i;
            break;
        }
    }
    
    if(bufferIndex == -1) {
        [self _failWithErrorMessage:@"unknown buffer"];
        pthread_mutex_lock(&_queueBuffersMutex);
        pthread_cond_signal(&_queueBufferReadyCondition);
        pthread_mutex_unlock(&_queueBuffersMutex);
        return;
    }
    
    pthread_mutex_lock(&_queueBuffersMutex);
    
    _usedBuffer[bufferIndex] = NO;
    _buffersUsed--;
    
    pthread_cond_signal(&_queueBufferReadyCondition);
    pthread_mutex_unlock(&_queueBuffersMutex);
    
    @synchronized(self) {
        if(_buffersUsed == 0 && _playerState == STAudioStreamPlayerStatePlaying) {
            _errorStatus = AudioQueuePause(_audioQueue);
            if(_errorStatus) {
                [self _failWithErrorMessage:@"failed AudioQueuePause"];
                return;
            }
            self.playerState = STAudioStreamPlayerStateBuffering;
        }
    }
}

- (void)_handlePropertyChangeForAudioQueueWithProperyID:(NSNumber*)numID
{
    [self _handlePropertyChangeForAudioQueue:nil propertyID:[numID intValue]];
}

- (void)_handlePropertyChangeForAudioQueue:(AudioQueueRef)inAQ propertyID:(AudioQueuePropertyID)inID
{
    @autoreleasepool {
        if(![[NSThread currentThread] isEqual:_playerThread]) {
            [self performSelector:@selector(_handlePropertyChangeForAudioQueueWithProperyID:)
                         onThread:_playerThread
                       withObject:@(inID)
                    waitUntilDone:NO
                            modes:@[NSDefaultRunLoopMode]];
            return;
        }
        
        @synchronized(self) {
            if(inID == kAudioQueueProperty_IsRunning) {
                if(_playerState == STAudioStreamPlayerStateStopping) {
                    UInt32 isRunning = 0;
                    UInt32 size = sizeof(UInt32);
                    AudioQueueGetProperty(_audioQueue, inID, &isRunning, &size);
                    if(isRunning == 0) {
                        self.playerState = STAudioStreamPlayerStateStopped;
                    }
                }
                else if(_playerState == STAudioStreamPlayerStateWaitingForQueueToStart) {
                    [NSRunLoop currentRunLoop];
                    self.playerState = STAudioStreamPlayerStatePlaying;
                }
                else {
                    DLog(@"AudioQueue changed state in unexpected way.");
                }
            }
        }
    }
}

#pragma mark - AudioQueueProcessingTap Handler

- (void)_handleProcessingTap:(AudioQueueProcessingTapRef)audioQueueProcessingTap
           inputNumberFrames:(UInt32)inputNumberFrames
                 ioTimeStamp:(AudioTimeStamp *)ioTimeStamp
                     ioFlags:(UInt32 *)ioFlags
          outputNumberFrames:(UInt32 *)outputNumberFrames
                      ioData:(AudioBufferList *)ioData
{
    if(self.delegate && [self.delegate respondsToSelector:@selector(processingTapForAudioStreamPlayer:inputNumberFrames:ioTimeStamp:ioFlags:outputNumberFrames:ioData:)]) {
        [self.delegate processingTapForAudioStreamPlayer:self
                                       inputNumberFrames:inputNumberFrames
                                             ioTimeStamp:ioTimeStamp
                                                 ioFlags:ioFlags
                                      outputNumberFrames:outputNumberFrames
                                                  ioData:ioData];
    }
}


#pragma mark - AVAudioSession Notification Handler

- (void)audioSessionDidInterrupt:(NSNotification*)notification
{
    switch([notification.userInfo[AVAudioSessionInterruptionTypeKey] intValue]) {
        case AVAudioSessionInterruptionTypeBegan:
            if(self.playing) {
                [self pause];
                _pausedByInterruption = YES;
            }
            break;
        case AVAudioSessionInterruptionTypeEnded:
        default:
            if(self.paused && self.pausedByInterruption) {
                [self pause];
                _pausedByInterruption = NO;
            }
            break;
    }
}

- (void)audioSessionRouteDidChange:(NSNotification*)notification
{
    
}

@end
