//
//  STAudioStreamPlayer.h
//  STRTMPAudioPlayer
//
//  Created by saiten on 2013/12/12.
//  Copyright (c) 2013 saiten. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <AudioToolbox/AudioToolbox.h>
#import "STBlockingQueue.h"

extern NSString * const STAudioStreamPlayerErrorDomain;

#define STAudioStreamPlayerAQNumberOfBuffers       (16)
#define STAudioStreamPlayerAQDefaultBufferSize     (2048)
#define STAudioStreamPlayerAQMaxPacketDescriptions (512)

typedef NS_ENUM(NSInteger, STAudioStreamPlayerState) {
    STAudioStreamPlayerStateInitialized = 0,
    STAudioStreamPlayerStateStartingThread,
    STAudioStreamPlayerStateWaitingForData,
    STAudioStreamPlayerStatePlaying,
    STAudioStreamPlayerStateBuffering,
    STAudioStreamPlayerStateFlushingEOS,
    STAudioStreamPlayerStateWaitingForQueueToStart,
    STAudioStreamPlayerStateStopping,
    STAudioStreamPlayerStateStopped,
    STAudioStreamPlayerStatePaused,
};

typedef NS_ENUM(NSInteger, STAudioStreamPlayerStopReason) {
    STAudioStreamPlayerStopReasonTemporarily,
    STAudioStreamPlayerStopReasonUserAction,
    STAudioStreamPlayerStopReasonEndOfStream,
    STAudioStreamPlayerStopReasonError
};

@protocol STAudioStreamPlayerDelegate;

@interface STAudioStreamPlayer : NSObject
@property (nonatomic, weak     ) id<STAudioStreamPlayerDelegate> delegate;
@property (nonatomic, readonly ) STBlockingQueue                 *blockingQueue;
@property (nonatomic, readonly ) STAudioStreamPlayerState        playerState;
@property (nonatomic, readonly ) BOOL                             playing;
@property (nonatomic, readonly ) BOOL                             paused;
@property (nonatomic, readonly ) BOOL                             pausedByInterruption;
@property (nonatomic, readonly ) STAudioStreamPlayerStopReason   stopReason;
@property (nonatomic, readwrite) CGFloat                          volume;

- (id)initWithDelegate:(id<STAudioStreamPlayerDelegate>)delegate blockingQueue:(STBlockingQueue*)queue;
- (void)start;
- (void)stop;
- (void)pause;

@end

@protocol STAudioStreamPlayerDelegate <NSObject>
@optional
- (void)audioStreamPlayer:(STAudioStreamPlayer *)audioStreamPlayer didChangePlayerState:(STAudioStreamPlayerState)playerState;
- (void)audioStreamPlayer:(STAudioStreamPlayer *)audioStreamPlayer didFailWithError:(NSError *)error;
- (void)audioStreamPlayer:(STAudioStreamPlayer *)audioStreamPlayer didChangeAudioFileFormat:(AudioStreamBasicDescription *)asbdRef;
- (void)processingTapForAudioStreamPlayer:(STAudioStreamPlayer *)audioStreamPlayer
                        inputNumberFrames:(UInt32)inputNumberFrames
                              ioTimeStamp:(AudioTimeStamp *)ioTimeStamp
                                  ioFlags:(UInt32 *)ioFlags
                       outputNumberFrames:(UInt32 *)outputNumberFrames
                                   ioData:(AudioBufferList *)ioData;
@end

