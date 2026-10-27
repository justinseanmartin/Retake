import SwiftUI

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
            Text("Jot something down, share it, and watch it sync.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Get Started", action: dismiss)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .padding(32)
    }
}
