# Examples

## Notes

A small SwiftUI notes app for iPhone and iPad, made to be recorded by Retake: everything a scene
drives, and nothing that changes between takes. On a device it's called RetakeNotes, so it isn't
mistaken for the device's own Notes.

- A welcome screen on first launch, until **Get Started** is tapped.
- A library of notes, with **New Note**, and rows that drag up or down to reorder.
- A note's **Title** to type into, which shows **Synced** 1.5 s after it's saved, and a **Share**
  sheet whose **Send to Alex** shows **Sent**.
- In landscape, the library and the open note side by side.

What it starts on is a set's to decide: its notes are in `Documents/notes.json`, and its settings in
`UserDefaults` (`hasSeenWelcome`, and `sortOrder`, `manual` or `title`).

Its Retake project is in `Notes/Retake/`, as `retake init` makes one: `retake.json`, its sets,
scenes and edits, the files its sets copy, in `data/`, and the music and sound effects its edits
play, in `audio/`. Run Retake's commands from `Examples/Notes/`, or from inside `Retake/`.

A `screenshots` scene, for iPhone and iPad, captures stills of the library and of a note, on the
iPad open beside the library in landscape, into `Notes/Retake/output/captures/`. Its set,
`screenshots`, is `returning-user` with the app filling the screen, as a screenshot wants.

It has two edits:

- `tour`, for iPhone and iPad: getting started, then a note written, synced, shared and filed.
- `showcase`, for iPhone and iPad: every feature of an edit, one to a clip, each captioned with what
  it shows. It's the video at the top of Retake's README, the iPhone's and the iPad's side by side:
  touches and taps with a sound, a cut, a spotlight and a chime, a blur and a whoosh, a drag's tail,
  a letterboxed turn with an animated symbol, touches and captions in a color of their own, and a
  montage of other takes that ends on a credit, with cross-fades between them and music under it
  all. One edit makes both: it names steps and elements, not times or points, so each device's
  takes fill it in.

The music and sounds are made by `Retake/audio/generate.py`, so none of them is anyone else's.

### From a clone, in one go

You need a Mac with Xcode, an Apple account signed in to Xcode (Settings > Accounts; a free one
works), and an iPhone or iPad with Developer Mode on, connected by USB and trusted. Then, from the
repository's root:

```sh
Examples/Notes/run.sh
```

It does each step below, and finishes with the video's master and App Store files in
`Notes/Retake/output/cuts/`, and the `screenshots` scene's stills in `Notes/Retake/output/captures/`; once an iPhone's and an iPad's are both cut, it shares the two side by
side, a small MP4 with sound, in `Notes/Retake/output/share/`. Run it again to record and cut
again. Its options:

| Option | |
| --- | --- |
| `--team <id>` | The team to sign with, when the keychain has identities for several. |
| `--device <device>` | The device, by alias, UDID or name, when several are connected. |
| `--setup` | Only build Retake and sign the example, then say what to run. |
| `--cut-only` | Cut from the takes already recorded, without a device: after changing an edit. |
| `--readme` | Say how to make the iPhone's and iPad's side by side the README's video. GitHub plays only video uploaded to it, so the README links to an upload: drag the file from `Notes/Retake/output/share/` into a new issue's description on github.com, copy the link it adds without creating the issue, and put it in the README in place of the old. |

Nothing it writes is checked in: the build is in `.build/` (or
`RETAKE_SCRATCH_PATH`), the team in `Config/Signing.local.xcconfig`, and the rest in
`Notes/Retake/output/`, which Git ignores. Your device's alias, and everything else that's only
yours, is in `~/Library/Caches/retake/`.

### Step by step

From the repository's root:

1. Build `retake`, its support library, and The Button Heist's TheInsideJob, which it installs into
   the app. It prints the path of the `retake` it built; name that, so the commands below run it:

   ```sh
   Scripts/build.sh
   alias retake="$PWD/.build/release/retake"     # the path build.sh printed
   cd Examples/Notes
   ```

   The alias names the built `retake`; it doesn't build anything. Run `Scripts/build.sh` again
   only after pulling changes to Retake.

2. Sign the example with your team. Nothing checked in names one, so that the repository works for
   everyone and stays clean: your team goes in `Config/Signing.local.xcconfig`, which Git ignores.

   ```sh
   cp Config/Signing.example.xcconfig Config/Signing.local.xcconfig
   ```

   and set its `DEVELOPMENT_TEAM` to your team's ID: the ten letters and digits in Xcode's Settings
   > Accounts, or at developer.apple.com under Membership. It's also the `OU` of your Apple
   Development certificate, which is where `run.sh --setup` finds it, using
   `RETAKE_SIGNING_IDENTITY`'s when that's set, so the app's build and Retake's signing agree. The
   app's bundle ID is made from the team, `com.example.retake.<team>.notes`, so it's yours alone;
   `BUNDLE_ID_PREFIX` there changes it.

   Without a team, building Notes, in Xcode, `xcodebuild` or `retake install`, stops with
   *Notes has no development team to sign with*, and says how to give one. Don't choose a team in
   Xcode's Signing & Capabilities instead: that changes the project, which is checked in.

3. Connect the device, install the app with Retake in it, record the scenes, and cut the video:

   ```sh
   retake devices add iphone        # or ipad: names the connected device, for you only
   retake install
   retake record                    # every scene for the device's type
   retake cut showcase --open
   ```

   `install` stops with Xcode's or the device's own error when it can't sign the app for the
   device or install it there: the device locked, not trusting the Mac, or without Developer Mode.
   A device that isn't on your team's profiles yet needs `retake install
   --allow-provisioning-updates` once, which lets Xcode register it. `record` records each scene
   with no take yet; `record --force` records them all again, after changing the app. Edit
   `Retake/edits/showcase.json` and `retake cut showcase` again to see a change, without recording.

   If something fails and its message doesn't say why, `retake doctor` checks each part in turn:
   Xcode, the device, signing, the installed app, and a launch.

4. Once it's cut on both an iPhone and an iPad, share the two side by side, small enough to post,
   as `run.sh` does: the iPhone's on the left, with the iPad's sound, on a grey that stands apart
   from the edit's navy:

   ```sh
   retake share showcase/iphone+showcase/ipad --audio 2 --background "#3A3A3C"
   ```

   It's written to `Retake/output/share/showcase-iphone+showcase-ipad.mp4`.

Its integration test does step 3 from a copy of the project, so a run leaves the
example's own output alone: `RETAKE_TEST_DEVICE=<device> swift test --filter EndToEnd`.
