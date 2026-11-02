// The app's main thread watched for missed frames, so a take can say when its footage froze and
// whether The Button Heist, Retake or the app was busy then.
//
// A display link on the main run loop notes each time a frame comes more than a frame and a half
// after the one before: the main thread was busy for at least one whole frame. Each such hitch is
// kept with when it started, on the device's clock, as seconds since the reference date like The
// Button Heist's own timestamps, and how long it lasted. The list is written to
// <real home>/tmp/RetakeLaunch/hitches.json off the main thread, so watching adds no load of its own.
#import "RetakeSupport.h"
#import <QuartzCore/QuartzCore.h>
#import <UIKit/UIKit.h>

@interface RetakeHitchWatch : NSObject
@property (nonatomic) CFTimeInterval last;
@property (nonatomic, strong) NSMutableArray<NSArray<NSNumber *> *> *hitches;
@property (nonatomic, strong) dispatch_queue_t writing;
@property (nonatomic, copy) NSString *path;
@end

@implementation RetakeHitchWatch

- (void)tick:(CADisplayLink *)link {
    CFTimeInterval frame = link.targetTimestamp - link.timestamp;
    if (self.last > 0 && frame > 0 && link.timestamp - self.last > frame * 1.5) {
        CFTimeInterval duration = link.timestamp - self.last;
        NSTimeInterval started = NSDate.timeIntervalSinceReferenceDate - (CACurrentMediaTime() - self.last);
        [self.hitches addObject:@[@(started), @(duration)]];
        NSArray *snapshot = [self.hitches copy];
        NSString *path = self.path;
        dispatch_async(self.writing, ^{
            NSData *data = [NSJSONSerialization dataWithJSONObject:@{@"hitches": snapshot} options:0 error:nil];
            [data writeToFile:path atomically:YES];
        });
    }
    self.last = link.timestamp;
}

@end

void RetakeStartHitchWatch(void) {
    NSString *folder = [RetakeRealHome stringByAppendingPathComponent:@"tmp/RetakeLaunch"];
    [NSFileManager.defaultManager createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *path = [folder stringByAppendingPathComponent:@"hitches.json"];
    // An earlier launch's hitches aren't this one's.
    NSData *empty = [NSJSONSerialization dataWithJSONObject:@{@"hitches": @[]} options:0 error:nil];
    [empty writeToFile:path atomically:YES];
    // The constructor runs before UIKit is up; the main queue runs once the app's run loop does.
    dispatch_async(dispatch_get_main_queue(), ^{
        RetakeHitchWatch *watch = [RetakeHitchWatch new];
        watch.hitches = [NSMutableArray array];
        watch.writing = dispatch_queue_create("retake.hitches", DISPATCH_QUEUE_SERIAL);
        watch.path = path;
        // The display link retains its target, which lives as long as the app.
        CADisplayLink *link = [CADisplayLink displayLinkWithTarget:watch selector:@selector(tick:)];
        // At the screen's full rate, so an idle screen slowing its refresh isn't taken for a hitch.
        float fastest = (float)UIScreen.mainScreen.maximumFramesPerSecond;
        link.preferredFrameRateRange = CAFrameRateRangeMake(fastest, fastest, fastest);
        [link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    });
}
