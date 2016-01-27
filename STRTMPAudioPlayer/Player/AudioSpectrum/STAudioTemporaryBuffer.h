//
//  STAudioTemporaryBuffer.h
//  STRTMPAudioPlayer
//
//  Created by saiten on 2015/02/14.
//  Copyright (c) 2015 saiten. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface STAudioTemporaryBuffer : NSObject
@property (nonatomic, readonly) Float32 sampleRate;

- (instancetype)initWithSampleRate:(Float32)sampleRate;
- (instancetype)initWithSampleRate:(Float32)sampleRate bufferSize:(NSUInteger)bufferSize;
+ (instancetype)temporaryBufferWithSampleRate:(Float32)sampleRate;
+ (instancetype)temporaryBufferWithSampleRate:(Float32)sampleRate bufferSize:(NSUInteger)bufferSize;

- (void)pushSamples:(Float32 *)samples count:(NSUInteger)count;
@end
