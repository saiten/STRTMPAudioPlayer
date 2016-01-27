//
//  STRTMPStreaming.m
//  STRTMPAudioPlayer
//
//  Created by saiten on 2014/01/07.
//  Copyright (c) 2014 saiten. All rights reserved.
//

#import "STRTMPStreaming.h"
#import "librtmp/log.h"

NSString* const STRTMPStreamingErrorDomain = @"STRTMPStreamingErrorDomain";

#define STRTMPStreamingHashSWFCacheDays 30
#define STRTMPStreamingTimeoutSeconds 10

@implementation STRTMPStreaming {
    RTMP _rtmp;
    
    NSThread *_streamingThread;
    
    uint32_t _bufferTime;
    uint32_t _bufferSize;
}

#pragma mark - lifecycle

- (instancetype)initWithDelegate:(id<STRTMPStreamingDelegate>)delegate blockingQueue:(STBlockingQueue *)blockingQueue bufferTime:(uint32_t)bufferTime
{
    self = [super init];
    if(self) {
        _blockingQueue = blockingQueue;
        _delegate = delegate;
        
        _bufferTime = bufferTime;
        _bufferSize = blockingQueue.capacity / 2;
    }
    return self;
}

#pragma mark - public methods

- (void)start
{
    @synchronized(self) {
        if(_state != STRTMPStreamingStateInitialized) {
            return;
        }

        _state = STRTMPStreamingStateStartingThread;
        RTMP_ctrlC = false;
        
        _streamingThread = [[NSThread alloc] initWithTarget:self selector:@selector(_main) object:nil];
        _streamingThread.name = @"co.saiten.RDKRTMPStreaming";
        [_streamingThread start];
    }
}

- (void)stop
{
    @synchronized(self) {
        RTMP_ctrlC = true;
        [_blockingQueue close];
    }
}

#pragma mark - private methods

- (void)_main
{
    @autoreleasepool {
        @synchronized(self) {
            _state = STRTMPStreamingStateConnecting;
        
            if(![self _setupRTMPStream]) {
                goto cleanup;
            }
        }
        
        if(![self _connectRTMPStream]) {
            goto cleanup;
        }
        
        [self _readRTMPStream];
        
cleanup:
        RTMP_Close(&_rtmp);
        [_blockingQueue close];
        
        _state = STRTMPStreamingStateDisconnected;
        
        if([_delegate respondsToSelector:@selector(rtmpStreamingDidDisconnectStream:)]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [_delegate rtmpStreamingDidDisconnectStream:self];
            });
        }
    }
}

- (BOOL)_setupRTMPStream
{
#ifdef DEBUG
    RTMP_LogSetLevel(RTMP_LOGDEBUG);
#else
    RTMP_LogSetLevel(RTMP_LOGERROR);
#endif
    
    AVal aHostName  = { 0, 0 };
    AVal aPlayPath  = { 0, 0 };
    AVal aTcUrl     = { 0, 0 };
    AVal aPageUrl   = { 0, 0 };
    AVal aApp       = { 0, 0 };
    AVal aSwfUrl    = { 0, 0 };
    AVal aFlashVer  = { 0, 0 };
    AVal aSwfHash   = { 0, 0 };
    AVal aSocksHost = { 0, 0 };
    
    int protocol = RTMP_PROTOCOL_RTMP;
    unsigned int port = 1935;
    
    if(!_url) {
        [self _failWithErrorMessage:@"url empty"];
        return NO;
    }
    
    RTMP_Init(&_rtmp);

    STR2AVAL(aHostName, [_url.host cStringUsingEncoding:NSASCIIStringEncoding]);
    STR2AVAL(aTcUrl,    [_url.absoluteString cStringUsingEncoding:NSASCIIStringEncoding]);
    
    NSString *protocolString = _url.scheme;
    if([protocolString isEqual:@"rtmp"]) {
		protocol = RTMP_PROTOCOL_RTMP;
	} else if([protocolString isEqual:@"rtmpe"]) {
		protocol = RTMP_PROTOCOL_RTMPE;
    } else if([protocolString isEqual:@"rtmps"]) {
		protocol = RTMP_PROTOCOL_RTMPS;
    } else if([protocolString isEqual:@"rtmpt"]) {
		protocol = RTMP_PROTOCOL_RTMPT;
    } else if([protocolString isEqual:@"rtmpte"]) {
		protocol = RTMP_PROTOCOL_RTMPTE;
	} else {
		protocol = RTMP_PROTOCOL_UNDEFINED;
    }

    if(_url.port) {
        port = [_url.port intValue];
    }

    if(_app) {
        STR2AVAL(aApp, [_app cStringUsingEncoding:NSASCIIStringEncoding]);
    }
    
    if(_playPath) {
        STR2AVAL(aPlayPath, [_playPath cStringUsingEncoding:NSASCIIStringEncoding]);
    }    
    
    if(_playerURL) {
        STR2AVAL(aSwfUrl, [_playerURL.absoluteString cStringUsingEncoding:NSASCIIStringEncoding]);
    }

    // swf hash setting
    if(!_playerHash && _playerURL) {
        unsigned char *buf[RTMP_SWF_HASHLEN];
        if(RTMP_HashSWF([[_playerURL absoluteString] cStringUsingEncoding:NSASCIIStringEncoding],
                        &_playerSize,
                        (unsigned char*)buf,
                        STRTMPStreamingHashSWFCacheDays) == 0) {
            _playerHash = [NSData dataWithBytes:buf length:RTMP_SWF_HASHLEN];
        }
    }
    
    if(_playerHash) {
        aSwfHash.av_val = (char*)_playerHash.bytes;
        aSwfHash.av_len = RTMP_SWF_HASHLEN;
    }
    
    if(_flashVersion) {
        STR2AVAL(aFlashVer, [_flashVersion cStringUsingEncoding:NSASCIIStringEncoding]);
    }
    
    // rtmp option
    if([self.delegate respondsToSelector:@selector(rtmpStreaming:willStartConnectionForRTMP:)]) {
        [self.delegate rtmpStreaming:self willStartConnectionForRTMP:&_rtmp];
    }
    
    // setup stream    
    RTMP_SetupStream(&_rtmp, protocol, &aHostName, port, &aSocksHost, &aPlayPath,
                     &aTcUrl, &aSwfUrl, &aPageUrl, &aApp, NULL,
                     &aSwfHash, _playerSize, &aFlashVer,
                     NULL, NULL,
                     0, 0,
                     true, STRTMPStreamingTimeoutSeconds);
    return YES;
}

