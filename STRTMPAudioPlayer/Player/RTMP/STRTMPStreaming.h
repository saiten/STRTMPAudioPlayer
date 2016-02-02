//
//  STRTMPStreaming.h
//  STRTMPAudioPlayer
//
//  Created by saiten on 2014/01/07.
//  Copyright (c) 2014 saiten. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "STBlockingQueue.h"
#import <librtmp/rtmp.h>

extern NSString* const STRTMPStreamingErrorDomain;

#define STR2AVAL(av, str)  av.av_val = (char*)str; av.av_len = (int)strlen(av.av_val)

typedef NS_ENUM(NSInteger, STRTMPStreamingState) {
    STRTMPStreamingStateInitialized,
    STRTMPStreamingStateStartingThread,
    STRTMPStreamingStateConnecting,
    STRTMPStreamingStateConnected,
    STRTMPStreamingStateStreaming,
    STRTMPStreamingStateDisconnecting,
    STRTMPStreamingStateDisconnected,
    STRTMPStreamingStateFailed
};

@class STRTMPStreaming;

@protocol STRTMPStreamingDelegate <NSObject>
@optional
- (void)rtmpStreaming:(STRTMPStreaming*)rtmpStreaming willStartConnectionForRTMP:(RTMP*)rtmpRef;
- (void)rtmpStreamingDidConnectStream:(STRTMPStreaming*)rtmpStreaming;
- (void)rtmpStreamingDidDisconnectStream:(STRTMPStreaming*)rtmpStreaming;
- (void)rtmpStreaming:(STRTMPStreaming*)rtmpStreaming didFailWithError:(NSError*)error;
@end

@interface STRTMPStreaming : NSObject
@property (nonatomic, weak) id<STRTMPStreamingDelegate> delegate;
@property (nonatomic, readonly) STBlockingQueue *blockingQueue;
@property (nonatomic, readonly) STRTMPStreamingState state;

@property (nonatomic, strong)    NSURL    *url;
@property (nonatomic, strong)    NSString *app;
@property (nonatomic, strong)    NSString *playPath;
@property (nonatomic, strong)    NSURL    *playerURL;
@property (nonatomic, strong)    NSData   *playerHash;
@property (nonatomic, readwrite) uint      playerSize;
@property (nonatomic, strong)    NSString *flashVersion;

- (instancetype)initWithDelegate:(id<STRTMPStreamingDelegate>)delegate
                   blockingQueue:(STBlockingQueue*)blockingQueue
                      bufferTime:(uint32_t)bufferTime;
- (void)start;
- (void)stop;
@end
