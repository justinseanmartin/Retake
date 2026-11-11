<!-- Generated from Retake's schemas: RETAKE_REGENERATE=1 swift test --filter Reference. Don't edit. -->

# retake.json

A Retake project's configuration. Every field is optional.

Its schema is published at <https://justinseanmartin.github.io/Retake/schemas/0.0.3/retake.schema.json>, and `retake schema retake` prints it.

## Fields

| Field | Type | Default | Description |
| --- | --- | --- | --- |
| `$schema` | string |  | The URL of the schema the file is written against, for editors. Optional; a file is read against this Retake's schema whatever it names. |
| `bundleID` | string matching `^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*$` |  | The app's bundle ID. Without it, the bundle ID comes from the app `retake install` last embedded. |
| `build` | [object](#build-with-scheme), or [object](#build-with-command) |  | How `retake install` builds the app when it isn't given one: a scheme, or a command of the project's own. |
| `device` | string, not empty |  | The device commands use when none is named: an alias, a UDID, or a device's name. |
| `defaultSet` | string, not empty |  | The set a scene starts on when it names none, and the one `retake compose` gives a new scene. |
| `output` | string, not empty | `"output"` | Where takes and cuts go. Relative to the directory holding retake.json. |
| `hitchWarning` | number ≥ 0 | `50` | The milliseconds the app's main thread must miss frames for, at once, for `record` and `cut` to warn of it. |

### `build`, with `scheme`

Retake builds a scheme with xcodebuild, for iOS devices, with its build products in the project's build folder.

| Field | Type | Default | Description |
| --- | --- | --- | --- |
| `scheme` | string, not empty | required | The scheme to build. |
| `workspace` | string, not empty |  | The workspace holding the scheme, needed only when the directory holds more than one. Relative to the directory holding retake.json. |
| `xcodeproj` | string, not empty |  | The project holding the scheme, needed only when the directory holds more than one. Relative to the directory holding retake.json. |
| `configuration` | string, not empty | `"Debug"` | The build configuration, which must be development-signed for the device. |
| `allowProvisioningUpdates` | boolean | `false` | Lets xcodebuild register the device and update profiles on your team. |
| `optimize` | boolean | `true` | Builds with the compiler's optimization on, Swift at -O and C at -Os, whatever the configuration says, so the app runs as fast as its users see it. |

### `build`, with `command`

The project's own command builds the app: for builds one xcodebuild call can't make. It's run with /bin/sh in the project's directory, with the device's UDID in RETAKE_DEVICE_UDID.

| Field | Type | Default | Description |
| --- | --- | --- | --- |
| `command` | string, not empty | required | The command that builds the app. |
| `app` | string, not empty | required | The .app the command leaves. Relative to the directory holding retake.json. |
