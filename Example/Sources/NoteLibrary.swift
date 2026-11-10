import Foundation
import Observation

/// The keys Notes keeps in `UserDefaults.standard`, which a set's `defaults` can give.
enum Settings {
    /// Whether the welcome screen has been dismissed.
    static let hasSeenWelcome = "hasSeenWelcome"
    /// How the library is ordered: `manual` (as dragged) or `title`.
    static let sortOrder = "sortOrder"
}

struct Note: Codable, Identifiable, Equatable {
    var id: UUID
    var title: String
    var body: String
}

/// The notes, read from and saved to `Documents/notes.json`.
@MainActor
@Observable
final class NoteLibrary {
    private(set) var notes: [Note]
    /// The note whose save hasn't synced yet; nil once it has.
    private(set) var syncing: Note.ID?
    private let file: URL

    init(file: URL = URL.documentsDirectory.appending(path: "notes.json")) {
        self.file = file
        notes = (try? JSONDecoder().decode([Note].self, from: Data(contentsOf: file))) ?? []
    }

    func sorted(by order: String) -> [Note] {
        order == "title" ? notes.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending } : notes
    }

    func add() -> Note {
        let note = Note(id: UUID(), title: "", body: "")
        notes.insert(note, at: 0)
        return note
    }

    func update(_ note: Note) {
        guard let index = notes.firstIndex(where: { $0.id == note.id }) else { return }
        notes[index] = note
        save()
        sync(note.id)
    }

    func move(from source: Int, to destination: Int) {
        guard notes.indices.contains(source), notes.indices.contains(destination), source != destination else { return }
        notes.insert(notes.remove(at: source), at: destination)
        save()
    }

    private func save() {
        try? JSONEncoder().encode(notes).write(to: file, options: .atomic)
    }

    /// Syncing takes a fixed 1.5 s, so a scene can wait for it the same way on every take.
    private func sync(_ id: Note.ID) {
        syncing = id
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            if syncing == id { syncing = nil }
        }
    }
}
