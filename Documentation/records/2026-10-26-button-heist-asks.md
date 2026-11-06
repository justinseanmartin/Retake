# Asks for The Button Heist

Status: **open** (2026-10-27). Requests for The Button Heist, collected while building Retake's
proofs of concept and shared with its maintainer, who answered all but the seventh in 0.7.0 and
0.7.1 (released 2026-10-24 and 2026-10-26); the seventh was closed without being sent, as Retake
doesn't need it. Each says what would help, why, and what we found. Retake relies on what they
changed (a version that names the contract, refusing a mismatch at the handshake, injection as a
supported way to use TheInsideJob, and a public Swift client), so this record is where to start if
any of it changes. Retake now pins the 0.7.1 release; what that showed is in
[the proofs of concept](2026-10-26-proofs-of-concept.md), under "Proof of concept 1 again".

Building on 0.7.1 then turned up three more, in [Asks for after 0.7.1](#asks-for-after-071): what Retake does through The
Button Heist's tooling SPI, or works around, because the public client doesn't offer it yet. None is
sent yet.

| Ask | Status |
| --- | --- |
| [1. A version that changes when the contract does](#1-a-version-that-changes-when-the-contract-does) | Done: contract hashes between releases (#1479, #1485). |
| [2. Published Debug device frameworks per release](#2-published-debug-device-frameworks-per-release) | Done: `theinsidejob-<version>.zip` (#1478). |
| [3. Injection as a supported way to use TheInsideJob](#3-injection-as-a-supported-way-to-use-theinsidejob) | Done: documented and covered by CI (#1478, #1483). |
| [4. Building The Button Heist's Tuist project on Xcode 27.1](#4-building-the-button-heists-tuist-project-on-xcode-271) | Done (#1481). |
| [5. A public way to drive an app from Swift](#5-a-public-way-to-drive-an-app-from-swift) | Done: `ButtonHeist.withSession` (#1483). |
| [6. Two connection details found along the way](#6-two-connection-details-found-along-the-way) | Both fixed (#1480). |
| [7. Optional: a build stamp in the binary](#7-optional-a-build-stamp-in-the-binary) | Closed, not sent: Retake doesn't need it. |
| [8. Timed drags in a plan](#8-timed-drags-in-a-plan) | Open, not sent. Retake uses the tooling SPI meanwhile. |
| [9. A public failure code for a thrown error](#9-a-public-failure-code-for-a-thrown-error) | Open, not sent. Retake reads `FenceError`'s cases meanwhile. |
| [10. The screen's size, or a turn, through the public client](#10-the-screens-size-or-a-turn-through-the-public-client) | Open, not sent. Retake watches element frames meanwhile. |
| [11. A touch on an app's own sheet, on iOS 27](#11-a-touch-on-an-apps-own-sheet-on-ios-27) | Open, not sent. Found 2026-10-27; not yet narrowed down. |

**Context.** Retake records App Store preview videos by driving an app with The Button Heist on a
USB-connected device. Rather than asking apps to link TheInsideJob, Retake builds it as one Debug
framework (through The Button Heist's SwiftPM `TheInsideJob` product, wrapped in a dynamic library
product) and injects it into the app at launch with `DYLD_INSERT_LIBRARIES`. ThePlant's `+load`
auto-start is what makes that work with no app code. Retake links the `ButtonHeist` client library,
and pins one Button Heist commit, currently on main. Everything below was found against main,
`9e56a7dc` to `d6257101`, on Xcode 27.1 and iOS 26.6.2.

## 1. A version that changes when the contract does

**Ask.** Change the reported version whenever the commands or the wire format change, not only at
release: a pre-release version on main (`0.6.39-dev.3`), or a protocol revision, bumped with each
breaking change, that the handshake also compares.

**Why.** A client and an app must run the same Button Heist, and today the handshake can't tell
whether they do between releases: main reports `0.6.38`, like the `v0.6.38` tag, while its commands
(`191a6a85` folded `one_finger_tap` and the rest into `action`) and wire format (`5ab16a57` added a
required `source` field to interface elements) have changed. A `9e56a7dc` client and a `d6257101`
app both report `0.6.38` and pass the handshake. Then every reply fails to decode ("Failed to decode
server message"), yet the app still carries out each command: in our test, three taps the client
never saw succeed all landed. A tool that doesn't check for itself plays its whole script blind.

A version that changes with the contract makes incompatible builds refuse each other at the
handshake, for every client, however the app was built: linked from source through SwiftPM, a local
checkout, a vendored framework, or injected.

**Done** in #1479 and #1485. Builds between releases report the release with a 12-character contract
hash (`0.7.1-d53fb59edbf3`), CI requires the hash to change with the commands or the wire format,
and a mismatch is refused at the handshake with `protocolMismatch` before any command runs.

## 2. Published Debug device frameworks per release

**Ask.** Publish TheInsideJob, built Debug for iOS devices, with each release, next to the CLI and
MCP tarballs: for example `theinsidejob-<version>-iphoneos-debug.zip`, holding one dynamic framework
with its dependencies and resource bundles inside.

**Why.** Retake, and anyone injecting TheInsideJob rather than linking it, could download the
framework for a version instead of building The Button Heist. Building from source would then be
needed only to work on The Button Heist itself.

**What we found building it.** The SwiftPM route works with no Tuist: a package with one target
depending on the `TheInsideJob` product, and a `type: .dynamic` library product, built with
`xcodebuild build -configuration Debug -destination 'generic/platform=iOS'`, gives one
self-contained framework (29 MB, unstripped) that links only system libraries, with ThePlant's
`+load` kept. AccessibilitySnapshotBH's Core and Model targets have SwiftPM resources, built as
`AccessibilitySnapshotBH_*.bundle` beside the framework; the app crashes at launch without them
(`unable to find bundle named AccessibilitySnapshotBH_AccessibilitySnapshotModel`), and works with
them copied inside the framework.

**Done** in #1478. Each release publishes `theinsidejob-<version>.zip`, with its checksum in
`checksums.txt`: one `TheInsideJob.xcframework` with device and simulator slices, its dependencies
linked statically, the resource bundles inside, licenses, and `VERSION` and `XCODE_VERSION` files.
Builds between releases have no published bundle.

## 3. Injection as a supported way to use TheInsideJob

**Ask.** Treat loading TheInsideJob into an unmodified Debug app with `DYLD_INSERT_LIBRARIES` as a
supported way to use it, alongside linking it: keep the `+load` auto-start, and the `INSIDEJOB_*`
environment configuration it relies on, working for an injected copy.

**Why.** It needs nothing from the app's project, so TheInsideJob can't reach an App Store build by
accident. Tested on iOS 26.6.2: the injected framework started itself, took the port and token from
`INSIDEJOB_PORT` and `INSIDEJOB_TOKEN`, and drove the app over the USB tunnel, including synthetic
touches.

**Done** in #1478 and #1483. `docs/PREBUILT-IOS.md`, "Inject into a development app", documents the
steps Retake takes, and the integration CI covers an unlinked host, injection at launch, and the
public Swift client.

## 4. Building The Button Heist's Tuist project on Xcode 27.1

**Ask.** Make the Tuist project build on Xcode 27.1 without overrides.

**What we found.** Building the `TheInsideJob` scheme failed twice, and succeeded with overrides on
the command line:

- AccessibilitySnapshotBH's targets have `IPHONEOS_DEPLOYMENT_TARGET` 13.0, below Xcode 27.1's
  supported 15.0 (fixed with `IPHONEOS_DEPLOYMENT_TARGET=16.0`).
- `ButtonHeistSupport/TimedOneShot.swift:107` uses `withCheckedContinuation(isolation:function:_:)`,
  deprecated in favor of the `nonisolated(nonsending)` overload, and warnings are treated as errors
  (fixed with `SWIFT_TREAT_WARNINGS_AS_ERRORS=NO`).

The SwiftPM build (2) hit neither.

**Done** in #1481.

## 5. A public way to drive an app from Swift

**Ask.** Make the parts of `TheFence` that run commands public, or add a small public client API
over them: connect to a target, send an action or one DSL step, get the interface, and read typed
results.

**Why.** Retake drives apps from its own process with the `ButtonHeist` library, and found
everything it needs there: connecting is public, but running commands (`admit`, `execute`,
`FenceCommandInput`, `FenceResponse`) is `@_spi(ButtonHeistTooling)`, which The Button Heist's own
CLI imports. Retake uses that SPI for now, pinned to one commit. A public surface would let it
follow releases without depending on tooling SPI. The typed actions in `ThePlans`
(`HeistActionCommand`, `TapTarget`, `DragTarget`) are already public and worked well.

**Done** in #1483. `ButtonHeist.withSession(_:operation:)` connects once and disconnects on every
exit path; within it, `run` executes a plan (DSL or `HeistPlan`) and returns its `HeistResult` with
the device's timing, and `captureInterface()` reads the current screen without discovery scrolling.

## 6. Two connection details found along the way

- **The USB tunnel counts as a network connection.** With `INSIDEJOB_SCOPE=simulator,usb`, a
  connection from the Mac over a device's USB tunnel (`devicectl`'s tunnel address, such as
  `fda8:…::1`) was rejected as "network connections are not allowed"; it took `network` in the
  scope. If `usb` is meant to admit it, that looks like a bug; if not, the docs could say so.
- **A direct address works only from a config file.** `EnvironmentConfig.resolve(deviceFilter:)`
  takes `[address]:port` as a direct target only for loopback; anything else becomes a discovery
  query and fails with "No devices found". A config file's target with the same address connects. A
  public way to pass a direct target and token would save writing a temporary config file.

**Both fixed** in #1480. The default `simulator,usb` scope now admits the CoreDevice tunnel
(recognized by its address pair, which the code notes to revisit if CoreDevice's addressing
changes), and an explicit `host:port` or `[IPv6]:port` works as `deviceFilter`, `--device` or
`BUTTONHEIST_DEVICE`.

## 7. Optional: a build stamp in the binary

**Ask.** Embed the version and commit TheInsideJob was built from in the binary, where a tool can
read it without running the app, such as a fixed-prefix string in its own section:

```c
__attribute__((used, section("__TEXT,__bh_build")))
static const char buttonHeistBuild[] = "buttonheist-build:v1;version=0.6.38;commit=d6257101…;dirty=0";
```

**Why it's only a nice-to-have.** With (1), a tool can tell compatible builds apart. What a stamp
adds is the exact commit, for a tool's records, when nothing else says it: an app built by someone
else's script, or linking The Button Heist from a local checkout or a vendored framework. For an app
that pins it as a Swift package, the commit in `Package.resolved` is enough. Today the framework's
`Info.plist` has a generic `1.0` (`1`), and a static link leaves no framework at all.

**Closed, not sent.** The release bundle's `VERSION` file names the version, but nothing in the
framework itself does, not even its `Info.plist`. Retake wouldn't use it: a take records the version
the app reports at the handshake, which (1) made exact; `record` and `doctor` judge an installed
app's compatibility from the `Retake` dictionary `embed` writes into its `Info.plist`; and `check`
and `embed` need only whether TheInsideJob is there, not which. At most it would let a message say
which version an app links, which isn't worth asking another project for.

## Asks for after 0.7.1

Found while building `retake rehearse` (the v0.0.1 plan's commit 18), which plays a scene's steps
through 0.7.1's public Swift client: `ButtonHeist.withSession`, then one `heist.run(plan)` per step,
and `heist.captureInterface()` to read the screen. Retake's goal is to use only the public client,
so it can follow releases without depending on SPI that makes no compatibility promise. Where it
can't yet, it uses `@_spi(ButtonHeistTooling) import ButtonHeist` in one file,
`Sources/RetakeCore/Playing/ButtonHeistDriver.swift`, or works around the gap; each ask below names
which, and what dropping the workaround needs. Code paths are in The Button Heist 0.7.1.

## 8. Timed drags in a plan

**Ask.** Admit a drag's `duration` (and a swipe's) in a `HeistPlan`, so `heist.run` can play a drag
at a given speed; or offer a public way to send one direct action, outside a plan, with typed
results.

**Why.** A scene's `drag` has a `duration`, 0.5 s unless given (README, "Scenes"), and real scenes
use others: an app's own scenes drag a piece in 0.25 s and draw one in 0.8 s, so the drag on camera
matches how a person moves. In 0.7.1, a plan holding `.drag(DragTarget(…, duration:))` is refused at
admission: `HeistActionCommand.durableHeistActionFailure`
(`ThePlans/Model/HeistActionCommand+Durability.swift`) returns "drag duration … is not a durable
heist action" for any non-nil duration, and the same for swipes. The builder `drag(from:to:)` has no
duration at all. A drag with no duration plays at `DragTarget.defaultDuration`, 0.5 s.

**What Retake does meanwhile.** A drag at exactly 0.5 s goes in a plan, through the public client.
Any other duration is sent as a direct command through the tooling SPI: the typed
`HeistActionCommand.drag` is encoded to JSON, decoded as a `HeistValue`, and run with
`heist.execute(heist.admit(FenceCommandInput(command: .action, arguments:
CommandArgumentEnvelope(values: ["action": …]))))`, judging the `FenceResponse` by `isFailure`
(`ButtonHeistDriver.perform`). Checked on an iPad: a 0.8 s drag reordered the example's rows in 1.25
s of wall time. Dropping the SPI for this needs either change above.

## 9. A public failure code for a thrown error

**Ask.** A public way to get The Button Heist's `KnownFailureCode` and message for any error its
client throws: for example making `DiagnosticFailure.init(_ error: Error)` public, or a public
`failureDetails` on `FenceError`.

**Why.** Retake turns a client error into an exit status (Documentation/cli.md, "Exit status"): a
`protocol.mismatch` at connect stops with 3 and says to embed the app again; an unreachable server
(`connection.endpoint_unreachable`, `transport.*`) is retried for a few seconds, then is 3; an error
inside a step fails the step (1). The mapping from an error to its code exists, but isn't public:
`DiagnosticFailure.init(_:)` (`TheButtonHeist/TheFence/FenceResponseModels.swift`) is internal,
`FenceError.diagnosticFailure` (`TheFence+FailureTaxonomy.swift`) is internal, and
`FenceResponse.failure(_:)`, which uses it, is SPI. `HandoffConnectionError` is internal too, though
`start()` wraps it in a `FenceError`.

**What Retake does meanwhile.** It reads `FenceError`'s public cases itself
(`ButtonHeistDriver.classify`): `.diagnostic(failure)` carries a public `failure.details.code`;
`.authFailed`, `.notConnected`, `.actionTimeout` and `.sessionLocked` map to their codes; anything
else has no code and is reported by its `localizedDescription`. If a release adds a case or wraps
errors differently, Retake's mapping falls behind silently, which a public mapping would prevent.

## 10. The screen's size, or a turn, through the public client

**Ask.** Let a client know when the app's interface has turned: the screen's current bounds on
`Interface` (or in a public, refreshable `ServerInfo`), or `WaitFor(.screenChanged)`, or another
predicate, firing for a rotation.

**Why.** A scene's `orientation` step turns the device with `devicectl device orientation set`, and
"ends when the app has turned" (README), so the next step's points land on the turned layout.
`devicectl` returns in about 0.2 s, before the app has relaid out. Proof of concept 4 found that
`WaitFor(.screenChanged)` doesn't fire for a rotation. The server knows the screen's bounds
(`ScreenMetrics.current.bounds`, sent as `ServerInfo.screenWidth` and `screenHeight` at the
handshake), but `ServerInfo` reaches only the client's internal session state
(`HandoffConnectionLifecycle.serverInfo`), and isn't sent again after a turn. `devicectl` doesn't
report the screen's size in points either.

**What Retake does meanwhile.** After turning, it reads the screen with `captureInterface()` every
0.1 s until the elements' frames differ from before the turn and have settled, failing after 5 s
(`Player.turn`). A look has settled when nothing moved since the last, or only a third of the
elements at most, all of which were moving the look before too, as a looping animation does; and
something other than those must have moved since before the turn, so an animation alone doesn't pass
for one. On the iPad, turning the example to landscape and back ended in 0.76–1.31 s, once its
two-column layout had settled. It can be fooled by a screen whose elements don't move when it turns,
and costs a capture every 0.1 s; knowing the bounds would make it exact.

## 11. A touch on an app's own sheet, on iOS 27

**Ask.** Find out why a synthesized touch on a button in an app's own sheet closes the sheet,
instead of pressing the button, on an iPhone on iOS 27.2, and fix it if it's The Button Heist's.

**What we found.** Retake's example app presents a SwiftUI sheet of its own (`.sheet` with a
`.medium` detent) holding a "Send to Alex" button. On an iPhone 17e (`iPhone18,5`) on iOS 27.2, with
The Button Heist 0.7.1's framework injected, two seconds after the sheet was presented,
`captureInterface()` listed the button at frame (137, 585, 115×33), activation point (195, 601).
Then:

- a tap on the element (`TapTarget(selection: .element(.label("Send to Alex")))`) reported success,
  and the sheet closed, with the button's action never run;
- a tap by point at (195, 601), the button's own activation point, did the same;
- an accessibility activation of the element ran its action: the sheet showed "Sent".

The same scene's tap on the same button, after the sheet had settled, worked on an iPad Pro 11-inch
(3rd generation) on iOS 26.6.2. It did again the same day, the iPad restarted and the scene played
through `retake record --dry-run`. The sheet is the app's own, in its process, so it isn't the
out-of-process boundary `docs/SCOPE-AND-LIMITS.md` describes. A touch that closes a medium sheet is
what a touch outside it does, so the touch may be delivered to a window or view other than the one
the frame came from; whether it's iOS 27's sheets, or iPhone sheets, isn't known yet. An iPad on iOS
27 would tell them apart.

**What Retake does meanwhile.** Nothing: a scene tapping a button in a sheet on iOS 27 fails at the
step after it. `activate` presses the button, with no touch drawn, where a scene can do without the
touch.
