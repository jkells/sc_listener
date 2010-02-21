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
#import "kiss_fftr.h"

// 500ms = 44100 * (500/1000) = 22050 samples @ 2bytes each = 44100 
// A higher sample size gives more accurate results at the expense of responsiveness.
// 44,100 byte buffer will only report frequency every 500ms.
//#define kBUFFERSIZE 44100
#define kFFTSIZE 32768
#define kBUFFERSIZE 32768
//#define kFFTSIZE 32768
#define kSAMPLERATE 44100

@interface SCListener : NSObject {
	AudioQueueLevelMeterState *levels;
	
	AudioQueueRef queue;
	AudioStreamBasicDescription format;
	Float64 sampleRate;

	// Audio Buffer
	short audio_data[kBUFFERSIZE];
	UInt32 audio_data_len;
	
	// Buffers for fft
	kiss_fft_scalar in_fft[kFFTSIZE];
	kiss_fft_cpx out_fft[kFFTSIZE];
	double freq_db[kFFTSIZE/2];
	double freq_db_harmonic[kFFTSIZE/2];
}

+ (SCListener *)sharedListener;

- (void)listen;
- (BOOL)isListening;
- (void)pause;
- (void)stop;
- (double*) freq_db;
- (double*) freq_db_harmonic;
- (Float32)frequency;
- (Float32)averagePower;
- (Float32)peakPower;
- (AudioQueueLevelMeterState *)levels;

@end
