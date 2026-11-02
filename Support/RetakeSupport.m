// The library's one constructor, running each part in order: the take's home first, so that the
// defaults are set up for the home the take will use, then the windows' shape and appearance, the watch for missed
// frames, the sound kept running, then the report.
#import "RetakeSupport.h"

NSString *RetakeRealHome;

__attribute__((constructor))
static void RetakeSupportStart(void) {
    NSDictionary<NSString *, NSString *> *environment = NSProcessInfo.processInfo.environment;
    if (!environment[@"RETAKE_STATE"] && !environment[@"RETAKE_CLEANUP"]) return;
    RetakeStartClock();
    RetakeRealHome = NSHomeDirectory();
    if (environment[@"RETAKE_CLEANUP"]) RetakeCleanUpAndExit(environment);
    RetakeSetUpState(environment);
    RetakeSetUpDefaults(environment);
    RetakeSetUpAspect(environment);
    RetakeSetUpAppearance(environment);
    RetakeStartHitchWatch();
    RetakeKeepAudioRunning();
    RetakeWriteReport(environment, NSHomeDirectory());
}
