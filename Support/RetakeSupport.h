// Retake's support library: loaded into the app, only when Retake launches it, through
// DYLD_INSERT_LIBRARIES, to set up a take before any of the app's own code runs. What Retake and
// the library expect of each other is versioned by RETAKE_SUPPORT_CONTRACT, which changes only
// when that does: the environment below, how defaults and files are delivered, how it reports.
// Documentation/cli.md, "Compatibility with an embedded app", says how the two are checked against each
// other; Sources/RetakeCore/SupportLibrary.swift holds the same number, and a test keeps them equal.
//
// The launch environment Retake sets:
//
//   RETAKE_STATE       clean, cloned or live: what the app's data starts as (README.md, "state")
//   RETAKE_TAKE        an id for the take, naming its home in tmp/RetakeTakes/
//   RETAKE_DEFAULTS    the set's defaults, as a JSON object
//   RETAKE_ASPECT_PORTRAIT, RETAKE_ASPECT_LANDSCAPE
//                      the shapes the app's windows take, such as 3:4 (README.md, "aspect")
//   RETAKE_CLEANUP     1 for a launch that only deletes takes' homes and staged files, then exits
//
// and the set's files, which the Mac stages in the app's container, in tmp/RetakeSet/, laid out as
// they go: Documents/…, Library/…. The library writes tmp/RetakeLaunch/report.json in the app's
// real home, for Retake to copy back, and tmp/RetakeLaunch/hitches.json, the times the app's main
// thread missed frames, for Retake to copy back once the take is recorded.
#import <Foundation/Foundation.h>

#define RETAKE_SUPPORT_CONTRACT 2

/// The app's real home, before the take's redirects it.
extern NSString *RetakeRealHome;

/// Builds the take's home for its state, and points the app at it.
void RetakeSetUpState(NSDictionary<NSString *, NSString *> *environment);

/// Replaces UserDefaults.standard for the take, or writes the set's defaults into the real ones.
void RetakeSetUpDefaults(NSDictionary<NSString *, NSString *> *environment);

/// Sizes the app's windows to the preview's shape.
void RetakeSetUpAspect(NSDictionary<NSString *, NSString *> *environment);

void RetakeStartClock(void);

/// Watches the main thread for missed frames, writing each to tmp/RetakeLaunch/hitches.json.
void RetakeStartHitchWatch(void);

/// Plays silence for as long as the app runs, so its sound output never idles and restarts.
void RetakeKeepAudioRunning(void);

/// Writes the launch report; `home` is the take's, or nil when it has none.
void RetakeWriteReport(NSDictionary<NSString *, NSString *> *environment, NSString *home);

/// Deletes takes' homes and staged files, writes the report, and exits.
void RetakeCleanUpAndExit(NSDictionary<NSString *, NSString *> *environment);
