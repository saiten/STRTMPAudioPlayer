//
//  STAudioSpectrumAnalyzer.h
//  STRTMPAudioPlayer
//
//  Created by saiten on 2015/02/11.
//  Copyright (c) 2015 saiten. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <Accelerate/Accelerate.h>

// Octave band type definition.
typedef NS_ENUM(NSUInteger, STOctaveBandType)
{
    RDKOctaveBandType4,
    RDKOctaveBandTypeVisual,
    RDKOctaveBandType8,
    RDKOctaveBandTypeStandard,
    RDKOctaveBandType24,
    RDKOctaveBandType31
};

struct STSpectrumData
{
    NSUInteger length;
    Float32 data[0];
};

typedef struct STSpectrumData STSpectrumData;
typedef const struct STSpectrumData *STSpectrumDataRef;

// ref: https://github.com/keijiro/AudioSpectrum

@interface STAudioSpectrumAnalyzer : NSObject
@property (nonatomic, assign) NSUInteger        pointNumber;
@property (nonatomic, assign) STOctaveBandType octaveBandType;

@property (nonatomic, readonly) STSpectrumDataRef rawSpectrumDataRef;
@property (nonatomic, readonly) STSpectrumDataRef octaveBandSpectrumDataRef;

- (void)processAudioTemporaryBuffers:(NSArray *)audioTemporaryBuffers;
- (void)processWaveform:(const Float32 *)waveform sampleRate:(Float32)sampleRate;
- (void)processWaveform:(const Float32 *)waveform1 withAdding:(const Float32*)waveform2 sampleRate:(Float32)sampleRate;
@end
