//
//  STFLVConverter.m
//  STRTMPAudioPlayer
//
//  Created by saiten on 2014/01/10.
//  Copyright (c) 2014 saiten. All rights reserved.
//

#import "STFLVConverter.h"

typedef struct {
	uint8_t tag_type;
	uint32_t data_size;
	uint32_t timestamp;
	uint8_t timestamp_extended;
	uint32_t stream_id;
} flv_tag_header;

typedef struct {
	uint8_t audio_object_type;
	uint8_t frequency_index;
	uint8_t channel;
	uint16_t frame_length;
} aac_simple_header;


@implementation STFLVConverter {
    NSThread *_converterThread;
    
    STBlockingQueue *_inputBlockingQueue;
    STBlockingQueue *_outputBlockingQueue;
}

#pragma mark - lifecycle

- (id)initWithDelegate:(id<STFLVConverterDelegate>)delegate
    inputBlockingQueue:(STBlockingQueue *)inputBlockingQueue outputBlockingQueue:(STBlockingQueue *)outputBlockingQueue
{
    self = [super init];
    if(self) {
        _state = STFLVConverterStateIntialized;
        _delegate = delegate;
        _inputBlockingQueue = inputBlockingQueue;
        _outputBlockingQueue = outputBlockingQueue;
    }

    return self;
}

#pragma mark - public methods

- (void)start
{
    @synchronized(self) {
        if(_state != STFLVConverterStateIntialized) {
            return;
        }

        _state = STFLVConverterStateStartingThread;
        
        _converterThread = [[NSThread alloc] initWithTarget:self selector:@selector(_main) object:nil];
        _converterThread.name = @"co.saiten.RDKFLVConverter";
        [_converterThread start];
    }
}

- (void)stop
{
    @synchronized(self) {
        if(_state == STFLVConverterStateConverting) {
            _state = STFLVConverterStateTerminating;
        }
    }
}

#pragma mark - private methods

- (void)_main
{
    @autoreleasepool {
        _state = STFLVConverterStateConverting;
        
        if([_delegate respondsToSelector:@selector(flvConverterDidStartConvert:)]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [_delegate flvConverterDidStartConvert:self];
            });
        }
        
        [self _convert];
        
        _state = STFLVConverterStateFinished;
        [_outputBlockingQueue close];
        
        if([_delegate respondsToSelector:@selector(flvConverterDidFinishConvert:)]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [_delegate flvConverterDidFinishConvert:self];
            });
        }
    }
}

- (void)_convert
{
    char flvHeader[9];
    [_inputBlockingQueue popWithBytes:(int8_t *)flvHeader size:9];
    
    if(!(flvHeader[0] == 'F' && flvHeader[1] == 'L' && flvHeader[2] == 'V')) {
        [self _failWithErrorMessage:@"unknown data"];
        return;
    }
    
    aac_simple_header aacHeader = { 0 };
    
    while(_state == STFLVConverterStateConverting) {
        if(![self _readFLVTagWithAACHeader:(aac_simple_header*)&aacHeader]) {
            break;
        }
        
    }
}

- (BOOL)_readFLVTagWithAACHeader:(aac_simple_header*)aacHeaderRef
{
    flv_tag_header tagHeader = { 0 };
    uint8_t buffer[15];
    
    int32_t readBytes = [_inputBlockingQueue popWithBytes:(int8_t*)buffer size:15];
    if(readBytes <= 0) {
        return NO;
    }
    
    // buffer[0-3] : previous tag size
    tagHeader.tag_type           = buffer[4];
    tagHeader.data_size          = (uint32_t)((buffer[ 5] << 16) | (buffer[ 6] << 8) | buffer[ 7]);
    tagHeader.timestamp          = (uint32_t)((buffer[ 8] << 16) | (buffer[ 9] << 8) | buffer[10]);
    tagHeader.timestamp_extended = buffer[11];
    tagHeader.stream_id          = (uint32_t)((buffer[12] << 16) | (buffer[13] << 8) | buffer[14]);
    
    if(tagHeader.tag_type == 0x08) { // audio_tag
        return [self _readAudioTagWithTagHeader:&tagHeader aacHeader:aacHeaderRef];
    } else {
        return [self _readThroughWithLength:tagHeader.data_size];
    }
}

