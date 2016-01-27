//
//  STFLVConverter.h
//  STRTMPAudioPlayer
//
//  Created by saiten on 2014/01/10.
//  Copyright (c) 2014 saiten. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "STBlockingQueue.h"

@class STFLVConverter;

@protocol STFLVConverterDelegate <NSObject>
- (void)flvConverterDidStartConvert:(STFLVConverter*)flvConverter;
- (void)flvConverterDidFinishConvert:(STFLVConverter*)flvConverter;
- (void)flvConverter:(STFLVConverter*)flvConverter didFailWithError:(NSError*)error;
@end

typedef NS_ENUM(NSInteger, STFLVConverterState) {
    STFLVConverterStateIntialized,
    STFLVConverterStateStartingThread,
    STFLVConverterStateConverting,
    STFLVConverterStateTerminating,
    STFLVConverterStateFinished,
    STFLVConverterStateFailed
};

@interface STFLVConverter : NSObject
@property (nonatomic, readonly) STFLVConverterState state;
@property (nonatomic, weak) id<STFLVConverterDelegate> delegate;

- (id)initWithDelegate:(id<STFLVConverterDelegate>)delegate
    inputBlockingQueue:(STBlockingQueue*)inputBlockingQueue outputBlockingQueue:(STBlockingQueue*)outputBlockingQueue;

- (void)start;
- (void)stop;
@end
