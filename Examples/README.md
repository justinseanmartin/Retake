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

It has two edits:

- `tour`, for iPhone and iPad: getting started, then a note written, synced, shared and filed.
- `showcase`, for iPad: every feature of an edit, one to a clip, each captioned with what it shows.
  It's the video at the top of Retake's README: touches and taps with a sound, a cut, a spotlight
  and a chime, a blur and a whoosh, a drag's tail, a letterboxed turn with an animated symbol, and
  a montage of other takes, with cross-fades between them and music under it all.

The music and sounds are made by `Retake/audio/generate.py`, so none of them is anyone else's.

### From a clone, in one go

You need a Mac with Xcode, an Apple account signed in to Xcode (Settings > Accounts; a free one
works), an iPhone or iPad with Developer Mode on, connected by USB and trusted, and, for the small
copies at the end, `ffmpeg` (`brew install ffmpeg`). Then, from the repository's root:

```sh
Examples/Notes/run.sh
```

It does each step below, and finishes with the video's master and App Store files in
`Notes/Retake/output/cuts/`, and small copies of it, an MP4 with sound and a GIF, in
`Notes/Retake/output/share/`. Run it again to record and cut again. Its options:

| Option | |
| --- | --- |
| `--team <id>` | The team to sign with, when the keychain has identities for several. |
| `--device <device>` | The device, by alias, UDID or name, when several are connected. |
| `--setup` | Only build Retake and sign the example, then say what to run. |
| `--cut-only` | Cut from the takes already recorded, without a device: after changing an edit. |
| `--readme` | Write the iPad's small copies to `Documentation/media/`, for the README. |

Nothing it writes is checked in, except with `--readme`: the build is in `.build/` (or
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
   retake cut showcase --open       # on an iPhone: retake cut tour --open
   ```

   `install` stops with Xcode's or the device's own error when it can't sign the app for the
   device or install it there: the device locked, not trusting the Mac, or without Developer Mode.
   A device that isn't on your team's profiles yet needs `retake install
   --allow-provisioning-updates` once, which lets Xcode register it. `record` records each scene
   with no take yet; `record --force` records them all again, after changing the app. Edit
   `Retake/edits/showcase.json` and `retake cut showcase` again to see a change, without recording.

   If something fails and its message doesn't say why, `retake doctor` checks each part in turn:
   Xcode, the device, signing, the installed app, and a launch.

4. Make a copy small enough to share, as `run.sh` does:

   ```sh
   ffmpeg -i Retake/output/cuts/ipad/showcase/showcase-ipad.mp4 -vf scale=720:-2 \
       -c:v libx264 -crf 25 -pix_fmt yuv420p -c:a aac -b:a 80k showcase.mp4
   ```

Its integration test does step 3 from a copy of the project, so a run leaves the
example's own output alone: `RETAKE_TEST_DEVICE=<device> swift test --filter EndToEnd`.