- (BOOL)_readThroughWithLength:(int32_t)length
{
    int8_t buffer[1024];
    while(length > 0 && _state == STFLVConverterStateConverting) {
        int32_t readableSize = MIN(length, 1024);
        int32_t readBytes = [_inputBlockingQueue popWithBytes:buffer size:readableSize];
        if(readBytes <= 0) {
            return NO;
        }
        length -= readBytes;
    }

    return YES;
}

- (BOOL)_readAudioTagWithTagHeader:(flv_tag_header*)tagHeaderRef aacHeader:(aac_simple_header*)aacHeaderRef
{
    uint8_t head = 0;
    int32_t readBytes = [_inputBlockingQueue popWithBytes:(int8_t*)&head size:1];
    if(readBytes <= 0) {
        return NO;
    }
    
	//uint8_t streo = head & 0x01;
	//uint8_t size = (head & 0x02) >> 1;
	//uint8_t rate = (head & 0x0c) >> 2;
    uint8_t format = (head & 0xf0) >> 4;

    if(format == 0x0A) { // aac only
        return [self _readAACWithTagHeader:tagHeaderRef aacHeader:aacHeaderRef];
    } else {
        return [self _readThroughWithLength:tagHeaderRef->data_size - 1];
    }
}

- (BOOL)_readAACWithTagHeader:(flv_tag_header*)tagHeaderRef aacHeader:(aac_simple_header*)aacHeaderRef
{
    uint8_t dataType = 0;
    int32_t readBytes = [_inputBlockingQueue popWithBytes:(int8_t*)&dataType size:1];
    if(readBytes <= 0) {
        return NO;
    }

    int32_t dataSize = tagHeaderRef->data_size - 2;
    

    if(dataType == 0) {
        // header
        if(dataSize >= 2) {
            uint8_t buffer[2];
            readBytes = [_inputBlockingQueue popWithBytes:(int8_t*)buffer size:2];
            if(readBytes <= 0) {
                return NO;
            }
            
			aacHeaderRef->audio_object_type = (buffer[0]  & 0xf8) >> 3;
			aacHeaderRef->frequency_index   = ((buffer[0] & 0x07) << 1) | ((buffer[1] & 0x80) >> 3);
			aacHeaderRef->channel           = (buffer[1]  & 0x78) >> 3;
            
            dataSize -= 2;
        }
        
        return [self _readThroughWithLength:dataSize];
    } else {
        aacHeaderRef->frame_length = dataSize + 7;
        if([self _writeAACHeaderWithAACHeader:aacHeaderRef] <= 0) {
            return NO;
        }
        
        int8_t buffer[1024];
        while(dataSize > 0 && _state == STFLVConverterStateConverting) {
            int32_t readBytes = [_inputBlockingQueue popWithBytes:buffer size:MIN(dataSize, 1024)];
            if(readBytes <= 0) {
                return NO;
            }
            int32_t writeBytes = [_outputBlockingQueue pushWithBytes:buffer size:readBytes];
            if(writeBytes != readBytes) {
                return NO;
            }
            
            dataSize -= writeBytes;
        }

        return YES;
    }
}

- (int32_t)_writeAACHeaderWithAACHeader:(aac_simple_header*)aacHeaderRef
{
	uint8_t header[7];
	memset(header, 0, 7);
    
	uint8_t profile = 1;
	uint8_t private_bit = 0;
    
	header[0] = 0xff;
	header[1] = 0xf1;
	header[2] = ((profile & 0x03) << 6) |
                ((aacHeaderRef->frequency_index & 0x0f) << 2) |
                ((private_bit & 0x01) << 1) |
                ((aacHeaderRef->channel & 0x04));
	header[3] = ((aacHeaderRef->channel & 0x03) << 6) |
                ((aacHeaderRef->frame_length & 0x1800) >> 11);
	header[4] = ((aacHeaderRef->frame_length & 0x07f8) >> 3);
	header[5] = ((aacHeaderRef->frame_length & 0x0007) << 5) | 0x1f;
	header[6] = 0x0c;

	return [_outputBlockingQueue pushWithBytes:(const int8_t*)header size:7];
}

- (void)_failWithErrorMessage:(NSString*)errorMessage
{
    _state = STFLVConverterStateFailed;
    if([_delegate respondsToSelector:@selector(flvConverter:didFailWithError:)]) {
        NSError *error = nil;

        dispatch_async(dispatch_get_main_queue(), ^{
            [_delegate flvConverter:self didFailWithError:error];
        });
    }
}

@end
