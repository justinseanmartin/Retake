# Examples

## Notes

A small SwiftUI notes app for iPhone and iPad, made to be recorded by Retake: everything a scene
drives, and nothing that changes between takes.

- A welcome screen on first launch, until **Get Started** is tapped.
- A library of notes, with **New Note**, and rows that drag up or down to reorder.
- A note's **Title** to type into, which shows **Synced** 1.5 s after it's saved, and a **Share**
  sheet whose **Send to Alex** shows **Sent**.
- In landscape, the library and the open note side by side.

What it starts on is a set's to decide: its notes are in `Documents/notes.json`, and its settings in
`UserDefaults` (`hasSeenWelcome`, and `sortOrder`, `manual` or `title`).

To build it for a device, copy `Notes/Config/Signing.example.xcconfig` to
`Notes/Config/Signing.local.xcconfig`, which isn't checked in, and fill in your team and a bundle ID
prefix of your own. Then open `Notes/Notes.xcodeproj`, or build its `Notes` scheme with
`xcodebuild`.
