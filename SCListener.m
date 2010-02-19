//
// SCListener 1.0.1
// http://github.com/stephencelis/sc_listener
//
// (c) 2009-* Stephen Celis, <stephen@stephencelis.com>.
// Released under the MIT License.
//

#import "SCListener.h"

@interface SCListener (Private)

- (void)updateLevels;
- (void)setupQueue;
- (void)setupFormat;
- (void)setupBuffers;
- (void)setupMetering;
- (UInt32)getFreqFromBuffer: (short*) buffer length: (UInt32) length;
- (UInt32)findOptimalSampleLength: (UInt32) samples;
- (void)setAudioBuffer: (short*) buffer length: (UInt32) length;
@end

static SCListener *sharedListener = nil;
static void listeningCallback(void *inUserData, AudioQueueRef inAQ, AudioQueueBufferRef inBuffer, const AudioTimeStamp *inStartTime, UInt32 inNumberPacketsDescriptions, const AudioStreamPacketDescription *inPacketDescs) {
	SCListener *listener = (SCListener *)inUserData;
	if ([listener isListening]){
		[listener setAudioBuffer:inBuffer->mAudioData length: inBuffer->mAudioDataByteSize];
		AudioQueueEnqueueBuffer(inAQ, inBuffer, 0, NULL);
	}
}

@implementation SCListener

+ (SCListener *)sharedListener {
	@synchronized(self) {
		if (sharedListener == nil)
			[[self alloc] init];
	}

	return sharedListener;
}

- (void)dealloc {
	[sharedListener stop];
	[super dealloc];
}

#pragma mark -
#pragma mark Listening

- (void)listen {
	if (queue == nil){
		[self setupQueue];
    }
	AudioQueueStart(queue, NULL);
}

- (void)pause {
	if (![self isListening])
		return;

	AudioQueueStop(queue, true);
}

- (void)stop {
	if (queue == nil)
		return;

	AudioQueueDispose(queue, true);
	queue = nil;
}

- (BOOL)isListening {
	if (queue == nil)
		return NO;

	UInt32 isListening, ioDataSize = sizeof(UInt32);
	OSStatus result = AudioQueueGetProperty(queue, kAudioQueueProperty_IsRunning, &isListening, &ioDataSize);
	return (result != noErr) ? NO : isListening;
}

#pragma mark -
#pragma mark Levels getters

- (Float32)averagePower {
	if (![self isListening])
		return 0.0;

	return [self levels][0].mAveragePower;
}

- (Float32)peakPower {
	if (![self isListening])
		return 0.0;

	return [self levels][0].mPeakPower;
}

- (AudioQueueLevelMeterState *)levels {
  if (![self isListening])
    return nil;
	
	[self updateLevels];
	return levels;
}

- (void)updateLevels {
	UInt32 ioDataSize = format.mChannelsPerFrame * sizeof(AudioQueueLevelMeterState);
	AudioQueueGetProperty(queue, (AudioQueuePropertyID)kAudioQueueProperty_CurrentLevelMeter, levels, &ioDataSize);
}

#pragma mark -
#pragma mark Frequency 

- (Float32)frequency {
	short buffer[kBUFFERSIZE];
	UInt32 buffer_length;
	@synchronized(self) {
		memcpy(buffer, audio_data, kBUFFERSIZE);
		buffer_length = audio_data_len;
	}
	if(buffer_length ==0 )
		return 0;
	else	
		return [self getFreqFromBuffer: buffer length: buffer_length];
}

- (void)setAudioBuffer: (short*) buffer length: (UInt32) length{
	@synchronized(self) {
		memcpy(audio_data, buffer, length);
		audio_data_len = length;
		
	}
}

// Find the largest sample size that is a power of 2
- (UInt32) findOptimalSampleLength: (UInt32) samples{
	int result = 1;
	while(samples){
		samples >>= 1;
		result <<= 1;
	}
	
	return (result >> 1);
}


- (double) hamming_window: (short) input totalSamples: (short) totalSamples{
    double a = 2.0 * 3.141592654 / ( totalSamples - 1 );
	double w;
	
    w = 0.5 - 0.5 * cos( a * input );
    return w;
}


- (void) performWindow: (short*) buffer totalSamples: (UInt32) totalSamples{
	for (int i = 0; i < totalSamples; i++){
		buffer[i] *= [self hamming_window: i totalSamples: totalSamples];
	}
}


