// The app's sound kept running while it's recorded, so the recording doesn't lose frames.
//
// When an app's audio starts again after a second or so of silence, the device restarts its sound
// output, and the screen recording over USB drops 0.2 to 0.5 s of video while it does. The app looks
// smooth on the device; only the recording stutters, just before each sound that follows a quiet
// stretch. An audio engine playing noise far below hearing, a few steps of 16-bit sound, keeps the
// output running, so it never restarts. It mixes with the app's own sound and doesn't change the
// session's category, which stays the app's.
#import "RetakeSupport.h"
#import <AVFoundation/AVFoundation.h>

static AVAudioEngine *engine;

static void startEngine(void) {
    NSError *error;
    if (!engine.isRunning) [engine startAndReturnError:&error];
}

void RetakeKeepAudioRunning(void) {
    // Once the app is up, so its own audio setup comes first.
    dispatch_async(dispatch_get_main_queue(), ^{
        engine = [AVAudioEngine new];
        AVAudioFormat *format = [engine.mainMixerNode outputFormatForBus:0];
        AVAudioSourceNode *silence = [[AVAudioSourceNode alloc] initWithRenderBlock:^OSStatus(BOOL *isSilence, const AudioTimeStamp *time, AVAudioFrameCount frames, AudioBufferList *output) {
            // Noise far below hearing, about -80 dB, rather than zeros, which the output idles on.
            for (UInt32 index = 0; index < output->mNumberBuffers; index++) {
                float *samples = output->mBuffers[index].mData;
                UInt32 count = output->mBuffers[index].mDataByteSize / sizeof(float);
                for (UInt32 sample = 0; sample < count; sample++) samples[sample] = ((float)arc4random_uniform(2001) - 1000.0f) * 1e-7f;
            }
            return noErr;
        }];
        [engine attachNode:silence];
        [engine connect:silence to:engine.mainMixerNode format:format];
        // The app changing its session's category or route stops the engine; it's started again.
        [NSNotificationCenter.defaultCenter addObserverForName:AVAudioEngineConfigurationChangeNotification object:engine queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
            startEngine();
        }];
        [NSNotificationCenter.defaultCenter addObserverForName:AVAudioSessionInterruptionNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
            if ([note.userInfo[AVAudioSessionInterruptionTypeKey] unsignedIntegerValue] == AVAudioSessionInterruptionTypeEnded) startEngine();
        }];
        startEngine();
        // An app activating its session stops the engine with no notification, as AVAudioSession's
        // activate(options:) does on iOS 27, so it's looked at often and started again.
        [NSTimer scheduledTimerWithTimeInterval:0.25 repeats:YES block:^(NSTimer *timer) { startEngine(); }];
    });
}
