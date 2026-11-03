// The app held to light or dark, whatever the device is set to:
//
//   RETAKE_APPEARANCE=light    every window scene's userInterfaceStyle trait is overridden to light
//
// Set on each window scene as it connects, before any of its windows draws, so the app's first frame
// is in the appearance asked for and a window made later inherits it from the start; and on each
// window once, as it first shows, since on iOS 27 a SwiftUI app's windows don't take the scene's.
// Not set per window as it lays out: a window the app shows mid-animation, like an overlay for a
// transition, would change appearance after its animations began, and SwiftUI finishes those at once. The launch
// screen is the system's, drawn before any of the app's code runs, so it still follows the device: a
// dark device shows a dark launch screen, then the app light.
#import "RetakeSupport.h"
#import <UIKit/UIKit.h>

void RetakeSetUpAppearance(NSDictionary<NSString *, NSString *> *environment) {
    NSString *appearance = environment[@"RETAKE_APPEARANCE"];
    UIUserInterfaceStyle style;
    if ([appearance isEqualToString:@"light"]) style = UIUserInterfaceStyleLight;
    else if ([appearance isEqualToString:@"dark"]) style = UIUserInterfaceStyleDark;
    else return;
    // The observers live as long as the app.
    [NSNotificationCenter.defaultCenter addObserverForName:UISceneWillConnectNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
        if ([note.object isKindOfClass:UIWindowScene.class]) ((UIWindowScene *)note.object).traitOverrides.userInterfaceStyle = style;
    }];
    // On iOS 27 a SwiftUI app's windows don't take the scene's override, so each window is held too,
    // once, as it first shows, before it draws: unless it asks for an appearance of its own.
    [NSNotificationCenter.defaultCenter addObserverForName:UIWindowDidBecomeVisibleNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
        UIWindow *window = note.object;
        if ([window isKindOfClass:UIWindow.class] && window.overrideUserInterfaceStyle == UIUserInterfaceStyleUnspecified) {
            window.overrideUserInterfaceStyle = style;
        }
    }];
}
