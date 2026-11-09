# The `retake` command

This is the contract for Retake's command line: each command, what it reads and writes, and how it
fails. How the files fit together is in the [README](../README.md), and every field of every file is in the
[reference](reference/), generated from Retake's schemas.

Retake hasn't had its first release yet; this describes the command as it's built.

## Conventions

### Finding the project

A project is a folder: its configuration file, `retake.json`, and beside it the project's own
folders, `sets/`, `scenes/` and `edits/`, and its output, `output/`. [`init`](#retake-init) makes it in `Retake/`,
at the root of the repository, so the project's files are in one place, apart from the app's own.
What each person's Retake keeps for itself, their builds and device aliases, is outside any project,
in `~/Library/Caches/retake/`.

Every command except `init`, `devices`, `embed`, `info`, `check`, `schema` and `version` runs in a
project, named by its configuration file, under any name. (`devices` reads one when there is one,
for its aliases and `device`.) The first of these that's given names it:

1. `--config <path>`;
2. the `RETAKE_CONFIG` environment variable;
3. `retake.json` in the current directory;
4. `Retake/retake.json` in the current directory.

So a project in `Retake/` is found from the directory holding it, such as the repository's root, and
from inside it. A path from either of the first two is relative to the current directory. If the
file named doesn't exist, or neither of the last two does, the command fails (2). No other directory
is searched, so a command never acts on a project it wasn't pointed at. `RETAKE_CONFIG` saves typing
`--config` in a shell that works on one project:

```sh
export RETAKE_CONFIG=Previews/retake.json
retake record create-note
retake cut video1
```

The project's folders are beside the configuration file, whatever its own folder is called, and
every relative path in it, such as `build`'s `workspace`, is relative to the directory holding it.
So the file needn't sit beside the app's Xcode project: `Retake/retake.json` names `"workspace":
"../MyApp.xcworkspace"`, and in a repository whose previews live in `Previews/`,
`Previews/retake.json` does the same, run from the repository's root with `retake record --config
Previews/retake.json`.

A project somewhere other than `Retake/` is simplest named once for the repository, in the
`mise.toml` Retake is [installed](../README.md#install) with, so every command finds it from any directory in the
repository:

```toml
[env]
RETAKE_CONFIG = "{{config_root}}/Previews/retake.json"
```

`{{config_root}}` is the directory holding `mise.toml`.

### The output directory

What Retake makes that's worth keeping — takes and cuts — goes in the project's output directory,
the first of these that's given:

1. `--output-dir <dir>`, relative to the current directory;
2. the `RETAKE_OUTPUT_DIR` environment variable, relative to the current directory;
3. the configuration file's `output`, relative to the directory holding it;
4. `output/` beside the configuration file.

`init` adds the default, or the one it's given, to the project's `.gitignore`. The paths below are
written with the default, inside the project's folder. Retake creates the directory when it first
writes to it. An environment variable that's set but empty counts as not set, for both variables.

It holds the takes edits are cut from, so moving it somewhere temporary, such as `/tmp` or an agent's scratch
directory, suits runs whose takes don't need to outlive it: a take recorded there is gone when the
directory is cleared, and an edit can't `cut` until its scenes are recorded again.

### Finding the app

Commands that launch the app, or put a set's files in its container, need its bundle ID, which comes
from the first of these that's given:

1. the configuration file's `bundleID`;
2. the app `install` last embedded, which it records in the output directory's `installed.json`.

So a project that installs with `retake install` needn't name its bundle ID at all, which suits an
app whose bundle ID differs from one developer to the next, each signing it with a prefix of their
own. A project that installs the app itself, with `retake embed` in its own script, gives
`bundleID`. Without either, the command fails (2), asking for one, as it does when the output
directory is somewhere `install` hasn't been run, such as a new `--output-dir`. `embed` and
`install` read the bundle ID from the app they're given or build.

### Choosing a device

Commands that use a device take `--device <device>`, where `<device>` is:

1. an alias from `retake devices add`,
2. a UDID, or
3. a device's name, exactly as `devicectl` reports it.

Without `--device`, Retake uses the `RETAKE_DEVICE` environment variable, then the configuration
file's `device`, and failing those the one device connected by USB. With several connected and none
named, the command stops and lists them. A device that's missing, none connected or the one named
not among them, is looked for again for up to 3 seconds before the command fails, since `devicectl`
leaves a connected device out of its list now and then, for a moment. `RETAKE_DEVICE` comes before
the configuration file because devices belong to people, and the file is shared: it suits a session
spent on one device.

The device's **type** — `iphone` or `ipad`, asked of the device itself — picks the folders a command
works in: `scenes/<type>/` and `output/takes/<type>/`.

### Names

Scenes, sets and edits are named by their file name without `.json`: `create-note` is
`scenes/<type>/create-note.json`, and `video1` is `edits/video1.json`. Takes are named by their
scene: for each device type, a scene has its take, `create-note.mov`, the take that one replaced,
`create-note.previous.mov`, and its latest failure, `create-note.failed.mov`, each with its step
log beside it. A video's record names each take it was cut from by its scene, device type and when
it was recorded.

### Takes from an earlier Retake

An earlier Retake numbered takes, in a folder per scene, `output/takes/<type>/<scene>/1.mov` and so
on. This Retake doesn't read them: a command that reads takes (`record`, `takes`, `cut`, `status`,
and `validate`, which reports a problem) fails (1) while any are there, naming each folder and
saying to delete it with `retake clean --takes <scene>` or by hand, and to record the scene again.

### Reading the project's files

Every command reads the project's files the same way, strictly, against Retake's [schemas](#schemas): a key
Retake doesn't know, a value of the wrong type or outside its range, or a missing required field
fails the command (1) before it does anything, and every error names the file and the path to the
field:

```
edits/video1.json: clips[3].from.fraction: 1.4 is outside -1 to 1
scenes/ipad/create-note.json: steps[2]: unknown key "tapp"
```

A file may name its schema in a `"$schema"` key, for editors; Retake never adds one. A file without
one is read against this Retake's schema; one naming another version's is read against this Retake's
too, with a warning when the versions differ, since the schema can't be older or newer than the code
reading it.

### Output

Commands print progress for people. Those that report something — `devices`, `takes`, `status`,
`doctor`, `embed`, `info`, `validate`, `version` — take `--json` for a stable, machine-readable
form instead, and `compose --json` answers each action with a line of JSON.

Notes (`note:`), warnings (`warning:`), questions asked at a terminal, and the `✖` error that ends
a command go to standard error; everything else goes to standard output, including the `✓` and `✖`
lines `record` and `cut` print for each scene or edit, so a pipe or `--json` gets only the output.

### Environment variables

Some options can also be set in the environment, for a shell or a script that runs many commands the
same way. An option given on the command line always wins over its variable, and a variable that's
set but empty counts as not set. Paths are relative to the current directory.

| Variable | Stands in for | Used by |
| --- | --- | --- |
| `RETAKE_CONFIG` | `--config` | Every command that runs in a project, `init` and `devices`. |
| `RETAKE_OUTPUT_DIR` | `--output-dir` | Every command that runs in a project. |
| `RETAKE_DEVICE` | `--device` | Every command that uses a device, except `devices add`. |
| `RETAKE_SIGNING_IDENTITY` | `--identity` | `embed`, `install`. |
| `RETAKE_PROVISIONING_PROFILE` | `--profile` | `embed`, `install`. |

`devices add` ignores `RETAKE_DEVICE`: its `<device>` says which connected device to name, not which
to use. Nothing that discards work, such as `clean`'s `--yes`, has a variable.

### Exit status

| Status | Meaning |
| --- | --- |
| 0 | Done. |
| 1 | The command failed: a step didn't run, a render failed, a check found a problem. |
| 2 | The command was used wrongly: an unknown option, a missing argument, a name that doesn't exist. |
| 3 | The environment isn't right: no device, a device on Wi-Fi, no signing identity, or an app that wasn't embedded, or was embedded by an incompatible Retake. |

A command that does several things — recording several scenes, cutting several edits — reports each,
and exits with the worst status among them.

## Commands

| Command | Does |
| --- | --- |
| [`init`](#retake-init) | Creates a project. |
| [`doctor`](#retake-doctor) | Checks the setup end to end, to find why a command failed. |
| [`devices`](#retake-devices) | Lists devices, and names them. |
| [`install`](#retake-install) | Builds the app if asked, embeds Retake in it, and installs it. |
| [`embed`](#retake-embed) | Adds what Retake needs to a built app, for installing it yourself. |
| [`compose`](#retake-compose) | Writes a scene a step at a time, on the device. |
| [`record`](#retake-record) | Records takes, or with `--dry-run`, plays scenes without recording them. |
| [`takes`](#retake-takes) | Lists takes. |
| [`clean`](#retake-clean) | Deletes takes and cuts, or take data left on the device. |
| [`cut`](#retake-cut) | Renders videos. |
| [`status`](#retake-status) | Summarizes scenes, takes, edits and videos. |
| [`info`](#retake-info) | Prints how a take or video was made. |
| [`check`](#retake-check) | Checks an archive for TheInsideJob. |
| [`validate`](#retake-validate) | Checks the project's files. |
| [`schema`](#retake-schema) | Prints the schemas. |
| [`version`](#retake-version) | Prints Retake's version and The Button Heist's it's built against. |

---

### `retake init`

```
retake init [--config <path>] [--output-dir <dir>] [--bundle-id <id>] [--scheme <name>]
```

Creates a project: `retake.json`, and beside it the folders `sets/`, `scenes/iphone/`,
`scenes/ipad/` and `edits/`. They go in `Retake/` in the current directory, unless `--config` (or
`RETAKE_CONFIG`) names the configuration file to create, such as `--config Previews/retake.json`.

`--output-dir` puts the [output directory](#the-output-directory) somewhere other than `output/` beside the configuration
file, and writes it into `retake.json` as `output`, so every command uses it without being told.
`RETAKE_OUTPUT_DIR` isn't read here: it's for one shell's commands, not the project's.

The output directory is gitignored: in a `.gitignore` in the project's folder, or when it's outside
that folder, in the current directory's `.gitignore`, when it's below the current directory, and in
neither when it isn't.

Asks for the scheme when it isn't given and can't be found in an Xcode project in the current
directory. Writes `bundleID` only when `--bundle-id` gives one; otherwise the bundle ID comes from
the app `install` builds (see [Finding the app](#finding-the-app)).

At a terminal, it then offers to name each device connected by USB, as [`devices add`](#retake-devices) does, once
through: it suggests the device's type, `iphone` or `ipad`, as its alias (`ipad2` when `ipad` is
taken), which an empty answer takes, and `-` skips the device. Then it asks whether there's another
device to name; if there is, it waits for it to be connected by USB and offers to name it, and asks
again, until the answer is no. A device can be named later with `devices add`. Without a terminal,
nothing is asked.

Ends by saying how commands will [find the project](#finding-the-project). In `Retake/`, they find it from the current
directory and from inside `Retake/`, and a project moved or renamed later needs `--config` or
`RETAKE_CONFIG`. Anywhere else, every command needs one of them, so `init` prints the `mise.toml`
lines that name it for the repository.

Fails (2) if the configuration file already exists, or, with none named, when commands in the
current directory would already find a project, so `init` run inside one doesn't make another in it.

### `retake doctor`

```
retake doctor [--device <device>] [--json]
```

For when something fails and its message doesn't say why; the other commands check what they need
as they go. Checks, in order, and reports each as passed, warned or failed, or skipped when it needs one that
failed, such as the app's installation when there's no device:

1. Xcode, `devicectl` and `codesign` are available.
2. The device is connected by USB, paired, and offered for screen capture.
3. A development signing identity is in the keychain, and a provisioning profile covers the app's
   bundle ID and the device.
4. The app is installed on the device. Whether Retake is embedded in it, by `retake install` or
   `retake embed`, is the next check's to find.
5. The app launches, Retake's support library and The Button Heist's server answer, and both are
   [compatible](#compatibility-with-an-embedded-app) with this Retake. It launches on the project's `defaultSet`, or with none, on
   nothing but Retake's own `clean` state, and cleans up after itself as `record` does.

A check warns when it can't say, such as which provisioning profile covers the app before Retake
knows its bundle ID. Exits 0 when nothing failed, otherwise with the status of the first failure.
With `--json`, prints the checks as a list, each with its `check`, `outcome` and `detail`.

### `retake devices`

```
retake devices [--config <path>] [--json]
retake devices add <alias> [<device>]
retake devices remove <alias>
```

With no subcommand, lists devices: each connected device's name, UDID, type, model, and whether it's
wired, and each alias, whether connected or not. Then it says which device commands would use, and
what [chose it](#choosing-a-device), so a take never lands on a device by surprise:

```
→ ipad (from RETAKE_DEVICE)
```

or `(from retake.json)`, `(the only one connected)`, or that several are connected and none is
chosen. It needs no project, but reads one's `device` when there is one, found as
[Finding the project](#finding-the-project) says.

`add` names a device: the one `<device>` gives, by its UDID or its name as `devicectl` reports it,
or with none given, the one connected; with several connected and none given, it asks which. It
records the device's UDID and its screen-capture identity, which differ, in
`~/Library/Caches/retake/devices.json`. Fails (2) if the alias is taken. `<device>` is an argument,
not `--device`, since it says which device to name rather than which to use, and `RETAKE_DEVICE`
plays no part. When `RETAKE_DEVICE` names a different device, `add` notes that the shell's commands
will still use that one:

```
Commands in this shell still use "ipad" (RETAKE_DEVICE); pass --device phone to use this one.
```

`remove` forgets an alias.

Aliases are each person's, for every project, and are kept with everything else of Retake's outside
the project, never in the repository: a device's UDID and name are its owner's, and the name is
often theirs too ("Anna's iPad"); and one person's `ipad` isn't another's. A project's `retake.json`
can name a default `device` for everyone, which each person's own alias of that name then stands
for. Clearing `~/Library/Caches` forgets them, and `devices add` names each device again.

### `retake install`

```
retake install [--app <path>]
               [--scheme <name> [--workspace <path> | --xcodeproj <path>] [--configuration <name>]
                [--allow-provisioning-updates] [--no-optimize]]
               [--device <device>] [--identity <identity>] [--profile <path>]
```

Builds the app if asked to, runs [`embed`](#retake-embed) on a copy of it, and installs the copy on the device.
It's the usual way to get the app onto a device for Retake; `embed` alone is for a build script or
tool that installs the app itself. It's needed once per build of the app, not before each recording.

The build itself isn't changed: the copy is in the project's build folder, below, replaced each
time, and the output directory's `installed.json` records its bundle ID, for [finding the app](#finding-the-app). On
APFS, the copy is a clone of the build, so it takes no time and no space until embedding changes it,
when the build is on the same volume as the build folder, as one `install` builds always is.

Builds are kept out of the project, since a build rewrites thousands of files each time: in
`~/Library/Caches/retake/builds/<project>/`, one folder per project, named for the project's folder
and its path. They can all be made again, so clearing the cache only makes the next `install` build
from scratch.

Where the app comes from, the first that applies:

1. `--app`: an already built, development-signed `.app` for iOS devices.
2. `--scheme`: Retake builds it with `xcodebuild`, as below.
3. `retake.json`'s `build`, in one of two forms:

   <!-- schema: retake -->
   ```json
   "build": { "scheme": "MyApp", "workspace": "MyApp.xcworkspace", "configuration": "Debug" }
   ```

   <!-- schema: retake -->
   ```json
   "build": { "command": "scripts/build-for-retake.sh", "app": "build/Debug-iphoneos/MyApp.app" }
   ```

   The first builds with `xcodebuild`, as `--scheme` does; `workspace` or `xcodeproj` is needed only
   when the directory holds more than one. The second is for projects one `xcodebuild` call can't
   build: generated projects (Tuist, XcodeGen), fastlane, Bazel, or anything with its own steps.
   Retake runs `command` with `/bin/sh` in the project's directory, passing the device's UDID in
   `RETAKE_DEVICE_UDID`, and fails (1) if it exits non-zero or `app` doesn't exist afterwards.

With none of these, fails (2).

**Building with `xcodebuild`.** Retake builds the scheme for iOS devices in `configuration` (`Debug`
unless given), with its build products in the project's build folder, so it doesn't disturb your own
builds, and finds the `.app` from the build's settings. Signing is the project's own. Any
configuration works, so long as it's development-signed for the device; `Debug` is the default
because it usually is.

It builds with the compiler's optimisation on, whatever the configuration says (Swift at `-O`, C and
Objective-C at `-Os`), since a preview should show the app running as fast as it does for its users,
and a Debug build at `-Onone` can stutter where a release wouldn't. The configuration is otherwise
the same, so `#if DEBUG` code, and the launch flags a set turns on, still work. `--no-optimize` (or
`"optimize": false` in `build`) builds as the configuration says instead. A `command` build is the
project's own, and is left as it is.

