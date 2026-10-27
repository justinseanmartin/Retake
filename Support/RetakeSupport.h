// Retake's support library: loaded into the app, only when Retake launches it, through
// DYLD_INSERT_LIBRARIES, to set up a take before any of the app's own code runs. What Retake and
// the library expect of each other is versioned by RETAKE_SUPPORT_CONTRACT, which changes only
// when that does: the environment below, how defaults and files are delivered, how it reports.
// docs/cli.md, "Compatibility with an embedded app", says how the two are checked against each
// other; Sources/RetakeCore/SupportLibrary.swift holds the same number, and a test keeps them equal.
//
// The launch environment Retake sets:
//
//   RETAKE_STATE       clean, cloned or live: what the app's data starts as (README.md, "state")
//   RETAKE_TAKE        an id for the take, naming its home in tmp/RetakeTakes/
//   RETAKE_DEFAULTS    the set's defaults, as a JSON object
//
// and the set's files, which the Mac stages in the app's container, in tmp/RetakeSet/, laid out as
// they go: Documents/…, Library/….
#import <Foundation/Foundation.h>

#define RETAKE_SUPPORT_CONTRACT 1

/// The app's real home, before the take's redirects it.
extern NSString *RetakeRealHome;

/// Builds the take's home for its state, and points the app at it.
void RetakeSetUpState(NSDictionary<NSString *, NSString *> *environment);

/// Replaces UserDefaults.standard for the take, or writes the set's defaults into the real ones.
void RetakeSetUpDefaults(NSDictionary<NSString *, NSString *> *environment);
