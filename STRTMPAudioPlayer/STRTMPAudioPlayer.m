//
//  STRTMPAudioPlayer.m
//  STRTMPAudioPlayer
//
//  Created by saiten on 2016/01/20.
//  Copyright © 2016 saiten. All rights reserved.
//

#import "STRTMPAudioPlayer.h"
#import "STRTMPStreaming.h"
#import "STFLVConverter.h"
#import "STAudioStreamPlayer.h"
#import "STAudioTemporaryBuffer.h"

#define kBlockingQueueCapacity   (4096)
#define kRTMPStreamingBufferTime (30000)

@interface STRTMPAudioPlayer () <STRTMPStreamingDelegate, STFLVConverterDelegate, STAudioStreamPlayerDelegate>
@property (nonatomic, strong) STRTMPStreaming *rtmpStreaming;
@property (nonatomic, strong) STFLVConverter *flvConverter;
@property (nonatomic, strong) STAudioStreamPlayer *audioStreamPlayer;
@property (nonatomic, strong) NSMutableArray<STAudioTemporaryBuffer *> *currentAudioSamples;
@end

@implementation STRTMPAudioPlayer

- (instancetype)initWithConnectionParameters:(id<STRTMPConnectionParameter>)connectionParameter
{
    self = [super init];
    if(self) {
        _connectionParameter = connectionParameter;
        _playing = false;
    }
    return self;
}

- (void)setConnectionParameter:(id<STRTMPConnectionParameter>)connectionParameter
{
    @synchronized(self) {
        if(self.playing) {
            [self stop];
        }
        _connectionParameter = connectionParameter;
    }
}

- (void)play
{
    @synchronized(self) {
        if(_playing) {
            return;
        }
        _playing = YES;
        
        [self _setupComponents];
    }
    
    self.rtmpStreaming.url = self.connectionParameter.url;
    self.rtmpStreaming.app = self.connectionParameter.app;
    self.rtmpStreaming.playPath = self.connectionParameter.playPath;
    
    self.rtmpStreaming.playerURL  = self.connectionParameter.playerURL;
    self.rtmpStreaming.playerHash = self.connectionParameter.playerHash;
    self.rtmpStreaming.playerSize = self.connectionParameter.playerSize.unsignedIntValue;
    
    self.rtmpStreaming.flashVersion = self.connectionParameter.flashVersion;

    [self.rtmpStreaming start];
    [self.flvConverter start];
    [self.audioStreamPlayer start];
}

- (void)stop
{
    @synchronized(self) {
        if(!_playing) {
            return;
        }
    }

    [self.audioStreamPlayer stop];
    [self.flvConverter stop];
    [self.rtmpStreaming stop];
}

- (void)_setupComponents
{
    STBlockingQueue *streamingToConverter = [STBlockingQueue blockingQueueWithQueueCapacity:kBlockingQueueCapacity];
    STBlockingQueue *converterToPlayer = [STBlockingQueue blockingQueueWithQueueCapacity:kBlockingQueueCapacity];
    
    self.rtmpStreaming = [[STRTMPStreaming alloc] initWithDelegate:self
                                                     blockingQueue:streamingToConverter
                                                        bufferTime:kRTMPStreamingBufferTime];
    self.flvConverter = [[STFLVConverter alloc] initWithDelegate:self
                                              inputBlockingQueue:streamingToConverter
                                             outputBlockingQueue:converterToPlayer];
    self.audioStreamPlayer = [[STAudioStreamPlayer alloc] initWithDelegate:self
                                                             blockingQueue:converterToPlayer];
}

#pragma mark - STRTMPStreamingDelegate

- (void)rtmpStreaming:(STRTMPStreaming *)rtmpStreaming willStartConnectionForRTMP:(RTMP *)rtmpRef
{
    for(NSString *connectMessage in self.connectionParameter.connectMessages) {
        AVal aOpt = AVC("conn");
        AVal aVal = { 0, 0 };
        STR2AVAL(aVal, [connectMessage cStringUsingEncoding:NSASCIIStringEncoding]);
        RTMP_SetOpt(rtmpRef, &aOpt, &aVal);
    }
}

- (void)rtmpStreamingDidConnectStream:(STRTMPStreaming *)rtmpStreaming
{
}

- (void)rtmpStreamingDidDisconnectStream:(STRTMPStreaming *)rtmpStreaming
{
}

- (void)rtmpStreaming:(STRTMPStreaming *)rtmpStreaming didFailWithError:(NSError *)error
{
}

#pragma mark - STFLVConverterDelegate

- (void)flvConverterDidStartConvert:(STFLVConverter *)flvConverter
{
}

- (void)flvConverterDidFinishConvert:(STFLVConverter *)flvConverter
{
}

- (void)flvConverter:(STFLVConverter *)flvConverter didFailWithError:(NSError *)error
{
}

#pragma mark - STAudioStreamPlayerDelegate

- (void)audioStreamPlayer:(STAudioStreamPlayer *)audioStreamPlayer didChangePlayerState:(STAudioStreamPlayerState)playerState
{
}

- (void)audioStreamPlayer:(STAudioStreamPlayer *)audioStreamPlayer didChangeAudioFileFormat:(AudioStreamBasicDescription *)asbdRef
{
    if(self.currentAudioSamples) {
        [self.currentAudioSamples removeAllObjects];
    } else {
        self.currentAudioSamples = [NSMutableArray array];
    }
    
    Float32 sampleRate = asbdRef->mSampleRate;
    int channelCount = asbdRef->mChannelsPerFrame;
    for(int i= 0; i< channelCount; i++) {
        STAudioTemporaryBuffer *tempBuffer = [STAudioTemporaryBuffer temporaryBufferWithSampleRate:sampleRate];
        [self.currentAudioSamples addObject:tempBuffer];
    }
}

- (void)audioStreamPlayer:(STAudioStreamPlayer *)audioStreamPlayer didFailWithError:(NSError *)error
{
}

- (void)processingTapForAudioStreamPlayer:(STAudioStreamPlayer *)audioStreamPlayer inputNumberFrames:(UInt32)inputNumberFrames ioTimeStamp:(AudioTimeStamp *)ioTimeStamp ioFlags:(UInt32 *)ioFlags outputNumberFrames:(UInt32 *)outputNumberFrames ioData:(AudioBufferList *)ioData
{
    for(int index = 0; index < ioData->mNumberBuffers; index++) {
        AudioBuffer *audioBuffer = &ioData->mBuffers[index];
        [self.currentAudioSamples[index] pushSamples:audioBuffer->mData
                                               count:audioBuffer->mDataByteSize / sizeof(Float32)];
    }
}

@end
