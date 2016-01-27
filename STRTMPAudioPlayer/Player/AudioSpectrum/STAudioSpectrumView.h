//
//  RDKAudioSpectrumView.h
//  STRTMPAudioPlayer
//
//  Created by saiten on 2015/02/14.
//  Copyright (c) 2015 saiten. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "STAudioSpectrumAnalyzer.h"

@protocol STAudioSpectrumViewDataSource;

@interface STAudioSpectrumView : UIView
@property (nonatomic, weak) id <STAudioSpectrumViewDataSource> dataSource;
@property (nonatomic, assign) NSUInteger framesPerSecond;

- (void)start;
- (void)stop;
@end

@protocol STAudioSpectrumViewDataSource <NSObject>
- (NSArray *)audioTemporaryBuffersForAudioSpectrumView:(STAudioSpectrumView *)audioSpectrumView;
@end

