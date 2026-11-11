# Retake

**App Store preview videos captured on real iOS devices and defined in JSON as sets, scenes and edits.**

Retake plays your app on a USB-connected iPhone or iPad while the Mac records its screen and sound,
then cuts the recordings into a finished preview with captions, touches, spotlights, cards,
transitions, sound and music. Everything that makes the video is a file kept with your code, so when
the app changes you record again and render the same edits: no screen recording by hand, no
timeline to rebuild, and no guessing which frames you used last time.

[![The example's showcase, cut by Retake: touches, cuts, a spotlight, a blur, a drag, a turn, a card and a montage, each captioned. Play it.](https://justinseanmartin.github.io/Retake/showcase/poster.jpg)](https://justinseanmartin.github.io/Retake/showcase/)

Every frame of [the video above](https://justinseanmartin.github.io/Retake/showcase/) was made by Retake from [the example app](Example),
recorded on a physical iPhone and iPad, and cut for each from the one
[`showcase`](Example/Retake/edits/showcase.json) edit.

Retake's lingo:

- A **[set](#sets-the-state-a-take-starts-from)** defines the app's state before recording: its
  files, user defaults, launch arguments and environment.
- A **[scene](#scenes-the-walk-through-the-app)** is a walk through the app, starting from a set,
  which Retake plays on the device and records.
- A scene is **[composed](Documentation/cli.md#retake-compose)** one action (tap, drag, wait, etc.)
  at a time, interactively, by a person or an agent.
- A **[take](#takes-footage-and-a-step-log)** is a scene's recording: the movie, with a log of its
  steps.
- An **[edit](#edits-the-video-cut-from-the-takes)** defines how takes are mixed into a finished
  video.
- A **[cut](Documentation/cli.md#retake-cut)** is that finished video, rendered from an edit's
  takes.

**How you use it.** [Install Retake](#install), then start your favorite coding agent in your app's
repository and ask it to integrate Retake. Describe the flows you want recorded, the state each one
starts from, and what each video should emphasize. The agent writes the sets, composes the scenes on
your device, records the takes, writes the edits and renders the cuts. Watch them, and keep asking
for changes to the scenes and edits until the video looks just how you want it.

Retake is made to be driven that way: an agent composes a scene as you would, told after each
action what happened and what's on screen; every file has a [schema](#schemas) that `retake validate`
checks a project against; and the commands that report something take `--json`.

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

**What about App Store screenshots?** Retake is purpose built for App Store preview videos. Its
`capture` step saves stills from the same scenes, which can serve, but at the device's own
resolution, which often isn't a size App Store Connect takes; see
[Captures](#captures-stills-from-the-same-scenes).

> **Status:** an early release; see [the latest](https://github.com/justinseanmartin/Retake/releases/latest).
> Retake is an experiment in generalizing a tool I'd used for two of the apps I've released to the
> App Store.
>
> **Stability:** until 1.0, nothing is guaranteed to stay the same between versions. If you'd like to
> avoid breakage, pin to an exact version: `mise use github:justinseanmartin/Retake@<version>`.
> Breaking changes will be documented in the [release notes](RELEASE.md) and come with a new minor
> version, from 0.1 to 0.2. Compatibility guarantees start at 1.0.

## Contents

- [How it works](#how-it-works)
- [Install](#install)
- [Quick start](#quick-start)
- [Embedding Retake into your app](#embedding-retake-into-your-app)
- [Sets: the state a take starts from](#sets-the-state-a-take-starts-from) ([`state`](#state-clean-cloned-or-live))
- [Scenes: the walk through the app](#scenes-the-walk-through-the-app)
- [Takes: footage and a step log](#takes-footage-and-a-step-log)
- [Captures: stills from the same scenes](#captures-stills-from-the-same-scenes)
- [Edits: the video cut from the takes](#edits-the-video-cut-from-the-takes)
- [What's recorded in each file](#whats-recorded-in-each-file)
- [Devices](#devices)
- [The Button Heist, and Retake's version pin](#the-button-heist-and-retakes-version-pin)
- [Project layout](#project-layout)
- [Limitations](#limitations)

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

You don't need any other tools installed to use Retake. When a command fails and its message
doesn't say why, `retake doctor` checks each part of the setup in turn, to find which.

## Quick start

```sh
retake init                              # Retake/: retake.json, a starter set, scene and edit; output/ gitignored
retake devices add iphone                # name the USB-connected device
retake install --scheme MyApp            # build Debug, embed Retake, and install it
retake record launch                     # record the starter scene: the app launching
retake cut preview --type iphone         # cut the starter edit, for the iPhone only
retake compose <scene>                   # then write your own scenes, a step at a time, on the device
```

**NOTE:** Start recording with the device on the home screen, and with Focus modes off, to keep
extra noise out of the status bar, such as "◀ Safari" or a Do Not Disturb moon.

**Take a look at the example app.** [`Example`](Example) is a simple notes app with its `Retake/`
project, ready to run. Its sets start the app fresh or as a returning user with stored notes. Its
scenes walk through getting started, writing a note, sharing it and seeing it sync, and reordering
notes with the device turned. Its edits cut those into an App Store preview (`tour`) and a tour of
Retake's editing features (`showcase`), the video above. To run it from a clone of Retake, see
[running the example](CONTRIBUTING.md#running-the-example).

## Embedding Retake into your app

**Retake needs nothing from your app's code.** `retake install` takes a Debug build of it, adds
[The Button Heist](#the-button-heist-and-retakes-version-pin)'s in-app server (TheInsideJob) and Retake's own small support library into the app's
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
build you install for testing, and record with whichever one is on the device. Run `retake check`
on release archives if a build you embed could ever be archived.

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
data you use the app with. Some of the app's state is out of their reach; see
[what `state` doesn't cover yet](#what-state-doesnt-cover-yet).

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

Points, and layouts, differ between devices, so scenes are written per device type: `scenes/iphone/`
and `scenes/ipad/`. A scene of the same name on each type, with every step id an edit references, is
what lets one edit cut both.

A scene sees and touches only what the app itself draws, not the system's alerts or share sheets;
see [what a scene can't reach](#what-a-scene-cant-reach).

## Takes: footage and a step log

`retake record` records a USB-connected device's screen and sound the way QuickTime's "New Movie
Recording" does: at the resolution and frame rate the device sends its screen in, with no prompt or
recording indicator on the device. While it's recorded, the device's sound goes to the Mac, so the
device itself plays none.

Each take is a movie and a step log: when each step started and ended on the movie's own clock,
where each touch landed, and the elements on screen after each step, with their labels and frames.
The log is what lets an edit draw touches where they happened, find elements to spotlight or blur,
and cut on steps rather than seconds, on any take of the same scene. Retake writes it, and a project
never edits it; every field is in the [step log reference](Documentation/reference/take.md).

A scene keeps two takes for each device type: the latest that succeeded, which edits are cut from,
and the one before it. If a new take comes out worse, `retake takes --restore <scene>` puts the
previous one back. A recording that fails or is interrupted doesn't replace a take.

Each take records how it was made, which `retake takes` lists; see
[what's recorded in each file](#whats-recorded-in-each-file). Retake doesn't guess when the app has
changed enough to need new takes: `retake record` records only scenes with no take yet, and
`retake record --force` records them all again.

Recording a device reliably takes care. Retake handles invalid or incomplete video streams, avoids
the hitch an audio stream causes as it starts, records in the right color space, and recovers from
the app or the recording failing to start.

Retake's support library logs each time the app's main thread misses a frame. `record` warns of
those from the first step on, and `cut` of any a clip plays across, including in the lead-in, just
after the app launches.

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

Each `capture` is a screenshot the device takes, at its screen's own resolution, in the device's
orientation, with the same clean status bar as a recording. It has no alpha channel, as App Store
Connect requires, and keeps the device's color space. When `devicectl` can't take a screenshot,
`record` warns and saves the frame the screen is filmed in instead, which can be a different size.

A capture is taken as soon as the step before it ends. If the screen needs longer to settle, give
that step a `hold`, though it's rarely needed. A capture takes 1 to 2 seconds waiting on `devicectl`,
which the take records as a still stretch: cut it in the edit, or capture in a scene of its own. A
capture step is a step like any other in the take, which an edit can anchor to.

The stills go in the output directory's `captures/<type>/<scene>/<name>.png`, and are replaced only
when the scene plays through without a failure. `retake record --stills-only` takes only the
captures, leaving takes alone: with no scene named, those of each scene missing them, or all of
them with `--force`. `retake clean --captures` deletes them.

**NOTE: A capture may not be the right size for App Store Connect,** which takes screenshots only
in exact sizes. A capture is the device's screen size, so the device decides which display it can
serve. Leave `"previewAspect": true` out of a set used for captures, so the app fills the screen.
See Apple's
[screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications)
for the sizes.

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
failures, along with scene definitions and takes no edit uses, though it keeps every scene that
captures.

### Clips

A clip can:

- **Play faster or slower**, to skip waits without cutting them.
- **Cross-fade** into the clip before, with its sound fading over a longer time if needed.
- **Draw the take's touches**, from the step log: every tap and drag, unless the clip sets `"touches": false`.
  They're white unless the edit's `touchColor` says otherwise; a clip's `touchColor` changes its
  own, and its `touchColors` a single touch's, by the step that made it.
- **Carry captions**, any number, each up between two moments; see [captions](#captions).
- **Spotlight** an element, dimming the rest, with a pulsing ring around it.
- **Blur** an element over a stretch of the take, for anything private it shows.
- **Show a card**, a color covering the picture with its captions on it, for a title between
  clips (`card`). Over the whole clip, it fades in and out with the cross-fades either side, so
  what's under it never shows; with a `from` or `to`, over that stretch only.
- **Pop in stills** from other takes, over the clip or over a color of their own (`stillsBackground`),
  one after another from `stillsIn`, or just after the clip starts, and pop them out again, in the
  same order, at `stillsOut`.
- **Cue sound effects**, which play at normal speed however fast the clip plays, or play the take's
  own sound; see [sound](#sound).
- **Show the device orientation rotating**, when a scene turns it; see [turns](#turns).

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

### Anchors: times that follow the app

Every time referenced by an edit is an anchor: a moment in the clip's take, given by a step and how
far from it. Anchors are:

- a clip's `from`, `to`, `stillsIn` and `stillsOut`;
- a caption's, card's, spotlight's or blur's `from` and `to`;
- a sound's or still's `at`.

Anchors should name steps by `id`, which stays the same as steps are added and removed. The `start` and `end` anchors are reserved and reference the take's first and
last frames, lead-in and tail included. You can also use step numbers as an anchor, counted from 1
(or backwards from -1), but this is not very durable and thus not encouraged. An anchor is the
moment its step starts, unless `"edge": "end"` makes it the moment the step ends: to start a clip
just after a turn has finished, for instance. It can then be moved from there by one of:

- **`offset`**, in seconds, back when negative: for breathing room before or after a moment.
- **`fraction`**, from -1 to 1, a share of the way to the next step's start, or back to the
  previous step's end: for a moment partway through something whose length varies between devices
  or builds, such as an animation.

If no step marks the moment you want, add a `waitFor` step (optionally with `"gone": true`) to get more
granular anchors to use.

For example, this scene taps New Note, types a title, and waits for the note to sync:

<!-- schema: scene -->
```json
{
  "set": "returning-user",
  "steps": [
    { "waitFor": { "label": "New Note" }, "hold": 1 },
    { "tap": { "label": "New Note" }, "hold": 1.5, "id": "new-note" },
    { "type": { "text": "Groceries\n", "into": { "value": "Title" } }, "hold": 0.5, "id": "type-title" },
    { "waitFor": { "label": "Synced" }, "hold": 2, "id": "synced" }
  ]
}
```

and this clip cuts it, anchored to those step ids:

<!-- schema: edit clip -->
```json
"take": "create-note",
"from": { "step": "new-note", "offset": -0.5 },
"to": { "step": "synced", "offset": 1, "edge": "end" },
"captions": [
  { "text": "Jot it down", "y": 0.8, "color": "#1F6FEB", "to": { "step": "type-title", "fraction": 0.5 } }
],
"sounds": [{ "file": "audio/chime.m4a", "at": { "step": "synced", "edge": "end" } }]
```

- `from` starts the clip half a second before New Note is tapped.
- The caption goes halfway between the start of typing and the start of the next step, however long
  the typing took in this take.
- The chime plays at the `synced` step's end: the moment Synced appeared, whenever the sync finished.
- `to` ends the clip a second after that, within the step's 2-second hold.

Anchored this way, an edit lines up again when the scene is recorded again as the app changes, and
one edit can cut both the iPhone's takes and the iPad's.

### One edit for every device type

Anything in a clip, or at the top of the edit, can be given again under a device type, such as
`"ipad": { "speed": 1.3 }`, and applies only to that type's video. That's for what is a choice of
design rather than of timing: a caption's height clear of each layout, a clip a little faster where
an animation runs longer. The canvas, frame rate and size come from App Store Connect's preview
specifications for each type, so an edit names device types rather than pixels.

In the [showcase](Example/Retake/edits/showcase.json), trimmed here, the iPad turns to landscape
while the iPhone stays upright, and a card fills the iPhone's video for as long as the iPad's turn
takes:

<!-- schema: edit -->
```json
{
  "devices": ["iphone", "ipad"],
  "clips": [
    {
      "take": "reorder",
      "from": { "step": "reorder", "offset": -0.4 },
      "to": { "step": "open", "offset": -0.1 },
      "captions": [
        { "text": "Drags, drawn with a tail", "y": 0.8, "color": "#1F6FEB", "to": { "step": "turn", "offset": -0.3 } },
        { "text": "Turns, kept upright", "y": 0.8, "color": "#1F6FEB", "from": { "step": "turn", "offset": -0.3 } }
      ],
      "iphone": {
        "to": { "step": "turn", "offset": -0.3 },
        "captions": [{ "text": "Drags, drawn with a tail", "y": 0.8, "color": "#1F6FEB" }]
      }
    },
    {
      "devices": ["iphone"],
      "take": "reorder",
      "from": { "step": "reorder", "offset": -1.2 },
      "to": { "step": "turn", "offset": -0.1 },
      "card": { "color": "#FFD43B" },
      "captions": [{ "text": "Customize the cut for each device", "y": 0.5, "color": "#1B2A4E" }]
    }
  ]
}
```

An override is laid over what it overrides: an object merges key by key, so the `iphone` override
above changes the clip's `to` and keeps its `take` and `from`, and `"ipad": { "y": 0.08 }` in a
caption changes only its `y`. A list or a single value replaces what's there, so the iPhone's
`captions` are its whole list, without the caption for the turn it doesn't show.

A clip that names `devices`, as the card does, is in only those types' videos: one type can show
something the others don't, or show something else in its place.

One device type's takes in an edit must come from devices with the same screen, since positions in
the step log are the screen's points: `cut` refuses an edit whose iPhone takes, say, mix a 6.1-inch
and a 6.9-inch iPhone, naming the takes on each.

### Captions

A clip's `captions` are text over the video, shown from its `from` to its `to`
[anchors](#anchors-times-that-follow-the-app). A caption with neither is up for the whole clip, but
clear of its cross-fades. Any number can be up at once, and they may overlap; when and where each
appears is the edit's to say. A caption's `to` can name a later clip by its `id`, to stay up over the
clips until then, as `{ "clip": "sync", "step": "synced", "offset": -0.2 }` does in the
[edit above](#edits-the-video-cut-from-the-takes). Only `to` can name another clip: a caption that
starts in a later clip belongs to that clip.

An anchor outside the part of the take its clip plays fails the `cut`, naming the caption.

`y` places a caption's center as a share of the video's height, from 0 at the top to 1 at the
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
edit is. A take's own sound plays at its clip's `speed`, so it may not sound right in a clip sped
up or slowed down.

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
corners a turn uncovers, are the edit's `background` color, black unless it says otherwise.

## What's recorded in each file

Every movie Retake writes says how it was made, in its own metadata, so a take or a video found
later can be traced to the app and the setup behind it:

- the version of Retake that made it;
- the app's version and build (`CFBundleShortVersionString` and `CFBundleVersion`);
- the version of The Button Heist that drove the app;
- the device's model, such as "iPad Pro (11-inch) (3rd generation)" (`iPad13,4`), and its iOS
  version.

A take also records its scene, set and state. A video records the edit it was cut from, the same
details for each take in it, with its scene and when it was recorded, and every app build, device
and Button Heist its takes were recorded with, since they may differ. `retake cut` warns when they do.

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
interface: steps find elements the way VoiceOver does, and touches are synthesized inside the app.

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
`https://justinseanmartin.github.io/Retake/schemas/<version>/edit.schema.json`, for the release
`retake version` names. Editors that read JSON
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

## Limitations

Retake does what the App Store previews it was first built for needed. There is definitely still
room for improvement and additions:

- **The effects are limited.** Each of [a clip's effects](#clips) takes a handful of
  options, not full control of its style, and there are few kinds: a caption's symbol has one
  animation, for one.
- **The iPhone Duo isn't supported yet.** Its folding screen gives it two sizes of screen, which
  scenes, aspects and edits don't yet tell apart. Support should be straightforward to add, but
  needs a physical iPhone Duo to be tested on.
- **Captures are done in the device's own resolution,** which often isn't a size App Store Connect
  takes screenshots in; see [Captures](#captures-stills-from-the-same-scenes).

### What `state` doesn't cover yet

- **App group containers** (`containerURL(forSecurityApplicationGroupIdentifier:)`) and **defaults
  suites** (`UserDefaults(suiteName:)`) are the real ones in every state. A group's container is
  shared with the app's extensions, which Retake doesn't launch.
- **Code that calls `CFPreferences` directly** reads the real defaults, and so do system frameworks
  that keep their own state in the app's defaults, such as StoreKit's update timestamps.
- **The keychain** is the real one: iOS keeps it even across reinstalls. Keychain state needs a
  launch flag of the app's own.

### Things a `set` can't control

On a physical device, nothing outside the app can grant permissions in advance, change the clock, or
fill the photo library, and a scene can't answer a permission prompt either (see
[what a scene can't reach](#what-a-scene-cant-reach)). A permission granted by hand stays granted,
whatever a set's `state`, since iOS keeps it apart from the app's files and defaults, so grant it
once, before recording.

### What a `scene` can't reach

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

Pull requests that add any of these, or anything else, are welcome: see
[CONTRIBUTING.md](CONTRIBUTING.md) to build Retake from source and send a change. Or fork it and go
wild.

## License

Apache License 2.0; see [LICENSE](LICENSE). Retake's releases include TheInsideJob as The Button Heist (also
Apache 2.0) publishes it, with its dependencies linked in and their licenses shipped with it.
