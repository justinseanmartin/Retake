// The launch report, and the cleanup launch.
//
// Each launch Retake makes writes <real home>/tmp/RetakeLaunch/report.json, which Retake copies
// back before the first step: it shows the library loaded, which contract it speaks, and that the
// take was set up as asked, naming the take so a report from an earlier launch can't pass for it.
//
// RETAKE_CLEANUP=1 is a launch for cleaning up only: the library deletes takes' homes and staged
// files, writes its report, and exits before any of the app's code runs, so the app never shows.
#import "RetakeSupport.h"
#include <mach/mach_time.h>
#include <unistd.h>

static uint64_t started;

void RetakeStartClock(void) {
    started = mach_absolute_time();
}

static double millisecondsSinceStart(void) {
    mach_timebase_info_data_t info;
    mach_timebase_info(&info);
    return (double)(mach_absolute_time() - started) * info.numer / info.denom / 1e6;
}

void RetakeWriteReport(NSDictionary<NSString *, NSString *> *environment, NSString *home) {
    NSMutableDictionary *report = [@{
        @"contract": @(RETAKE_SUPPORT_CONTRACT),
        @"take": environment[@"RETAKE_TAKE"] ?: @"",
        @"state": environment[@"RETAKE_STATE"] ?: @"",
        @"milliseconds": @(millisecondsSinceStart()),
    } mutableCopy];
    if (environment[@"RETAKE_CLEANUP"]) report[@"cleanedUp"] = @YES;
    if (home) report[@"home"] = [home stringByReplacingOccurrencesOfString:RetakeRealHome withString:@"~"];
    NSString *folder = [RetakeRealHome stringByAppendingPathComponent:@"tmp/RetakeLaunch"];
    [NSFileManager.defaultManager createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:nil];
    NSData *data = [NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingSortedKeys error:nil];
    [data writeToFile:[folder stringByAppendingPathComponent:@"report.json"] atomically:YES];
}

void RetakeCleanUpAndExit(NSDictionary<NSString *, NSString *> *environment) {
    NSFileManager *files = NSFileManager.defaultManager;
    for (NSString *folder in @[@"tmp/RetakeTakes", @"tmp/RetakeSet"]) {
        [files removeItemAtPath:[RetakeRealHome stringByAppendingPathComponent:folder] error:nil];
    }
    RetakeWriteReport(environment, nil);
    // _exit, not exit: exit's handlers need a lock dyld holds while it runs this constructor, and the
    // process hangs waiting for it. There's nothing to flush.
    _exit(0);
}
