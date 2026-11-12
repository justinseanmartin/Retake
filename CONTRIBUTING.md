# Contributing to Retake

Pull requests are welcome, whether they fix something or add what Retake doesn't do yet; the
README's [limitations](README.md#limitations) are a good place to start. For a large change, open
an issue first to talk it over. Or fork it and go wild.

- **Tests.** Add tests for what you change: useful ones, not mundane ones, each taking well under a
  second. `swift test` runs them, and [CI](.github/workflows/ci.yml) runs them on every pull
  request, with the device tests skipping themselves. With a device connected,
  `RETAKE_TEST_DEVICE=<device> swift test --filter EndToEnd` also records and cuts the example from
  a copy of its project.
- **Docs.** A change to what a command or file does changes the [README](README.md), the
  [command reference](Documentation/cli.md) or the [schemas](#schemas) with it, and goes in
  [RELEASE.md](RELEASE.md) under the next release, saying whether it breaks anything.
- **Commits** follow [Conventional Commits](https://www.conventionalcommits.org), such as
  `feat(record): …` or `fix(subprocess): …`, as `git log` shows.

## Building from source

Retake is a Swift package. To work on it you need only Xcode.

`.xcode-version` names the Xcode that Retake's releases are built with. For working on Retake it's
the version known to work, not a requirement: nothing checks it locally, and other versions usually
work too. If a build fails on yours, that's the version to try. Releases are different: the release
build uses exactly that version, and fails without it. TheInsideJob isn't built by Retake at all;
it's The Button Heist's own release build, which records its Xcode in the bundle's `XCODE_VERSION`.

```sh
Scripts/build.sh               # builds a runnable retake, and prints its path
swift test
```

`Scripts/build.sh` is the three steps a source checkout needs before `retake` can install an app,
each quick when there's nothing new: `swift build -c release`, `Scripts/build-support.sh`, which
builds Retake's support library for iOS, and `Scripts/fetch-insidejob.sh`, which gets the
TheInsideJob Retake installs, for the pinned release. It builds into `RETAKE_SCRATCH_PATH`, or
`.build`, and prints the path of the `retake` it built, last and alone, for a script to run:
`retake="$(Scripts/build.sh)"` builds once, then `"$retake"` runs it as often as needed.

`swift build` fetches The Button Heist's packages at the pinned release, since Retake links its
client library directly. `Scripts/fetch-insidejob.sh` downloads the same release's
`theinsidejob-<version>.zip`, checks it against the release's checksums, and puts its
`TheInsideJob.xcframework` where a locally built `retake` installs it from. Released builds include
it. Neither needs The Button Heist's own development tools.

## Running the example

To run [the example](Example) from a fresh clone, connect a device by USB and run one script, which
builds Retake, signs the example with your team, and records and cuts it:

```sh
Example/run.sh
```

[Its README](Example/README.md) says what it does, step by step. By hand, once
`run.sh --setup` has signed it, from `Example/`:

```sh
retake install                           # builds the example, embeds Retake, installs it
retake record                            # records each scene, for the device's type
retake cut tour                          # renders it, for the device's type
```

## Schemas

The schemas in `Documentation/reference/` are generated from Retake's file types, and checked in.
After changing what a file may say, regenerate them, and the reference beside them:

```sh
swift run retake schema --output Documentation/reference
RETAKE_REGENERATE=1 swift test --filter Reference
```

A pre-commit hook refuses a commit whose staged schemas differ from what the types generate. Turn it
on once per clone with `git config core.hooksPath Scripts/git-hooks`. It builds `retake` into
`RETAKE_SCRATCH_PATH`, or `.build` unless that's set.

Editors fetch the schemas from GitHub Pages, at the URL each one's `$id` names. Once they've changed
on `main`, publish them there with `Scripts/publish-schemas.sh`: it copies them into
`schemas/<version>/` on the `gh-pages` branch, checked out in `.pages/` (ignored by Git), pushes,
and turns Pages on the first time. It publishes only `main` with nothing uncommitted, and won't
replace a version's schemas once they're published, since files name them by their URL; `--force`
does all three.

The README's video is on GitHub Pages too, since GitHub plays no video in a README but its own
uploads: the README shows a poster that links to `showcase/`, a page that plays it. Once the
example's showcase is recorded and cut on both an iPhone and an iPad, `Example/run.sh --cut-only
--readme` publishes it with `Scripts/publish-showcase.sh`, which copies the side by side into
`showcase/` on `gh-pages` with its poster and page, and pushes, replacing the one before.

## Releasing

Releases are built and published from a maintainer's Mac, not by CI: signing and notarizing take a
Developer ID and a notary profile that only the maintainer's keychain has. Once the release's pull
request, which sets `RetakeVersion.current` and dates its RELEASE.md entry, is merged:

```sh
git switch main && git pull
git tag -a v<version> -m "Retake <version>" && git push origin v<version>
Scripts/release.sh <output-dir>
gh release create v<version> --title "Retake <version>" \
    --notes-file <(Scripts/release-notes.sh <version>) <output-dir>/retake-*.tar.gz*
Scripts/publish-schemas.sh
```

`Scripts/release.sh` builds from the checkout, so run it from a clean one at the tag. It reads the
Developer ID and notary profile from `Scripts/release.local.env` (see its `.example`), and refuses
to build until RELEASE.md dates the version and the docs name no other release.
`Scripts/release-notes.sh` prints the version's RELEASE.md section, which is the GitHub release's
notes, so what a release breaks is said there too.

## Working on Retake and The Button Heist together

For changes that span both, point Retake at a local clone of The Button Heist:

```sh
export RETAKE_BUTTONHEIST_PATH=../TheButtonHeist
swift build
Scripts/fetch-insidejob.sh
```

With `RETAKE_BUTTONHEIST_PATH` set, `swift build` uses that clone instead of the pinned release, and
`Scripts/fetch-insidejob.sh` builds TheInsideJob from it rather than downloading it. One variable
drives both on purpose: Retake's client and the framework it installs must come from the same
source. A clone between releases reports a version with its contract hash, so a framework built from
a different state of the clone is refused at the handshake rather than half working. Rebuild both
after changing the clone.

A build from a clone says so. `retake version` names the clone's path and commit, ending in `-dirty`
when it has uncommitted changes, and so does each take's metadata. Release builds refuse to run with
the variable set.

SwiftPM drops The Button Heist's pin from `Package.resolved` while building from a clone. Don't
commit that change: `git checkout Package.resolved` puts the pin back, and
`Scripts/fetch-insidejob.sh` needs it to download the release.
