# TODO

Working notes: what's been verified, what's unknown, and what to test before it's relied on. Not
user-facing; the README and docs/cli.md describe Retake as it will be. Requests for The Button
Heist are in [ASKS.md](ASKS.md).

## Verified

Tested 2026-10-23 on an iPad Pro 11-inch (3rd generation, iPad13,4) on iOS 26.6.2, from a Mac on
Xcode 27.1, with a throwaway SwiftUI app that has no reference to The Button Heist.

- **Injection works.** TheInsideJob and its eight dependency frameworks, built Debug for iOS
  devices from The Button Heist's main (`9e56a7dc`, reports `0.6.38`), were copied into the app's
  `Frameworks/`, the app re-signed with a development identity and a wildcard team profile, and
  launched with `DYLD_INSERT_LIBRARIES=@executable_path/Frameworks/TheInsideJob.framework/TheInsideJob`.
  dyld loaded all nine, TheInsideJob started itself (ThePlant's `+load`), and the `buttonheist`
  CLI connected over the USB tunnel, read the interface, and drove it with `activate` and
  `oneFingerTap`. No change to the app's executable was needed.
- **In-memory `UserDefaults.standard` works**, through a second injected library (Objective-C) that
  replaces `+[NSUserDefaults standardUserDefaults]` with a subclass overriding the reads, typed
  getters, writes, `registerDefaults:` and KVO registration. Checked from the app:
  - seeded values reach `@AppStorage` and `bool(forKey:)`/`integer(forKey:)`/`string(forKey:)`;
  - `register(defaults:)` still applies beneath them, including after a seeded key is removed;
  - writes through `@AppStorage` and direct `set(_:forKey:)` both update `@AppStorage` views;
  - `UserDefaults.didChangeNotification` posts on each write;
  - nothing persists: relaunched without it, the app sees its real stored values.
- **TheInsideJob builds as one framework from SwiftPM, with no Tuist.** A wrapper package with a
  `type: .dynamic` library product depending on The Button Heist's `TheInsideJob` product, built
  with `xcodebuild build -scheme RetakeInsideJob -configuration Debug -destination
  'generic/platform=iOS'`, gives a single `RetakeInsideJob.framework` (29 MB, unstripped Debug)
  holding TheInsideJob and every dependency, linking only system libraries, with ThePlant's `+load`
  kept. Injected alone, it started the server and took synthetic taps. This is how The Button
  Heist says apps consume it (its SwiftPM products are its public integration surface, in
  `docs/API.md`); Tuist is only for developing The Button Heist itself. It also needed none of the
  overrides its Tuist project needs on Xcode 27.1.
  - **SwiftPM resource bundles must go inside the framework.** AccessibilitySnapshotBH's Core and
    Model targets have resources, built as `AccessibilitySnapshotBH_*.bundle` beside the framework.
    Left out, the app crashes at launch (`unable to find bundle named …`); copied into
    `RetakeInsideJob.framework/`, where `Bundle.module` looks for a package linked into a
    framework, it works. The build script must collect every `*.bundle` the build makes.
- **Movie metadata.** Custom QuickTime metadata (`AVMetadataKeySpace.quickTimeMetadata`, keys like
  `retake.app.version`) survives `AVAssetWriter` to `.mov` and `AVAssetExportSession` to a ProRes
  `.mov`, and reads back through AVFoundation and `ffprobe`; Spotlight indexes
  `com.apple.quicktime.software` as the encoding application. `AVAssetWriter` to `.mp4` silently
  drops all of it, and iTunes-style items too. What survives in `.mp4` is the common identifiers
  `commonIdentifierSoftware` and `commonIdentifierDescription`, written as ISO user data
  (`uiso/swre`, `uiso/dscp`): AVFoundation reads them; `ffprobe` doesn't show them.
- **A set's `state` works for files: `clean`, `cloned` and `live`.** Tested with a third injected
  library (Objective-C) that builds the take's home in its constructor, at
  `<container>/tmp/RetakeTakes/<take>/`, and redirects the app to it by setting `HOME`,
  `CFFIXED_USER_HOME` and `TMPDIR`, with nothing swizzled. The set's files were staged by the Mac,
  with `devicectl device copy to`, in `<container>/tmp/RetakeSet/`. A sample app on a fresh
  install, with a real note and a 200 MB file in its real Documents, ran `live`, `cloned`, `clean`,
  `live`:
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
- **The capture device's identity isn't the UDID** (`28B5A844-…` against `00008103-…`), and its
  name is the device's, curly apostrophe and `(2)` suffix included. Hence device aliases holding
  both.
- **The Button Heist's handshake needs exactly equal versions**
  (`TheScore/Wire/ClientMessages.swift`), and `ping`'s `PongPayload` reports only the version
  string: main and the `v0.6.38` tag both report `0.6.38`, with different command sets
  (`191a6a85` folded `one_finger_tap` and the rest into `action`). Main moves the wire format between
  releases too: `5ab16a57` (#1476) added a required `source` field to the interface snapshot
  element, decoded strictly, so a client from `9e56a7dc` and a server from `d6257101`, both
  reporting `0.6.38`, would pass the handshake and then fail to read the interface. Pinning by
  commit, and building both sides from it, is what keeps them matched.

- **Proof of concept 1: The Button Heist's client library drives the app from Retake's own process
  (2026-10-24).** A small macOS program linked against the `ButtonHeist` and `TheScore` products at
  `d6257101`, by a SwiftPM path dependency, drove the test app on the iPad with TheInsideJob
  injected from the same commit. Everything Retake needs worked, with no command-line tool:
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

- **Proof of concept 4: `aspect` from an injected library, and turning the device (2026-10-24).**
  A fourth injected library (Objective-C, 70 KB) clamps every app window's frame in
  `-[UIWindow setFrame:]`, rechecked in `-layoutSubviews`, to a shape per orientation, leaving the
  keyboard's and other system windows alone. Same iPad, test app showing its own geometry:
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

- **Proof of concept 3: recording an iPhone (2026-10-24).** An iPhone 17e (`iPhone18,5`) on iOS 27.0,
  wired, with the test app and TheInsideJob from `d6257101` injected, driven by `spikes/client` and
  recorded by `spikes/recorder`:
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
    which (see `device settings appearance` below).
  - **Only devices connected by USB are offered for capture**: with the iPad on the network, the
    phone was the only capture device.
- **Proof of concept 2: end to end in a real app (2026-10-24).** A shipping SwiftUI app with a
  dozen of its own dynamic frameworks, Firebase, RevenueCat and a keychain library, built Debug at
  `-O` by its own side-load script, with an embed step (`spikes/scripts/embed.sh`) added between its
  build and its install. iPad Pro 11-inch (3rd generation), iOS 26.6.2, The Button Heist `d6257101`.
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

## Proofs of concept before building

Each could still change Retake's shape, so they come before the real code.

1. [x] **Linking The Button Heist's client into Retake.** Done; see Verified. One scene played from a small Swift
       program linked against the `ButtonHeist` library at the pinned commit: connecting to the
       app over the USB tunnel, running actions, reading the interface. If its public API doesn't
       cover what Retake needs in-process, Retake drives the prebuilt command-line tool instead,
       which changes how it's built and shipped.
2. [x] **End to end in a real app.** Done; see Verified. A large app with many frameworks, built and installed by its
       own side-load script with `retake embed` added, launched in `clean` state, playing one
       scene. Shows whether the support library's constructor runs before anything in the app
       reaches `UserDefaults` or its home directory, how the launch check reports, and whether the
       app uses app groups, Core Data or `CFPreferences` in ways `state` doesn't cover yet. If the
       app group question comes back yes for anything a preview shows, app groups become v1.
3. [x] **Recording an iPhone.** Done; see Verified. Everything so far ran on an iPad: the clean status bar, the
       capture identity, the frame rate, and drops.
4. [x] **`aspect` from the injected library, and turning the device with `devicectl`.** Done; see
       Verified. Left open below: the hidden switch, alerts. Both
       decide what shape the app is laid out at and how the edit crops it, so they're tested
       together:
       - Sizing the app's window to 3:4 at the top of an iPad's screen, with no app code: that
         SwiftUI and UIKit lay out in the window's size, the safe area drops the home indicator's
         inset, size classes stay right, sheets and alerts stay inside the window, and touches by
         point still land. If a window can't be resized this way, `aspect` falls back to a
         documented launch flag the app reads.
       - `devicectl device orientation set` mid-take, as a scene step (`{ "orientation":
         "landscape-left" }`): whether it turns the app with no hand on the device, how soon, and
         whether the step log can time it. If it works, a landscape layout is the app's real one,
         and the edit's **turn** effect animates between the two, rather than an `aspect` step
         faking a landscape band inside a portrait screen. Keep the `aspect` step only if this
         doesn't work.
       - The recording across the turn: the captured frames change shape when the device turns, so
         whether the recorder keeps one file through the change, and how the edit's crop follows.
       - `aspect` in landscape: a 4:3 window on a screen wider than 4:3, pinned to one side, so
         `aspect` may need a value per orientation, and the crop an anchor to match.
       - The window and the turn together: that a resized window follows the rotation, rather than
         keeping its portrait frame on a landscape screen.

## To test

### Injection and install

- [ ] On an iPhone, and on the oldest iOS Retake will support.
- [ ] An app with extensions, and with entitlements a wildcard profile can't carry (app groups,
      push, iCloud, associated domains): re-signing must keep them, with the app's own profile.
- [ ] Apps signed with Xcode-managed (automatic) profiles: reuse `embedded.mobileprovision` as is.
- [ ] Refusing apps that link TheInsideJob already, statically and as a framework: detection by
      framework and by symbol in the executable and `*.debug.dylib`, with no false positives from
      the app merely depending on other Button Heist modules.
- [ ] `retake embed` in place, then installing with `devicectl` directly: that the app launches
      normally from the home screen with nothing loaded, and records when Retake launches it.
- [ ] Embedding twice, and embedding over another Retake version's embed: finding and replacing
      what the earlier one added (by the `Retake` `Info.plist` dictionary) and re-signing cleanly.
- [ ] Adding to `Info.plist` after the build: re-signing seals it again, and nothing else
      (asset catalogs, app extensions' own plists) needs to agree.
- [ ] The launch check: how the support library reports in, with its contract version and the
      embedded Button Heist commit, before the first step (a value read through The Button Heist,
      or a file written to the take's home that `devicectl` copies back), so `record` can fail
      clearly when the installed app wasn't embedded or was embedded by an incompatible Retake.
      Embedding the commit into the support library at build time, from the same pin.
- [ ] Whether `doctor` can read the installed app's `Info.plist` `Retake` dictionary over
      `devicectl` without launching it, or must launch it.
- [ ] `install --scheme` against plain projects and workspaces, and `build.command` with a
      generated one (Tuist, XcodeGen).
- [ ] Finding the `.app` from `xcodebuild -showBuildSettings` (`TARGET_BUILD_DIR`,
      `FULL_PRODUCT_NAME`) with build products under `output/build/`, including schemes that
      build several apps.
- [ ] A development-signed Release-configuration build: that injection works (dyld honoring
      `DYLD_INSERT_LIBRARIES` depends on the signing, not the configuration).
- [ ] The errors `xcodebuild` and `codesign` give for an unregistered device, so `install` can
      recognize them and fail (3) naming the UDID; and that `-allowProvisioningUpdates` registers
      it when asked.

### Building TheInsideJob

- [ ] The wrapper depending on The Button Heist by URL at a `revision:`, rather than a local path,
      as Retake will. The tested commit, `9e56a7dc`, is on the public repository's main.
- [ ] `RETAKE_BUTTONHEIST_PATH` switching both manifests to `.package(path:)`: what it does to
      `Package.resolved` when switched on and off (it shouldn't leave a local path committed), and
      recording the clone's commit and dirty state at build time for `retake version` and take
      metadata. CI and the release build fail when it's set.
- [ ] Stripping the framework for release, and whether a stripped Debug build still starts.
- [ ] The licenses of everything the framework contains (The Button Heist is Apache 2.0;
      AccessibilitySnapshotBH to check), for the release.

### Linking The Button Heist's client

- [x] Its API covers what Retake needs in-process, through `@_spi(ButtonHeistTooling)`. See
      Verified.
- [x] An app whose TheInsideJob differs but reports the same version: commands run, replies don't
      decode. See Verified.
- [ ] Pinning a `revision:` in Package.swift, and moving the pin forward, for tracking main.
- [ ] Tap by point, `activate`, and long press, which the proof of concept didn't send.
- [ ] Recording timing: placing each step's start and end on the movie's clock from the device's
      own `elapsedMs`, measured from when Retake sent it, rather than from replies that arrive
      about 100 ms late.
- [ ] Whether a failed decode drops the connection: after each, the client reconnected before the
      next command, though the proof of concept asked for no automatic reconnect.
- [ ] Building Retake with the SPI import in release mode, and whether SwiftPM resolves The Button
      Heist by URL at a `revision:` for a library product with `@_spi` use.

### In-memory defaults

- [ ] Which of KVO and `didChangeNotification` `@AppStorage` relies on, by turning each off.
- [ ] Suites, `UserDefaults(suiteName:)`, including app groups.
- [ ] Values JSON can't express — `Data`, `Date` — in a set's `defaults`: a typed encoding, or a
      plist alongside the set.
- [ ] Delivering the values by a file copied into the container rather than an environment
      variable, for size and types.
- [ ] Order: that the library's constructor always runs before anything in the app or its
      frameworks reaches `UserDefaults.standard`, including other frameworks' `+load`.
- [ ] Code calling `CFPreferences` directly, and Foundation's own reads (`AppleLanguages`), which
      should keep reading the real defaults.

### Sets

- [ ] Copying into app group containers with `devicectl`.
- [ ] Copying into `Library/Preferences` while `defaults` isn't used: whether `cfprefsd` serves a
      cached copy instead.

### A set's `state`: `clean`, `cloned`, `live`

A take gets its own copy of the app's data, built in the container at launch by the injected
library and pointed to in place of the real one, so recording never changes the app's real data:
empty plus the set's files (`clean`), or a clone of the real data with the set's files on top
(`cloned`). `live` uses the real data, and keeps the take's changes. The README documents `clean`
(the default) and `live`; `cloned` works for files (tested above) but is dropped from v1, since its
defaults half is untested and no preview needs it. `state` replaces the earlier `reset` field.

- [ ] App group containers: redirecting `containerURL(forSecurityApplicationGroupIdentifier:)` to
      a per-take copy of each group's container, alongside suites in the in-memory defaults. Where
      the copy can live, since a group container is shared with the app's extensions, which aren't
      launched with the injected library.
- [ ] Core Data, and SQLite opened before the first take's library runs, on the redirected paths.
- [ ] (If `cloned` returns.) Space: confirm on a nearly full device that a `cloned` take of a large container takes no
      real space until written (its speed says it's a clone, but space wasn't measured).
- [ ] Anything that resolves the home directory before the library's constructor runs (another
      injected library's or framework's initializer) keeps the real path. Check the order holds
      with TheInsideJob and the defaults library both injected, and in an app with many frameworks.
- [ ] `live` mode for defaults: writing the set's `defaults` into the real defaults at launch.
- [ ] (If `cloned` returns.) `cloned` mode for defaults: copying the app's real defaults into the in-memory store before
      replacing `UserDefaults.standard`. (A cloned `Library/Preferences` plist does nothing:
      `cfprefsd` reads the real container's.)
- [ ] Where the take's home lives. `tmp/RetakeTakes/` worked; iOS can purge `tmp` while the app
      isn't running, which is harmless between takes but worth knowing.

### Recording

- [ ] That the device's screen-capture identity is stable across reconnects and restarts, since
      aliases store it.
- [ ] The camera permission prompt, if any, for a mise-installed `retake` recording a
      device, and how it's attributed (the terminal, or `retake`).
- [ ] The clean status bar on iPad, and from `recordsLaunch`.
- [ ] Takes of one device type on two models with different screen sizes: warn, or refuse.

### `aspect` and orientation

- [ ] Alerts inside a resized window: the proof of concept's alert step didn't run (it came right
      after a sheet closed, and its target wasn't found), so whether alerts stay inside is unknown.
- [ ] An `orientation` scene step: `devicectl device orientation set`, then waiting until the app's
      window has turned, logged in the step log with the moment the captured frames change shape.
- [ ] The `aspect` step is dropped from the docs in favour of real turns; bring it back only if a
      case needs a shape change without turning, with a switch The Button Heist can see.
- [ ] `turns` (`letterboxed`, `device`) and `turnBlur` in the editor, from the step log's shape
      changes; `spikes/edit/render-turns.sh` is the ffmpeg stand-in.
- [ ] A scene's starting `orientation`, set before launch, and an `orientation` step's end: when
      the app's window has turned, not The Button Heist's `.screenChanged`.
- [ ] Turning the right way: which quarter turn each landscape orientation needs in the file, and
      in the edit, so the footage's rotation reads as the device turning.
- [ ] `aspect` with apps that read `UIScreen.main.bounds`, with UIKit apps, and with multiple windows.
- [ ] Restoring the device's orientation after a take, and what `orientation set` leaves behind
      (the device reported `faceUp` before the test).

### `devicectl` in Xcode 27.1

It has device commands Retake was going to work around. Each needs trying on a device before the
README's "things a set can't control" changes:

- [ ] `device simulate statusBar`: an explicit status bar, rather than relying on capture cleaning it.
- [ ] `device orientation set` / `rotate`: see proof of concept 4.
- [ ] `device settings appearance`: light and dark, as set fields.
- [ ] `device simulate location`: a location, as a set field.
- [ ] `device capture screen-record`: whether it records sound, at full frame rate, for long enough,
      and without the step-clock alignment the CoreMediaIO recorder gives. Likely not a
      replacement, but worth knowing.
- [ ] `devicectl` can copy files to and from an app's container but not delete them.

### Editing

- [ ] That App Store Connect accepts an `.mp4` with a description and software field, and what of
      it survives into the preview it serves (it re-encodes uploads). Nothing in it is private, but
      it shows the app's build.
- [ ] App Store Connect's current preview requirements per device type: sizes, frame
      rate, length (15–30 s), file size, codecs.
- [ ] Anchors on real retakes, and across iPhone and iPad: whether `offset` and `fraction` between
      steps and `waitFor`s reproduce what a hand-made per-device retiming did, with no visual
      detection (such as a sheet's arrival found by luminance).
- [ ] `conform` turning plain seconds into anchors: picking the latest step at or before each time
      gives readable anchors, or whether the nearest edge (start or end, either side) is better.
- [ ] Per-device overrides: which fields may be overridden (any clip field, top-level fields), and
      how an override of a nested object merges (replace or merge).
- [ ] Element snapshots in the step log: the cost of fetching the interface after each step (it
      runs during the step's hold, but could cause hitches in what's recorded), its size per take,
      and matching a spotlight's or blur's label when several elements share it (an index, or
      traits, as steps disambiguate).
- [ ] `waitFor`: what The Button Heist offers for waiting on an element (a wait command, or
      polling the interface), and how precisely the step log can time the element's arrival.

### Schemas and validation

- [ ] Generating JSON Schema (2020-12) from the Swift `Codable` types: a small generator of our own
      over descriptor types (as The Button Heist does for its commands), or a library such as
      swift-json-schema's macros. It has to carry descriptions, defaults, ranges (`fraction`'s -1
      to 1), `oneOf` for steps and anchors' `offset`-or-`fraction`, and `additionalProperties:
      false` everywhere.
- [ ] Per-device overrides (`"ipad": { … }` in a clip or at the top of an edit) in the schema:
      a partial of the same object, which needs the generator to emit an all-optional copy.
- [ ] Strict decoding that matches the schema: unknown keys rejected, and errors that give the
      JSON path (`clips[3].from.fraction`), not `DecodingError`'s coding-path dump.
- [ ] Generating `docs/reference/*.md` from the schemas, and the test that fails when the
      checked-in schemas or reference drift from the types.
- [ ] A test that validates every JSON block in `README.md` and `docs/` against the schemas
      (fenced blocks that are fragments, such as `"spotlight": …`, need a marker saying what they
      are a part of, or to be skipped).
- [ ] Editor support: that VS Code completes, describes and marks errors from a remote
      `"$schema"` URL, and from a local path for offline use; what Xcode's JSON editing does (likely
      nothing).
- [ ] `retake validate` with takes: resolving anchors and element snapshots without rendering, and
      how fast it is on a project with many takes.
- [ ] `conform` rewriting an edit without reordering its keys or reformatting it, so its diff is
      only the change.

## Decisions to make

- [x] The GitHub repository: `justinseanmartin/Retake`, public, for mise's `github:` backend (and a
      Homebrew tap later).
- [x] License: Apache 2.0, as The Button Heist is.
- [ ] Where the schemas are hosted, at a URL naming the version (a GitHub Pages site, or the
      release's assets, if editors follow their redirects), and the URL's form.
- [ ] Whether `$schema` is required in a file, or only written by `init` and `conform`.
- [ ] Add `.xcode-version` (Xcode 27.1, the version tested so far), and have the release workflow
      select exactly that version and fail without it. Locally it stays advisory.
- [ ] The metadata keys' namespace. QuickTime convention is reverse DNS (`com.example.retake.*`);
      the docs use a bare `retake.*` until there's a domain or organization to name.
- [ ] Developer ID signing and notarization for the direct download (no Developer ID certificate is
      set up yet).
- [ ] mise's `github:` backend with the release tarball's layout (`bin/`, `share/`).