- (void) performFFT: (short*) buffer totalSamples: (UInt32) totalSamples{
	memset(in_fft, 0, kBUFFERSIZE * sizeof(kiss_fft_cpx));
	memset(out_fft, 0, kBUFFERSIZE * sizeof(kiss_fft_cpx));
	memset(freq_db, 0, kBUFFERSIZE / 2 );
	
	[self performWindow: buffer totalSamples: totalSamples];
	
	// Populate FFT input.
	for(UInt32 i = 0; i < totalSamples; i++){
		in_fft[i].r = buffer[i];
		in_fft[i].i = 0;
	}
	
	// Run FFT
	kiss_fft_cfg kiss_cfg = kiss_fft_alloc(totalSamples, 0, NULL, NULL);
	kiss_fft(kiss_cfg, in_fft, out_fft);
	free(kiss_cfg);
	
	
	// Calculate amplitude. ( half the fft is a duplicate )
	for(int i = 0; i < totalSamples / 2; i++)
	{	
		freq_db[i] = out_fft[i].r * out_fft[i].r + out_fft[i].i * out_fft[i].i;
	}
}

- (void) addHarmonics: (UInt32) totalSamples{
	const int max_harmonics = 5;
	int fft_range = totalSamples / 2;
	
	// Add harmonics together
	for(int i = 0; i < fft_range / max_harmonics; i++){	
		for(int j = 2; j <= max_harmonics; j++){
			freq_db[i] += freq_db[i*j];
		}
	}
}

// Calculate the frequency of an audio buffer using fft.
- (UInt32)getFreqFromBuffer: (short*) buffer length: (UInt32) length{
	// Two bytes per sample.
	UInt32 totalSamples = length/2;
	totalSamples = [self findOptimalSampleLength: totalSamples];
	
	[self performFFT: buffer totalSamples: totalSamples];
	[self addHarmonics: totalSamples];
	
	// Find highest db value in the output.
	UInt32 max = 0;
	UInt32 max_index = 0;
	for(UInt32 i = 0; i < totalSamples / 2 / 5; i++){
		UInt32 db = freq_db[i];
		if(db > max){
			max = db;
			max_index = i;
		}
	}
	 
	// Calculate frequency.
	return max_index * format.mSampleRate / totalSamples;
}

#pragma mark -
#pragma mark Setup

- (void)setupQueue {
	if (queue)
		return;

	[self setupFormat];
	AudioQueueNewInput(&format, listeningCallback, self, NULL, NULL, 0, &queue);
	[self setupBuffers];
	[self setupMetering];
}

- (void)setupFormat {
#if TARGET_IPHONE_SIMULATOR
	format.mSampleRate = 44100.0;
#else
	UInt32 ioDataSize = sizeof(sampleRate);
	AudioSessionGetProperty(kAudioSessionProperty_CurrentHardwareSampleRate, &ioDataSize, &sampleRate);
	format.mSampleRate = sampleRate;
#endif
	format.mFormatID = kAudioFormatLinearPCM;
	format.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
	format.mFramesPerPacket = format.mChannelsPerFrame = 1;
	format.mBitsPerChannel = 16;
	format.mBytesPerPacket = format.mBytesPerFrame = 2;
}

- (void)setupBuffers {
	AudioQueueBufferRef buffers[3];
	for (NSInteger i = 0; i < 3; ++i) { 
		AudioQueueAllocateBuffer(queue, kBUFFERSIZE, &buffers[i]); 
		AudioQueueEnqueueBuffer(queue, buffers[i], 0, NULL); 
	}
}

- (void)setupMetering {
	levels = (AudioQueueLevelMeterState *)calloc(sizeof(AudioQueueLevelMeterState), format.mChannelsPerFrame);
	UInt32 trueValue = true;
	AudioQueueSetProperty(queue, kAudioQueueProperty_EnableLevelMetering, &trueValue, sizeof(UInt32));
}

#pragma mark -
#pragma mark Singleton Pattern

+ (id)allocWithZone:(NSZone *)zone {
	@synchronized(self) {
		if (sharedListener == nil) {
			sharedListener = [super allocWithZone:zone];
			return sharedListener;
		}
	}

	return nil;
}

- (id)copyWithZone:(NSZone *)zone {
	return self;
}

- (id)init {
	if ([super init] == nil){
		return nil;
	}
	
	AudioSessionInitialize(NULL,NULL,NULL,NULL);
	return self;
}

- (id)retain {
	return self;
}

- (unsigned)retainCount {
	return UINT_MAX;
}

- (void)release {
	// Do nothing.
}

- (id)autorelease {
	return self;
}

@end
