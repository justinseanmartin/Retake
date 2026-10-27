// The library's one constructor, running each part in order: the take's home first, so that the
// defaults are set up for the home the take will use.
#import "RetakeSupport.h"

NSString *RetakeRealHome;

__attribute__((constructor))
static void RetakeSupportStart(void) {
    NSDictionary<NSString *, NSString *> *environment = NSProcessInfo.processInfo.environment;
    if (!environment[@"RETAKE_STATE"]) return;
    RetakeRealHome = NSHomeDirectory();
    RetakeSetUpState(environment);
    RetakeSetUpDefaults(environment);
}
