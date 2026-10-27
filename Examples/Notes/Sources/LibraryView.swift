import SwiftUI

/// The notes, newest first unless dragged into another order, with the note open beside them in
/// landscape and over them in portrait. The keyboard doesn't count: on an iPad in portrait it
/// leaves less height than width, which would otherwise turn the layout, and lose the field being
/// typed into, as soon as it appears.
struct LibraryView: View {
    @Environment(NoteLibrary.self) private var library
    @AppStorage(Settings.sortOrder) private var sortOrder = "manual"
    @State private var open: Note.ID?

    var body: some View {
        GeometryReader { geometry in
            if geometry.size.width > geometry.size.height {
                HStack(spacing: 0) {
                    list.frame(width: geometry.size.width * 0.4)
                    Divider()
                    editor ?? AnyView(placeholder)
                }
            } else if let editor {
                editor
            } else {
                list
            }
        }
        .ignoresSafeArea(.keyboard)
    }

    private var list: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 8) {
                    let notes = library.sorted(by: sortOrder)
                    ForEach(Array(notes.enumerated()), id: \.element.id) { index, note in
                        NoteRow(note: note, rows: notes.count) { offset in
                            if sortOrder == "manual" { library.move(from: index, to: index + offset) }
                        }
                        .onTapGesture { open = note.id }
                    }
                }
                .padding()
            }
            .overlay {
                if library.notes.isEmpty {
                    ContentUnavailableView("No Notes", systemImage: "note.text", description: Text("Tap New Note to start one."))
                }
            }
            .navigationTitle("Library")
            .toolbar {
                Button("New Note", systemImage: "square.and.pencil") { open = library.add().id }
            }
        }
    }

    private var editor: AnyView? {
        guard let open, let note = library.notes.first(where: { $0.id == open }) else { return nil }
        return AnyView(NoteEditorView(note: note) { self.open = nil })
    }

    private var placeholder: some View {
        Text("Select a note").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A note in the library, dragged up or down by whole rows to reorder it.
struct NoteRow: View {
    let note: Note
    let rows: Int
    let moved: (Int) -> Void
    @State private var drag: CGFloat = 0
    private let height: CGFloat = 64

    var body: some View {
        HStack {
            Text(note.title.isEmpty ? "Untitled" : note.title).font(.headline)
            Spacer()
            Image(systemName: "line.3.horizontal").foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .frame(height: height)
        .background(.background.secondary, in: .rect(cornerRadius: 12))
        .offset(y: drag)
        .zIndex(drag == 0 ? 0 : 1)
        .gesture(
            DragGesture(minimumDistance: 10)
                .onChanged { drag = $0.translation.height }
                .onEnded { value in
                    drag = 0
                    let offset = Int((value.translation.height / (height + 8)).rounded())
                    if offset != 0 { moved(offset) }
                },
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(note.title.isEmpty ? "Untitled" : note.title)
    }
}
