//
//  STRTMPAudioPlayer.h
//  STRTMPAudioPlayer
//
//  Created by saiten on 2016/01/20.
//  Copyright © 2016 saiten. All rights reserved.
//

#import <Foundation/Foundation.h>

@protocol STRTMPConnectionParameter
@property (nonatomic, readonly, nonnull) NSURL *url;
@property (nonatomic, readonly, nullable) NSString *app;
@property (nonatomic, readonly, nullable) NSString *playPath;
@property (nonatomic, readonly, nullable) NSURL *playerURL;
@property (nonatomic, readonly, nullable) NSData *playerHash;
@property (nonatomic, readonly, nullable) NSNumber *playerSize;
@property (nonatomic, readonly, nullable) NSString *flashVersion;
@property (nonatomic, readonly, nullable) NSArray<NSString *> *connectMessages;
@end

@protocol STRTMPAudioPlayerDelegate
@end

@interface STRTMPAudioPlayer : NSObject
@property (nonatomic, strong, nonnull) id<STRTMPConnectionParameter> connectionParameter;
@property (nonatomic, weak, nullable) id<STRTMPAudioPlayerDelegate> delegate;
@property (nonatomic, readonly) BOOL playing;

- (__nonnull instancetype)initWithConnectionParameters:(__nullable id<STRTMPConnectionParameter>)connectionParameter;

- (void)play;
- (void)stop;

@end