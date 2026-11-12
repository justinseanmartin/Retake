# Releases

What each release of Retake adds and changes, newest first. Until 1.0, a breaking change comes with
a new minor version, from 0.1 to 0.2, and is spelled out here; a patch version, such as 0.0.2, adds
to what's there without breaking it. Pin a version with `mise use github:justinseanmartin/Retake@<version>`.

## 0.0.3 (unreleased)

**Breaking: scenes pick their device types as edits do.** A project's scenes move out of
`scenes/iphone/` and `scenes/ipad/`, which aren't read any more, into `scenes/`. Retake names any
scene left behind, in `validate` and `record`, and records nothing until it's moved.

- **To move a project**, put each scene in `scenes/`. Where a type's scene and the other's say the
  same, keep one. Where they differ, keep one and give the other's differences under `"iphone": {
  … }` or `"ipad": { … }`, in a step or at the top, as in an edit; give a step only one type plays
  `"devices": ["ipad"]`. A scene for only one type names it: `"devices": ["iphone"]`.
- An edit that anchored by step number to a scene that now has a step for one type only should
  anchor by the step's `id`: the step keeps its number on both types, so the numbers after it don't
  move, but nothing can anchor to it on the type that skips it.

**Scenes**

- **A scene names the device types it plays on**, `devices`, every one unless it says, and a
  step's own `devices` the types among those it plays on: on another it's skipped but keeps its
  number, so the steps after it are numbered alike, and an anchor to it fails there. Anything at a
  scene's top or in a step can be given again under `iphone` or `ipad`, laid over what it overrides,
  as in an edit; an override or a step's `devices` naming a type the scene doesn't play on is
  refused.
- **`compose` writes the scene for the device it's on**, keeping each step it doesn't change as the
  file has it, its overrides and `devices` with it.
- **`retake init`** starts a project with `scenes/` and one `launch` scene for every type.
- **An edit's `devices`** is every type unless it names some, as a scene's is.

**Taps and drags**

- **A tap or a drag's end on an element can be moved off it**, by `offset` in points and
  `offsetPercent` in percent of the element's width and height, from its activation point: for a
  finger that has to touch or lift somewhere the element places rather than on it, such as a game
  piece drawn above the finger. A tap or a drag's start with an offset is touched where Retake finds
  it on the screen just before. Nothing breaks.

**Fixes**

- **`retake compose` waits out each step's hold** before answering, as `record` does, rather than
  only writing it into the scene: a tap's from when it's sent, any other step's from when it ends,
  and the scene's `defaultHold` for a step that gives none. The next step no longer runs while the
  app is still moving from the last, landing where it wouldn't in a take, and the screen `compose`
  prints after a step, with its `suggestion`, is the one once the hold is over. Nothing breaks.

## 0.0.2 (2026-11-10)

Stills from the same scenes as the videos, and turns that wait for the device.

**Captures**

- A scene's **`capture`** step saves the screen as a PNG, named for the step, as `record` plays the
  scene, into the output directory's `captures/<type>/<scene>/`. It's a screenshot the device
  takes, at its screen's own resolution, with the clean status bar the device shows while it's
  recorded. See [Captures](README.md#captures-stills-from-the-same-scenes).
- **`retake record --stills-only`** takes a scene's captures without recording a take.
- **`retake compose`** adds a capture step with `capture --name <name>`.
- **`retake clean --captures`** deletes captures, and `clean --unused` keeps every scene that
  captures.
- `record` says, for each size it captured, which App Store Connect display takes screenshots that
  size, and which display it requires. A capture is the device's own resolution, which often isn't
  a size App Store Connect takes: Retake isn't purpose built specifically for App Store screenshots.

**Changes**

- **`retake init` writes a starter set, scene and edit** in a new project: `sets/base.json`, as
  the `defaultSet`; a `launch` scene for each device type, which records the app launching; and
  `edits/preview.json`, which cuts it, captioned. A project whose folders already hold files gets
  none of them.
- **A turn waits for the rotation.** While `record` has the device's screen, an `orientation` step
  ends once the screen has stopped moving, not as soon as the app has turned; when composing, a
  second and a half after the turn. A scene no longer needs a `hold` after a turn to keep the
  rotation out of the next step.
- Fixed a hang when many of the tools Retake runs, such as `devicectl`, ran at once on a Mac with
  few cores, as Retake's own tests do on CI.

**Compatibility**

Everything 0.0.1 wrote still works with 0.0.2: its files, its takes, and the apps it embedded,
since the support library's contract is unchanged. Two things to know:

- A take recorded again with 0.0.2 has its `orientation` steps end later, after the rotation rather
  than during it. An edit anchored to a turn's end, such as a clip that starts there, lands later in the
  take than it did, so check those clips after recording again, and drop a `hold` a scene has after
  a turn only to wait for it.
- A file whose `"$schema"` names 0.0.1's schema is read as 0.0.2's, with a warning; `retake cut`
  updates the key. Retake 0.0.1 can't read a scene with a `capture` step.

## 0.0.1 (2026-11-09)

The first release of Retake: App Store preview videos made from your running iOS app, on a real
iPhone or iPad over USB, re-recorded and re-cut from files you check in.

- **Sets** put the app in a known state before a take: its files, defaults, launch environment and
  arguments, appearance, and the preview's shape (`previewAspect`), with no code in the app.
- **Scenes** walk through the app by what's on screen, with taps, typing, drags, waits and turns;
  `retake compose` writes one a step at a time on the device.
- **`retake record`** plays each scene on the device and records a take: a movie and a step log of
  when each step ran and what was on screen.
- **Edits** cut the takes into a video, anchored to steps rather than seconds, so a new take reuses
  the edit: captions, touches, spotlights, blurs, stills, cards, music and sounds, cross-fades,
  speed, and per-device overrides. **`retake cut`** renders a ProRes master and an `.mp4` to App
  Store Connect's specification.
- **`retake share`** makes a small video to post: one cut or take, or several side by side, such as
  the iPhone's and the iPad's.
- **`retake status`**, **`takes`**, **`info`**, **`validate`**, **`doctor`**, **`check`**, and JSON
  Schemas for every file, published at `https://justinseanmartin.github.io/Retake/schemas/0.0.1/`
  for editors to complete and check them.

Needs a Mac with Apple silicon on macOS 14 or later, Xcode, and an iPhone or iPad on iOS 17 or
later. Built against The Button Heist 0.7.1. The binary is signed with a Developer ID and
notarized.