- (BOOL)_connectRTMPStream
{
    if(RTMP_ctrlC) {
        return NO;
    }
    
    RTMP_SetBufferMS(&_rtmp, _bufferTime);
    
    if(!RTMP_Connect(&_rtmp, NULL)) {
        [self _failWithErrorMessage:@"failed connect"];
        return NO;
    }
    
    if(!RTMP_ConnectStream(&_rtmp, 0)) {
        [self _failWithErrorMessage:@"failed connect stream"];
        return NO;
    }
    
    _state = STRTMPStreamingStateConnected;
    
    if([_delegate respondsToSelector:@selector(rtmpStreamingDidConnectStream:)]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate rtmpStreamingDidConnectStream:self];
        });
    }
    
    return YES;
}

- (void)_readRTMPStream
{
    _state = STRTMPStreamingStateStreaming;
    
    char *buffer = (char*)malloc(_bufferSize);
    if(buffer == NULL) {
        [self _failWithErrorMessage:@"failed allocate buffer"];
        return;
    }
    
    //int32_t currentTime, lastUpdate;
    //currentTime = RTMP_GetTime();
    //lastUpdate = currentTime - 1000;

    int retries = 0;
    while(!RTMP_ctrlC && _state == STRTMPStreamingStateStreaming) {
        
        int readSize = 0;
        do {
            readSize = RTMP_Read(&_rtmp, buffer, _bufferSize);
            if(readSize > 0) {
                [_blockingQueue pushWithBytes:(const int8_t*)buffer size:readSize];
            }
        } while(!RTMP_ctrlC && readSize >= 0 && RTMP_IsConnected(&_rtmp) && !RTMP_IsTimedout(&_rtmp));

        if(RTMP_IsTimedout(&_rtmp) || RTMP_IsConnected(&_rtmp)) {
            if(retries++ < 3) {
                if(!RTMP_Connect(&_rtmp, NULL)) {
                    [self _failWithErrorMessage:@"failed reconnect"];
                    break;
                }
                if(!RTMP_ConnectStream(&_rtmp, 0)) {
                    [self _failWithErrorMessage:@"failed reconnect stream"];
                    break;
                }
            }
        }
        // reconnect
        else if(!RTMP_ctrlC) {
            DLog(@"challenge reconnect");
            if(_rtmp.m_pausing == 3) {
                if(!RTMP_ReconnectStream(&_rtmp, 0)) {
                    DLog(@"failed reconnect stream");
                    [self _failWithErrorMessage:@"failed connect stream"];
                    break;
                }
            } else if(!RTMP_ToggleStream(&_rtmp)) {
                DLog(@"failed toggle stream");
                [self _failWithErrorMessage:@"failed toggle stream"];
                break;
            }
        }
    }
    
    free(buffer);
}

- (void)_failWithErrorMessage:(NSString*)errorMessage
{
    _state = STRTMPStreamingStateFailed;
    NSError *error = [NSError errorWithDomain:STRTMPStreamingErrorDomain
                                         code:_state
                                     userInfo:@{ NSLocalizedDescriptionKey: errorMessage }];
    
    if([_delegate respondsToSelector:@selector(rtmpStreaming:didFailWithError:)]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [_delegate rtmpStreaming:self didFailWithError:error];
        });
    }
}

@end
