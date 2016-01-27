//
//  STAudioSpectrumAnalyzer.m
//  STRTMPAudioPlayer
//
//  Created by saiten on 2015/02/11.
//  Copyright (c) 2015 saiten. All rights reserved.
//

#import "STAudioSpectrumAnalyzer.h"

// Octave band type definition
static Float32 middleFrequenciesForBands[][32] = {
    { 125.0f, 500, 1000, 2000 },
    { 250.0f, 400, 600, 800 },
    { 63.0f, 125, 500, 1000, 2000, 4000, 6000, 8000 },
    { 31.5f, 63, 125, 250, 500, 1000, 2000, 4000, 8000, 16000 },
    { 25.0f, 31.5f, 40, 50, 63, 80, 100, 125, 160, 200, 250, 315, 400, 500, 630, 800, 1000, 1250, 1600, 2000, 2500, 3150, 4000, 5000, 6300, 8000 },
    { 20.0f, 25, 31.5f, 40, 50, 63, 80, 100, 125, 160, 200, 250, 315, 400, 500, 630, 800, 1000, 1250, 1600, 2000, 2500, 3150, 4000, 5000, 6300, 8000, 10000, 12500, 16000, 20000 }
};

static Float32 bandwidthForBands[] = {
    1.41421356237f, // 2^(1/2)
    1.25992104989f, // 2^(1/3)
    1.41421356237f, // 2^(1/2)
    1.41421356237f, // 2^(1/2)
    1.12246204831f, // 2^(1/6)
    1.12246204831f  // 2^(1/6)
};

static inline NSUInteger CountBands(NSUInteger bandType)
{
    for (NSUInteger i = 0;; i++) {
        if (middleFrequenciesForBands[bandType][i] == 0) {
            return i;
        }
    }
}

@implementation STAudioSpectrumAnalyzer {
    vDSP_DFT_Setup _dftSetup;
    DSPSplitComplex _dftBuffer;
    Float32 *_inputBuffer;
    Float32 *_window;
    
    STSpectrumData *_rawSpectrumDataRef;
    STSpectrumData *_octaveBandSpectrumDataRef;
}

#pragma mark - lifecycle

- (instancetype)init
{
    self = [super init];
    if(self) {
        self.pointNumber    = 1024;
        self.octaveBandType = RDKOctaveBandTypeStandard;
    }
    return self;
}

- (void)dealloc
{
    vDSP_DFT_DestroySetup(_dftSetup);
    
    [self _clearBuffers];
}

- (void)_clearBuffers
{
    free(_dftBuffer.imagp);
    free(_dftBuffer.realp);
    free(_inputBuffer);
    free(_window);
    
    free((void*)_rawSpectrumDataRef);
    free((void*)_octaveBandSpectrumDataRef);
}

#pragma mark - porperties

- (void)setPointNumber:(NSUInteger)pointNumber
{
    if(_pointNumber == pointNumber) {
        return;
    }
    
    if(_pointNumber != 0) {
        [self _clearBuffers];
    }
    
    _pointNumber = pointNumber;
    
    if(_pointNumber > 0) {
        _dftSetup = vDSP_DFT_zrop_CreateSetup(_dftSetup, _pointNumber, vDSP_DFT_FORWARD);
        _dftBuffer.imagp = calloc(_pointNumber / 2, sizeof(Float32));
        _dftBuffer.realp = calloc(_pointNumber / 2, sizeof(Float32));
        
        _inputBuffer = calloc(_pointNumber, sizeof(Float32));
        
        _window = calloc(_pointNumber, sizeof(Float32));
        vDSP_blkman_window(_window, _pointNumber, 0);
        
        Float32 normFactor = 2.0f / _pointNumber;
        vDSP_vsmul(_window, 1, &normFactor, _window, 1, _pointNumber);
        
        _rawSpectrumDataRef = calloc(sizeof(STSpectrumData) + sizeof(Float32) * _pointNumber / 2, 1);
        _rawSpectrumDataRef->length = _pointNumber / 2;
    }
}

- (void)setOctaveBandType:(STOctaveBandType)octaveBandType
{
    if(_octaveBandType == octaveBandType) {
        return;
    }
    
    _octaveBandType = octaveBandType;
    
    if(_octaveBandSpectrumDataRef) {
        free(_octaveBandSpectrumDataRef);
    }
    NSUInteger bandCount = CountBands(_octaveBandType);
    _octaveBandSpectrumDataRef = calloc(sizeof(STSpectrumData) + sizeof(Float32) * bandCount, 1);
    _octaveBandSpectrumDataRef->length = bandCount;
}

#pragma mark - public methods

- (void)processAudioTemporaryBuffers:(NSArray *)audioTemporaryBuffers
{
    
}

- (void)processWaveform:(const Float32 *)waveform sampleRate:(Float32)sampleRate
{
    NSUInteger length = _pointNumber / 2;
    
    // Split the waveform.
    DSPSplitComplex dest = { _dftBuffer.realp, _dftBuffer.imagp };
    vDSP_ctoz((const DSPComplex *)waveform, 2, &dest, 1, length);
    
    // Apply the window function.
    vDSP_vmul(_dftBuffer.realp, 1, _window, 2, _dftBuffer.realp, 1, length);
    vDSP_vmul(_dftBuffer.imagp, 1, _window + 1, 2, _dftBuffer.imagp, 1, length);
    
    // DFT
    vDSP_DFT_Execute(_dftSetup, _dftBuffer.realp, _dftBuffer.imagp, _dftBuffer.realp, _dftBuffer.imagp);
    
    // Zero out the nyquist value.
    _dftBuffer.imagp[0] = 0;
    
    // Calculate power spectrum.
    Float32 *rawSpectrum = _rawSpectrumDataRef->data;
    vDSP_zvmags(&_dftBuffer, 1, rawSpectrum, 1, length);

    // Add -128db offset to avoid log(0).
    float kZeroOffset = 1.5849e-13;
    vDSP_vsadd(rawSpectrum, 1, &kZeroOffset, rawSpectrum, 1, length);
    
    // Calculate the band levels.
    NSUInteger bandCount = _octaveBandSpectrumDataRef->length;
    const Float32 *middleFreqs = middleFrequenciesForBands[_octaveBandType];
    Float32 bandWidth = bandwidthForBands[_octaveBandType];
    
    Float32 freqToIndexCoeff = _pointNumber / sampleRate;
    int maxIndex = (int)_pointNumber / 2 - 1;
    
    for (NSUInteger band = 0; band < bandCount; band++)
    {
        int idxlo = MIN((int)floorf(middleFreqs[band] / bandWidth * freqToIndexCoeff), maxIndex);
        int idxhi = MIN((int)floorf(middleFreqs[band] * bandWidth * freqToIndexCoeff), maxIndex);
        vDSP_maxv(rawSpectrum + idxlo, 1, &_octaveBandSpectrumDataRef->data[band], idxhi - idxlo + 1);
    }
}

- (void)processWaveform:(const Float32 *)waveform1 withAdding:(const Float32 *)waveform2 sampleRate:(Float32)sampleRate
{
    float scalar = .5f;
    vDSP_vasm(waveform1, 1, waveform2, 1, &scalar, _inputBuffer, 1, _pointNumber);
    
    [self processWaveform:_inputBuffer sampleRate:sampleRate];
}

@end
