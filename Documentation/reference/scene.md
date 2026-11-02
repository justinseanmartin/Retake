<!-- Generated from Retake's schemas: RETAKE_REGENERATE=1 swift test --filter Reference. Don't edit. -->

# A scene

A scene: a set, and the steps played on it.

Its schema is published at <https://justinseanmartin.github.io/Retake/schemas/0.0.1/scene.schema.json>, and `retake schema scene` prints it.

## Fields

| Field | Type | Default | Description |
| --- | --- | --- | --- |
| `$schema` | string |  | The URL of the schema the file is written against, for editors. Optional; a file is read against this Retake's schema whatever it names. |
| `set` | string, not empty |  | The set the scene starts on; the project's defaultSet when not given. |
| `setup` | list of [step](#step) |  | Steps played before recording starts. Nothing anchors to them, so they have no id. |
| `leadIn` | number ≥ 0 | `1` | Seconds recorded before the first step. |
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
| `tap` | [object](#steptap-with-x), or [element](#element) |  | Touches a point, x and y, or an element. A tap by point is drawn in the video; one on an element isn't. |
| `drag` | [object](#stepdrag) |  | A straight one-finger drag from one point to another. |
| `type` | [object](#steptype) |  | Types text key by key on the on-screen keyboard. |
| `activate` | [element](#element) |  | An accessibility activation of an element, with no touch, for getting somewhere off camera. |
| `orientation` | `"portrait"`, `"portrait-upside-down"`, `"landscape-left"` or `"landscape-right"` |  | Turns the device, with no hand on it; the step ends when the app has turned. |
| `waitFor` | [object](#stepwaitfor) |  | Waits until an element is on screen, or with gone until it isn't. The step fails if it doesn't happen in time. |
| `hold` | number ≥ 0 |  | Seconds to pause after the step, or for a tap, from when it's sent; the scene's defaultHold when not given. |
| `id` | string, not empty |  | The name edits anchor to. Unique in the scene; it can't look like a number, which anchors count steps by, nor be start or end. |

Gives exactly one of `tap`, `drag`, `type`, `activate`, `orientation` or `waitFor`, or only `hold`.

#### `step.tap`, with `x`

| Field | Type | Default | Description |
| --- | --- | --- | --- |
| `x` | number ≥ 0 | required | Screen points from the left. |
| `y` | number ≥ 0 | required | Screen points from the top. |

#### `step.drag`

A straight one-finger drag from one point to another.

| Field | Type | Default | Description |
| --- | --- | --- | --- |
| `from` | [object](#stepdragfrom) | required | Where the finger comes down. |
| `to` | [object](#stepdragto) | required | Where it lifts. |
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
| `occurrence` | integer ≥ 1 |  | Which of several matching elements, counted from 1 in the order VoiceOver reads the screen. |
| `gone` | boolean | `false` | Waits for the element to leave instead. |
| `timeout` | number > 0 | `10` | Seconds to wait. |

Gives at least one of `label`, `value`, `identifier`, `hint` and `traits`.

#### `step.drag.from`

Where the finger comes down.

| Field | Type | Default | Description |
| --- | --- | --- | --- |
| `x` | number ≥ 0 | required | Screen points from the left. |
| `y` | number ≥ 0 | required | Screen points from the top. |

#### `step.drag.to`

Where it lifts.

| Field | Type | Default | Description |
| --- | --- | --- | --- |
| `x` | number ≥ 0 | required | Screen points from the left. |
| `y` | number ≥ 0 | required | Screen points from the top. |

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
