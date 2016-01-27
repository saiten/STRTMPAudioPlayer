//
//  STBlockingQueue.h
//  STRTMPAudioPlayer
//
//  Created by saiten on 2014/01/09.
//  Copyright (c) 2014 saiten. All rights reserved.
//

#import <Foundation/Foundation.h>

extern int32_t const STBlockingQueueDefaultCapacity;

@interface STBlockingQueue : NSObject
@property (nonatomic, readonly) BOOL    closed;
@property (nonatomic, readonly) BOOL    discontinuity;
@property (nonatomic, readonly) int32_t capacity;

- (instancetype)initWithQueueCapacity:(int32_t)capacity;
+ (instancetype)blockingQueueWithQueueCapacity:(int32_t)capacity;

- (int32_t)pushWithBytes:(const int8_t*)buffer size:(int32_t)size;
- (int32_t)pushWithBytes:(const int8_t*)buffer size:(int32_t)size discontinuity:(BOOL)discontinuity;
- (int32_t)popWithBytes:(int8_t*)buffer size:(int32_t)size;
- (int32_t)popWithBytes:(int8_t*)buffer size:(int32_t)size discontinuity:(BOOL*)discontinuity;

- (void)close;

@end