**A device the profile doesn't include.** When the build or the embedded app can't be signed for the
device, typically because it isn't registered on your team, Retake fails (3) and says so, naming the
device's UDID. It never registers devices or changes profiles on its own. With
`--allow-provisioning-updates` (or `"allowProvisioningUpdates": true` in `build`), it passes
`-allowProvisioningUpdates` to `xcodebuild`, which lets Xcode register the device and update
profiles on your team. That's only possible when Retake runs `xcodebuild`; for `--app` and `command`
builds, register the device in Xcode or your own build.

Fails (3) if no identity and profile can sign it for development on the device: the build's own, or
those given instead.

### `retake embed`

```
retake embed <app> [--output <path>] [--identity <identity>] [--profile <path>]
                   [--json]
```

Adds what Retake needs to an already built, development-signed `.app` for iOS devices, for when your
own build script or tool installs the app. [`install`](#retake-install) runs it as one of its steps. Needs no project
and no device.

1. Adds the TheInsideJob framework Retake is built against to the app's `Frameworks/`.
2. Adds Retake's support library to `Frameworks/`.
3. Adds a `Retake` dictionary to the app's `Info.plist`, recording the Retake version that embedded
   it, its support library's contract version, and the Button Heist version it embedded.
4. Re-signs everything it added, and the app, with the identity and provisioning profile the app was
   signed with, keeping the app's entitlements. `--identity` and `--profile`, or
   `RETAKE_SIGNING_IDENTITY` and `RETAKE_PROVISIONING_PROFILE`, replace either: for an app built
   without signing, or signed with a profile that doesn't include the device. An app built
   unsigned gets only the minimal development entitlements (the profile's app ID for its bundle ID,
   its team, `get-task-allow` and its own keychain group), so build an app that needs capabilities
   signed, for `embed` to keep its own.

The app's own executable isn't changed. The `.app` is changed in place, unless `--output` names
where to write a copy. Prints the path of the result, or with `--json`, it and what was embedded.

Nothing added runs unless Retake launches the app: the libraries load only through the launch
environment Retake passes. Opened from the home screen, an embedded app behaves as it would without
Retake, so one build can serve both for testing by hand and for recording.

Embedding an app again replaces what an earlier embed added, from any version of Retake, so a build
script can embed every build without checking first.

Fails (3) if no identity and profile can sign it for development on devices: the app's own, or those
given instead. Fails (1) if the app already contains TheInsideJob, as a framework or linked into an
executable, naming where: Retake supplies its own, and two copies in one app can't both run. Leave
it out of the builds you record with.

#### Compatibility with an embedded app

An app embedded by one Retake can be recorded by another, so upgrading Retake doesn't mean embedding
every build again, when two things agree:

- **The support library's contract version**, a number that changes only when what Retake and its
  library expect of each other changes: the environment it reads, how defaults and files are
  delivered, how it reports at launch.
- **The Button Heist version** embedded, which must be the one this Retake's client is built
  against. Builds between releases carry a hash of The Button Heist's contract in their version, so
  equal versions mean the same commands and wire format.

`record`, `compose` and `doctor` check both at launch: the contract version from what the support
library reports, and The Button Heist's version at its own handshake, which refuses a mismatch
before any command runs. They stop (3) when either differs, saying to embed the app again. An
upgrade of Retake that changes neither works with apps already on devices.

A build script that installs the app itself, on several devices:

```sh
retake embed "$APP"
for udid in $DEVICES; do
  xcrun devicectl device install app --device "$udid" "$APP"
done
```

### `retake compose`

```
retake compose <scene> [--set <set>] [--device <device>] [--json]
```

Writes a scene a step at a time, on the device. Launches the app on the scene's set, or for a new
scene, `--set` (`retake.json`'s `defaultSet` when not given); plays the steps the scene already has,
with their holds, as `record` does, since a step can need the app to have settled after the one
before; and prints what's on screen: each element's label, value, identifier, hint, traits, frame
and activation point, in screen points. Then it takes actions, one a line, each an action's name and
its options:

```
> tap --label "New Note" --id new-note --hold 0.8
> type --text "Groceries\n" --value "Title"
> waitFor --label "Synced"
> inspect
```

A step runs as soon as it's given. One that runs is added to `scenes/<type>/<scene>.json`, and
what's on screen after it is printed; one that doesn't is left out, saying why, and the scene
carries on from wherever the app is. Each step's action is named as its step is in a scene file, and
takes the options its step does there; every one but `hold` also takes `--id <name>` and `--hold
<seconds>`, both optional, and `hold` takes `--id`:

| Action | Required | Optional |
| --- | --- | --- |
| `tap` | An element, or `--x <x> --y <y>` | |
| `drag` | `--from <x>,<y> --to <x>,<y>` | `--duration <seconds>` (0.5) |
| `type` | `--text <text>`, where `\n` presses return | An element to type into (the field already being typed in) |
| `activate` | An element | |
| `orientation` | `--to portrait`, `portrait-upside-down`, `landscape-left` or `landscape-right` | |
| `waitFor` | An element | `--gone`, `--timeout <seconds>` (10, at most The Button Heist's longest wait, 60 unless `BUTTONHEIST_MAX_WAIT_TIMEOUT` raises it) |
| `hold` | `--seconds <seconds>` | |

A `tap` at a point that lands on an element is added, and `compose` says so, with the `tap` that
names it instead: a step that names an element finds it wherever the layout puts it, on every
device. The name is the shortest that no other element on screen matches: its `--label`, or its
label with, or in place of it, its `--identifier`, `--value`, `--hint` or `--traits`, as few as tell
it apart. Traits name it alone only when it has nothing else. Only when nothing tells it apart from
another does the name end with an `--occurrence`, and `compose` says that breaks when the layout
changes. In `--json`, that step is the reply's `suggestion`.

`hold` adds a step that's only a pause, as `{ "hold": 2 }` does in a file. A step's `--hold` is the
scene's `defaultHold` when it isn't given.

An element is any of `--label <text>`, `--value <text>`, `--identifier <text>`, `--hint <text>` and
`--traits <trait>,<trait>`, at least one, with `--occurrence <n>` (counted from 1, optional) to pick
one of several that match. Name an element closely enough that only it matches, rather than reaching
for `--occurrence`: it's a last resort, for elements nothing else tells apart, since it breaks when
the layout changes. Other actions act on the scene rather than the app, and add no step:

| Action | Required | Optional | Does |
| --- | --- | --- | --- |
| `inspect` | | An element | Prints what's on screen again, or only the elements that match, each with the options that pick it out. |
| `set` | `--hold <seconds>` or `--id <name>`, or both | | Changes the last step's hold, or its id, for edits to anchor to. |
| `undo` | | How many steps, `<n>` (1) | Drops the last step, or the last `<n>`, then launches the app again and replays the rest. |
| `replay` | | | Launches the app again and replays every step, dropping none. |
| `steps` | | | Lists the scene's steps. |
| `help` | | An action's name | Lists the actions and their options, or one action's. |
| `quit` | | | Ends; so does Control-D. |

`undo` and `help` take their one option bare: `undo 3`, `help tap`. `inspect` with an element, such
as `inspect --label "Delete"`, is for picking out one of several alike: it lists them in the order
VoiceOver reads them, each after the shortest options that name it and no other element on screen,
chosen as a tap's suggestion is, such as `--label "Delete" --traits header` or `--identifier
"delete-groceries"`. An element nothing tells apart from another gets an `--occurrence` as well.
`replay` gets the app back to where the scene ends after something moved it off course, such as a
step that failed partway, without dropping anything.

At a terminal, an action given without an option it needs asks for it, saying which options are
optional and what they default to. Read from a pipe, as when a script or an agent drives it, the
action fails instead, naming what's missing, and nothing is asked.

With `--json`, each reply is one line of JSON, for a program to read, with `ok` true, or false for
an error. A step is written as the scene file writes it, and an element as the step log does: its
`label`, `value`, `identifier`, `hint`, `traits`, `frame` (`[x, y, width, height]`) and
`activationPoint` (`[x, y]`), in screen points, each left out when it has none.

- **After launching**, and after `undo` and `replay`, which launch again: for a scene that has
  steps, `{"ok": true, "steps": […]}`, the steps replayed, after `{"ok": false, "error":
  "Replaying the scene: …"}` if one didn't run; then `{"ok": true, "screen": […]}`, what's on
  screen.
- **`inspect`**: `{"ok": true, "screen": […]}`. Given an element, only those that match, each with
  its `name`, the element as a step names it, such as `{"label": "Delete", "traits": ["header"]}`,
  left out for an element with nothing to name it by.
- **A step added**: `{"ok": true, "number": 3, "step": {…}, "screen": […]}`, its number among the
  scene's steps, from 1, and what's on screen after it; for a tap at a point that lands on an
  element, with `"suggestion": {…}`, the step that names the element instead.
- **`set`**: `{"ok": true, "number": 3, "step": {…}}`, the last step as changed.
- **`steps`**: `{"ok": true, "steps": […]}`.
- **`help`**: `{"ok": true, "help": "…"}`, the text `help` prints.
- **An error**: `{"ok": false, "error": "…"}`, for a step that didn't run, or an action that's
  wrong; nothing is added.

`quit`, and the end of the input, reply nothing.

<!-- schema: none -->
```json
{"ok": true, "number": 1, "step": { "tap": { "x": 802, "y": 54 } }, "screen": [{ "label": "Notes", "traits": ["header"], "frame": [20, 96, 160, 41], "activationPoint": [100, 116.5] }, { "label": "New Note", "traits": ["button"], "frame": [780, 32, 44, 44], "activationPoint": [802, 54] }], "suggestion": { "tap": { "label": "New Note" } }}
```

The scene is written after each change, its other fields kept as they are; a new scene's file names
its set, and is first written with its first step. At the end, the app is launched once more to
delete the take's copy of its data from the device, as `record` does.

Fails (2) for a new scene with no set to launch on, and for `--set` given for a scene that already
names one.

### `retake record`

```
retake record [<scene>... | --for <edit>] [--force] [--device <device>] [--stop-on-failure]
              [--dry-run]
```

Records each scene chosen again:

| Form | Records |
| --- | --- |
| `retake record` | Every scene in `scenes/<type>/` with no take yet. |
| `retake record --force` | Every scene in `scenes/<type>/`. |
| `retake record --for <edit>` | Every scene the edit uses that has no take yet. |
| `retake record --for <edit> --force` | Every scene the edit uses. |
| `retake record <scene>...` | The scenes named, whether or not they have takes. |

`--force` records again scenes that already have a take. When every scene chosen already has a
take, `record` says so and records nothing.

For each scene, in order:

1. Stops the app, and copies the set's files to the device; its defaults go with the launch.
2. Launches the app with the set's environment and arguments. Before the app's code runs, Retake's
   support library builds the take's data from the set's `state` (`clean`, `cloned` or `live`; see
   the README) and deletes earlier takes' copies. If the support library doesn't report in, or
   reports an [incompatible](#compatibility-with-an-embedded-app) contract or Button Heist version, the scene fails (3) before its first
   step, saying to `retake embed` or `retake install` the app again.
3. Plays the setup steps, then records the lead-in, the steps with their holds, and the tail. After
   each step, and when each `waitFor` is satisfied, records the elements on screen in the step log,
   and once before the first step, when the lead-in is over.
4. Writes the movie and its step log as `output/takes/<type>/<scene>.recording.mov` and `.json`,
   then, when every step ran, renames them into place as the scene's take, `<scene>.mov` and
   `<scene>.json`. The take it replaces becomes `<scene>.previous.*`, deleting the previous one
   before it, and the scene's latest failure, `<scene>.failed.*`, is deleted: it's no longer the
   latest news.

After the last scene, when any take was `clean` or `cloned`, launches the app once more to delete
the take's copy of its data and the staged set files from the device, as [`clean --on-device`](#retake-clean) does,
so none is left behind.

A take whose step fails is kept as the scene's latest failure, `<scene>.failed.mov` and `.json`,
replacing the last, for its footage to show what went wrong; no edit is cut from it, and the take
and the previous one are left alone. A recording that's interrupted, or can't record at all, keeps
nothing and changes none of the scene's takes; what it wrote under `.recording` is deleted then, or,
for one killed outright, by the next recording of the scene. Recording carries on with the next
scene unless `--stop-on-failure` is given, and a summary at the end lists each scene's new take or
failure.

Since a stutter or a hitch still counts as success, the take a retake replaces is kept as the
previous one: when the new take came out worse, [`retake takes --restore <scene>`](#retake-takes)
puts it back.

**`--dry-run`** plays the scenes chosen as `record` would, without recording them, for trying a
scene out while writing it: it launches on each scene's set, plays its setup and steps with their
holds, prints each step as it plays, and deletes the take's copy of the app's data from the device
at the end. It writes nothing to the project, its console log going to a temporary folder as every
launch's does, and fails (1) at the first step that doesn't run, naming it. It plays
every step with its hold, as a take would: a step can need the app to have settled after the one
before, so a dry run that skipped holds could fail where a take wouldn't, or pass where it fails.

### `retake takes`

```
retake takes [<scene>] [--device <device> | --type <type>] [--json]
retake takes --restore <scene> [--device <device> | --type <type>]
```

Lists takes, of one scene or all: each scene's take, its previous take and its latest failure, each
with when it was recorded, the app's version and build, the device and its model, duration, frames
dropped, why a failure failed, and the edits cut from the take. A take whose [step
log](reference/take.md) can't be read is listed as failed, saying why: one recorded by an earlier
Retake that didn't log its screen, frames and dropped frames is to be recorded again, and one
recorded by a newer Retake, in a later step log `format`, needs Retake updated.

Without `--device` or `--type`, lists takes of both device types.

With `--json`, prints a list of takes, by device type, then scene, then kind. Each gives its
`deviceType`, `scene` and `kind` (`take`, `previous` or `failed`); where its step log can be read,
`recordedAt`, `app` (`version` and `build`), `device` (`model`, `marketingName` and `os`),
`duration` in seconds, `frames` and `dropped`, named as the step log names them; then `successful`,
whether an edit can be cut from it, `failure`, why it failed, for one that did, `problem`, why its
movie or step log can't be used, for one that can't, and `usedBy`, the edits cut from it, which
only a scene's take has:

<!-- schema: none -->
```json
[
  {
    "deviceType": "ipad", "scene": "create-note", "kind": "take", "recordedAt": "2026-11-06T09:30:00Z",
    "app": { "version": "1.9.0", "build": "412" },
    "device": { "model": "iPad13,4", "marketingName": "iPad Pro (11-inch) (3rd generation)", "os": "26.6.2 (23G90)" },
    "duration": 12.346, "frames": 740, "dropped": 0, "successful": true, "usedBy": ["video1"]
  },
  {
    "deviceType": "ipad", "scene": "create-note", "kind": "failed", "recordedAt": "2026-11-06T09:41:12Z",
    "app": { "version": "1.9.0", "build": "412" },
    "device": { "model": "iPad13,4", "marketingName": "iPad Pro (11-inch) (3rd generation)", "os": "26.6.2 (23G90)" },
    "duration": 4.211, "frames": 252, "dropped": 0, "successful": false,
    "failure": "create-note: step 2 of 3, tap \"Send\", didn't run: \"Send\" isn't on screen", "usedBy": []
  }
]
```

**`--restore <scene>`** puts back the scene's previous take, in place of the take that replaced it,
which becomes the previous take in turn, so restoring again undoes it. The next cut uses the take
put back, and `status` says a video cut from the other is out of date. Fails (2) when the scene has
no previous take, or has one for both device types and neither `--device` nor `--type` says which.
Moving the files by hand does the same: rename `<scene>.mov` and `<scene>.json` aside, then the
`.previous` ones to `<scene>.mov` and `<scene>.json`.

### `retake clean`

```
retake clean [--takes [<scene>,...]] [--cuts [<edit>,...]] [--type <type>] [--yes]
retake clean --unused [--type <type>] [--yes]
retake clean --on-device [--device <device>]
```

Deletes takes and cuts, of both device types unless `--type` names one:

| Form | Deletes |
| --- | --- |
| `retake clean` | Every take and every cut. |
| `retake clean --takes` | Every take. |
| `retake clean --takes create-note,share-note` | The takes of `create-note` and `share-note`: each one's take, previous take and latest failure. |
| `retake clean --cuts` | Every cut. |
| `retake clean --cuts video1` | `video1`'s cuts. |
| `retake clean --unused` | Every unreferenced scene definition and take, and every previous take and failure. Keeps each referenced scene's take. |

`--takes` and `--cuts` can be given together. `--takes` also deletes the numbered takes an
[earlier Retake](#takes-from-an-earlier-retake) left, in `output/takes/<type>/<scene>/`, of the
scenes named, or of every scene. It lists what it will delete, warning of each take an edit is cut
from, which the edit needs recorded again before its next cut, and asks first, unless `--yes`.
Fails (2), deleting nothing, if a scene or edit named has nothing to delete.

`clean` deletes a scene's take, previous take and failure together. To drop only the previous take
or the failure, delete its two files, `<scene>.previous.*` or `<scene>.failed.*`, by hand, or
`--unused` drops every one.

`--unused` derives what is needed from every edit, including scenes used only for stills. It refuses
to delete anything if an edit cannot be read, because that edit's dependencies are unknown. It
leaves rendered cuts, sets and other project files alone. `--type` limits both takes and scene
definitions to one device type. It refuses to run while an earlier Retake's numbered takes are there.

`--on-device` deletes, instead, what Retake leaves in the app's container on the device: takes'
copies of the app's data, and staged set files. `record` does this at the end of a run, so it's for
one that was interrupted. Only the app can delete files in its container, so this launches it in a
mode that deletes them and quits before any of the app's own code runs; iOS then opens the app
again, as from the home screen, and Retake closes it. It never touches the app's real data, nor
takes or cuts on the Mac.

Edits are left as they are: they name no takes. `retake clean` then `retake record` starts everything
over.

### `retake cut`

```
retake cut <edit>... [--type <type>] [--draft] [--open]
retake cut --all [--type <type>] [--draft]
```

Renders each edit, for each device type it names (or only `--type`'s), from each scene's take, to
`output/cuts/<type>/<edit>/`:

- `<edit>-<type>-master.mov`, ProRes, and
- `<edit>-<type>.mp4`, H.264 at the size and frame rate App Store Connect specifies for the type.

Both show the whole edit: its captions, touches, spotlights, stills and sound, and its blurs, an
edit's and a turn's, so neither shows what a blur hides. An edit with blurs takes a little longer to
cut, since its master is written twice: once as the edit is composed, and again with the blurs.

Each video records the takes it was cut from in its [metadata](#a-videos-fields). The edit isn't
touched, except that a time given in plain seconds becomes an anchor against its scene's take,
the latest step to start at or before it and an `offset` from that step's start,
checked against those takes before the edit is rewritten. A caption's `from` or
`to` in seconds that is the moment it starts or ends anyway, on every device type, to a sixtieth of
a second, is dropped instead, so it keeps following its clip; the rewritten edit keeps
its fields' order, and a `"$schema"` naming one of Retake's schemas is updated to this Retake's. To
cut from the take a scene's take replaced, put it back with [`takes --restore`](#retake-takes)
before cutting.

`--draft` renders a quick, smaller H.264 alone, `<edit>-<type>-draft.mp4`: for checking timing, and
for sharing where the full size isn't needed, such as a post on social media. A draft outside App
Store Connect's limits is warned about rather than failed. `--open` opens the result.

Warns, and carries on, when the edit's takes were recorded on more than one build of the app, device
or iOS version, or Button Heist, naming the takes on each; the video's [metadata](#a-videos-fields) lists all of them.

Fails (1) if a scene has no successful take, saying why when its take can't be read, an anchor doesn't resolve, an element a spotlight
or blur names isn't in the take's step log at that moment, one device type's takes come from devices
with different screens (naming the takes on each), or the result is outside App Store Connect's
limits for a preview, such as its length.

### `retake status`

```
retake status [--json]
```

Summarizes the project, per device type:

- each scene, when its take, its previous take and its latest failure were recorded, and why the
  failure failed;
- each edit, and the take of each scene it's cut from, by when it was recorded;
- each video, and whether it's out of date: its edit has changed since it was rendered, or a scene's
  take isn't the one its record names by device type and when it was recorded, as when the scene
  has been recorded again or its previous take put back. A video cut by an earlier Retake, whose
  record names takes by number, is out of date, since its takes can't be told.

With `--json`, prints a list of device types, each with its `deviceType`, `scenes`, `edits` and
`videos`:

- A scene gives its `scene`, and its `take`, `previous` and `failed`, each null when it has none, or
  its `recordedAt`, `successful`, whether an edit can be cut from it, and as `takes --json` gives
  them, `failure` and `problem`.
- An edit gives its `edit` and `uses`, each scene it's cut from as its `scene` and the `recordedAt`
  of its take, left out when the scene has no successful take, and `problem` when the edit can't be
  read, which is listed for each device type, since it can't say which it's for.
- A video gives its `edit`, its `file`'s name, whether it's a `draft`, when it was `renderedAt`,
  whether it's `upToDate`, the `changes` that make it out of date, and `mixed`, what its takes span
  more than one of, as `cut` warns.

<!-- schema: none -->
```json
[
  {
    "deviceType": "ipad",
    "scenes": [
      {
        "scene": "create-note",
        "take": { "recordedAt": "2026-11-06T09:30:00Z", "successful": true },
        "previous": null,
        "failed": { "recordedAt": "2026-11-06T09:41:12Z", "successful": false, "failure": "create-note: step 2 of 3, tap \"Send\", didn't run: \"Send\" isn't on screen" }
      }
    ],
    "edits": [
      { "edit": "video1", "uses": [{ "scene": "create-note", "recordedAt": "2026-11-06T09:30:00Z" }, { "scene": "share-note" }] }
    ],
    "videos": [
      {
        "edit": "video1", "file": "video1-ipad.mp4", "draft": false, "renderedAt": "2026-11-06T10:02:45Z",
        "upToDate": false, "changes": ["share-note has no successful take now"], "mixed": []
      }
    ]
  }
]
```

Reports; never fails on what it finds, except an [earlier Retake's](#takes-from-an-earlier-retake)
numbered takes, which it refuses.

### `retake info`

```
retake info <movie>... [--json]
```

Prints the [metadata](#movie-metadata) Retake wrote into each movie: a take, a master, or an `.mp4`.
A video lists each take it was cut from by its scene and when it was recorded. Works on any of them
wherever they've been moved to, outside a project as well as in one. Fails (1) for a movie Retake
didn't write.

With `--json`, prints a list with an object for each movie that could be read, giving its `movie`,
as it was named, and its `take` or its `video`. A take gives [its fields](#a-takes-fields) named
as its step log names them: `scene`, `set`, `state`, `deviceType`, `device` (`model`,
`marketingName` and `os`), `app` (`bundleID`, `version` and `build`), `retake`, `buttonHeist`
(`version`, and `commit` for a Retake built from a local clone) and `recordedAt`. A video gives
its record as the `.mp4`'s description holds it, whose `takes` give each one's `scene`,
`deviceType` and `recordedAt`:

<!-- schema: none -->
```json
[
  {
    "movie": "output/takes/ipad/create-note.mov",
    "take": {
      "scene": "create-note", "set": "returning-user", "state": "cloned", "deviceType": "ipad",
      "device": { "model": "iPad13,4", "marketingName": "iPad Pro (11-inch) (3rd generation)", "os": "26.6.2 (23G90)" },
      "app": { "bundleID": "com.example.notes", "version": "1.9.0", "build": "412" },
      "retake": "0.1.0", "buttonHeist": { "version": "0.7.1" }, "recordedAt": "2026-11-06T09:30:00Z"
    }
  }
]
```

A video's `video` is the record shown under [a video's fields](#a-videos-fields).

### `retake check`

```
retake check <path>
```

Checks an `.xcarchive`, `.ipa` or `.app` for TheInsideJob and Retake's support library, in its
frameworks and in its executables. Exits 1 if either is found, naming where, and 0 if neither is. It
also exits 1 when it can't read part of what it checks, since what it can't read it can't clear,
naming it and saying how to let it: in an Xcode build phase, by adding it to the phase's inputs, or
by running `check` on the archive once it's built. Made for a release script or an archive's build
phase. In a phase with Xcode's script sandbox on, list as the phase's inputs the app, its
`Info.plist`, its executable, its `Frameworks` folder and each framework's executable, which are
what `check` reads. An app embedded by `retake install` is a copy, so never reaches an archive; one
embedded in place by `retake embed` would, if the same build were archived, which `check` catches.

### `retake validate`

```
retake validate [<file>...] [--offline] [--json]
```

Checks the project's files, or the files named, against the schemas, then what a schema can't say:

- names that must exist: a scene's set, a set's `extends` (with no cycles), a set's `files`, an
  edit's scenes, sounds and music;
- that step ids are unique in a scene, aren't numbers, and aren't `start` or `end`;
- that every step id an edit references exists in that scene for each device type;
- that no scene or edit has `+` in its name, and no edit is named as a scene is, since
  `retake share` joins clips with `+` and reads a name as either a cut or a take;
- with takes recorded, that every anchor resolves in each scene's take, and every
  element a spotlight or blur names is in the step log at that moment, as `cut` will check. A scene
  with no successful take here, as in a fresh clone or on CI, is warned about rather than failed,
  and what's cut from it isn't checked. An [earlier Retake's](#takes-from-an-earlier-retake)
  numbered takes are a problem, naming each folder to delete. `--offline` skips this.

Needs no device and changes nothing. Prints every problem, not just the first, and fails (1) if
there's any. Made for CI and pre-commit hooks, and for an agent checking an edit it changed;
`--json` prints the problems as a list, each with its file, path and message.

### `retake schema`

```
retake schema (retake | set | scene | edit | take)
retake schema --output <dir>
```

Prints the schema for one kind of file, or with `--output` writes all of them there, one or the
other, as
`<kind>.schema.json`. They are the same schemas the files' `"$schema"` URLs name, for this version
of Retake. `take` is a take's step log, which Retake writes and names no schema in.

### `retake version`

```
retake version [--json]
```

Prints Retake's version and the version of The Button Heist it's built against. For a Retake built
from a local clone of The Button Heist (`RETAKE_BUTTONHEIST_PATH`), it also prints the clone's path
and commit, which ends in `-dirty` when the clone had uncommitted changes.

## Schemas

Each kind of file Retake reads has a [JSON Schema](https://json-schema.org) (draft 2020-12): `retake.json`, sets, scenes and
edits, and the step logs Retake writes beside its takes (`take`), which a project doesn't edit.
They're published with each release, at a URL that names the version,
`https://justinseanmartin.github.io/Retake/schemas/<version>/<kind>.schema.json`, and `retake
schema` prints them.

- **They are generated, not written.** Retake's Swift types for the files are the only source of
  truth: each field's description, type, range and default are written once, on the type, and the
  schemas and the [reference](reference/) are generated from them. A test fails if the checked-in schemas or
  reference differ from what the types generate, and every JSON example in the README and these docs
  is validated against the schemas.
- **They are strict.** Every object rejects keys it doesn't define, the same as Retake's own
  reading, so an editor marks a misspelled key rather than leaving it to be ignored.
- **They change with Retake.** A release that changes what a file may say changes the schema version
  in its URL. Retake reads only its own version's shape: a file written for an older one that no
  longer fits fails with the field to change. A step log is read by its own `format` instead, which
  Retake doesn't write until a change needs one: a log without it is format 1, and one of a later
  format is refused as recorded by a newer Retake.

## Files Retake writes

Retake writes in four places: the project, its output directory, the app's container on the device,
and its own cache, outside any project.

**In the project**, in `Retake/` unless [`init`](#retake-init) was told otherwise. Nothing but these commands
changes a project's own files:

| Path | What |
| --- | --- |
| `retake.json`, `sets/`, `scenes/iphone/`, `scenes/ipad/`, `edits/` | Created by `init`. |
| `.gitignore` | Created by `init`, or added to, naming the output directory. An output directory outside the project's folder goes in the current directory's `.gitignore` instead. |
| `scenes/<type>/*.json` | Written by `compose`. |
| `edits/*.json` | Rewritten by `cut` when it turns times in plain seconds into anchors, keeping a `"$schema"` that names one of Retake's up to date. |

**In the output directory**, `output/` in the project's folder unless [moved](#the-output-directory), and gitignored.
What's worth keeping, and nothing that's rewritten wholesale:

| Path | What |
| --- | --- |
| `takes/<type>/<scene>.mov` | The scene's take: the latest recording of it that succeeded, which edits are cut from. |
| `takes/<type>/<scene>.json` | Its [step log](reference/take.md), and what it was recorded with: device, app version and build, set and state, Retake and Button Heist versions. |
| `takes/<type>/<scene>.previous.mov`, `.json` | The take the scene's take replaced, for [`takes --restore`](#retake-takes) to put back. A new take that succeeds deletes it, keeping the take it replaces here instead. |
| `takes/<type>/<scene>.failed.mov`, `.json` | The scene's latest failure, kept to show what went wrong. A new failure replaces it, and a new take that succeeds deletes it. |
| `takes/<type>/<scene>.recording.mov`, `.json` | A take while it's recorded, renamed into place once it's done. One left by a recording killed outright is deleted by the next. |
| `cuts/<type>/<edit>/` | Rendered videos, from `cut`. |
| `installed.json` | The bundle ID of the app `install` last embedded, for [finding the app](#finding-the-app). |

**On the device**, in the app's container:

| Path | What |
| --- | --- |
| `tmp/RetakeSet/` | The set's files, staged for launch, and consumed by the launch that lays them out. |
| `tmp/RetakeTakes/` | Each take's copy of the app's data, for `clean` and `cloned` sets, deleted by the next launch, and at the end of a run (or by `clean --on-device`). A `live` take writes into the app's real data instead. |
| `tmp/RetakeLaunch/report.json` | What Retake's support library reports at launch, which Retake reads back to check it; replaced by each launch. |

**In Retake's cache**, `~/Library/Caches/retake/`, each person's own and for every project, never in
a repository:

| Path | What |
| --- | --- |
| `builds/<project>/DerivedData/` | The app as `install` builds it with `xcodebuild`. |
| `builds/<project>/installed/` | The copy `install` embeds Retake in and installs, replaced each time. |
| `devices.json` | Device aliases, from `devices add`, `devices remove` and `init`. |
| `insidejob/<version>/` | TheInsideJob for the Button Heist version Retake is built against, for a Retake built from source (`Scripts/fetch-insidejob.sh`), or `insidejob/clone/` for one built from a clone of The Button Heist; a release carries its own. |
| `support/<contract>/` | Retake's support library, by its contract version, for a Retake built from source; a release carries its own. |
| `screen-capture-released` | When Retake last let go of a device's screen, so the next command waits out the 8 seconds macOS takes to offer it again. |

`<project>` is named for the project's folder and the folder holding it, with a hash of the
project's path, such as `Notes-Retake-8a9e87f7`, so two projects, or two clones of one, never share
a build. Everything here but `devices.json` can be made again: clearing the cache costs a full build
at the next `install`, and forgets device aliases, which `devices add` names again.

**Elsewhere:**

| Path | What |
| --- | --- |
| The `.app` given to `embed` | Changed in place, unless `--output` says otherwise. |
| `$TMPDIR/retake-*` | What one command works with: the app's console during a run, `devicectl`'s answers, the launch report copied back, and an archive `check` unpacks. A run's console is kept for when a launch fails, whose last lines the error quotes, and is left for the system to clear. |

## Movie metadata

Every movie Retake writes records how it was made. Takes and masters are QuickTime movies, and carry
the fields below as QuickTime metadata, which `ffprobe` and AVFoundation read. MP4 has no place for
custom fields that AVFoundation will write, so the `.mp4` carries the same record as JSON in its
description (ISO user data, which AVFoundation reads and `ffprobe` doesn't), with the software field
beside it. `retake info` reads both.

Nothing personal is written: not the device's name, nor its UDID.

### Standard fields

| Field | Value |
| --- | --- |
| `com.apple.quicktime.software` | `Retake <version>`, which Finder and Spotlight show as the encoding software. |
| `com.apple.quicktime.make` | `Apple`. Takes only. |
| `com.apple.quicktime.model` | The device's marketing name, such as `iPad Pro (11-inch) (3rd generation)`. Takes only. |
| `com.apple.quicktime.creationdate` | When it was recorded or rendered, ISO 8601. |

### A take's fields

| Field | Value |
| --- | --- |
| `retake.version` | Retake's version, such as `0.1.0`. |
| `retake.scene` | The scene's name. |
| `retake.set` | The set's name. |
| `retake.state` | The set's `state`: `clean`, `cloned` or `live`. |
| `retake.app.bundle-id` | The app's bundle ID. |
| `retake.app.version` | The app's `CFBundleShortVersionString`, such as `1.9.0`. |
| `retake.app.build` | The app's `CFBundleVersion`, such as `412`. |
| `retake.buttonheist.version` | The Button Heist version that drove the app, such as `0.7.1`: the one embedded in it, which is the one Retake is built against. A build between releases ends in its contract hash, such as `0.7.1-d53fb59edbf3`. |
| `retake.buttonheist.commit` | Only for a Retake built from a local clone of The Button Heist: the clone's full commit, ending in `-dirty` when it had uncommitted changes. |
| `retake.device.model` | The device's hardware identifier, such as `iPad13,4`. |
| `retake.device.type` | `iphone` or `ipad`. |
| `retake.device.os` | The iOS version and build, such as `26.6.2 (23G90)`. |

`retake.buttonheist.version` tells any two builds of The Button Heist apart that could disagree,
releases or not, since builds between releases carry their contract hash. The commit is recorded
only where the version can't say where the build came from: a local clone.

### A video's fields

| Field | Value |
| --- | --- |
| `retake.version` | The Retake that rendered it. |
| `retake.edit` | The edit's name. |
| `retake.device.type` | The device type this video was rendered for. |
| `retake.app.bundle-id` | The app's bundle ID. |
| `retake.app.versions` | JSON array: each distinct app version and build among the video's takes, as `{"version", "build"}`. |
| `retake.devices` | JSON array: each distinct device among the takes, as `{"model", "marketingName", "os"}`. |
| `retake.buttonheist.versions` | JSON array: each distinct Button Heist among the takes, as `{"version"}`, with `"commit"` for a take recorded by a Retake built from a local clone. |
| `retake.takes` | JSON array: for each take in the video, its `scene`, `deviceType` and `recordedAt`, which together name the take and which `status` compares with the scene's take now, and the take's own fields above. A video cut by an earlier Retake gives a `take` number instead of `recordedAt`. |

The three summary fields are always arrays, holding one entry when every take agrees, so a reader
handles one shape. Entries are in the order the video first shows them, and each pairs values that
belong together, such as a version with its build. `retake.takes` says which take used which.

`cut` warns when the takes span more than one entry in any of them — different builds of the app,
different devices or iOS versions, or different Button Heists — and names the takes on each. `retake
status` and `retake info` show the same.

The `.mp4`'s description holds all of a video's fields as one JSON object. Here, one take was
recorded on a later build than the other:

<!-- schema: none -->
```json
{
  "retake": { "version": "0.1.0" },
  "edit": "video1",
  "deviceType": "iphone",
  "bundleID": "com.example.notes",
  "appVersions": [
    { "version": "1.9.0", "build": "412" },
    { "version": "1.9.0", "build": "415" }
  ],
  "devices": [
    { "model": "iPhone18,5", "marketingName": "iPhone 17e", "os": "26.6.2 (23G90)" }
  ],
  "buttonHeistVersions": [
    { "version": "0.7.1" }
  ],
  "takes": [
    { "scene": "create-note", "deviceType": "iphone", "recordedAt": "2026-11-06T09:30:00Z", "retake": "0.1.0", "app": { "version": "1.9.0", "build": "412" }, "device": { "model": "iPhone18,5", "os": "26.6.2 (23G90)" }, "buttonHeist": { "version": "0.7.1" } },
    { "scene": "share-note", "deviceType": "iphone", "recordedAt": "2026-11-06T11:12:40Z", "retake": "0.1.0", "app": { "version": "1.9.0", "build": "415" }, "device": { "model": "iPhone18,5", "os": "26.6.2 (23G90)" }, "buttonHeist": { "version": "0.7.1" } }
  ]
}
```
