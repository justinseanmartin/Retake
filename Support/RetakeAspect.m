// The app laid out at a preview's shape, with no app code, by sizing its windows:
//
//   RETAKE_ASPECT_PORTRAIT=3:4    the window's shape while the screen is portrait, pinned to the top
//   RETAKE_ASPECT_LANDSCAPE=4:3   its shape while the screen is landscape, pinned to the left
//
// Every app window's frame is clamped in -setFrame:, and checked again in -layoutSubviews, so it
// holds through rotation and anything UIKit resizes. The keyboard's and other system windows are
// left alone, so they still span the screen.
#import "RetakeSupport.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static double portraitAspect, landscapeAspect;

static double parseAspect(NSString *value) {
    NSArray<NSString *> *parts = [value componentsSeparatedByString:@":"];
    if (parts.count != 2 || parts[0].doubleValue <= 0 || parts[1].doubleValue <= 0) return 0;
    return parts[0].doubleValue / parts[1].doubleValue;
}

static BOOL isAppWindow(UIWindow *window) {
    NSString *name = NSStringFromClass(window.class);
    // UITextEffectsWindow, UIRemoteKeyboardWindow and the like are the system's.
    return window.windowScene != nil && ![name containsString:@"Keyboard"] && ![name containsString:@"TextEffects"];
}

static CGRect targetFrame(UIWindow *window, CGRect proposed) {
    if (!isAppWindow(window)) return proposed;
    CGRect screen = window.windowScene.coordinateSpace.bounds;
    if (CGRectIsEmpty(screen)) return proposed;
    BOOL landscape = screen.size.width > screen.size.height;
    double aspect = landscape ? landscapeAspect : portraitAspect;
    if (aspect <= 0) return screen;
    double width = screen.size.width, height = screen.size.height;
    if (width / height > aspect) width = round(height * aspect);   // wider than the shape: pinned left
    else height = round(width / aspect);                             // taller: pinned to the top
    return CGRectMake(0, 0, width, height);
}

static IMP originalSetFrame, originalLayoutSubviews;

static void retakeSetFrame(UIWindow *self, SEL _cmd, CGRect frame) {
    ((void (*)(id, SEL, CGRect))originalSetFrame)(self, _cmd, targetFrame(self, frame));
}

static void retakeLayoutSubviews(UIWindow *self, SEL _cmd) {
    CGRect target = targetFrame(self, self.frame);
    if (!CGRectEqualToRect(self.frame, target)) ((void (*)(id, SEL, CGRect))originalSetFrame)(self, @selector(setFrame:), target);
    ((void (*)(id, SEL))originalLayoutSubviews)(self, _cmd);
}

// Gives UIWindow its own implementation of `selector`, returning the one it had: a method of its own
// is replaced, and an inherited one is added to UIWindow alone, since replacing UIView's would run
// this for every view. Which UIWindow overrides varies with iOS: on 17, it inherits layoutSubviews.
static IMP replaceInWindow(SEL selector, IMP replacement) {
    Method method = class_getInstanceMethod(UIWindow.class, selector);
    IMP inherited = method_getImplementation(method);
    if (class_addMethod(UIWindow.class, selector, replacement, method_getTypeEncoding(method))) return inherited;
    return method_setImplementation(method, replacement);
}

void RetakeSetUpAspect(NSDictionary<NSString *, NSString *> *environment) {
    portraitAspect = parseAspect(environment[@"RETAKE_ASPECT_PORTRAIT"] ?: @"");
    landscapeAspect = parseAspect(environment[@"RETAKE_ASPECT_LANDSCAPE"] ?: @"");
    if (portraitAspect <= 0 && landscapeAspect <= 0) return;
    originalSetFrame = replaceInWindow(@selector(setFrame:), (IMP)retakeSetFrame);
    originalLayoutSubviews = replaceInWindow(@selector(layoutSubviews), (IMP)retakeLayoutSubviews);
}
