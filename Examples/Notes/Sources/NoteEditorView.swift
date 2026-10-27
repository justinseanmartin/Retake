import SwiftUI

/// A note being written: its title, its text, whether it has synced, and sharing it.
struct NoteEditorView: View {
    @Environment(NoteLibrary.self) private var library
    @State private var note: Note
    @State private var sharing = false
    let close: () -> Void

    init(note: Note, close: @escaping () -> Void) {
        _note = State(initialValue: note)
        self.close = close
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Title", text: $note.title)
                    .font(.title2.bold())
                    .submitLabel(.done)
                    .onSubmit { library.update(note) }
                TextField("Note", text: $note.body, axis: .vertical)
                    .lineLimit(4...)
                Section {
                    if library.syncing == note.id {
                        Label("Syncing…", systemImage: "arrow.triangle.2.circlepath")
                    } else if !note.title.isEmpty {
                        Label("Synced", systemImage: "checkmark.icloud")
                            .foregroundStyle(.green)
                    }
                }
            }
            .navigationTitle(note.title.isEmpty ? "New Note" : note.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Library") {
                        library.update(note)
                        close()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Share", systemImage: "square.and.arrow.up") { sharing = true }
                        .disabled(note.title.isEmpty)
                }
            }
            .sheet(isPresented: $sharing) {
                ShareView(title: note.title)
                    .presentationDetents([.medium])
            }
        }
    }
}

/// Sharing a note: a contact to send it to, and a confirmation.
struct ShareView: View {
    let title: String
    @Environment(\.dismiss) private var dismiss
    @State private var sent = false

    var body: some View {
        VStack(spacing: 20) {
            Text("Share \u{201C}\(title)\u{201D}").font(.headline)
            if sent {
                Label("Sent", systemImage: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.green)
                Button("Done") { dismiss() }
                    .buttonStyle(.bordered)
            } else {
                Button("Send to Alex") { sent = true }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }
}
