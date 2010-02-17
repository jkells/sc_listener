//
// SCListener 1.0.1
// http://github.com/stephencelis/sc_listener
//
// (c) 2009-* Stephen Celis, <stephen@stephencelis.com>.
// Released under the MIT License.
//

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioQueue.h>
#import <AudioToolbox/AudioServices.h>
#import "kiss_fft.h"

// 500ms = 44100 * (500/1000) = 22050 samples @ 2bytes each = 44100 
// A higher sample size gives more accurate results at the expense of responsiveness.
// 44,100 byte buffer will only report frequency every 500ms.
#define kBUFFERSIZE 32768

@interface SCListener : NSObject {
	AudioQueueLevelMeterState *levels;
	
	AudioQueueRef queue;
	AudioStreamBasicDescription format;
	Float64 sampleRate;

	// Audio Buffer
	short audio_data[kBUFFERSIZE];
	UInt32 audio_data_len;
	
	// Buffers for fft
	kiss_fft_cpx in_fft[kBUFFERSIZE];
	kiss_fft_cpx out_fft[kBUFFERSIZE];
}

+ (SCListener *)sharedListener;

- (void)listen;
- (BOOL)isListening;
- (void)pause;
- (void)stop;

- (Float32)frequency;
- (Float32)averagePower;
- (Float32)peakPower;
- (AudioQueueLevelMeterState *)levels;

@end
