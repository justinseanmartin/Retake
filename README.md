# Retake

**App Store preview videos captured on real iOS devices and defined in JSON as sets, scenes and edits.**

Retake plays your app on a USB-connected iPhone or iPad while the Mac records its screen and sound,
then cuts the recordings into a finished preview with captions, touches, spotlights, cards,
transitions, sound and music. Everything that makes the video is a file kept with your code, so when
the app changes you record again and render the same edits: no screen recording by hand, no
timeline to rebuild, and no guessing which frames you used last time.

https://github.com/user-attachments/assets/416e4ecd-30a8-4cd1-bf05-2343f5dca131

Every frame of the video above is Retake's: [the example app](Examples/Notes),
recorded on an iPhone and an iPad, and cut for each from the one
[`showcase`](Examples/Notes/Retake/edits/showcase.json) edit, which turns the iPad and puts a card
in the iPhone's place.

Retake's commands and files use five words:

- A **[set](#sets-the-state-a-take-starts-from)** defines the app's state before recording: its
  files, user defaults, launch arguments and environment.
- A **[scene](#scenes-the-walk-through-the-app)** is a walk through the app, starting from a set,
  which Retake plays on the device and records.
- A **[take](#takes-footage-and-a-step-log)** is a scene's recording: the movie, with a log of its
  steps.
- An **[edit](#edits-the-video-cut-from-the-takes)** defines how takes are mixed into a finished
  video.
- A **cut** is that finished video, rendered from an edit's takes.

**How you use it.** [Install Retake](#install), then start your favorite coding agent in your app's
repository and ask it to integrate Retake. Describe the flows you want recorded, the state each one
starts from, and what each video should emphasize. The agent writes the sets, composes the scenes on
your device, records the takes, writes the edits and renders the cuts. Watch them, and keep asking
for changes to the scenes and edits until the video looks just how you want it.

Retake is made to be driven that way: an agent [composes a scene](#scenes-the-walk-through-the-app)
on the device a step at a time, told after each action what happened and what's on screen; every
file has a [schema](#schemas) that `retake validate` checks a project against; and the commands
that report something take `--json`.

**What sets it apart:**

- **Recorded on real hardware.** Anything that animates renders best on the device itself, and a
  simulator recording stutters where a preview needs to be smooth. Retake records at the rate the
  device sends its screen, and [warns of hitches](#takes-footage-and-a-step-log).
- **The same starting state, every take.** A scene's [set](#sets-the-state-a-take-starts-from) is
  put in place before the app launches, with nothing added to your project, so what changes between
  takes is the app, not its data.
- **Edits anchored to steps, not seconds.** An edit cuts at moments such as 0.2 s before a sheet
  appears, not at timestamps. When an animation that took 700 ms takes 950 ms in the next build, or
  on the iPad, the same edit still lines up; see [anchors](#anchors-times-that-follow-the-app).

**What it doesn't do yet.** The [effects](#what-a-clip-can-do) are limited: each takes a handful of
options, not full control of its style, and there are few kinds. Pull requests that add capability
are welcome, or fork it and go wild. And Retake isn't purpose built specifically for App Store
screenshots: a `capture` step saves stills from the same scenes, but at the device's own
resolution, which often isn't a size App Store Connect takes; see
[Captures](#captures-stills-from-the-same-scenes).

> **Status:** an early release, 0.0.1. Retake is an experiment in making a general tool of
> something built twice before, for two apps' App Store previews on iPhone and iPad, and it makes
> both of theirs.
>
> **Stability:** until 1.0, nothing is guaranteed to stay the same between versions: not the
> command line, not the JSON of its files, schemas or output. If you depend on it, pin an exact
> version, such as `mise use github:justinseanmartin/Retake@0.0.1`. What is promised is that every
> breaking change is spelled out in the release notes and comes with a new minor version, from 0.1
> to 0.2. Compatibility guarantees start at 1.0.

## Contents

- [How it works](#how-it-works)
- [Install](#install)
- [Quick start](#quick-start)
- [Your app](#your-app)
- [Sets: the state a take starts from](#sets-the-state-a-take-starts-from) ([`state`](#state-clean-cloned-or-live))
- [Scenes: the walk through the app](#scenes-the-walk-through-the-app)
- [Takes: footage and a step log](#takes-footage-and-a-step-log)
- [Captures: stills from the same scenes](#captures-stills-from-the-same-scenes)
- [Edits: the video cut from the takes](#edits-the-video-cut-from-the-takes)
- [What's recorded in each file](#whats-recorded-in-each-file)
- [Devices](#devices)
- [The Button Heist, and Retake's version pin](#the-button-heist-and-retakes-version-pin)
- [Project layout](#project-layout)
- [Building from source](#building-from-source)

The full command reference is [Documentation/cli.md](Documentation/cli.md), and every field of every file is in
[Documentation/reference](Documentation/reference/), generated from Retake's [schemas](#schemas).

## How it works

```
 set + scene ──retake record──▶ take (movie + step log) ──retake cut──▶ video.mp4
                                                          edit.json
```

1. **`retake install`** puts a Debug build of your app on a USB-connected device, with what Retake
   needs to drive it embedded in the build. Your project doesn't change. (If you install builds
   yourself, `retake embed` does just the embedding.)
2. **`retake record <scene>`** launches the app on the scene's set, plays its steps, and records the
   device's screen and sound. A recording that succeeds becomes the scene's take, and the take it
   replaces is kept as the previous one.
3. **`retake cut <edit>`** renders the edit from each scene's take, for every device type it names,
   to a ProRes master and an `.mp4` for App Store Connect.

## Install

Retake is a single command for macOS, released with everything it needs:

```sh
mise use github:justinseanmartin/Retake   # from GitHub Releases
```

Add `@<version>` to pin one, since nothing is guaranteed stable before 1.0 (see the status note
above).

**You need:**

- A Mac with Apple silicon, running macOS 14 or later.
- Xcode, for `devicectl` and `codesign`. Its version doesn't matter to Retake.
- A physical iPhone or iPad on iOS 17 or later, connected **by USB**. Devices over Wi-Fi can't be
  recorded.
- Camera and microphone access for the terminal you run `retake` in, which macOS asks for, in the
  terminal's name, the first time `record` runs from it: a device's screen and sound come to the Mac
  as a camera does.

> [!NOTE]
> **The iPhone Duo isn't supported yet.** Its folding screen gives it two sizes of screen, which
> scenes, aspects and edits don't yet tell apart. Support should be straightforward to add, but
> needs a physical iPhone Duo to test it on.

You don't need any other tools installed to use Retake. When a command fails and its message
doesn't say why, `retake doctor` checks each part of the setup in turn, to find which.

## Quick start

```sh
retake init                              # Retake/: retake.json and the folders below, output/ gitignored
retake devices add iphone                # name the connected device "iphone"
retake install --scheme MyApp            # build Debug, embed Retake, and install it
retake compose create-note               # write a scene a step at a time, on the device
retake record --dry-run create-note      # play a scene without recording it
retake record create-note share-note     # record takes
retake cut video1                        # render the video, for each device type
```

**The way to start is the example**, [`Examples/Notes`](Examples/Notes): a small notes app with no Retake code in
it, and its `Retake/` project, ready to run. Its sets start the app on a first launch and on a
returning user's notes; its scenes, for iPhone and iPad, walk through getting started, writing a
note, syncing and sharing it; and its edits cut them into a preview, `tour`, and into `showcase`,
the video above. From a fresh clone, with a device connected by USB, one script builds
Retake, signs the example with your team, and records and cuts it:

```sh
Examples/Notes/run.sh
```

[Examples/README.md](Examples/README.md) says what it does, step by step. By hand, once
`run.sh --setup` has signed it, from `Examples/Notes`:

```sh
retake install                           # builds the example, embeds Retake, installs it
retake record                            # records each scene, for the device's type
retake cut tour                          # renders it, for the device's type
```

Its integration test does all of that, from a copy of the project: `RETAKE_TEST_DEVICE=<device>
swift test --filter EndToEnd`.

## Your app

**Retake needs nothing from your app's code.** `retake install` takes a Debug build of it, adds The
Button Heist's in-app server (TheInsideJob) and Retake's own small support library into the app's
bundle, re-signs it with the identity and profile it was already signed with, and installs it. Both
are loaded only when Retake launches the app, through the launch environment; the app's own
executable is unchanged. Nothing is added to your project, so neither can reach an App Store build.

**If you build and install the app yourself**, with a script, fastlane, or CI, run `retake embed` on
the built `.app` before installing it:

```sh
retake embed build/Debug-iphoneos/MyApp.app
xcrun devicectl device install app --device "$UDID" build/Debug-iphoneos/MyApp.app
```

An embedded app behaves as it always does when opened from the home screen, so you can embed every
build you install for testing, and record with whichever one is on the device. Run `retake check` on release archives if a build you
embed in could ever be archived.

`install` can also run your own build command, from `retake.json`, when one `xcodebuild` call can't
build your app; see [`retake install`](Documentation/cli.md#retake-install).

**Your app shouldn't link TheInsideJob itself.** Retake always supplies its own, the exact version
it's built against (see [the version pin](#the-button-heist-and-retakes-version-pin)), and `embed` and `install` stop if the app already
contains one. If you link it for other tooling, leave it out of the builds you record with.

What you may want to add, Debug-only and optional, is **launch flags for content that varies.**
Anything that differs between takes or between viewers — prices by region, random picks, dates, a
signed-in account — is best fixed by a flag your app reads at launch, which a set turns on.

**The status bar takes care of itself.** While a Mac records an iOS device's screen, iOS shows a
clean status bar: 9:41, full signal, full battery.

**So does the preview's shape.** App Store previews have fixed shapes, which a device's screen
rarely matches: an iPad preview is 3:4. A set's [`previewAspect`](#previewaspect-the-previews-shape) lays the app out at the preview's
shape, with no code in the app.

## Sets: the state a take starts from

A set is everything that puts the app into a known state before a take: its data, its settings, and
its launch environment. A scene names its set, so every take of the scene starts the same way.

<!-- schema: set -->
```json
{
  "extends": "base",
  "state": "clean",
  "files": {
    "Documents/notes.sqlite": "data/returning-user/notes.sqlite",
    "Library/Application Support/Media/": "data/returning-user/media/"
  },
  "defaults": { "hasSeenOnboarding": true, "sortOrder": "recent" },
  "environment": { "MYAPP_REGION_NEUTRAL_PRICES": "1" },
  "arguments": ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"],
  "previewAspect": true
}
```

`files` are put in the app's data before launch, at the paths the app reads them from, so an app
that keeps its data in Documents or Application Support starts on a known state with no code at all.
Their sources are relative to `retake.json`; `..` can reach a fixture shared with the app project or
another Retake project, while absolute paths are rejected so the project stays portable.
`defaults` are what `UserDefaults.standard` holds at launch: strings, numbers, booleans, and lists
and dictionaries of them, as JSON has; a `Data` or `Date` value can't be given yet. Give defaults
this way, not as a plist in `files`: one copied into `Library/Preferences` isn't read. `environment`
and `arguments` are added to the launch, for your app's own Debug-only flags and for the language
and locale. `extends` builds on another set, so what every set shares is written once, and a flag
only one scene needs goes in a small set of its own that extends the one it builds on. `state` and
`previewAspect` are below, and every field is in the [set reference](Documentation/reference/set.md).

### `state`: clean, cloned or live

A set's `state` says what the app's data starts as for a take, and whether the take's changes are
kept. In the order to reach for them:

- **`clean`**, the default: the app's files and defaults start empty, apart from the set's `files`
  and `defaults`. A take depends only on the set, so it's the same on any device and any day, which
  is what previews need: one edit cuts every device's takes, and recording again reproduces the
  video.
- **`cloned`**: the app's files and defaults start as its real ones, with the set's on top, but what
  the take changes is thrown away. For a set that needs the app's real data, such as an account
  signed in by hand, without recording ever changing the data you use the app with. A take then
  depends on the device's data as well as the set, so takes on different devices, or on different
  days, can differ.
- **`live`**: the app's real files and defaults, with the set's written into them, and the take's
  changes are kept as the app's. Only for takes whose changes should persist, such as a sequence of
  takes that build on each other.

`clean` and `cloned` give each take its own copy of the app's data, so recording never changes the
data you use the app with.

**How it works.** At launch, before any of the app's code runs, Retake's support library builds the
take's home folder inside the app's container, puts the set's files in it, and points the app at it.
Every standard folder lookup follows: `NSHomeDirectory()`, `FileManager`'s Documents, Application
Support and Caches, `URL.documentsDirectory`, `NSTemporaryDirectory()`, and the databases and files
your code opens there, SQLite included. A `cloned` take's copy is a clone of the real files
(`clonefile`), which takes no time to make and no space until the take writes to it.

Each take's copy is deleted when the app next launches under Retake, and `record` launches it once
more at the end of a run to delete the last, so no copy is left on the device. `retake clean
--on-device` does the same on demand, after a run that was interrupted. Only the app itself can
delete files in its container, so both launch it in a mode that deletes them and quits before any of
the app's own code runs. iOS then opens the app again, as it would from the home screen, and Retake
closes it.

### Defaults in memory

In `clean` and `cloned`, Retake replaces `UserDefaults.standard` for the take with an in-memory
store. The app reads and writes it as it always does, through `UserDefaults` and `@AppStorage`;
nothing is written to the app's real defaults, and everything is gone when the app quits. In
`clean`, every take starts from exactly the set's values, whatever the last one changed. A clean
start still reads launch arguments (`-key value`, as a set's `arguments` may give) and the global
domain (such as `AppleLanguages`); only the app's own domain starts empty. In `cloned`, a key the
set doesn't give, and the take hasn't written or removed, reads through to the app's real defaults,
so the take sees them without copying them, and can't change them.

It behaves as the real defaults do in the ways an app notices: values the app registers with
`register(defaults:)` still apply beneath the set's; the typed getters (`bool(forKey:)`,
`integer(forKey:)` and so on) read the same values; and every write updates `@AppStorage` views and
key-value observers, and posts `UserDefaults.didChangeNotification`.

### What `state` doesn't cover yet

- **App group containers** (`containerURL(forSecurityApplicationGroupIdentifier:)`) and **defaults
  suites** (`UserDefaults(suiteName:)`) are the real ones in every state. A group's container is
  shared with the app's extensions, which Retake doesn't launch.
- **Code that calls `CFPreferences` directly** reads the real defaults, and so do system frameworks
  that keep their own state in the app's defaults, such as StoreKit's update timestamps.
- **The keychain** is the real one: iOS keeps it even across reinstalls. Keychain state needs a
  launch flag of the app's own.

### `previewAspect`: the preview's shape

With `"previewAspect": true`, Retake's support library sizes the app's window to the App Store
preview's shape for the device type being recorded, 886:1920 on an iPhone and 3:4 on an iPad, as
wide as the screen and pinned to its top, and the edit crops the band left below it. The app lays
itself out in its window as it always does, SwiftUI and UIKit alike: on an iPad it sees a 3:4
window, with the safe area of a window that doesn't reach the home indicator. Nothing in the app
needs to know. Without it, the app fills the screen, and the edit crops the screen evenly to the
preview's shape instead.

When a scene turns the device to landscape, the window takes the same shape turned (4:3 for 3:4),
pinned to the screen's left. The keyboard and the system's status bar and home indicator aren't the
app's window, so they still span the screen: a keyboard rises into the band the edit crops. A set
that extends another can turn `previewAspect` on or off for itself.

An app that sizes its layout from `UIScreen.main.bounds` rather than its window or its views'
geometry won't follow; one that reads the screen once at launch and then its geometry will.

### `appearance`: light or dark

`"appearance": "light"` (or `"dark"`) holds the app's windows to that appearance, whatever the device
is set to, so a take looks the same on any device. The launch screen is the system's, drawn before
the app runs, so it still follows the device: on a device in dark mode, a `light` take starts dark
and turns light as the app's first frame comes up.

### Things a set can't control

On a physical device, nothing outside the app can grant permissions in advance, change the clock, or
fill the photo library, and a scene can't answer a permission prompt either (see
[what a scene can't reach](#what-a-scene-cant-reach)). A permission granted by hand stays granted, whatever a set's `state`,
since iOS keeps it apart from the app's files and defaults; so grant what a scene needs once, before
recording.

## Scenes: the walk through the app

A scene is a set and the steps played on it. The way to write one is **`retake compose`**, on the
device: it launches the app on the set, shows what's on screen, and takes each step as an action
with named options, such as `tap --label "New Note"`, running it at once and adding it to the scene
when it runs, so a scene is only ever made of steps that worked. `undo` takes the last one back. An
agent can drive it just as well: `retake compose <scene> --json` reads actions a line each from
standard input and answers each with a line of JSON, saying what ran, what failed and why, and
what's on screen now. See [`retake compose`](Documentation/cli.md#retake-compose).

Scenes are JSON files, so they can be written or changed by hand too. A scene's `set` is the
project's `defaultSet` unless it names one:

<!-- schema: scene -->
```json
{
  "set": "returning-user",
  "setup": [{ "activate": { "label": "Library" } }],
  "leadIn": 1.5,
  "tail": 2,
  "defaultHold": 0.5,
  "steps": [
    { "tap": { "label": "New Note" }, "hold": 1.2, "id": "new-note" },
    { "type": { "text": "Groceries\n", "into": { "value": "Title" } } },
    { "tap": { "x": 195, "y": 410 } },
    { "drag": { "from": { "x": 120, "y": 590 }, "to": { "x": 260, "y": 500 }, "duration": 0.8 }, "id": "reorder" },
    { "waitFor": { "label": "Synced" }, "id": "synced" },
    { "capture": "synced-list" },
    { "hold": 2 }
  ]
}
```

Each step does one thing, led by what it does:

- **`tap`** touches a point, `x` and `y`, or an element, at its activation point. Either is drawn in
  the video.
- **`drag`** is a straight one-finger drag `from` one point or element `to` another, over
  `duration` seconds, 0.5 unless given. An element is touched at its activation point, as the
  screen has it just before the drag, so dragging a list's row by its handle to another row's handle
  needs no coordinates: `{ "from": { "label": "Reorder Book club" }, "to": { "label": "Reorder
  Weekend plans" } }`.
- **`type`** types `text` key by key on the on-screen keyboard, where `\n` presses return, into the
  element `into` names, or the field already being typed in. It fails if typing changed nothing on
  screen, not a field's value nor whether it's being edited, as when the field lost its focus first;
  text that's only returns isn't checked, since a field may ignore return.
- **`activate`** is an accessibility activation of an element, with no touch, for getting somewhere
  off camera.
- **`orientation`** turns the device, to `portrait`, `portrait-upside-down`, `landscape-left` or
  `landscape-right`, with no hand on it, and ends when the app has turned and the device has drawn
  the rotation: while `record` has its screen, once the screen stops moving; otherwise, as when
  composing, a second and a half after the turn.
- **`waitFor`** waits until an element is on screen, or with `"gone": true` until it isn't, for up
  to `timeout` seconds, 10 unless given. The step fails if it doesn't happen. The Button Heist waits
  at most 60 seconds, so a longer `timeout` is refused when the scene is read, unless
  `BUTTONHEIST_MAX_WAIT_TIMEOUT` raises the limit: The Button Heist reads it both where Retake runs
  and in the app, so set it in Retake's environment and in the set's `environment`.
- **`capture`** saves the screen as a still, by the name it gives, as it is when the step before has
  ended and held; see
  [captures](#captures-stills-from-the-same-scenes). Each capture in a scene has a name of its
  own, of letters, digits, `-`, `_` and `.`, and none is in `setup`, which isn't recorded.

After what it does, a step can give its `hold`, the pause after it, so the take has room to breathe;
the edit trims what it doesn't need. A tap's hold runs from when the tap is sent, so taps land a
hold apart however long the app takes to settle after each; every other step's runs from when it
ends. It's the scene's `defaultHold` unless given, which is 0 unless
the scene gives one. A step can be only a `hold`, a pause. Last comes its `id`, below.

A step names an element as VoiceOver knows it: by its `label`, its `value` (a text field's
placeholder or what's typed in it, as the field has no label of its own), its `identifier` (an
`accessibilityIdentifier` the app sets), its `hint` (what VoiceOver says it does), or its `traits`,
as `retake compose` prints them, such as `["header"]` or `["button", "selected"]`, every one of
which it must have; any of them together. Traits tell apart elements that share a label, such as a
screen's title and a button named the same. When several elements match, the step fails, listing
them, each with its traits and hint and the shortest name that picks it out, and saying to name the
one meant more closely, by its traits, identifier, value or hint as well. Do that wherever you can:
`retake compose` suggests the same names. `occurrence` picks one of several that match, counted from
1 in the order VoiceOver reads the screen. It's a last resort, for elements nothing else tells
apart, since it breaks when the layout changes.

**Name elements rather than points wherever you can.** A step that names an element finds it
wherever the layout puts it, on every device, and after the app's layout changes, where a point
belongs to one screen's layout. And an element a step can name is one VoiceOver can reach, so
writing scenes this way checks your app's accessibility as you go: a button a step can't name is one
a VoiceOver user can't find either, and is worth an accessibility label. Points are for what has no
element of its own, such as a spot on a canvas or a game board: a point's `x` and `y` are screen
points, or a percentage of the screen's width or height as the device faces, such as `"50%"`, which
holds better across devices.

A tap or a drag that lands while something is still moving, such as a sheet rising, can miss what it
was aimed at, so a step that follows one that presents or dismisses something should wait for it: a
`waitFor` on what arrives, or on what leaves with `"gone": true`.

The step log records when an `orientation` step's frames changed shape, for the edit to
[show the turn](#turns), and when a `waitFor`'s element appeared, so an edit can cut on what the app did,
such as a sheet arriving, not just on what the scene did. Every step, its options and their defaults
are in the [scene reference](Documentation/reference/scene.md).

A step's `id` names it for edits to anchor to; see [anchors](#anchors-times-that-follow-the-app). Ids are unique within a scene, can't
look like a number, and can't be `start` or `end`, which name the take's own edges.

A scene starts in its `orientation`, `portrait` unless it says otherwise; Retake turns the device to
it before launching the app, so a take never starts the way the last one ended.

`setup` steps play before recording starts. `leadIn` and `tail` record a little before the first
step and after the last, 1 second each unless given, so the edit has frames to cut in and out on.
`"recordsLaunch": true` starts recording before the app launches, to catch its launch screen; the
lead-in then starts once the app is up and reachable, so the first step waits for its first screen
to settle, as it would without the launch.

Points, and layouts, differ between devices, so scenes are written per device type: `scenes/iphone/` and `scenes/ipad/`. A scene of the same name on each type, with every step id an edit references, is what lets
one edit cut both.

### What a scene can't reach

The Button Heist acts from inside the app, so a scene sees and touches only what the app itself
draws. What another process shows is out of its reach:

- **The system's alerts**: permission prompts (location, notifications, camera, tracking and the
  rest), and other alerts iOS shows over the app.
- **Share sheets, and other system screens shown inside the app**, such as composing mail or picking
  a document.
- **`SFSafariViewController`**, and the pages a `WKWebView` shows.
- **Notifications, Control Center, the home screen and other apps.**

A step naming one fails, as if it weren't on screen. Keep them out of takes: grant a permission by
hand before recording, as it then stays granted; and where a preview should show one, have the app
show a stand-in of its own under a launch flag the set turns on. The recording still captures
whatever is on screen, so a system alert that appears unasked is in the take. The Button Heist's
[scope and limits](https://github.com/TheButtonHeist/TheButtonHeist/blob/v0.7.1/docs/SCOPE-AND-LIMITS.md) say more.

## Takes: footage and a step log

`retake record` records a USB-connected device's screen and sound the way QuickTime's "New Movie
Recording" does: at the resolution and frame rate the device sends its screen in, with no prompt or
recording indicator on the device. That's the screen's own resolution on an iPhone, but not on every
iPad: an iPad Pro (11-inch) (3rd generation) sends its 1668×2388 screen as 1200×1718. The app plays
on the device's screen as usual, but its sound comes through the Mac while it's recorded, rather
than the device's speaker.

Each take is a movie and a step log: when each step started and ended on the movie's own clock,
where each touch landed, and the elements on screen after each step, with their labels and frames.
The log is what lets an edit draw touches where they happened, find elements to spotlight or blur,
and cut on steps rather than seconds, on any take of the same scene. Retake writes it, and a project
never edits it; every field is in the [step log reference](Documentation/reference/take.md).

A scene keeps, for each device type, one take: the latest that succeeded, which edits are cut from.
Recording it again keeps the take it replaces as its previous one, deleting the one before, so a
retake that came out worse, with a stutter a step can't see, loses nothing: `retake takes --restore
<scene>` puts the previous take back. A recording that fails is kept as the scene's latest failure,
to show what went wrong, and leaves the take alone, as does one that's interrupted; a success
deletes the failure. Each take records what it was made with, which `retake takes` lists; see
[what's recorded in each file](#whats-recorded-in-each-file). Retake never decides a take is out of date: you know when the app has changed enough
to record again. `retake clean` then `retake record` starts everything over.

Recording a device reliably takes more care than it looks. Retake handles the failures that
otherwise cost a take: a break in the stream doesn't end the file; silences, when the device sends
no audio, are filled so later sounds stay on their frames; the device's full-range color is
converted rather than played back oversaturated; and a recording that fails to start, or a launch
that doesn't take, is tried again.

Two more are the app's side of it. When an app's sound starts again after a quiet stretch, the
device restarts its sound output, and the recording loses up to half a second of video while it
does, though the app looks smooth on the device; Retake's support library plays noise far below
hearing for as long as the app runs, so the output never stops. And the library watches the app's
main thread for missed frames: `record` warns of the take's hitches from its first step on, how many
and the longest, saying whether the longest came while a step was being played, and `cut` warns of
any a clip plays, the lead-in's included. Only hitches as long as `retake.json`'s `hitchWarning`,
50 ms unless it says otherwise, are warned of.

## Captures: stills from the same scenes

A scene's **`capture`** step saves the screen as a still, a PNG named for the step, as `record`
plays the scene:

<!-- schema: scene -->
```json
{
  "set": "screenshots",
  "steps": [
    { "waitFor": { "label": "Reading list" } },
    { "capture": "library" },
    { "tap": { "label": "Reading list" } },
    { "waitFor": { "label": "Share" } },
    { "capture": "note" }
  ]
}
```

Each still is a screenshot the device takes, through `devicectl`, at its screen's own resolution:
1668×2388 on an iPad Pro (11-inch) (3rd generation), whose screen `record` films at 1200×1718. It's
taken while Retake has the screen open, as `record` does even with `--stills-only`, so its status
bar is the one QuickTime shows, the device's while its screen is recorded: 9:41, with full bars and
battery. That's all it cleans, though: a Focus's symbol stays beside the time, and so does iOS's
link back to the app that was open before Retake launched yours, such as "◀ Slack". Turn Focus off,
and go to the home screen, before recording to keep both out. A still faces as the screen did,
landscape when the device was turned, with no touches drawn on it; like every App Store
screenshot, it has no alpha channel, and it's in the device's color space, such as Display P3.
When the device can't take a screenshot, `record` warns and captures the frame its screen is
filmed in instead.

The step takes the screen as the step before left it, once that step has ended and its hold is
over, without waiting for it to settle, which a screen with a looping animation never does. A step
ends once The Button Heist sees the app settle, and a turn once the device has drawn it, so most
need no hold before a capture; one whose screen goes on moving after it ends, such as a timed
animation the app starts, needs a `hold` long enough for it to come to rest.

**A capture takes 1 to 2 seconds**, as long as the device takes to answer `devicectl`, and the app
waits on that screen for all of it. A take recorded with its captures shows that as a still stretch
at each one, the capture step's length, which the movie records through. So a capture in the middle
of a scene an edit cuts from puts that pause in the video, unless the edit cuts it out: give the
capture step an `id`, and end one clip at its start and begin the next at its end. Keep a video's
scenes free of captures, and take the screenshots in scenes of their own, with
`record --stills-only`, unless the pause is wanted.

The stills go in the output directory's `captures/<type>/<scene>/<name>.png`, apart from the
scene's takes. A recording takes them into a folder of its own, and only when it plays every step
do they replace the scene's captures, all together, so a scene's captures are always from one
recording. One that fails leaves the scene's captures as they were. A scene can be recorded for its
captures and its take together, and an edit can cut from a scene that captures; a capture step is
a step like any other in the take, which an edit can anchor to.

**`retake record --stills-only`** takes only the captures, writing no take: it plays the scenes
that capture with the device's screen open but not recorded, without their lead-in and tail, and
leaves their takes alone. With no scene named, it takes the captures of each scene that captures
and has none yet, or with `--force`, every one.

**A capture may not be the right size for App Store Connect.** App Store Connect takes screenshots
only in exact sizes, and requires one display's for each device type, scaling them down for the
others: iPhone with Dynamic Island (medium display), 1179×2556 or 1206×2622, and the iPad 13-inch
display, 2064×2752 or 2048×2732. A still is only as large as the device's screen, so the device
decides which display it can serve: an iPhone 17e's 1170×2532 is the size for iPhone with Face ID
(medium display), and an iPad Pro (11-inch) (3rd generation)'s 1668×2388 for the iPad 11-inch
display, neither of them required. `record` says, for each size it captured, which display takes
it, and which display App Store Connect requires; its
[screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications)
list every display and size. Resized, a still can still serve for marketing, framed in a device's
chrome. For App Store screenshots at exact sizes, a tool made for them, such as
[Goldie](https://github.com/software-mansion-labs/goldie), or snapshot tests of an app staged for
them, will serve you better.

A set with [`previewAspect`](#previewaspect-the-previews-shape) shrinks the app's window to a
preview video's shape, which a screenshot doesn't want, so a scene for screenshots starts on a set
that leaves it off; one that extends the set the videos use, with `"previewAspect": false`, is
enough.

`retake clean --captures` deletes captures, every scene's or those named, and `retake clean` with
nothing else deletes them with the takes and cuts.

## Edits: the video cut from the takes

An edit is a list of clips, each a stretch of a take, played in order. One edit makes the video for
every device type it names, from that type's takes of the same scenes:

<!-- schema: edit -->
```json
{
  "intent": "The core loop in 20 s: create a note, share it, see it sync.",
  "devices": ["iphone", "ipad"],
  "music": { "file": "audio/theme.m4a", "volume": 0.6, "fadeOut": 1.5 },
  "tapSound": { "file": "audio/tap.m4a", "volume": 0.5 },
  "background": "#F4F1EA",
  "clips": [
    {
      "intent": "The empty library, then New Note tapped.",
      "take": "create-note",
      "from": { "step": "start", "offset": 1.2 },
      "to": { "step": "new-note", "offset": 0.6, "edge": "end" },
      "speed": 1.5,
      "touches": true,
      "sounds": [{ "file": "audio/pop.m4a", "at": { "step": "new-note" } }],
      "captions": [
        {
          "text": "Jot it down",
          "y": 0.12,
          "color": "#1F6FEB",
          "to": { "clip": "sync", "step": "synced", "offset": -0.2 },
          "ipad": { "y": 0.08 }
        }
      ]
    },
    {
      "id": "sync",
      "intent": "The note syncing, cut just before its badge settles.",
      "take": "create-note",
      "from": { "step": "reorder", "fraction": 0.5, "edge": "end" },
      "to": { "step": "synced", "offset": -0.2 },
      "speed": 1,
      "ipad": { "speed": 1.3 },
      "takeAudio": true,
      "sounds": [
        { "file": "audio/chime.m4a", "at": { "step": "synced" }, "volume": 0.8, "duration": 1.2 }
      ],
      "crossfade": 0.4
    }
  ]
}
```

The `intent` fields aren't read by the render. They say what the edit and each clip are there to
show, in your app's terms, so whoever changes the video later knows what each moment is for.

An edit doesn't name its takes: it's always cut from each scene's take, and the video records which
those were. To cut from a scene's previous take, [put it back](#takes-footage-and-a-step-log) first.

`retake clean --unused` keeps the take of every scene any edit uses and deletes previous takes and
failures, along with scene definitions and takes no edit uses.

### Anchors: times that follow the app

Every time in an edit — a clip's `from` and `to`, a caption's, spotlight's, blur's or card's
`from` and `to`, a sound's `at`, a still's `at`, and `stillsIn` and `stillsOut` — is an anchor: a
moment in the clip's take, given by a step and where to go from it.

An anchor's `step` is a step's `id`, its number counted from 1, or a negative number counting back
from the last (`-1` is the last step); `start` and `end` are the take's first and last frames,
lead-in and tail included. An anchor is at the step's start, or at its end with `"edge": "end"`, and
moves from there: `offset` in seconds, forward when positive and back when negative, so an offset of
0 is that edge itself; `fraction`, from -1 to 1, a share of the way from there to the neighbouring
step, forward to the next step's start or back to the previous step's end, with the take's `start`
and `end` standing in past the first and last steps.

An anchor has `offset` or `fraction`, not both; with neither, it's the edge itself. A plain number
of seconds from the take's start still works, and the first `cut` turns it into an anchor against
the scene's take.

Since a take's steps are the same however long the app takes over them, an edit anchored to steps
cuts the same moments from any take of its scenes: a newer take on the same device, or a take on a
different device whose animations run longer. Which kind of anchor to use:

- **Near a cut, an `offset`** from the nearest step: 0.2 s before a sheet appears is 0.2 s before it
  on every device.
- **Partway through something that stretches, a `fraction`**, between two moments the app decides,
  such as a tap and the `waitFor` that sees its animation finish. A gap that's mostly a step's fixed
  `hold` doesn't stretch with the app, so a fraction across it lands at different points in the
  animation on different devices.

Anchor to a step's `id` rather than its number. Ids make an edit readable and survive steps being
added to a scene; numbers don't, though `-1` always finds the last step. An anchor that doesn't
resolve — an unknown id, a number past either end, a fraction outside -1 to 1 or with no step on
that side — fails the `cut`, naming the clip.

### One edit for every device type

Anything in a clip, or at the top of the edit, can be given again under a device type, such as
`"ipad": { "speed": 1.3 }`, and applies only to that type's video. That's for what is a choice of
design rather than of timing: a caption's height clear of each layout, a clip a little faster where
an animation runs longer. The canvas, frame rate and size come from App Store Connect's preview
specifications for each type, so an edit names device types rather than pixels.

An override is laid over what it overrides: an object merges key by key, so `"ipad": { "y": 0.08 }`
in a caption changes only its `y`, while a list or a single value replaces what's there, so an
override of a clip's `captions` gives that type's video its whole list.

A clip that names `devices`, such as `"devices": ["iphone"]`, is in only those types' videos: one
type can show something the others don't, or show something else in its place.

One device type's takes in an edit must come from devices with the same screen, since positions in
the step log are the screen's points: `cut` refuses an edit whose iPhone takes, say, mix a 6.1-inch
and a 6.9-inch iPhone, naming the takes on each.

### What a clip can do

- **Play faster or slower**, to skip waits without cutting them.
- **Cross-fade** into the clip before, with its sound fading over a longer time if needed.
- **Draw the take's touches**, from the step log: every tap and drag, unless the clip sets `"touches": false`.
  They're white unless the edit's `touchColor` says otherwise; a clip's `touchColor` changes its
  own, and its `touchColors` a single touch's, by the step that made it.
- **Carry captions**, any number, each up between two moments; see [captions](#captions).
- **Spotlight** an element, dimming the rest, with a pulsing ring around it.
- **Blur** an element over a stretch of the take, for anything private it shows.
- **Show a card**, a colour covering the picture with its captions on it, for a title between
  clips (`card`). Over the whole clip, it fades in and out with the cross-fades either side, so
  what's under it never shows; with a `from` or `to`, over that stretch only.
- **Pop in stills** from other takes, over the clip or over a colour of their own (`stillsBackground`),
  one after another from `stillsIn`, or just after the clip starts, and pop them out again, in the
  same order, at `stillsOut`.
- **Cue sound effects**, which play at normal speed however fast the clip plays, or play the take's
  own sound; see [sound](#sound).
- **Show the device turning**, when a scene turns it; see [turns](#turns).

Spotlights and blurs name an element the way steps do, by its accessibility label, and Retake finds
its frame in the take's step log, which records what was on screen just before the first step, and
after each step. So the same spotlight lands on the same button on every device, with no rectangles
to measure:

<!-- schema: edit clip -->
```json
"spotlight": { "element": { "label": "Share" }, "padding": 8 },
"blurs": [{ "element": { "label": "Name" }, "from": { "step": "type-name" }, "to": { "step": "end" } }]
```

An element is matched as a step's target is, so where several share a label, its traits, identifier,
value or hint pick one out, as they do for a step; `occurrence`, counted from 1, is the last resort
there too. The frame used is the element's in the latest snapshot at or before the moment, or before
the first step has ended, in the one taken just before it. Where only part of an element matters,
its `part` names it, in points from the element's top-left corner or percentages of its frame, the
whole frame on any side not given: `"part": { "x": "62%", "width": "31%" }` is the word "Alex" in a
"Send to Alex" button. Something moving between snapshots, such as a keyboard sliding up, is better
covered by a `rect`, in screen points or percentages of the screen as the device faced, given per
device type where layouts differ.

### Captions

A clip's `captions` are text over the video, each shown from its `from` to its `to`, which are
anchors. A caption with neither is up for the whole clip, but clear of its cross-fades: it comes up
once the clip has faded in, and goes as the next clip starts to fade in, so one caption is gone
before the next arrives. Any number can be up at once, and they may overlap; where each sits is the
edit's to say.

A caption can run on over the clips after it. Its `to` names a later clip by its `id`, and is then
an anchor in that clip's take, with everything an anchor takes: a `step`, and an `offset`,
`fraction` or `edge` from it, as `{ "clip": "sync", "step": "synced", "offset": -0.2 }` does above.
`{ "clip": "sync" }` alone keeps the caption up through that clip, leaving as the next clip starts
to fade in. Only `to` can name another clip: a caption
that starts in a later clip belongs to that clip.

An anchor outside the part of the take its clip plays fails the `cut`, naming the caption.

`y` places a caption's centre as a share of the video's height, from 0 at the top to 1 at the
bottom, measured on the video itself, so after any band `previewAspect` crops away. Since it's a share
rather than pixels, one value suits every size of a device type's video; a per-device value is for
layouts that differ, where each needs the caption clear of something else.

A caption can show an SF Symbol before its text, and animate it. `rotate` is the one animation so
far, turning the symbol by `degrees` (clockwise when positive) over `duration` seconds, from when
the caption appears:

<!-- schema: edit clip -->
```json
"captions": [
  {
    "text": "Turn for two pages",
    "y": 0.1,
    "color": "#6A3DE8",
    "from": { "step": "turn", "offset": -0.4 },
    "symbol": {
      "name": "rotate.right",
      "animation": { "rotate": { "degrees": 90, "duration": 0.4 } }
    }
  }
]
```

### Sound

A video's sound is the edit's music, under the sound of its clips:

- **`music`** plays under the whole video, at its `volume`, fading out over `fadeOut` seconds at the
  end.
- **A clip's `sounds`** are effects, each starting at its `at`, an anchor in the clip's take. They
  play at normal speed however fast the clip plays, so a sound lands on its moment without being
  sped up. `volume` sets its level, and `duration` cuts it short, fading out, for an effect longer
  than the moment it's for.
- **A clip's `takeAudio`** plays the take's own sound, recorded from the device, with the clip, at
  the speed the clip plays; the edit's `takeAudioVolume` sets its level for every clip that plays
  it. A clip's `audioCrossfade`, longer than its `crossfade`, cross-fades the sound over longer than
  the picture: the clip before's sound fades out over it, and the clip's own starts that much before
  the clip before ends, ahead of its picture, fading in. Each side fades so whether or not the other
  plays its take's sound.
- **The edit's `tapSound`** plays as each touch a clip draws (`touches`) lands, at its `volume`: on
  each tap, and at the start of each drag, where its finger comes down.

Sound files are paths relative to the directory holding the configuration file, as every path in an
edit is.

### Turns

When a scene turns the device, its take holds both shapes: the recording keeps the shape it started
in, and frames recorded the other way are stored turned a quarter to fit, with the step log saying
when. An edit's `turns` chooses how a video shows them. With `letterboxed`, the default, the app
stays upright: landscape stretches are letterboxed on the canvas, and the device's own rotation
animation plays between them. With `device`, the video stays in the device's frame, so the app is
sideways while the device is landscape, as a camera fixed to the device would see it.

`"turnBlur": { "duration": 0.6 }` blurs each turn, easing in just before it and out after, which
hides the in-between frames of the rotation and the device's short gap in frames as the screen
changes shape. Both can be set for the whole edit, or for one clip. The letterbox bands, and the
corners a turn uncovers, are the edit's `background` colour, black unless it says otherwise.

## What's recorded in each file

Every movie Retake writes says how it was made, in its own metadata, so a take or a video found
later can be traced to the app and the setup behind it:

- the version of Retake that made it;
- the app's version and build (`CFBundleShortVersionString` and `CFBundleVersion`);
- the version of The Button Heist that drove the app;
- the device's model, such as "iPad Pro (11-inch) (3rd generation)" (`iPad13,4`), and its iOS
  version.

A take also records its scene, set and state. A video records the edit it was cut from, the same
details for each take in it, with its scene and when it was recorded, and every app build, device and Button Heist its takes were
recorded with, since they may differ. `retake cut` warns when they do.

`retake info <movie>` prints all of it. Takes and masters are QuickTime movies, so other tools read
the fields too: `ffprobe` lists them, and Finder shows the software that made it. The `.mp4` for App
Store Connect carries the same record in its description, which Apple's tools read and `ffprobe`
doesn't.

Nothing personal is recorded: not the device's name, which usually includes its owner's, nor its
UDID.

## Devices

Devices are named by aliases you choose, kept for every project in
`~/Library/Caches/retake/devices.json`, never in a repository, since devices belong to people:

```sh
retake devices                 # connected devices, their type, and whether they're wired
retake devices add ipad        # pick a connected device and call it "ipad"
retake record --device ipad create-note
```

An alias stands for both of a device's identities, which differ and which Retake needs both of: its
UDID, for installing and launching, and its screen-capture device, for recording. Without an alias,
`--device` also takes a UDID or a device's name, and with one device connected it can be left out. A
project's `retake.json` can name a default alias, and `RETAKE_DEVICE` names yours for a shell
session, over the project's.

## The Button Heist, and Retake's version pin

Retake drives your app with [The Button Heist](https://github.com/TheButtonHeist/TheButtonHeist), which acts on the app through its accessibility
interface: steps find elements the way VoiceOver does, and touches are synthesised inside the app.

> [!IMPORTANT]
> **Each Retake release is built against exactly one release of The Button Heist, and works only
> with that release.** The Button Heist's client and in-app server must be the same version, and its
> commands change between releases. Retake doesn't try to support several versions at once. `retake
> version` prints the version it's built against.
>
> Retake always supplies TheInsideJob itself, the framework The Button Heist publishes with that
> release, so it always matches Retake's client. An app that links its own is refused by `embed` and
> `install`. And when an app was embedded by a Retake built against a different version, `record`
> stops before the first step and asks for it to be embedded again.
>
> Once The Button Heist reaches a stable contract (a 1.0), Retake will consider supporting a range
> of versions rather than pinning one.

The Button Heist's version is precise: builds between releases report the release they follow with a
hash of their commands and wire format appended, such as `0.7.1-d53fb59edbf3`, and an app and a
client whose versions differ refuse each other before any command runs. So the version alone says
whether an app and a Retake can work together, and it's what Retake checks and records.

## Project layout

A project keeps the instructions for its videos in its repository, and the footage out of it.
`retake init` makes it in `Retake/`, at the repository's root, where every command finds it, from
the root or from inside `Retake/`:

```
Retake/
  retake.json        # the app, its build, the default device, and paths
  sets/*.json        # starting states, and the files they copy
  scenes/iphone/*.json
  scenes/ipad/*.json
  edits/*.json
  output/            # takes, captures and videos; gitignored, and movable with --output-dir
```

`output/` is gitignored, since its movies are too large for a repository: `retake init` adds it to
the `.gitignore`, so a project made without `init` should add it there itself. See
[`retake init`](Documentation/cli.md#retake-init) for keeping its movies long term.

The folders' names are lowercase, and Retake reads them only as named: a folder in another case,
such as `Edits/`, which git can keep after a folder is renamed on a Mac, is reported, by `validate`
and by any command that can't find a file in it, rather than read as empty.

Builds and your device aliases are kept outside the repository, in `~/Library/Caches/retake/`, for
every project: a build rewrites thousands of files each time, and aliases name your own devices.

A project can live anywhere, under any folder's name: `retake init --config Previews/retake.json`
makes one in `Previews/`, and commands then need `--config` or `RETAKE_CONFIG` to find it, which the
repository's `mise.toml` can set for everyone; see [finding the project](Documentation/cli.md#finding-the-project).

### Schemas

Every file Retake reads has a [JSON Schema](https://json-schema.org), released with Retake and versioned with it:
`retake.json`, sets, scenes and edits, and the step logs Retake writes beside its takes. Retake
reads every file against its own schema, so a file needn't name one. For an editor, a file can name
its schema in a `"$schema"` key: the URL its schema is published at, which names Retake's version,
such as
`https://justinseanmartin.github.io/Retake/schemas/0.0.1/edit.schema.json`. Editors that read JSON
Schema, VS Code among them, fetch it from there, and complete fields as you type, describe them on
hover, and mark mistakes; nothing is copied into the project. Retake never adds the key, and `retake
cut` keeps one up to date. `retake schema` prints the schemas, for tools and agents, or writes
them to a directory for working offline.

Retake reads the files strictly, against the same schemas: a key it doesn't know is an error, not
ignored, and every error names the file and the field, such as `edits/video1.json:
clips[3].from.fraction: 1.4 is outside -1 to 1`. `retake validate` checks a whole project without a
device, including what only the takes can answer, such as an anchor's step id existing in its scene.

The [reference](Documentation/reference/) lists every field of every file, generated from the schemas. This README explains
how the pieces fit together; the reference is where each field is defined.

## Building from source

Retake is a Swift package. To work on it you need only Xcode.

`.xcode-version` names the Xcode that Retake's releases are built with. For working on Retake it's
the version known to work, not a requirement: nothing checks it locally, and other versions usually
work too. If a build fails on yours, that's the version to try. Releases are different: the release
build uses exactly that version, and fails without it. TheInsideJob isn't built by Retake at all;
it's The Button Heist's own release build, which records its Xcode in the bundle's `XCODE_VERSION`.

```sh
Scripts/build.sh               # builds a runnable retake, and prints its path
swift test
```

`Scripts/build.sh` is the three steps a source checkout needs before `retake` can install an app,
each quick when there's nothing new: `swift build -c release`, `Scripts/build-support.sh`, which
builds Retake's support library for iOS, and `Scripts/fetch-insidejob.sh`, which gets the
TheInsideJob Retake installs, for the pinned release. It builds into `RETAKE_SCRATCH_PATH`, or
`.build`, and prints the path of the `retake` it built, last and alone, for a script to run:
`retake="$(Scripts/build.sh)"` builds once, then `"$retake"` runs it as often as needed.

`swift build` fetches The Button Heist's packages at the pinned release, since Retake links its
client library directly. `Scripts/fetch-insidejob.sh` downloads the same release's
`theinsidejob-<version>.zip`, checks it against the release's checksums, and puts its
`TheInsideJob.xcframework` where a locally built `retake` installs it from. Released builds include
it. Neither needs The Button Heist's own development tools.

The schemas in `Documentation/reference/` are generated from Retake's file types, and checked in.
After changing what a file may say, regenerate them, and the reference beside them:

```sh
swift run retake schema --output Documentation/reference
RETAKE_REGENERATE=1 swift test --filter Reference
```

A pre-commit hook refuses a commit whose staged schemas differ from what the types generate. Turn it
on once per clone with `git config core.hooksPath Scripts/git-hooks`. It builds `retake` into
`RETAKE_SCRATCH_PATH`, or `.build` unless that's set.

Editors fetch the schemas from GitHub Pages, at the URL each one's `$id` names. Once they've changed
on `main`, publish them there with `Scripts/publish-schemas.sh`: it copies them into
`schemas/<version>/` on the `gh-pages` branch, checked out in `.pages/` (ignored by Git), pushes,
and turns Pages on the first time. It publishes only `main` with nothing uncommitted, and won't
replace a version's schemas once they're published, since files name them by their URL; `--force`
does all three.

### Working on Retake and The Button Heist together

For changes that span both, point Retake at a local clone of The Button Heist:

```sh
export RETAKE_BUTTONHEIST_PATH=../TheButtonHeist
swift build
Scripts/fetch-insidejob.sh
```

With `RETAKE_BUTTONHEIST_PATH` set, `swift build` uses that clone instead of the pinned release, and
`Scripts/fetch-insidejob.sh` builds TheInsideJob from it rather than downloading it. One variable
drives both on purpose: Retake's client and the framework it installs must come from the same
source. A clone between releases reports a version with its contract hash, so a framework built from
a different state of the clone is refused at the handshake rather than half working. Rebuild both
after changing the clone.

A build from a clone says so. `retake version` names the clone's path and commit, ending in `-dirty`
when it has uncommitted changes, and so does each take's metadata. Release builds refuse to run with
the variable set.

SwiftPM drops The Button Heist's pin from `Package.resolved` while building from a clone. Don't
commit that change: `git checkout Package.resolved` puts the pin back, and
`Scripts/fetch-insidejob.sh` needs it to download the release.

## License

Apache License 2.0; see [LICENSE](LICENSE). Retake's releases include TheInsideJob as The Button Heist (also
Apache 2.0) publishes it, with its dependencies linked in and their licenses shipped with it.
