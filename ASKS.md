# Asks for The Button Heist

Requests for The Button Heist, collected while building Retake, to share with its author. Each says
what would help, why, and what we found; the suggestions are only suggestions.

**Where they stand (2026-10-26).** Shared with the maintainer, who answered all but the last in
0.7.0 and 0.7.1 (released 2026-10-24 and 2026-10-26). Retake now pins the 0.7.1 release; what it
changes for Retake is in [the proofs of concept](docs/records/2026-10-26-proofs-of-concept.md),
under "Proof of concept 1 again".

| Ask | Status |
| --- | --- |
| [1. A version that changes when the contract does](#1-a-version-that-changes-when-the-contract-does) | Done: contract hashes between releases (#1479, #1485). |
| [2. Published Debug device frameworks per release](#2-published-debug-device-frameworks-per-release) | Done: `theinsidejob-<version>.zip` (#1478). |
| [3. Injection as a supported way to use TheInsideJob](#3-injection-as-a-supported-way-to-use-theinsidejob) | Done: documented and covered by CI (#1478, #1483). |
| [4. Building The Button Heist's Tuist project on Xcode 27.1](#4-building-the-button-heists-tuist-project-on-xcode-271) | Done (#1481). |
| [5. A public way to drive an app from Swift](#5-a-public-way-to-drive-an-app-from-swift) | Done: `ButtonHeist.withSession` (#1483). |
| [6. Two connection details found along the way](#6-two-connection-details-found-along-the-way) | Both fixed (#1480). |
| [7. Optional: a build stamp in the binary](#7-optional-a-build-stamp-in-the-binary) | Open, and needed less now that (1) is done. |

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
app both report `0.6.38` and pass the handshake. Then every reply fails to decode ("Failed to
decode server message"), yet the app still carries out each command: in our test, three taps the
client never saw succeed all landed. A tool that doesn't check for itself plays its whole script
blind.

A version that changes with the contract makes incompatible builds refuse each other at the
handshake, for every client, however the app was built: linked from source through SwiftPM, a
local checkout, a vendored framework, or injected.

**Done** in #1479 and #1485. Builds between releases report the release with a 12-character
contract hash (`0.7.1-d53fb59edbf3`), CI requires the hash to change with the commands or the wire
format, and a mismatch is refused at the handshake with `protocolMismatch` before any command runs.

## 2. Published Debug device frameworks per release

**Ask.** Publish TheInsideJob, built Debug for iOS devices, with each release, next to the CLI and
MCP tarballs: for example `theinsidejob-<version>-iphoneos-debug.zip`, holding one dynamic
framework with its dependencies and resource bundles inside.

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

**Why.** It needs nothing from the app's project, so TheInsideJob can't reach an App Store build
by accident. Tested on iOS 26.6.2: the injected framework started itself, took the port and token
from `INSIDEJOB_PORT` and `INSIDEJOB_TOKEN`, and drove the app over the USB tunnel, including
synthetic touches.

**Done** in #1478 and #1483. `docs/PREBUILT-IOS.md`, "Inject into a development app", documents
the steps Retake takes, and the integration CI covers an unlinked host, injection at launch, and
the public Swift client.

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
  `fda8:…::1`) was rejected as "network connections are not allowed"; it took `network` in the scope.
  If `usb` is meant to admit it, that looks like a bug; if not, the docs could say so.
- **A direct address works only from a config file.** `EnvironmentConfig.resolve(deviceFilter:)`
  takes `[address]:port` as a direct target only for loopback; anything else becomes a discovery
  query and fails with "No devices found". A config file's target with the same address connects.
  A public way to pass a direct target and token would save writing a temporary config file.

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
else's script, or linking The Button Heist from a local checkout or a vendored framework. For an
app that pins it as a Swift package, the commit in `Package.resolved` is enough. Today the
framework's `Info.plist` has a generic `1.0` (`1`), and a static link leaves no framework at all.

**Open.** The release bundle's `VERSION` file names the version, but nothing in the framework
itself does. With (1) done, the version the handshake reports is precise enough for Retake's
compatibility check, so this matters only for records of builds made outside a release.
