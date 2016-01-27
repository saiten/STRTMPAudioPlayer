//
//  RDKAudioSpectrumView.m
//  STRTMPAudioPlayer
//
//  Created by saiten on 2015/02/14.
//  Copyright (c) 2015 saiten. All rights reserved.
//

#import "STAudioSpectrumView.h"
#import "STAudioSpectrumAnalyzer.h"

@interface STAudioSpectrumView()
@property (nonatomic, strong) STAudioSpectrumAnalyzer *analyzer;
@property (nonatomic, weak) CADisplayLink *displayLink;
@end

@implementation STAudioSpectrumView

#pragma mark - lifecycle

- (instancetype)init
{
    self = [super init];
    if(self) {
        [self _setup];
    }
    return self;
}

- (id)initWithCoder:(NSCoder *)aDecoder
{
    self = [super initWithCoder:aDecoder];
    if(self) {
        [self _setup];
    }
    return self;
}

- (instancetype)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if(self) {
        [self _setup];
    }
    return self;
}


- (void)_setup
{
    self.framesPerSecond = 10;
    self.analyzer = [[STAudioSpectrumAnalyzer alloc] init];
}

- (void)dealloc
{
    [self stop];
}

#pragma mark - public method

- (void)start
{
    self.displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(_update:)];
    self.displayLink.frameInterval = self.framesPerSecond;
    [self.displayLink addToRunLoop:[NSRunLoop currentRunLoop] forMode:NSRunLoopCommonModes];
}

- (void)stop
{
    [self.displayLink invalidate];
}

#pragma mark - update

- (void)_update:(id)sender
{
    NSArray *audioBuffers = nil;
    if(self.dataSource && [self.dataSource respondsToSelector:@selector(audioTemporaryBuffersForAudioSpectrumView:)]) {
        audioBuffers = [self.dataSource audioTemporaryBuffersForAudioSpectrumView:self];
    }
    if(!audioBuffers || audioBuffers.count == 0) {
        return;
    }
    
    [self.analyzer processAudioTemporaryBuffers:audioBuffers];
    
}

/*
// Only override drawRect: if you perform custom drawing.
// An empty implementation adversely affects performance during animation.
- (void)drawRect:(CGRect)rect {
    // Drawing code
}
*/

@end
