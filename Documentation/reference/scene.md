<!-- Generated from Retake's schemas: RETAKE_REGENERATE=1 swift test --filter Reference. Don't edit. -->

# A scene

A scene: a set, and the steps played on it, on each of its device types. Anything at the top or in a step can be given again under a device type, and applies only on that type.

Its schema is published at <https://justinseanmartin.github.io/Retake/schemas/0.0.3/scene.schema.json>, and `retake schema scene` prints it.

Every object in an edit, at the top and in each of the definitions below, can be given again under `iphone` or
`ipad`, with any of its fields, and applies only to that device type's video. An object in an override is laid over
the one it overrides key by key; a list, or a single value, replaces it. At the top, an override can't give
`devices`.

## Fields

| Field | Type | Default | Description |
| --- | --- | --- | --- |
| `$schema` | string |  | The URL of the schema the file is written against, for editors. Optional; a file is read against this Retake's schema whatever it names. |
| `devices` | list of `"iphone"` or `"ipad"`, at least 1, each once |  | The device types it plays on; every one when not given. |
| `set` | string, not empty |  | The set the scene starts on; the project's defaultSet when not given. |
| `setup` | list of [step](#step) |  | Steps played before recording starts. Nothing anchors to them, so they have no id. |
| `leadIn` | number ≥ 0 | `1` | Seconds recorded before the first step. For a scene that records its launch, they start once the app is reachable, after the launch is recorded. |
| `tail` | number ≥ 0 | `1` | Seconds recorded after the last step. |
| `defaultHold` | number ≥ 0 | `0` | The hold of each step that doesn't give its own. |
| `recordsLaunch` | boolean | `false` | Starts recording before the app launches, to catch its launch screen. |
| `orientation` | `"portrait"`, `"portrait-upside-down"`, `"landscape-left"` or `"landscape-right"` | `"portrait"` | The orientation the device is turned to before the app launches. |
| `steps` | list of [step](#step), at least 1 | required | What the scene does, in order. |

## Definitions

### step

One thing the scene does, led by what it does, and the pause after it. A step can be only a hold.

| Field | Type | Default | Description |
| --- | --- | --- | --- |
| `tap` | [object](#steptap-with-x), or [touchElement](#touchElement) |  | Touches a point, x and y, or an element. An element is touched at its activation point, as the screen has it just before the tap, moved by its offset and offsetPercent; the step log records where, so either is drawn in the video. |
| `drag` | [object](#stepdrag) |  | A straight one-finger drag from one point or element to another. An element is touched at its activation point, as the screen has it just before the drag, moved by its offset and offsetPercent. |
| `type` | [object](#steptype) |  | Types text key by key on the on-screen keyboard. |
| `activate` | [element](#element) |  | An accessibility activation of an element, with no touch, for getting somewhere off camera. |
| `orientation` | `"portrait"`, `"portrait-upside-down"`, `"landscape-left"` or `"landscape-right"` |  | Turns the device, with no hand on it; the step ends when the app has turned and the device has drawn the rotation. |
| `waitFor` | [object](#stepwaitfor) |  | Waits until an element is on screen, or with gone until it isn't. The step fails if it doesn't happen in time. |
| `capture` | string matching `^[A-Za-z0-9][A-Za-z0-9._-]*$` |  | Saves the screen as a still, as it is when the step before has ended and its hold is over, as a PNG named for it in the output directory's captures/<type>/<scene>/, when the scene is recorded. Unique in the scene. Not in setup. |
| `hold` | number ≥ 0 |  | Seconds to pause after the step, or for a tap, from when it's sent; the scene's defaultHold when not given. |
| `id` | string, not empty |  | The name edits anchor to. Unique in the scene; it can't look like a number, which anchors count steps by, nor be start or end. |
| `devices` | list of `"iphone"` or `"ipad"`, at least 1, each once |  | The device types it plays on; every one when not given. On another, it's skipped but keeps its number, so the steps after it are numbered alike on every type, and nothing can anchor to it there. |

Gives exactly one of `tap`, `drag`, `type`, `activate`, `orientation`, `waitFor` or `capture`, or only `hold`.

#### `step.tap`, with `x`

| Field | Type | Default | Description |
| --- | --- | --- | --- |
| `x` | number ≥ 0, or string matching `^(100(\.0+)?\|[0-9]{1,2}(\.[0-9]+)?)%$` | required | Screen points from the left, or a percentage of the screen's width as the device faces. |
| `y` | number ≥ 0, or string matching `^(100(\.0+)?\|[0-9]{1,2}(\.[0-9]+)?)%$` | required | Screen points from the top, or a percentage of the screen's height as the device faces. |

#### `step.drag`

A straight one-finger drag from one point or element to another. An element is touched at its activation point, as the screen has it just before the drag, moved by its offset and offsetPercent.

| Field | Type | Default | Description |
| --- | --- | --- | --- |
| `from` | [object](#stepdragfrom-with-x), or [touchElement](#touchElement) | required | Where the finger comes down: a point, x and y, or an element. |
| `to` | [object](#stepdragto-with-x), or [touchElement](#touchElement) | required | Where it lifts: a point, x and y, or an element. |
| `duration` | number > 0 | `0.5` | Seconds the drag takes. |

#### `step.type`

Types text key by key on the on-screen keyboard.

| Field | Type | Default | Description |
| --- | --- | --- | --- |
| `text` | string, not empty | required | What to type; \n presses return. |
| `into` | [element](#element) |  | The element to type into; the field already being typed in when not given. |

#### `step.waitFor`

Waits until an element is on screen, or with gone until it isn't. The step fails if it doesn't happen in time.

| Field | Type | Default | Description |
| --- | --- | --- | --- |
| `label` | string, not empty |  | Its accessibility label. |
| `value` | string |  | Its value: a text field's placeholder, or what's typed in it. |
| `identifier` | string, not empty |  | The accessibilityIdentifier the app gives it. |
| `hint` | string, not empty |  | Its accessibility hint: what VoiceOver says it does. |
| `traits` | list of `"adjustable"`, `"alert"`, `"allowsDirectInteraction"`, `"autoCorrectCandidate"`, `"backButton"`, `"button"`, `"causesPageTurn"`, `"deleteKey"`, `"draggable"`, `"footer"`, `"header"`, `"image"`, `"inactive"`, `"isEditing"`, `"keyboardKey"`, `"launchIcon"`, `"link"`, `"map"`, `"menuItem"`, `"notEnabled"`, `"pickerElement"`, `"playsSound"`, `"popupButton"`, `"radioButton"`, `"searchField"`, `"secureTextField"`, `"selected"`, `"selectionDismissesItem"`, `"spacer"`, `"startsMediaSession"`, `"staticText"`, `"statusBarElement"`, `"summaryElement"`, `"switchButton"`, `"tabBar"`, `"tabBarItem"`, `"tableIndex"`, `"textArea"`, `"textEntry"`, `"textOperationsAvailable"`, `"updatesFrequently"`, `"visited"` or `"webContent"`, at least 1, each once |  | Traits it has, every one, by The Button Heist's names, as `retake compose` prints them. |
| `occurrence` | integer ≥ 1 |  | Which of several matching elements, counted from 1 in the order VoiceOver reads the screen. A last resort, since it breaks when the layout changes: name the element closely enough, by its traits, identifier, value or hint, that only it matches. |
| `gone` | boolean | `false` | Waits for the element to leave instead. |
| `timeout` | number > 0 | `10` | Seconds to wait: at most The Button Heist's longest wait, by default 60 s, which BUTTONHEIST_MAX_WAIT_TIMEOUT raises, set where Retake runs and in the set's environment, for the app. |

Gives at least one of `label`, `value`, `identifier`, `hint` and `traits`.

#### `step.drag.from`, with `x`

| Field | Type | Default | Description |
| --- | --- | --- | --- |
| `x` | number ≥ 0, or string matching `^(100(\.0+)?\|[0-9]{1,2}(\.[0-9]+)?)%$` | required | Screen points from the left, or a percentage of the screen's width as the device faces. |
| `y` | number ≥ 0, or string matching `^(100(\.0+)?\|[0-9]{1,2}(\.[0-9]+)?)%$` | required | Screen points from the top, or a percentage of the screen's height as the device faces. |

#### `step.drag.to`, with `x`

| Field | Type | Default | Description |
| --- | --- | --- | --- |
| `x` | number ≥ 0, or string matching `^(100(\.0+)?\|[0-9]{1,2}(\.[0-9]+)?)%$` | required | Screen points from the left, or a percentage of the screen's width as the device faces. |
| `y` | number ≥ 0, or string matching `^(100(\.0+)?\|[0-9]{1,2}(\.[0-9]+)?)%$` | required | Screen points from the top, or a percentage of the screen's height as the device faces. |

### element

An element on screen, as VoiceOver knows it: by any of its label, value, identifier, hint and traits.

| Field | Type | Default | Description |
| --- | --- | --- | --- |
| `label` | string, not empty |  | Its accessibility label. |
| `value` | string |  | Its value: a text field's placeholder, or what's typed in it. |
| `identifier` | string, not empty |  | The accessibilityIdentifier the app gives it. |
| `hint` | string, not empty |  | Its accessibility hint: what VoiceOver says it does. |
| `traits` | list of `"adjustable"`, `"alert"`, `"allowsDirectInteraction"`, `"autoCorrectCandidate"`, `"backButton"`, `"button"`, `"causesPageTurn"`, `"deleteKey"`, `"draggable"`, `"footer"`, `"header"`, `"image"`, `"inactive"`, `"isEditing"`, `"keyboardKey"`, `"launchIcon"`, `"link"`, `"map"`, `"menuItem"`, `"notEnabled"`, `"pickerElement"`, `"playsSound"`, `"popupButton"`, `"radioButton"`, `"searchField"`, `"secureTextField"`, `"selected"`, `"selectionDismissesItem"`, `"spacer"`, `"startsMediaSession"`, `"staticText"`, `"statusBarElement"`, `"summaryElement"`, `"switchButton"`, `"tabBar"`, `"tabBarItem"`, `"tableIndex"`, `"textArea"`, `"textEntry"`, `"textOperationsAvailable"`, `"updatesFrequently"`, `"visited"` or `"webContent"`, at least 1, each once |  | Traits it has, every one, by The Button Heist's names, as `retake compose` prints them. |
| `occurrence` | integer ≥ 1 |  | Which of several matching elements, counted from 1 in the order VoiceOver reads the screen. A last resort, since it breaks when the layout changes: name the element closely enough, by its traits, identifier, value or hint, that only it matches. |

Gives at least one of `label`, `value`, `identifier`, `hint` and `traits`.

### touchElement

An element on screen, as VoiceOver knows it, touched at its activation point moved by offset and offsetPercent, which add up when both are given: for a touch placed by the element rather than on it, such as a game piece dropped below the cell it lands in.

| Field | Type | Default | Description |
| --- | --- | --- | --- |
| `label` | string, not empty |  | Its accessibility label. |
| `value` | string |  | Its value: a text field's placeholder, or what's typed in it. |
| `identifier` | string, not empty |  | The accessibilityIdentifier the app gives it. |
| `hint` | string, not empty |  | Its accessibility hint: what VoiceOver says it does. |
| `traits` | list of `"adjustable"`, `"alert"`, `"allowsDirectInteraction"`, `"autoCorrectCandidate"`, `"backButton"`, `"button"`, `"causesPageTurn"`, `"deleteKey"`, `"draggable"`, `"footer"`, `"header"`, `"image"`, `"inactive"`, `"isEditing"`, `"keyboardKey"`, `"launchIcon"`, `"link"`, `"map"`, `"menuItem"`, `"notEnabled"`, `"pickerElement"`, `"playsSound"`, `"popupButton"`, `"radioButton"`, `"searchField"`, `"secureTextField"`, `"selected"`, `"selectionDismissesItem"`, `"spacer"`, `"startsMediaSession"`, `"staticText"`, `"statusBarElement"`, `"summaryElement"`, `"switchButton"`, `"tabBar"`, `"tabBarItem"`, `"tableIndex"`, `"textArea"`, `"textEntry"`, `"textOperationsAvailable"`, `"updatesFrequently"`, `"visited"` or `"webContent"`, at least 1, each once |  | Traits it has, every one, by The Button Heist's names, as `retake compose` prints them. |
| `occurrence` | integer ≥ 1 |  | Which of several matching elements, counted from 1 in the order VoiceOver reads the screen. A last resort, since it breaks when the layout changes: name the element closely enough, by its traits, identifier, value or hint, that only it matches. |
| `offset` | [object](#touchelementoffset) |  | Screen points from the element's activation point. |
| `offsetPercent` | [object](#touchelementoffsetpercent) |  | Percentages of the element's width and height from its activation point: 50 is half its width or height, 250 two and a half. |

Gives at least one of `label`, `value`, `identifier`, `hint` and `traits`.

#### `touchElement.offset`

Screen points from the element's activation point.

| Field | Type | Default | Description |
| --- | --- | --- | --- |
| `x` | number | required | Points to the right; negative for left. |
| `y` | number | required | Points down; negative for up. |

#### `touchElement.offsetPercent`

Percentages of the element's width and height from its activation point: 50 is half its width or height, 250 two and a half.

| Field | Type | Default | Description |
| --- | --- | --- | --- |
| `x` | number | required | Percent of its width or height to the right; negative for left. |
| `y` | number | required | Percent of its width or height down; negative for up. |
