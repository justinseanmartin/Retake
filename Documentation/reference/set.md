<!-- Generated from Retake's schemas: RETAKE_REGENERATE=1 swift test --filter Reference. Don't edit. -->

# A set

A set: the state a take starts from — the app's data, its settings and its launch environment.

Its schema is published at <https://justinseanmartin.github.io/Retake/schemas/0.0.1/set.schema.json>, and `retake schema set` prints it.

## Fields

| Field | Type | Default | Description |
| --- | --- | --- | --- |
| `$schema` | string |  | The URL of the schema the file is written against, for editors. Optional; a file is read against this Retake's schema whatever it names. |
| `extends` | string, not empty |  | Another set this one builds on: its fields are laid under this set's. |
| `state` | `"clean"`, `"cloned"` or `"live"` | `"clean"` | What the app's data starts as for a take, and whether the take's changes are kept. clean: empty but for the set's files and defaults. cloned: the app's real data with the set's on top, the take's changes thrown away. live: the real data, the take's changes kept. |
| `files` | object of names to string, not empty |  | Files and folders put in the app's data before launch: each key is where it goes in the app's data, such as Documents/notes.json, and its value the file in the project, relative to the directory holding retake.json. A folder ends in / on both sides. |
| `defaults` | object of names to string |  | What UserDefaults.standard holds at launch: strings, numbers, booleans, and lists and dictionaries of them. null can't be stored. |
| `environment` | object of names to string |  | Environment variables added to the launch, for the app's own flags. DYLD_, INSIDEJOB_ and RETAKE_ are Retake's own. |
| `arguments` | list of string |  | Arguments added to the launch, such as -AppleLanguages (en). |
| `aspect` | [object](#aspect) |  | The preview's shape for a device type: the app's window is sized to it, and the edit crops the band left below. |

### `aspect`

The preview's shape for a device type: the app's window is sized to it, and the edit crops the band left below.

| Field | Type | Default | Description |
| --- | --- | --- | --- |
| `iphone` | string matching `^[0-9]*\.?[0-9]+:[0-9]*\.?[0-9]+$`, or [object](#aspectiphone) |  | The shape for portrait, with landscape its shape turned; or each orientation's. |
| `ipad` | string matching `^[0-9]*\.?[0-9]+:[0-9]*\.?[0-9]+$`, or [object](#aspectipad) |  | The shape for portrait, with landscape its shape turned; or each orientation's. |

### `aspect.iphone`

| Field | Type | Default | Description |
| --- | --- | --- | --- |
| `portrait` | string matching `^[0-9]*\.?[0-9]+:[0-9]*\.?[0-9]+$` |  | The shape in portrait. |
| `landscape` | string matching `^[0-9]*\.?[0-9]+:[0-9]*\.?[0-9]+$` |  | The shape in landscape; portrait's turned unless given. |

Gives at least one of `portrait` and `landscape`.

### `aspect.ipad`

| Field | Type | Default | Description |
| --- | --- | --- | --- |
| `portrait` | string matching `^[0-9]*\.?[0-9]+:[0-9]*\.?[0-9]+$` |  | The shape in portrait. |
| `landscape` | string matching `^[0-9]*\.?[0-9]+:[0-9]*\.?[0-9]+$` |  | The shape in landscape; portrait's turned unless given. |

Gives at least one of `portrait` and `landscape`.
