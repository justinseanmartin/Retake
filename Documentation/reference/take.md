<!-- Generated from Retake's schemas: RETAKE_REGENERATE=1 swift test --filter Reference. Don't edit. -->

# A step log

A take's step log, `<scene>.json` beside its movie `<scene>.mov` in the output directory's `takes/<type>/`, or `<scene>.previous.json` or `<scene>.failed.json` beside theirs: what was recorded, with what, and when each step happened on the movie's own clock, where it touched, and what was on screen after it. Retake writes it when it records the take, and reads it to list, clean and cut takes; a project doesn't write or edit it. Times are seconds into the movie, to the millisecond; positions and sizes on the screen are its points, portrait, to the hundredth.

Its schema is published at <https://justinseanmartin.github.io/Retake/schemas/0.0.2/take.schema.json>, and `retake schema take` prints it.

## Fields

| Field | Type | Default | Description |
| --- | --- | --- | --- |
| `format` | `1` |  | The step log's format. Retake doesn't write it: a log without it is format 1, the only one so far. A log of a later format was recorded by a newer Retake, and this one refuses it, saying to update Retake. |
| `scene` | string, not empty | required | The scene recorded, as its file in `scenes/<type>/` is named, without `.json`. |
| `take` | integer ≥ 1 |  | Deprecated: the take's number among the scene's, from 1, which takes recorded when they were numbered give. Still read, and ignored. |
| `set` | string, not empty | required | The set the scene started on. |
| `state` | `"clean"`, `"cloned"` or `"live"` | required | The set's state, which the take's data started from. |
| `deviceType` | `"iphone"` or `"ipad"` | required | The type of device recorded. |
| `device` | [object](#device) | required | The device recorded. Nothing personal: not its name, nor its UDID. |
| `app` | [object](#app) | required | The app recorded. |
| `retake` | string, not empty | required | The version of Retake that recorded it. |
| `buttonHeist` | [object](#buttonheist) | required | The Button Heist that drove the app: the one embedded in it. |
| `recordedAt` | string matching `^[0-9]{4}-(0[1-9]\|1[0-2])-(0[1-9]\|[12][0-9]\|3[01])T([01][0-9]\|2[0-3]):[0-5][0-9]:[0-5][0-9](\.[0-9]+)?(Z\|[+-]([01][0-9]\|2[0-3]):?[0-5][0-9])$` | required | When the take was recorded, in ISO 8601: to the second, with any fraction of it, and Z or the zone's offset, such as 2026-11-06T09:30:00Z. |
| `failure` | string |  | Why the take failed, for one whose step didn't run; absent for a take that played every step. No edit is cut from a failed take. |
| `duration` | number ≥ 0 | required | The movie's length, in seconds, to the millisecond. |
| `size` | list of integer ≥ 0, exactly 2 | required | The movie's size, [width, height], in capture pixels: its first frame's, which every frame is stored in. |
| `previewAspect` | [shape](#shape), or [preview-aspect](#preview-aspect) |  | The shape the set's previewAspect gave the app's window: at the top of the screen in portrait, and at its left in landscape; a shape alone is portrait's. Absent when the app filled the screen. The edit crops each frame to it. |
| `aspect` | [shape](#shape), or [preview-aspect](#preview-aspect) |  | Deprecated: previewAspect's old name, which takes recorded before it was renamed give. Still read, but never with previewAspect. |
| `screen` | list of number > 0, exactly 2 | required | The device's screen, [width, height], in points, portrait: what the log's touches and frames are in, for the edit to find them in the movie's frames. |
| `frames` | integer ≥ 0 | required | Frames written to the movie. |
| `dropped` | integer ≥ 0 | required | Frames the encoder wasn't ready for, which a hitch in the take shows. |
| `launch` | [object](#launch) |  | For a take recorded from before the app launched, as its scene's recordsLaunch asks: when it launched, for an edit to cut in on, each in seconds into the movie, to the millisecond. |
| `clock` | [object](#clock) | required | How the steps were placed on the movie's clock. |
| `beforeSteps` | [object](#beforesteps) |  | What was on screen once the lead-in was over, read just before the first step: what an edit's spotlights and blurs find their elements in until the first step has ended. Absent for a take recorded before Retake read it, or when the screen couldn't be read. |
| `steps` | list of [step](#step) | required | The steps played while recording, in order. Setup steps, played before recording starts, aren't logged. |
| `shapes` | list of [object](#shapes) | required | The movie's first shape, and each change after it, as the device turned. |
| `hitches` | list of [object](#hitches) |  | Each time the app's main thread missed a frame while it was recorded. Absent when Retake's support library didn't watch. |

### `device`

The device recorded. Nothing personal: not its name, nor its UDID.

| Field | Type | Default | Description |
| --- | --- | --- | --- |
| `model` | string | required | Its hardware identifier, such as iPad13,4. |
| `marketingName` | string |  | Its marketing name, such as iPad Pro (11-inch) (3rd generation), when devicectl gives one. |
| `os` | string | required | Its iOS version and build, such as 26.6.2 (23G90). |

### `app`

The app recorded.

| Field | Type | Default | Description |
| --- | --- | --- | --- |
| `bundleID` | string, not empty | required | Its bundle ID. |
| `version` | string |  | Its CFBundleShortVersionString, as installed on the device. |
| `build` | string |  | Its CFBundleVersion. |

### `buttonHeist`

The Button Heist that drove the app: the one embedded in it.

| Field | Type | Default | Description |
| --- | --- | --- | --- |
| `version` | string, not empty | required | Its version. |
| `commit` | string |  | The commit of the local clone it was built from, for one that was. |

### `launch`

For a take recorded from before the app launched, as its scene's recordsLaunch asks: when it launched, for an edit to cut in on, each in seconds into the movie, to the millisecond.

| Field | Type | Default | Description |
| --- | --- | --- | --- |
| `launched` | number | required | When Retake launched the app. |
| `reported` | number | required | When Retake's support library, in the app, reported in. |
| `connected` | number | required | When The Button Heist connected to the app. |

### `clock`

How the steps were placed on the movie's clock.

| Field | Type | Default | Description |
| --- | --- | --- | --- |
| `deviceAhead` | number |  | Seconds the device's clock was ahead of the Mac's, measured once at the start of the take, through which the device's own times for each step are placed. Absent when it couldn't be measured, and every step is timed by the Mac. |

### `beforeSteps`

What was on screen once the lead-in was over, read just before the first step: what an edit's spotlights and blurs find their elements in until the first step has ended. Absent for a take recorded before Retake read it, or when the screen couldn't be read.

| Field | Type | Default | Description |
| --- | --- | --- | --- |
| `at` | number | required | When the screen was read, in seconds into the movie, to the millisecond. |
| `elements` | list of [screen-element](#screen-element) | required | What was on screen, in the order VoiceOver reads it. |

### `shapes`

| Field | Type | Default | Description |
| --- | --- | --- | --- |
| `at` | number ≥ 0 | required | When the frames took this shape, in seconds into the movie, to the millisecond. |
| `size` | list of integer ≥ 0, exactly 2 | required | The frames' size as the device sent them, [width, height], in capture pixels. |
| `turn` | integer | required | Degrees clockwise the frames are turned to fit the movie's size: 0, 90, or -90 for a quarter counterclockwise. |

### `hitches`

| Field | Type | Default | Description |
| --- | --- | --- | --- |
| `at` | number | required | When the app last drew, in seconds into the movie, to the millisecond. |
| `duration` | number ≥ 0 | required | Seconds until it drew again. |

## Definitions

### step

One step as it was recorded.

| Field | Type | Default | Description |
| --- | --- | --- | --- |
| `number` | integer ≥ 1 | required | Its number among the scene's steps, from 1. |
| `id` | string, not empty |  | Its id in the scene, for one that has one. |
| `action` | string, not empty | required | The kind of step: tap, drag, type, activate, orientation, waitFor or capture, or hold for one that's only a pause. |
| `start` | number | required | When it began, in seconds into the movie, to the millisecond, as the device saw it where it could. |
| `end` | number | required | When it ended, in seconds into the movie, to the millisecond; for a waitFor, when its element came or went. |
| `timedBy` | `"device"` or `"mac"` | required | Whose times start and end are. device: the device's own, placed through clock.deviceAhead. mac: when the Mac sent the step and heard back, which a round trip either side widens. |
| `touch` | [point](#point) |  | Where it touched the screen: a tap's point, by point or on an element, and where a drag came down. |
| `touchEnd` | [point](#point) |  | Where a drag lifted. |
| `touchDuration` | number ≥ 0 |  | Seconds the finger was on the screen, from start, as The Button Heist timed it. |
| `elements` | list of [screen-element](#screen-element) |  | What was on screen when it ended, in the order VoiceOver reads it. |

### screen-element

An element on screen, as VoiceOver knows it, which an edit's spotlights and blurs find.

| Field | Type | Default | Description |
| --- | --- | --- | --- |
| `label` | string |  | Its accessibility label. |
| `value` | string |  | Its value. |
| `identifier` | string |  | The accessibilityIdentifier the app gives it. |
| `hint` | string |  | Its accessibility hint. |
| `traits` | list of string |  | Its traits, by The Button Heist's names. |
| `frame` | list of number, exactly 4 |  | Where it is, [x, y, width, height], in screen points. |
| `activationPoint` | [point](#point) |  | Where a tap on it touches. |

### point

[x, y], in screen points from the top left.

Type: list of number, exactly 2.

### preview-aspect

The app window's shape in portrait, and in landscape.

| Field | Type | Default | Description |
| --- | --- | --- | --- |
| `portrait` | [shape](#shape) |  | Its shape in portrait, at the top of the screen. |
| `landscape` | [shape](#shape) |  | Its shape in landscape, at the left of the screen. |

Gives at least one of `portrait` and `landscape`.

### shape

A width and a height, each a positive decimal with digits either side of any point, such as 3:4.

Type: string matching `^(0*[1-9][0-9]*(\.[0-9]+)?\|0+\.[0-9]*[1-9][0-9]*):(0*[1-9][0-9]*(\.[0-9]+)?\|0+\.[0-9]*[1-9][0-9]*)$`.
