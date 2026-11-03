import SwiftUI

// Config/Base.xcconfig sets this when no team is given to sign with.
#if NOTES_NEEDS_TEAM
#error("Notes has no development team to sign with. Run Examples/Notes/run.sh --setup, or copy Config/Signing.example.xcconfig to Config/Signing.local.xcconfig and fill it in.")
#endif

/// Notes, Retake's example app: a small notes app with everything a scene can drive, and
/// nothing that changes between takes. Its notes live in `Documents/notes.json` and its settings
/// in `UserDefaults`, so a set's `files` and `defaults` decide what it starts on.
@main
struct NotesApp: App {
    @State private var library = NoteLibrary()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(library)
        }
    }
}

struct RootView: View {
    @AppStorage(Settings.hasSeenWelcome) private var hasSeenWelcome = false

    var body: some View {
        if hasSeenWelcome {
            LibraryView()
        } else {
            WelcomeView { hasSeenWelcome = true }
        }
    }
}

/// The first screen a new install shows, until it's dismissed.
struct WelcomeView: View {
    let dismiss: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "note.text")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
            Text("Welcome to RetakeNotes")
                .font(.largeTitle.bold())
            Text("A demo app used to showcase Retake, a quick App Store preview capture tool.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Get Started", action: dismiss)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .padding(32)
    }
}
