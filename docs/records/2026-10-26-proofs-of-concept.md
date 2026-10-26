# Proofs of concept behind Retake's design

Status: **done** (2026-10-23 to 2026-10-26). What was tried on devices before Retake's code was
written, and what it showed. The [README](../../README.md) and [docs/cli.md](../cli.md) are designed
on these results, and [the v0.0.1 plan](2026-10-26-v0.0.1-implementation-plan.md) builds on them.
The code behind them is in `spikes/`, kept locally and not checked in.

## Why they came first

Four questions could each have changed Retake's shape, so they were answered before any of its code:

1. **Linking The Button Heist's client into Retake.** Whether its library drives an app from
   Retake's own process, connecting over the USB tunnel, running actions and reading the interface.
   If not, Retake would drive the prebuilt command-line tool, which changes how it's built and
   shipped.
2. **End to end in a real app.** A large app with many frameworks, built and installed by its own
   script with the embed step added, launched in `clean` state, playing one scene: whether the
   support library's constructor runs before the app reaches `UserDefaults` or its home directory,
   and whether the app uses app groups, Core Data or `CFPreferences` in ways `state` doesn't cover.
3. **Recording an iPhone.** Everything before ran on an iPad: the clean status bar, the capture
   identity, the frame rate, and drops.
4. **`aspect` from the injected library, and turning the device with `devicectl`.** Sizing the
   app's window to a preview's shape with no app code, turning the device mid-take with no hand on
   it, and recording across the turn. If turning hadn't worked, an `aspect` step faking a landscape
   band inside a portrait screen would have stood in for it.

All four came back yes, and The Button Heist's 0.7.0 and 0.7.1 releases then answered most of
[ASKS.md](../../ASKS.md), so the first was run again on 0.7.1.

## Before the proofs of concept (2026-10-23)

Tested 2026-10-23 on an iPad Pro 11-inch (3rd generation, iPad13,4) on iOS 26.6.2, from a Mac on
Xcode 27.1, with a throwaway SwiftUI app that has no reference to The Button Heist.

### Injection works

