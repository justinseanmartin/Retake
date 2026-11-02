import SwiftUI

/// The notes, newest first unless dragged into another order, with the note open beside them in
/// landscape and over them in portrait. The keyboard doesn't count: on an iPad in portrait it
/// leaves less height than width, which would otherwise turn the layout, and lose the field being
/// typed into, as soon as it appears.
struct LibraryView: View {
    @Environment(NoteLibrary.self) private var library
    @AppStorage(Settings.sortOrder) private var sortOrder = "manual"
    @State private var open: Note.ID?
    /// The note being dragged, and how far.
    @State private var dragging: (id: Note.ID, by: CGFloat)?

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
            // In place of the list rather than over it: as an overlay of the scroll view, it was
            // laid out a few words wide.
            Group {
                if library.notes.isEmpty {
                    ContentUnavailableView("No Notes", systemImage: "note.text", description: Text("Tap New Note to start one."))
                } else {
                    ScrollView {
                        VStack(spacing: 8) {
                            let notes = library.sorted(by: sortOrder)
                            ForEach(Array(notes.enumerated()), id: \.element.id) { index, note in
                                NoteRow(note: note, offset: offset(of: index, in: notes), dragged: dragging?.id == note.id) { by in
                                    dragging = (note.id, by)
                                } ended: {
                                    let destination = destination(in: notes)
                                    withAnimation(.spring(duration: 0.3)) {
                                        if sortOrder == "manual", let destination { library.move(from: index, to: destination) }
                                        dragging = nil
                                    }
                                }
                                .onTapGesture { open = note.id }
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Library")
            .toolbar {
                Button("New Note", systemImage: "square.and.pencil") { open = library.add().id }
            }
        }
    }

    /// Where the dragged note would go if let go now: whole rows from where it was.
    private func destination(in notes: [Note]) -> Int? {
        guard let dragging, let from = notes.firstIndex(where: { $0.id == dragging.id }) else { return nil }
        return min(max(from + Int((dragging.by / NoteRow.pitch).rounded()), 0), notes.count - 1)
    }

    /// How far a row is moved from its place: the dragged one with the finger, and those it has
    /// passed a row the other way, to make room for it.
    private func offset(of index: Int, in notes: [Note]) -> CGFloat {
        guard let dragging, let from = notes.firstIndex(where: { $0.id == dragging.id }), let to = destination(in: notes) else { return 0 }
        if index == from { return dragging.by }
        if from < to, (from + 1 ... to).contains(index) { return -NoteRow.pitch }
        if to < from, (to ..< from).contains(index) { return NoteRow.pitch }
        return 0
    }

    private var editor: AnyView? {
        guard let open, let note = library.notes.first(where: { $0.id == open }) else { return nil }
        return AnyView(NoteEditorView(note: note) { self.open = nil })
    }

    private var placeholder: some View {
        Text("Select a note").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A note in the library, dragged up or down by whole rows by its handle, on the right, to reorder
/// it. The list moves it: with the finger while it's dragged, and the others aside, springing, to
/// make room.
struct NoteRow: View {
    let note: Note
    let offset: CGFloat
    let dragged: Bool
    let changed: (CGFloat) -> Void
    let ended: () -> Void
    private static let height: CGFloat = 64
    /// From one row to the next: its height and the gap after it.
    static let pitch: CGFloat = height + 8

    var body: some View {
        HStack {
            Text(note.title.isEmpty ? "Untitled" : note.title).font(.headline)
            Spacer()
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.secondary)
                .frame(width: 44, height: Self.height)
                .contentShape(.rect)
                .gesture(
                    // Measured on the screen: the row moves with the finger, so in its own space
                    // the drag would seem to go only part of the way.
                    DragGesture(minimumDistance: 10, coordinateSpace: .global)
                        .onChanged { changed($0.translation.height) }
                        .onEnded { _ in ended() },
                )
        }
        .padding(.horizontal)
        .frame(height: Self.height)
        .background(.background.secondary, in: .rect(cornerRadius: 12))
        .shadow(color: .black.opacity(dragged ? 0.15 : 0), radius: 8, y: 4)
        .offset(y: offset)
        // The dragged row follows the finger; the others spring aside.
        .animation(dragged ? nil : .spring(duration: 0.25), value: offset)
        .zIndex(dragged ? 1 : 0)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(note.title.isEmpty ? "Untitled" : note.title)
    }
}
