# The `retake` command

This is the contract for Retake's command line: each command, what it reads and writes, and how it
fails. How the files fit together is in the [README](../README.md), and every field of every file is in the
[reference](reference/), generated from Retake's schemas.

Retake is in design, so this describes the command as it will be.

## Conventions

### Finding the project

A project is a folder: its configuration file, `retake.json`, and beside it the project's own
folders, `sets/`, `scenes/` and `edits/`, and its output, `output/`. [`init`](#retake-init) makes it in `Retake/`,
at the root of the repository, so everything of Retake's is in one place, apart from the app's own
files.

Every command except `init`, `version` and `devices` runs in a project, named by its configuration
file, under any name. (`devices` reads one when there is one, for its aliases and `device`.) The
first of these that's given names it:

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

What Retake writes — takes, cuts, and the builds `install` makes — goes in the project's output
directory, the first of these that's given:

1. `--output-dir <dir>`, relative to the current directory;
2. the `RETAKE_OUTPUT_DIR` environment variable, relative to the current directory;
3. the configuration file's `output`, relative to the directory holding it;
4. `output/` beside the configuration file.

`init` adds the default, or the one it's given, to the project's `.gitignore`. The paths below are
written with the default, inside the project's folder. Retake creates the directory when it first
writes to it. An environment variable that's set but empty counts as not set, for both variables.

It holds the takes edits pin, so moving it somewhere temporary, such as `/tmp` or an agent's scratch
directory, suits runs whose takes don't need to outlive it: a take recorded there is gone when the
directory is cleared, and an edit pinned to it fails to `cut` until it's recorded and conformed
again.

### Finding the app

Commands that launch the app, or put a set's files in its container, need its bundle ID, which comes
from the first of these that's given:

1. the configuration file's `bundleID`;
2. the app `install` last built and embedded, in the output directory's `build/`, from its
   `Info.plist`.

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
named, the command stops and lists them. `RETAKE_DEVICE` comes before the configuration file because
devices belong to people, and the file is shared: it suits a session spent on one device.

The device's **type** — `iphone` or `ipad`, asked of the device itself — picks the folders a command
works in: `scenes/<type>/` and `output/takes/<type>/`.

### Names

Scenes, sets and edits are named by their file name without `.json`: `create-note` is
`scenes/<type>/create-note.json`, and `video1` is `edits/video1.json`. Takes are numbered per scene
and device type, from 1, and are never renumbered.

### Reading the project's files

Every command reads the project's files the same way, strictly, against Retake's [schemas](#schemas): a key
Retake doesn't know, a value of the wrong type or outside its range, or a missing required field
fails the command (1) before it does anything, and every error names the file and the path to the
field:

```
edits/video1.json: clips[3].from.fraction: 1.4 is outside -1 to 1
scenes/ipad/create-note.json: steps[2]: unknown key "tapp"
```

Each file's `"$schema"` key says which schema it was written against, and is optional. A file
without one is read against this Retake's; one naming another version's is read against this
Retake's too, with a warning when the versions differ, since the schema can't be older or newer than
the code reading it.

### Output

Commands print progress for people. Those that report something — `devices`, `takes`, `status`,
`doctor`, `version` — take `--json` for a stable, machine-readable form instead.

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
| [`doctor`](#retake-doctor) | Checks the setup end to end. |
| [`devices`](#retake-devices) | Lists devices, and names them. |
| [`install`](#retake-install) | Builds the app if asked, embeds Retake in it, and installs it. |
| [`embed`](#retake-embed) | Adds what Retake needs to a built app, for installing it yourself. |
| [`compose`](#retake-compose) | Writes a scene a step at a time, on the device. |
| [`record`](#retake-record) | Records takes, or with `--dry-run`, plays scenes without recording them. |
| [`takes`](#retake-takes) | Lists takes. |
| [`clean`](#retake-clean) | Deletes takes and cuts. |
| [`conform`](#retake-conform) | Pins an edit to newer takes of its scenes. |
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

What doesn't belong in the repository goes in a `.gitignore` in the project's folder: the output
directory, and `devices.json`, where [`devices add`](#retake-devices) keeps aliases. An output directory outside the
project's folder goes in the current directory's `.gitignore` instead, when it's below the current
directory, and in neither when it isn't.

`retake.json` names its schema's URL in `"$schema"`, which editors fetch to complete and check it.
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
retake doctor [--device <device>]
```

Checks, in order, and reports each as passed, warned or failed:

1. Xcode, `devicectl` and `codesign` are available.
2. The device is connected by USB, paired, and offered for screen capture.
3. A development signing identity is in the keychain, and a provisioning profile covers the app's
   bundle ID and the device.
4. The app is installed on the device, with Retake embedded (by `retake install` or `retake embed`).
5. The app launches, Retake's support library and The Button Heist's server answer, and both are
   [compatible](#compatibility-with-an-embedded-app) with this Retake.

Exits 0 when everything passed, otherwise with the status of the first failure.

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
chosen. It needs no project, but reads one's aliases and `device` when there is one, found as
[Finding the project](#finding-the-project) says.

`add` names a device: the one `<device>` gives, by its UDID or its name as `devicectl` reports it,
or with none given, the one connected; with several connected and none given, it asks which. It
records the device's UDID and its screen-capture identity, which differ, in the project's
`devices.json`, beside `retake.json`. Fails (2) if the alias is taken, or there's no project.
`<device>` is an argument, not `--device`, since it says which device to name rather than which to
use, and `RETAKE_DEVICE` plays no part. When `RETAKE_DEVICE` names a different device, `add` notes
that the shell's commands will still use that one:

```
Commands in this shell still use "ipad" (RETAKE_DEVICE); pass --device phone to use this one.
```

`remove` forgets an alias.

Aliases are kept in the project, so nothing Retake keeps lives outside it, but not in the
repository: `init` gitignores `devices.json`. A device's UDID and name are its owner's, and the name
is often theirs too ("Anna's iPad"); and one person's `ipad` isn't another's. A project's
`retake.json` can name a default `device` for everyone, which each person's own alias of that name
then stands for.

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

The build itself isn't changed: the copy is in `output/build/installed/`, replaced each time. On
APFS, the copy is a clone of the build, so it takes no time and no space until embedding changes it,
when the build is on the same volume as the output directory, as one `install` builds always is.

Where the app comes from, the first that applies:

1. `--app`: an already built, development-signed `.app` for iOS devices.
2. `--scheme`: Retake builds it with `xcodebuild`, as below.
3. `retake.json`'s `build`, in one of two forms:

   ```json
   "build": { "scheme": "MyApp", "workspace": "MyApp.xcworkspace", "configuration": "Debug" }
   ```

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
unless given), with its build products under `output/build/`, so it doesn't disturb your own builds,
and finds the `.app` from the build's settings. Signing is the project's own. Any configuration
works, so long as it's development-signed for the device; `Debug` is the default because it usually
is.

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
   without signing, or signed with a profile that doesn't include the device.

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
| `waitFor` | An element | `--gone`, `--timeout <seconds>` (10) |
| `hold` | `--seconds <seconds>` | |

`hold` adds a step that's only a pause, as `{ "hold": 2 }` does in a file. A step's `--hold` is the
scene's `defaultHold` when it isn't given.

An element is any of `--label <text>`, `--value <text>`, `--identifier <text>`, `--hint <text>` and
`--traits <trait>,<trait>`, at least one, with `--occurrence <n>` (from 1, optional) to pick one of
several that match. Other actions act on the scene rather than the app, and add no step:

| Action | Required | Optional | Does |
| --- | --- | --- | --- |
| `inspect` | | An element | Prints what's on screen again, or only the elements that match, each with the `--occurrence` that picks it. |
| `set` | `--hold <seconds>` or `--id <name>`, or both | | Changes the last step's hold, or its id, for edits to anchor to. |
| `undo` | | How many steps, `<n>` (1) | Drops the last step, or the last `<n>`, then launches the app again and replays the rest. |
| `replay` | | | Launches the app again and replays every step, dropping none. |
| `steps` | | | Lists the scene's steps. |
| `help` | | An action's name | Lists the actions and their options, or one action's. |
| `quit` | | | Ends; so does Control-D. |

`undo` and `help` take their one option bare: `undo 3`, `help tap`. `inspect` with an element, such
as `inspect --label "Delete"`, is for picking out one of several alike: it lists them in the order
VoiceOver reads them, numbered as `--occurrence` counts them. `replay` gets the app back to where
the scene ends after something moved it off course, such as a step that failed partway, without
dropping anything.

At a terminal, an action given without an option it needs asks for it, saying which options are
optional and what they default to. Read from a pipe, as when a script or an agent drives it, the
action fails instead, naming what's missing, and nothing is asked. With `--json`, each reply is one
line of JSON, for a program to read: `{"ok": true, "step": {…}, "screen": […]}` after a step,
`{"ok": false, "error": "…"}` when one doesn't run or an action is wrong, and `{"ok": true,
"screen": […]}` for `inspect`, the screen as each element's `label`, `value`, `identifier`, `hint`,
`traits`, `frame` and `activationPoint`, with its `occurrence` when `inspect` was given an element.

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

Records a new take of each scene chosen:

| Form | Records |
| --- | --- |
| `retake record` | Every scene in `scenes/<type>/` with no take yet. |
| `retake record --force` | Every scene in `scenes/<type>/`. |
| `retake record --for <edit>` | Every scene the edit uses that has no take yet. |
| `retake record --for <edit> --force` | Every scene the edit uses. |
| `retake record <scene>...` | The scenes named, whether or not they have takes. |

`--force` adds a new take to scenes that already have one; it never replaces a take. When every
scene chosen already has a take, `record` says so and records nothing.

For each scene, in order:

1. Stops the app, and copies the set's files to the device; its defaults go with the launch.
2. Launches the app with the set's environment and arguments. Before the app's code runs, Retake's
   support library builds the take's data from the set's `state` (`clean`, `cloned` or `live`; see
   the README) and deletes earlier takes' copies. If the support library doesn't report in, or
   reports an [incompatible](#compatibility-with-an-embedded-app) contract or Button Heist version, the scene fails (3) before its first
   step, saying to `retake embed` or `retake install` the app again.
3. Plays the setup steps, then records the lead-in, the steps with their holds, and the tail. After
   each step, and when each `waitFor` is satisfied, records the elements on screen in the step log.
4. Writes `output/takes/<type>/<scene>/<n>.mov` and its step log `<n>.json`, `<n>` being one more
   than the scene's last take.

After the last scene, when any take was `clean` or `cloned`, launches the app once more to delete
the take's copy of its data and the staged set files from the device, as [`clean --on-device`](#retake-clean) does,
so none is left behind.

A take whose step fails is kept, marked failed, for its footage to show what went wrong; it can't be
pinned by an edit. Recording carries on with the next scene unless `--stop-on-failure` is given, and
a summary at the end lists each scene's new take or failure.

Existing takes are never changed.

**`--dry-run`** plays the scenes chosen as `record` would, without recording them, for trying a
scene out while writing it: it launches on each scene's set, plays its setup and steps with their
holds, prints each step as it plays, and deletes the take's copy of the app's data from the device
at the end. It writes nothing, and fails (1) at the first step that doesn't run, naming it. It plays
every step with its hold, as a take would: a step can need the app to have settled after the one
before, so a dry run that skipped holds could fail where a take wouldn't, or pass where it fails.

### `retake takes`

```
retake takes [<scene>] [--device <device> | --type <type>] [--json]
```

Lists takes, of one scene or all: number, when it was recorded, the app's version and build, the
device and its model, duration, frames dropped, whether it failed, and the edits that pin it.

Without `--device` or `--type`, lists takes of both device types.

### `retake clean`

```
retake clean [--takes [<scene>[@<take>],...]] [--cuts [<edit>,...]] [--type <type>] [--yes]
retake clean --on-device [--device <device>]
```

Deletes takes and cuts, of both device types unless `--type` names one:

| Form | Deletes |
| --- | --- |
| `retake clean` | Every take and every cut. |
| `retake clean --takes` | Every take. |
| `retake clean --takes create-note,share-note@2` | Every take of `create-note`, and take 2 of `share-note`. |
| `retake clean --cuts` | Every cut. |
| `retake clean --cuts video1` | `video1`'s cuts. |

`--takes` and `--cuts` can be given together. It lists what it will delete, naming each take an edit
pins, and asks first, unless `--yes`. Fails (2), deleting nothing, if a scene, take or edit named
doesn't exist.

Since [`conform`](#retake-conform) pins each scene's latest take, deleting later takes is how an edit goes back to an
earlier one: `retake clean --takes create-note@5`, then `retake conform video1`, pins take 4.

`--on-device` deletes, instead, what Retake leaves in the app's container on the device: takes'
copies of the app's data, and staged set files. `record` does this at the end of a run, so it's for
one that was interrupted. Only the app can delete files in its container, so this launches it in a
mode that deletes them and quits before any of the app's own code runs; iOS then opens the app
again, as from the home screen, and Retake closes it. It never touches the app's real data, nor
takes or cuts on the Mac.

Edits' pins are left as they are, now pointing at takes that don't exist, so `cut` fails until
they're recorded and conformed again. `retake clean` then `retake record` starts everything over.

### `retake conform`

```
retake conform <edit> [--type <type>] [--dry-run]
```

Pins an edit to the latest successful take of each scene it uses, for each device type it names, or
only `--type`'s. To cut from an earlier take, delete the takes after it with [`clean --takes`](#retake-clean).

An edit's anchors name steps, not seconds, so they find the same moments in the new takes without
changing. `conform` checks that every anchor resolves in the new takes, updates the edit's `takes`
pins, and rewrites the edit in place. It fails (1), writing nothing, if an anchor doesn't resolve,
naming the clip and the scene: an id the new take's scene no longer has, say.

Any time still given as plain seconds is first turned into an anchor against the take it was cut
from: the latest step starting at or before it, and the seconds after it. That's also how an edit
written in seconds moves to anchors once.

Prints each change. `--dry-run` prints them without writing. The rewritten edit keeps its fields'
order and its `"$schema"`, updated to this Retake's.

### `retake cut`

```
retake cut <edit>... [--type <type>] [--draft] [--open]
retake cut --all [--type <type>] [--draft]
```

Renders each edit, for each device type it names (or only `--type`'s), from the takes it pins, to
`output/cuts/<type>/<edit>/`:

- `<edit>-<type>-master.mov`, ProRes, and
- `<edit>-<type>.mp4`, H.264 at the size and frame rate App Store Connect specifies for the type.

`--draft` renders a quick, smaller H.264 alone: for checking timing, and for sharing where the full
size isn't needed, such as a post on social media. `--open` opens the result.

Warns, and carries on, when the edit's takes were recorded on more than one build of the app, device
or iOS version, or Button Heist, naming the takes on each; the video's [metadata](#a-videos-fields) lists all of them.

Fails (1) if a pinned take is missing or failed, an anchor doesn't resolve, an element a spotlight
or blur names isn't in the take's step log at that moment, one device type's takes come from devices
with different screens (naming the takes on each), or the result is outside App Store Connect's
limits for a preview, such as its length.

### `retake status`

```
retake status [--json]
```

Summarizes the project, per device type:

- each scene, its latest take, and when it was recorded;
- each edit, the takes it pins, and whether a scene has a newer take than the one it pins;
- each video, and whether its edit or pinned takes have changed since it was rendered.

Reports; never fails on what it finds.

### `retake info`

```
retake info <movie>... [--json]
```

Prints the [metadata](#movie-metadata) Retake wrote into each movie: a take, a master, or an `.mp4`. Works on any of
them wherever they've been moved to, outside a project as well as in one. Fails (1) for a movie
Retake didn't write.

### `retake check`

```
retake check <path>
```

Checks an `.xcarchive`, `.ipa` or `.app` for TheInsideJob and Retake's support library, in its
frameworks and in its executables. Exits 1 if either is found, naming where, and 0 if neither is.
Made for a release script or an archive's build phase. An app embedded by `retake install` is a
copy, so never reaches an archive; one embedded in place by `retake embed` would, if the same build
were archived, which `check` catches.

### `retake validate`

```
retake validate [<file>...] [--offline] [--json]
```

Checks the project's files, or the files named, against the schemas, then what a schema can't say:

- names that must exist: a scene's set, a set's `extends` (with no cycles), a set's `files`, an
  edit's scenes, sounds and music;
- that step ids are unique in a scene, aren't numbers, and aren't `start` or `end`;
- that a scene of the same name on each device type an edit names has the same step ids;
- with takes recorded, that every anchor resolves in the takes the edit pins, and every element a
  spotlight or blur names is in the step log at that moment, as `cut` will check. `--offline` skips
  this.

Needs no device and changes nothing. Prints every problem, not just the first, and fails (1) if
there's any. Made for CI and pre-commit hooks, and for an agent checking an edit it changed;
`--json` prints the problems as a list, each with its file, path and message.

### `retake schema`

```
retake schema [retake | set | scene | edit] [--output <dir>]
```

Prints the schema for one kind of file, or with `--output` writes all of them there, as
`<kind>.schema.json`. They are the same schemas the files' `"$schema"` URLs name, for this version
of Retake.

### `retake version`

```
retake version [--json]
```

Prints Retake's version and the version of The Button Heist it's built against. For a Retake built
from a local clone of The Button Heist (`RETAKE_BUTTONHEIST_PATH`), it also prints the clone's path
and commit, which ends in `-dirty` when the clone had uncommitted changes.

## Schemas

Each kind of file Retake reads has a [JSON Schema](https://json-schema.org) (draft 2020-12): `retake.json`, sets, scenes and
edits. They're published with each release, at a URL that names the version,
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
  longer fits fails with the field to change.

## Files Retake writes

Paths in the project are relative to its folder, `Retake/` unless [`init`](#retake-init) was told otherwise.

**In the project.** Nothing but these commands changes a project's own files:

| Path | What |
| --- | --- |
| `retake.json`, `sets/`, `scenes/iphone/`, `scenes/ipad/`, `edits/`, `.gitignore` | Created by `init`. |
| `scenes/<type>/*.json` | Written by `compose`. |
| `edits/*.json` | Rewritten by `conform`. |
| `devices.json` | Device aliases, from `devices add` and `remove`. Gitignored. |

**In the output directory**, `output/` unless [moved](#the-output-directory), and gitignored:

| Path | What |
| --- | --- |
| `takes/<type>/<scene>/<n>.mov` | A take's footage. |
| `takes/<type>/<scene>/<n>.json` | A take's step log, and what it was recorded with: device, app version and build, set and state, Retake and Button Heist versions. |
| `cuts/<type>/<edit>/` | Rendered videos, from `cut`. |
| `build/` | The app as `install` builds it, and the copy it embeds Retake in. |

**On the device**, in the app's container:

| Path | What |
| --- | --- |
| `tmp/RetakeSet/`, `tmp/RetakeTakes/` | The set's files, staged for launch, and the take's copy of the app's data, deleted at the end of the run (or by `clean --on-device`). A `live` take writes into the app's real data instead. |

**Elsewhere:**

| Path | What |
| --- | --- |
| The `.app` given to `embed` | Changed in place, unless `--output` says otherwise. |
| `~/Library/Caches/retake/` | Anything Retake can make again: TheInsideJob and the support library it embeds, and when it last used a device's screen. |

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
| `retake.take` | The take's number. |
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
| `retake.app.versions` | JSON array: each distinct app version and build among the video's takes, as `{"version", "build"}`. |
| `retake.devices` | JSON array: each distinct device among the takes, as `{"model", "marketingName", "os"}`. |
| `retake.buttonheist.versions` | JSON array: each distinct Button Heist among the takes, as `{"version"}`, with `"commit"` for a take recorded by a Retake built from a local clone. |
| `retake.takes` | JSON array: for each take in the video, its scene, take number, and the take's own fields above. |

The three summary fields are always arrays, holding one entry when every take agrees, so a reader
handles one shape. Entries are in the order the video first shows them, and each pairs values that
belong together, such as a version with its build. `retake.takes` says which take used which.

`cut` warns when the takes span more than one entry in any of them — different builds of the app,
different devices or iOS versions, or different Button Heists — and names the takes on each. `retake
status` and `retake info` show the same.

The `.mp4`'s description holds all of a video's fields as one JSON object. Here, one take was
recorded on a later build than the other:

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
    { "scene": "create-note", "take": 3, "retake": "0.1.0", "app": { "version": "1.9.0", "build": "412" }, "device": { "model": "iPhone18,5", "os": "26.6.2 (23G90)" }, "buttonHeist": { "version": "0.7.1" } },
    { "scene": "share-note", "take": 1, "retake": "0.1.0", "app": { "version": "1.9.0", "build": "415" }, "device": { "model": "iPhone18,5", "os": "26.6.2 (23G90)" }, "buttonHeist": { "version": "0.7.1" } }
  ]
}
```
