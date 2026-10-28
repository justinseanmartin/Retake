import Foundation

/// What `retake status` reports, per device type: each scene's latest take, each edit's pins and
/// whether a newer take is waiting, and each video and whether it's out of date. Reports; never
/// fails on what it finds. See Documentation/cli.md, "retake status".
public struct ProjectStatus: Sendable {
    public struct Section: Sendable {
        public var type: DeviceType
        public var scenes: [Scene] = []
        public var edits: [Edit] = []
        public var videos: [Video] = []
    }

    public struct Scene: Sendable {
        public var name: String
        /// Its latest take, failed or not; nil before it has one.
        public var latest: TakeStore.Take?
    }

    public struct Edit: Sendable {
        public var name: String
        public var pins: [Pin]
        /// Why the edit can't be read, which `validate` says in full.
        public var problem: String?
    }

    public struct Pin: Sendable {
        public var scene: String
        public var take: Int
        /// The latest take of the scene that didn't fail, when it's later than the one pinned.
        public var newer: Int?
        /// Why the pinned take can't be cut from: it isn't recorded, or failed.
        public var problem: String?
    }

    public struct Video: Sendable {
        public var edit: String
        public var file: URL
        public var draft: Bool
        public var renderedAt: Date?
        /// What has changed since it was rendered; empty when it's up to date.
        public var changes: [String]
        /// What its takes span more than one of, as `cut` warned.
        public var mixed: [String]
    }

    public var sections: [Section]

    /// The project's status, for each device type it has a scene, edit or video for, reading each
    /// video's record with `read`.
    public static func of(
        _ project: Project, reading read: @Sendable (URL) async throws(RetakeError) -> MovieInfo = MovieInfo.read,
    ) async -> ProjectStatus {
        let files = ProjectFiles(project: project)
        var edits: [String: EditFile] = [:], unreadable: [String: String] = [:]
        for name in files.names(in: project.edits) {
            let report = ProjectFiles.Report()
            if let edit = files.readEdit(name, into: report) {
                edits[name] = edit
            } else {
                unreadable[name] = report.problems.first.map { "\($0.description)\(report.problems.count > 1 ? " (and more; run `retake validate`)" : "")" } ?? "can't be read"
            }
        }

        var sections: [Section] = []
        for type in DeviceType.allCases {
            var section = Section(type: type)
            let takes = Dictionary(grouping: TakeStore.takes(for: [type], in: project), by: \.scene)
            section.scenes = files.names(in: project.scenes(for: type)).map { Scene(name: $0, latest: takes[$0]?.last) }

            for name in (edits.keys.filter { edits[$0]!.devices.contains(type) } + unreadable.keys).sorted() {
                guard let edit = edits[name] else {
                    section.edits.append(Edit(name: name, pins: [], problem: unreadable[name]))
                    continue
                }
                let pins = (edit.takes[type] ?? []).map { pin in
                    let recorded = takes[pin.name] ?? []
                    let latest = recorded.last { !$0.failed }?.number
                    var problem: String?
                    if let take = recorded.first(where: { $0.number == pin.value }) {
                        if take.failed { problem = take.recorded?.failure.map { "failed: \($0)" } ?? take.problem ?? "failed" }
                    } else {
                        problem = "isn't recorded"
                    }
                    return Pin(scene: pin.name, take: pin.value, newer: latest.flatMap { $0 > pin.value ? $0 : nil }, problem: problem)
                }
                section.edits.append(Edit(name: name, pins: pins))
            }

            for folder in Self.folders(in: project.cuts(for: type)) {
                let edit = folder.lastPathComponent
                let movies = ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).filter { $0.hasSuffix(".mp4") }.sorted()
                for movie in movies {
                    let file = folder.appending(path: movie)
                    section.videos.append(await video(file, of: edit, for: type, edits: edits, unreadable: unreadable, takes: takes, files: files, read: read))
                }
            }

            if !section.scenes.isEmpty || !section.edits.isEmpty || !section.videos.isEmpty { sections.append(section) }
        }
        return ProjectStatus(sections: sections)
    }

    static func folders(in folder: URL) -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).filter { !$0.hasPrefix(".") }.sorted()
            .map { folder.appending(path: $0, directoryHint: .isDirectory) }
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
    }

    static func modified(_ url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    /// A rendered video, and what has changed since: its edit, the takes the edit pins, or a pinned
    /// take recorded again under the same number.
    static func video(
        _ file: URL, of name: String, for type: DeviceType, edits: [String: EditFile], unreadable: [String: String],
        takes: [String: [TakeStore.Take]], files: ProjectFiles, read: (URL) async throws(RetakeError) -> MovieInfo,
    ) async -> Video {
        let rendered = modified(file)
        var video = Video(edit: name, file: file, draft: file.lastPathComponent.hasSuffix("-draft.mp4"), renderedAt: rendered, changes: [], mixed: [])
        let info: MovieInfo
        do {
            info = try await read(file)
        } catch {
            video.changes.append("it can't be read: \(error.message)")
            return video
        }
        video.mixed = info.mixed

        if unreadable[name] != nil {
            video.changes.append("its edit can't be read")
            return video
        }
        guard let edit = edits[name] else {
            video.changes.append("its edit is gone")
            return video
        }
        if let rendered, let changed = modified(files.editURL(name)), changed > rendered {
            video.changes.append("its edit has changed")
        }
        let pins = Dictionary((edit.takes[type] ?? []).map { ($0.name, $0.value) }, uniquingKeysWith: { first, _ in first })
        if case .array(let records)? = info.json[path: "takes"] {
            for record in records {
                guard let scene = record[path: "scene"]?.stringValue, case .number(let number)? = record[path: "take"] else { continue }
                let take = Int(number)
                if let pinned = pins[scene], pinned != take {
                    video.changes.append("\(scene) is pinned to take \(pinned) now, not \(take)")
                } else if pins[scene] == nil {
                    video.changes.append("\(scene) isn't pinned now")
                } else if let rendered, let log = takes[scene]?.first(where: { $0.number == take })?.log,
                          let recorded = modified(log), recorded > rendered {
                    video.changes.append("\(scene)@\(take) has been recorded again")
                }
            }
        }
        return video
    }
}