TheInsideJob and its eight dependency frameworks, built Debug for iOS devices from The Button
Heist's main (`9e56a7dc`, reports `0.6.38`), were copied into the app's `Frameworks/`, the app
re-signed with a development identity and a wildcard team profile, and launched with
`DYLD_INSERT_LIBRARIES=@executable_path/Frameworks/TheInsideJob.framework/TheInsideJob`. dyld loaded
all nine, TheInsideJob started itself (ThePlant's `+load`), and the `buttonheist` CLI connected over
the USB tunnel, read the interface, and drove it with `activate` and `oneFingerTap`. No change to
the app's executable was needed.

### In-memory `UserDefaults.standard` works

In-memory `UserDefaults.standard` works, through a second injected library (Objective-C) that
replaces `+[NSUserDefaults standardUserDefaults]` with a subclass overriding the reads, typed
getters, writes, `registerDefaults:` and KVO registration. Checked from the app:

- seeded values reach `@AppStorage` and `bool(forKey:)`/`integer(forKey:)`/`string(forKey:)`;
- `register(defaults:)` still applies beneath them, including after a seeded key is removed;
- writes through `@AppStorage` and direct `set(_:forKey:)` both update `@AppStorage` views;
- `UserDefaults.didChangeNotification` posts on each write;
- nothing persists: relaunched without it, the app sees its real stored values.

### TheInsideJob builds as one framework from SwiftPM, with no Tuist

A wrapper package with a `type: .dynamic` library product depending on The Button Heist's
`TheInsideJob` product, built with `xcodebuild build -scheme RetakeInsideJob -configuration Debug
-destination 'generic/platform=iOS'`, gives a single `RetakeInsideJob.framework` (29 MB, unstripped
Debug) holding TheInsideJob and every dependency, linking only system libraries, with ThePlant's
`+load` kept. Injected alone, it started the server and took synthetic taps. This is how The Button
Heist says apps consume it (its SwiftPM products are its public integration surface, in
`docs/API.md`); Tuist is only for developing The Button Heist itself. It also needed none of the
overrides its Tuist project needs on Xcode 27.1.

- **SwiftPM resource bundles must go inside the framework.** AccessibilitySnapshotBH's Core and
  Model targets have resources, built as `AccessibilitySnapshotBH_*.bundle` beside the framework.
  Left out, the app crashes at launch (`unable to find bundle named …`); copied into
  `RetakeInsideJob.framework/`, where `Bundle.module` looks for a package linked into a
  framework, it works. The build script must collect every `*.bundle` the build makes.

### Movie metadata

Custom QuickTime metadata (`AVMetadataKeySpace.quickTimeMetadata`, keys like `retake.app.version`)
survives `AVAssetWriter` to `.mov` and `AVAssetExportSession` to a ProRes `.mov`, and reads back
through AVFoundation and `ffprobe`; Spotlight indexes `com.apple.quicktime.software` as the encoding
application. `AVAssetWriter` to `.mp4` silently drops all of it, and iTunes-style items too. What
survives in `.mp4` is the common identifiers `commonIdentifierSoftware` and
`commonIdentifierDescription`, written as ISO user data (`uiso/swre`, `uiso/dscp`): AVFoundation
reads them; `ffprobe` doesn't show them.

### A set's `state` works for files: `clean`, `cloned` and `live`

Tested with a third injected library (Objective-C) that builds the take's home in its constructor,
at `<container>/tmp/RetakeTakes/<take>/`, and redirects the app to it by setting `HOME`,
`CFFIXED_USER_HOME` and `TMPDIR`, with nothing swizzled. The set's files were staged by the Mac,
with `devicectl device copy to`, in `<container>/tmp/RetakeSet/`. A sample app on a fresh install,
with a real note and a 200 MB file in its real Documents, ran `live`, `cloned`, `clean`, `live`:

- In `clean` and `cloned`, all eight lookups resolved inside the take's home: `NSHomeDirectory`,
  `FileManager.urls(for:in:)` (Documents, Application Support, Caches),
  `url(for:in:appropriateFor:create:)`, `NSSearchPathForDirectoriesInDomains`,
  `URL.documentsDirectory` and `NSTemporaryDirectory`. In `live`, all eight were real.
- `clean` saw only the set's file, and a new, empty database. `cloned` saw the real files, the set's
  file on top, and the real database's row plus its own. `live` saw the real data and the set's
  file, which it wrote into the real Documents.
- A SQLite database in write-ahead-log mode, in Application Support, followed the redirect.
- Copied back to the Mac after each take, the real container was unchanged by `clean` and
  `cloned`: no take's file, and its database held only the `live` takes' rows (`live,live` at the
  end). Both `live` takes' changes stayed.
- `clonefile` cloned the real Documents (200 MB) and Library in 9.5–20 ms.
- The library deleting earlier takes' homes at launch works: each take's home was there after it,
  and gone after the next. Nothing on the Mac can delete files in the container (`devicectl`
  copies to and from, but doesn't delete), so this is how they're cleaned up.

### The capture device's identity isn't the UDID

The capture device's identity isn't the UDID (`28B5A844-…` against `00008103-…`), and its name is
the device's, curly apostrophe and `(2)` suffix included. Hence device aliases holding both.

### The Button Heist's handshake needs exactly equal versions

The Button Heist's handshake needs exactly equal versions (`TheScore/Wire/ClientMessages.swift`),
and `ping`'s `PongPayload` reports only the version string: main and the `v0.6.38` tag both report
`0.6.38`, with different command sets (`191a6a85` folded `one_finger_tap` and the rest into
`action`). Main moves the wire format between releases too: `5ab16a57` (#1476) added a required
`source` field to the interface snapshot element, decoded strictly, so a client from `9e56a7dc` and
a server from `d6257101`, both reporting `0.6.38`, would pass the handshake and then fail to read
the interface. Pinning by commit, and building both sides from it, is what keeps them matched.
(Since 0.7.1, versions between releases carry a contract hash and the handshake refuses a mismatch;
see the last section, on 0.7.1.)

## Proof of concept 1: The Button Heist's client library drives the app from Retake's own process (2026-10-24)

At `d6257101`. The SPI, the `network` scope and the config file below are no longer needed as of
0.7.1; see the last section. A small macOS program linked against the `ButtonHeist` and `TheScore`
products at `d6257101`, by a SwiftPM path dependency, drove the test app on the iPad with
TheInsideJob injected from the same commit. Everything Retake needs worked, with no command-line
tool:

- **Connecting** over the USB tunnel took 35–42 ms. `EnvironmentConfig.resolve(...)` and
  `TheFence(configuration:)`, `start()` and `stop()` are public; running commands isn't. It needs
  `@_spi(ButtonHeistTooling) import ButtonHeist`, which The Button Heist's own CLI uses: `admit`,
  `execute`, `FenceCommandInput`, `FenceResponse`. SPI makes no compatibility promise, but Retake
  pins one commit anyway, and a change breaks Retake's build rather than a recording.
- **Two ways to send a step, both working.** Typed values (`HeistActionCommand.oneFingerTap(TapTarget(selection:
  .element(.label("Add one"))))`, `.drag(DragTarget(start:end:))`, `.dismissKeyboard`), so a
  wrong shape fails to compile; or `perform` with one line of The Button Heist's DSL
  (`TypeText("Retake", into: .value("Name"))`, `WaitFor(.exists(.label("Results")), timeout: 5)`),
  which is the only way to wait. Raw `action` JSON works too.
- **What each took**, from the Mac: ping 4 ms; a tap 115–270 ms until settled; typing 6 letters
  1.0 s; a drag 0.7–0.8 s; `get_interface` 50–240 ms (about 100 ms once warm); a `WaitFor` on a
  sheet shown 1.5 s after a tap returned in 2.4–2.55 s.
- **Timing comes back from the device.** Each result carries the device's own measurements: a
  tap's `interactionMs` (79 ms) and `expectationTiming.elapsedMs` until the screen settled
  (127 ms); a wait's `timing.elapsedMs` until the predicate held (2,402 ms) and
  `lastTreeChangeElapsedMs`. The round trip adds about 100 ms on top, so the step log should
  place a step's end from these, not from when the reply arrived.
- **Elements come with frames.** `get_interface` returns each element's label, traits, value,
  screen frame and activation point, and a ready-made `target` to send back. A full interface of
  the test app's 7 elements was 11 KB of JSON. Enough for element snapshots, spotlights and blurs
  by label.
- **Failures are clear and typed.** An unknown element fails with every element on screen listed;
  an unknown command (`one_finger_tap`) is refused before anything is sent.
- **A text field is found by its placeholder as `value`, not `label`.** `TypeText(…, into:
  .label("Name"))` failed; `.value("Name")` worked. Scenes need to say which.
- **The server rejects the USB tunnel unless `INSIDEJOB_SCOPE` includes `network`.**
  `simulator,usb` refused it as a network connection; `simulator,usb,network` accepted it.
- **A direct `[address]:port` only connects as a config file's target.** As a filter it's taken
  for a discovery query unless it's loopback, and fails with "No devices found". The proof of
  concept wrote a temporary config file and passed `configPath:`.
- **A mismatched app runs the commands it can't answer.** Against an app with TheInsideJob from
  `9e56a7dc` (also reporting `0.6.38`), the `d6257101` client connected and pinged, and every
  command after failed with "Failed to decode server message". But the actions ran: the app's
  count went to 3. A mismatched Retake would play a whole scene blind, so checking the embedded
  commit before the first step isn't optional.

## Proof of concept 2: end to end in a real app (2026-10-24)

A shipping SwiftUI app with a dozen of its own dynamic frameworks, Firebase, RevenueCat and a
keychain library, built Debug at `-O` by its own side-load script, with an embed step
(`spikes/scripts/embed.sh`) added between its build and its install. iPad Pro 11-inch (3rd
generation), iOS 26.6.2, The Button Heist `d6257101`.

- **Embedding a real app needs its own signature kept.** The spike's earlier `sign.sh` re-signed
  with a wildcard profile and minimal entitlements; a real app has its own profile, capabilities
  and maybe extensions. `embed.sh` reads the identity (the leaf certificate's SHA-1) and the
  entitlements from the built app, signs the added framework and dylibs with that identity, and
  re-signs only the outer app with its own entitlements, leaving nested signatures as built. It
  installed over a development build with no prompt, and an app embedded that way launched without
  Retake's environment runs as the plain build: nothing is loaded unless `DYLD_INSERT_LIBRARIES`
  says so.
- **`clean` held for everything the app reads.** On a device whose real data had four profiles
  and a 5.9 MB defaults plist, the `clean` launch showed the first-launch welcome screen; the scene
  (wait for it, tap "Get started", wait for the parental gate) ran on the first connection, twice.
  The support library's constructor ran before any of the app's code read defaults or files: the
  take's home was built in 1–9 ms, and the app saw none of its real state. A normal launch
  afterwards opened on the real profiles.
- **What still reached the real container under `clean`:** files nowhere (everything the app,
  Firebase, Crashlytics and URLSession wrote went to the take's copy); one key in the real
  defaults, `SKPurchaseIntentUpdatesLastChecked`, a timestamp StoreKit itself writes; and a
  Firebase health-monitor entry in its own defaults suite (`com.google.gmp.measurement.monitor`),
  as suites are documented to stay real. Neither changes what the app shows.
- **Uncovered cases the app uses:** no app groups, Core Data or `CFPreferences` in its own code.
  Its keychain (account and device identity) is the real one, and RevenueCat's and Firebase's
  suites are real; for a preview that starts on a welcome screen none of them showed. App groups
  stay out of v1.
- **Duplicate-class warnings at launch were the app's own** (SwiftProtobuf built into several of
  its frameworks), none from the injected framework, which carries its dependencies inside.
- **The recording**: 1200×1718 at ~59 fps, nothing dropped, through the launch.

## Proof of concept 3: recording an iPhone (2026-10-24)

An iPhone 17e (`iPhone18,5`) on iOS 27.0, wired, with the test app and TheInsideJob from `d6257101`
injected, driven by `spikes/client` and recorded by `spikes/recorder`:

- **Injection still works on iOS 27.0.** `DYLD_PRINT_LIBRARIES` showed both injected libraries
  loaded, before the app's own `*.debug.dylib`.
- **The recording is the full screen, 1170×2532**, unlike the iPad's scaled 1200×1718; 57–59 fps,
  nothing dropped, 48 kHz stereo sound. The status bar is the clean one (9:41, full signal and
  battery), and with `INSIDEJOB_FINGERPRINTS=false` no touch shows.
- **Every step ran**: taps, a sheet, typing six letters (0.8 s), dismissing the keyboard.
- **The first connection failed once** ("Could not reach ButtonHeist server at device",
  `connection.endpoint_unreachable`) about 5 s after launch, with the port open moments later and
  on every later try, recording or not. Unexplained; Retake must retry connecting for a few
  seconds before failing.
- **The device's appearance is in the recording**: the phone was in dark mode. A set should say
  which; `devicectl device settings appearance` may set it, after v0.0.1.
- **Only devices connected by USB are offered for capture**: with the iPad on the network, the
  phone was the only capture device.

## Proof of concept 4: `aspect` from an injected library, and turning the device (2026-10-24)

A fourth injected library (Objective-C, 70 KB) clamps every app window's frame in `-[UIWindow
setFrame:]`, rechecked in `-layoutSubviews`, to a shape per orientation, leaving the keyboard's and
other system windows alone. Same iPad, test app showing its own geometry:

- **Portrait at 3:4 works with no app code.** The window was 834×1112 at the top of the
  834×1194 screen; SwiftUI laid out in it (geometry 834×1080), the bottom safe-area inset went
  from 25 to 0, and the size class stayed regular. Taps by element and by point inside the window
  landed; a tap in the band below it failed to dispatch, as it should. A sheet presented centred
  in the window.
- **The keyboard isn't the window's.** It's a system window across the whole screen, so it rises
  into the band the edit crops; the app's own inset for it (258) is only the part inside the
  window. Scenes that type should expect a cut-off keyboard.
- **`devicectl device orientation set landscapeLeft` turns the app with no hand.** It returns in
  about 0.16–0.24 s, and the app relaid out for landscape (1194×834 without `aspect`, 1112×834 at
  4:3 pinned left with it, the home-indicator inset back since the window reaches the bottom).
  In landscape, the status bar and home indicator still span the whole screen, past the window.
- **The recording keeps going through a turn, but today's recorder squeezes it.** The captured
  stream changes shape with the device (1200×1718 to 1718×1200, then back), and the system's own
  rotation animation is in it. The recorder sizes its writer from the first frame, so landscape
  frames were squeezed into portrait. Turning frames of the other shape a quarter into the file's
  shape (Core Image, through a pixel buffer adaptor) fixed it: one file, no frames dropped, and
  the shape changes logged with their times, so the edit can turn them back. Shown upright, the
  footage has the device's real rotation animation, which may make the edit's synthetic turn
  unnecessary.
- **A first turn hitched for a quarter second, from the recorder, not the device.** The first
  quarter-turn render compiles Core Image's kernels (258 ms), holding the capture queue, and the
  capture output silently discards the frames that arrive meanwhile (they never reach the
  recorder, so they aren't counted as dropped). Rendering one blank frame when the writer starts
  fixed it: after that, the slowest turn took 7 ms. What's left is the device's own gap of about
  58 ms (3–4 frames) each time the stream changes shape, short enough for a blur over the turn
  to hide.
- **The capture is 1200×1718, not the screen's 1668×2388**, on this iPad; the stream is scaled.
- **The Button Heist draws a fingerprint where it touches, and the recording shows it** (about
  0.5 s per tap). `INSIDEJOB_FINGERPRINTS=false` removes it; Retake must always set it.
- **`devicectl device capture screenshot` shows the real status bar** (the time, the date); only
  the Mac's screen capture gets the clean one.
- **The Button Heist's `WaitFor(.screenChanged)` doesn't fire for a rotation.** An `orientation`
  step needs its own wait, such as on the window's size.
- **The hidden switch element wasn't found.** A 1×1 view added to the window with an
  accessibility label and `accessibilityActivate` didn't appear in The Button Heist's interface.
  Not pursued: a real turn covers what the switch was for.

## Proof of concept 1 again, on The Button Heist 0.7.1's release (2026-10-26)

0.7.0 and 0.7.1 answered most of [ASKS.md](ASKS.md), so Retake moved from a commit on main to the
0.7.1 release: `Package.swift` pins it `exact:`, and `retake version` reads its version from
`TheScore`, so the two can't drift. `spikes/client071` reran proof of concept 1 through the public
API alone, on the same iPad (iOS 26.6.2) from Xcode 27.1, against the test app with the release's
framework injected. Everything held:

- **The published framework injects as is.** `theinsidejob-0.7.1.zip` matched its checksum; its
  `ios-arm64` `TheInsideJob.framework` (28 MB, both AccessibilitySnapshotBH resource bundles
  inside, linking only system libraries) was copied into `Frameworks/`, signed with the app, and
  loaded through `DYLD_INSERT_LIBRARIES`. It was built with Xcode 26.6 (its `XCODE_VERSION`),
  which didn't matter. No build of The Button Heist is needed.
- **The default scope admits the USB tunnel.** Launched with no `INSIDEJOB_SCOPE`, the app took
  the connection over the tunnel; `network` is no longer needed.
- **A direct `[address]:port` works as `deviceFilter`**, connecting in 44–72 ms. No config file.
- **The public client covers what Retake needs, with no SPI.** In one
  `ButtonHeist.withSession`, `heist.run { … }` ran: tap by label, `TypeText` into a field found
  by `.value("Name")`, `dismissKeyboard()`, a drag, a tap then a `WaitFor` on a sheet, and a **tap
  by point** (at an element's frame centre, from `captureInterface()`), which the first proof of
  concept never sent. A tap on a missing element came back as a failed `HeistResult`, not a throw.
  `captureInterface()` took 47–133 ms for the 7-element screen.
- **Timing still comes from the device**, and now with clock times. Each step's result has
  `interactionMs`, `elapsedMs` until the screen settled, and `lastTreeChangeElapsedMs`; a wait's
  `elapsedMs` (2,261 ms for the sheet shown 1.5 s after the tap). New: each step's evidence holds
  the interface's absolute timestamps before and after it (seconds since 2001 on the device's
  clock, `814733660.149781`), which could place steps on the movie's clock better than elapsed
  times measured from when Retake sent each step.
- **A mismatched client is refused before anything runs.** A client from main (`5d05a318`,
  reporting `0.7.1-d53fb59edbf3`) against the `0.7.1` app threw a `FenceError` with code
  `protocol.mismatch`, naming both versions. The app's screen was untouched afterwards (`Taps 0`,
  `Name is empty`), where at `d6257101` a mismatched client's commands all ran.
- **A local clone needs `.package(name: "TheButtonHeist", path:)`.** SwiftPM names a path
  package after its directory, so a clone not called `TheButtonHeist` failed to resolve the
  products; `Package.swift` and the spike name it explicitly.
- Taps took 180–310 ms on the device, typing six letters 520–660 ms, a drag 720–760 ms. A tap
  that closes a sheet returns before the sheet has gone; a scene needs a `waitFor` after it.
