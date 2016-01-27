//
//  STAudioTemporaryBuffer.m
//  STRTMPAudioPlayer
//
//  Created by saiten on 2015/02/14.
//  Copyright (c) 2015 saiten. All rights reserved.
//

#import "STAudioTemporaryBuffer.h"

#define kDefaultBufferSize     (1024 * 16)

@implementation STAudioTemporaryBuffer {
    Float32 *_samples;
    NSUInteger _bufferSize;
    NSUInteger _offset;
}

#pragma mark - lifecycle

- (instancetype)initWithSampleRate:(Float32)sampleRate
{
    return [self initWithSampleRate:sampleRate bufferSize:kDefaultBufferSize];
}

- (instancetype)initWithSampleRate:(Float32)sampleRate bufferSize:(NSUInteger)bufferSize
{
    self = [super init];
    if(self) {
        _sampleRate = sampleRate;
        _bufferSize = bufferSize;
        _samples = malloc(_bufferSize * sizeof(Float32));
        memset(_samples, 0, _bufferSize * sizeof(Float32));
    }
    return self;
}

+ (instancetype)temporaryBufferWithSampleRate:(Float32)sampleRate
{
    return [[self alloc] initWithSampleRate:sampleRate];
}

+ (instancetype)temporaryBufferWithSampleRate:(Float32)sampleRate bufferSize:(NSUInteger)bufferSize
{
    return [[self alloc] initWithSampleRate:sampleRate bufferSize:bufferSize];
}

- (void)dealloc
{
    free(_samples);
}

- (void)pushSamples:(Float32 *)samples count:(NSUInteger)count
{
    NSUInteger rest = _bufferSize - _offset;
    if(count <= rest) {
        FloatCopy(samples, _samples, count);
        _offset += count;
    } else {
        FloatCopy(samples, _samples, rest);
        FloatCopy(samples + rest, _samples, count - rest);
        _offset = count - rest;
    }
}

static inline void FloatCopy(const Float32 *source, Float32 *destination, NSUInteger length)
{
    memcpy(destination, source, length * sizeof(Float32));
}

@end
