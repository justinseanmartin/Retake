<!-- Generated from Retake's schemas: RETAKE_REGENERATE=1 swift test --filter Reference. Don't edit. -->

# An edit

An edit: the video cut from the takes, for each device type it names. Anything in a clip, or at the top, can be given again under a device type, and applies only to that type's video.

Its schema is published at <https://justinseanmartin.github.io/Retake/schemas/0.0.1/edit.schema.json>, and `retake schema edit` prints it.

Every object in an edit, at the top and in each of the definitions below, can be given again under `iphone` or
`ipad`, with any of its fields, and applies only to that device type's video. An object in an override is laid over
the one it overrides key by key; a list, or a single value, replaces it. At the top, an override can't give
`devices` or `takes`.

## Fields

| Field | Type | Default | Description |
| --- | --- | --- | --- |
| `$schema` | string |  | The URL of the schema the file is written against, for editors. Optional; a file is read against this Retake's schema whatever it names. |
| `intent` | string |  | What the video is there to show. Not read by the render. |
| `devices` | list of `"iphone"` or `"ipad"`, at least 1, each once | required | The device types it makes a video for. |
| `takes` | [object](#takes) |  | The take of each scene the edit was last cut from, per device type, as `retake cut` records them. |
| `music` | [music](#music) |  |  |
| `tapSound` | [tap-sound](#tap-sound) |  |  |
| `takeAudioVolume` | number ≥ 0 | `1` | The level of the take's own sound, where a clip plays it. |
| `background` | [color](#color) | `"#000000"` | The colour of letterbox bands, and of the corners a turn uncovers. |
| `turns` | `"letterboxed"` or `"device"` | `"letterboxed"` | How the video shows the device turning. letterboxed: the app stays upright, landscape letterboxed on the canvas. device: the video stays in the device's frame. |
| `turnBlur` | [turn-blur](#turn-blur) |  |  |
| `clips` | list of [clip](#clip), at least 1 | required |  |

### `takes`

The take of each scene the edit was last cut from, per device type, as `retake cut` records them.

| Field | Type | Default | Description |
| --- | --- | --- | --- |
| `iphone` | object of names to integer ≥ 1 |  | Each scene's pinned iphone take, by the scene's name: its number. |
| `ipad` | object of names to integer ≥ 1 |  | Each scene's pinned ipad take, by the scene's name: its number. |

## Definitions

### clip

A stretch of a take, played in order.

| Field | Type | Default | Description |
| --- | --- | --- | --- |
| `id` | string, not empty |  | Names the clip, for a caption to run on into it. Unique in the edit. |
| `intent` | string |  | What the clip is there to show, for whoever changes the video later. Not read by the render. |
| `take` | string, not empty | required | The scene whose pinned take the clip is cut from. |
| `from` | [anchor](#anchor) | required | Where the clip starts in the take. |
| `to` | [anchor](#anchor) | required | Where it ends. |
| `speed` | number > 0 | `1` | How fast it plays: 2 is twice as fast. |
| `crossfade` | number ≥ 0 | `0` | Seconds it cross-fades in over the clip before. |
| `audioCrossfade` | number ≥ 0 |  | Seconds its sound fades in over, when longer than crossfade. |
| `touches` | boolean | `false` | Draws the take's touches, from the step log. |
| `takeAudio` | boolean | `false` | Plays the take's own sound with the clip. |
| `captions` | list of [caption](#caption) |  |  |
| `sounds` | list of [sound](#sound) |  | Sound effects, played at normal speed however fast the clip plays. |
| `spotlight` | [spotlight](#spotlight) |  |  |
| `blurs` | list of [blur](#blur) |  | Blurs over a stretch of the take, for anything private it shows. |
| `stills` | list of [still](#still) |  | Frames of other takes, popped in over the clip. |
| `turns` | `"letterboxed"` or `"device"` |  | How this clip shows the device turning; the edit's turns when not given. |
| `turnBlur` | [turn-blur](#turn-blur) |  |  |

### caption

Text over the video, from its from to its to.

| Field | Type | Default | Description |
| --- | --- | --- | --- |
| `text` | string, not empty | required |  |
| `y` | number from 0 to 1 | required | Its centre, as a share of the video's height: 0 at the top, 1 at the bottom. |
| `color` | [color](#color) | required |  |
| `from` | [anchor](#anchor) |  | When it starts; the clip's from when not given. |
| `to` | [anchor](#anchor), or [caption-end](#caption-end) |  | When it ends: an anchor in its clip's take, or, naming a later clip, in that clip's take; the clip's to when not given. |
| `symbol` | [symbol](#symbol) |  |  |

### symbol

An SF Symbol before the caption's text.

| Field | Type | Default | Description |
| --- | --- | --- | --- |
| `name` | string, not empty | required | The symbol's name, such as rotate.right. |
| `animation` | [animation](#animation) |  |  |

### animation

How the symbol moves, from when the caption appears.

| Field | Type | Default | Description |
| --- | --- | --- | --- |
| `rotate` | [rotate](#rotate) | required |  |

### rotate

Turns the symbol.

| Field | Type | Default | Description |
| --- | --- | --- | --- |
| `degrees` | number | required | Clockwise when positive. |
| `duration` | number > 0 | required | Seconds it takes. |

### sound

A sound effect.

| Field | Type | Default | Description |
| --- | --- | --- | --- |
| `file` | string, not empty | required | A sound file, relative to the directory holding retake.json. |
| `at` | [anchor](#anchor) | required | When it starts. |
| `volume` | number ≥ 0 | `1` | Its level, where 1 is as recorded. |
| `duration` | number > 0 |  | Seconds it plays before fading out, for an effect longer than its moment; all of it when not given. |

### spotlight

Dims the rest of the screen around an element or a rectangle, with a pulsing ring.

| Field | Type | Default | Description |
| --- | --- | --- | --- |
| `element` | [element](#element) |  | An element, found in the take's step log at the moment. |
| `rect` | [rect](#rect) |  |  |
| `padding` | number ≥ 0 | `8` | Points of space around it. |
| `color` | [color](#color) | `"#FFFFFF"` | The ring's colour. |
| `from` | [anchor](#anchor) |  | When it starts; the clip's from when not given. |
| `to` | [anchor](#anchor) |  | When it ends; the clip's to when not given. |

Gives exactly one of `element` or `rect`.

### blur

A blur over an element or a rectangle.

| Field | Type | Default | Description |
| --- | --- | --- | --- |
| `element` | [element](#element) |  | An element, found in the take's step log at the moment. |
| `rect` | [rect](#rect) |  |  |
| `from` | [anchor](#anchor) |  | When it starts; the clip's from when not given. |
| `to` | [anchor](#anchor) |  | When it ends; the clip's to when not given. |
| `radius` | number > 0 | `20` | How strong the blur is. |

Gives exactly one of `element` or `rect`.

### still

A frame of another take, popped in over the clip.

| Field | Type | Default | Description |
| --- | --- | --- | --- |
| `take` | string, not empty | required | The scene whose pinned take it's from. |
| `at` | [anchor](#anchor) | required | The moment in that take. |

### rect

A rectangle in screen points.

| Field | Type | Default | Description |
| --- | --- | --- | --- |
| `x` | number ≥ 0 | required |  |
| `y` | number ≥ 0 | required |  |
| `width` | number > 0 | required |  |
| `height` | number > 0 | required |  |

### music

Plays under the whole video.

| Field | Type | Default | Description |
| --- | --- | --- | --- |
| `file` | string, not empty | required | A sound file, relative to the directory holding retake.json. |
| `volume` | number ≥ 0 | `1` | Its level, where 1 is as recorded. |
| `fadeOut` | number ≥ 0 | `0` | Seconds it fades out over at the end. |

### tap-sound

Plays as each touch a clip draws lands: each tap by point, and the start of each drag.

| Field | Type | Default | Description |
| --- | --- | --- | --- |
| `file` | string, not empty | required | A sound file, relative to the directory holding retake.json. |
| `volume` | number ≥ 0 | `1` | Its level, where 1 is as recorded. |

### turn-blur

Blurs each turn, easing in just before it and out after.

| Field | Type | Default | Description |
| --- | --- | --- | --- |
| `duration` | number > 0 | required | Seconds the blur lasts. |

### anchor

A moment in a take: a step and where to go from it, or plain seconds from the take's start.

Type: number ≥ 0, or [step-anchor](#step-anchor).

### step-anchor

A step, and where to go from it.

| Field | Type | Default | Description |
| --- | --- | --- | --- |
| `step` | string, not empty, or integer, not 0 | required | A step's id, its number from 1, a negative number counting back from the last (-1 is the last), or start or end, the take's own first and last frames. |
| `offset` | number |  | Seconds to move: forward from the step's end, or back from its start. |
| `fraction` | number from -1 to 1 |  | A share of the gap to the neighbouring step to move: forward from the step's end toward the next step's start, or back from its start toward the previous step's end. |
| `edge` | `"start"` or `"end"` |  | Counts the offset or fraction from the step's other edge. |

### caption-end

A later clip, by its id, and an anchor in that clip's take; that clip's to when it gives no step.

| Field | Type | Default | Description |
| --- | --- | --- | --- |
| `clip` | string, not empty | required | The later clip's id. |
| `step` | string, not empty, or integer, not 0 |  | A step's id, its number from 1, a negative number counting back from the last (-1 is the last), or start or end, the take's own first and last frames. |
| `offset` | number |  | Seconds to move: forward from the step's end, or back from its start. |
| `fraction` | number from -1 to 1 |  | A share of the gap to the neighbouring step to move: forward from the step's end toward the next step's start, or back from its start toward the previous step's end. |
| `edge` | `"start"` or `"end"` |  | Counts the offset or fraction from the step's other edge. |

### element

An element on screen, as VoiceOver knows it: by any of its label, value, identifier, hint and traits.

| Field | Type | Default | Description |
| --- | --- | --- | --- |
| `label` | string, not empty |  | Its accessibility label. |
| `value` | string |  | Its value: a text field's placeholder, or what's typed in it. |
| `identifier` | string, not empty |  | The accessibilityIdentifier the app gives it. |
| `hint` | string, not empty |  | Its accessibility hint: what VoiceOver says it does. |
| `traits` | list of `"adjustable"`, `"alert"`, `"allowsDirectInteraction"`, `"autoCorrectCandidate"`, `"backButton"`, `"button"`, `"causesPageTurn"`, `"deleteKey"`, `"draggable"`, `"footer"`, `"header"`, `"image"`, `"inactive"`, `"isEditing"`, `"keyboardKey"`, `"launchIcon"`, `"link"`, `"map"`, `"menuItem"`, `"notEnabled"`, `"pickerElement"`, `"playsSound"`, `"popupButton"`, `"radioButton"`, `"searchField"`, `"secureTextField"`, `"selected"`, `"selectionDismissesItem"`, `"spacer"`, `"startsMediaSession"`, `"staticText"`, `"statusBarElement"`, `"summaryElement"`, `"switchButton"`, `"tabBar"`, `"tabBarItem"`, `"tableIndex"`, `"textArea"`, `"textEntry"`, `"textOperationsAvailable"`, `"updatesFrequently"`, `"visited"` or `"webContent"`, at least 1, each once |  | Traits it has, every one, by The Button Heist's names, as `retake compose` prints them. |
| `occurrence` | integer ≥ 1 |  | Which of several matching elements, counted from 1 in the order VoiceOver reads the screen. |

Gives at least one of `label`, `value`, `identifier`, `hint` and `traits`.

### color

A colour: #RRGGBB, or #RRGGBBAA with its opacity.

Type: string matching `^#([0-9A-Fa-f]{6}\|[0-9A-Fa-f]{8})$`.
