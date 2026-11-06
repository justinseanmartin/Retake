import Foundation

/// Prepares an edit for `retake cut`: turns any time still in plain seconds into an anchor against
/// its scene's latest successful take, which is what a time in seconds is read against, and checks
/// every anchor resolves in the latest takes before the edit is rewritten. See Documentation/cli.md,
/// the cut.
public enum CutPreparer {
    public struct Result: Sendable {
        /// The edit's new text, laid out as before.
        public var text: String
        /// What changed, a line each, for a person.
        public var changes: [String]
    }

    /// The normalized edit `name`, for each of its device types, or only `types`. Fails (1), with
    /// nothing to write, for an edit that can't be read, a scene with no successful take, a time in
    /// seconds whose take isn't here to turn it into an anchor, or an anchor or element that doesn't
    /// resolve in the new takes; misuse (2) for a type the edit doesn't name.
    public static func prepare(_ name: String, types requested: [DeviceType]? = nil, in project: Project) throws(RetakeError) -> Result {
        let files = ProjectFiles(project: project)
        let url = files.editURL(name)
        let report = ProjectFiles.Report()
        guard let edit = files.readEdit(name, into: report),
              let text = try? String(contentsOf: url, encoding: .utf8), case .object(var root) = try? JSONParser.parse(text) else {
            throw report.problems.isEmpty ? RetakeError(.failed, "\(project.displayPath(url)) can't be read.") : report.error
        }
        if let requested, let missing = requested.first(where: { !edit.devices.contains($0) }) {
            throw RetakeError(.usage, "\(name) isn't cut for \(missing.rawValue): its devices are \(edit.devices.map(\.rawValue).joined(separator: ", ")).")
        }
        let types = edit.devices.filter { requested?.contains($0) ?? true }
        var changes: [String] = []

        func log(_ scene: String, _ type: DeviceType) -> TakeLog? {
            TakeStore.takes(of: scene, for: [type], in: project).last(where: \.successful)?.recorded
        }
        var problems: [String] = []
        // Where each time in seconds was, by its path, for those it turns into a caption's default.
        var convertedPaths: [String: String] = [:]
        func converted(_ value: JSONValue, at path: String, scene: String?, type: DeviceType?) -> JSONValue {
            switch value {
            case .array(let values):
                return .array(values.enumerated().map { converted($1, at: "\(path)[\($0)]", scene: scene, type: type) })
            case .object(let object):
                let scene = object["take"].flatMap { if case .string(let take) = $0 { take } else { nil } } ?? scene
                return .object(JSONObject(object.entries.map { entry in
                    let at = path.isEmpty ? entry.key : "\(path).\(entry.key)"
                    if let override = DeviceType(rawValue: entry.key) {
                        guard types.contains(override) else { return entry }
                        return .init(key: entry.key, value: converted(entry.value, at: at, scene: scene, type: override))
                    }
                    guard ["from", "to", "at", "stillsIn", "stillsOut"].contains(entry.key), case .number(let seconds) = entry.value, let scene else {
                        return .init(key: entry.key, value: converted(entry.value, at: at, scene: scene, type: type))
                    }
                    // A time in an override is its type's; one shared by every type, the first's with a take.
                    let candidates = type.map { [$0] } ?? types
                    guard let source = candidates.lazy.compactMap({ type in log(scene, type).map { ($0, type) } }).first else {
                        problems.append("\(at): \(JSONReader.format(seconds)) s needs a successful take of \(scene) to become an anchor in; record it.")
                        return entry
                    }
                    let anchor = anchor(for: seconds, in: source.0)
                    changes.append("\(at): \(JSONReader.format(seconds)) s into \(scene) take \(source.0.take) (\(source.1.rawValue)) becomes \(JSONWriter.compact(anchor))")
                    convertedPaths[at] = "\(JSONReader.format(seconds)) s into \(scene) take \(source.0.take)"
                    return .init(key: entry.key, value: anchor)
                }))
            default:
                return value
            }
        }
        root = JSONObject(root.entries.map { entry in
            entry.key == "clips" ? .init(key: "clips", value: converted(entry.value, at: "clips", scene: nil, type: nil)) : entry
        })
        guard problems.isEmpty else { throw RetakeError(.failed, problems.joined(separator: "\n")) }

        // One of Retake's own schemas is brought up to this Retake's; any other is the project's.
        if let index = root.entries.firstIndex(where: { $0.key == "$schema" }),
           root.entries[index].value.stringValue.flatMap(SchemaReference.init(url:)) != nil {
            root.entries[index].value = .string(SchemaReference.current("edit").url)
        }

        let newText = JSONWriter.fitting(.object(root))
        guard !changes.isEmpty else { return Result(text: newText, changes: []) }

        // Every anchor and element resolves in the latest takes, or nothing is written.
        let reader = JSONReader(file: project.displayPath(url))
        guard let prepared = EditFile.read(newText, with: reader) else {
            throw RetakeError(.failed, reader.problems.map(\.description).joined(separator: "\n"))
        }
        let validator = ProjectValidator(files: files, offline: false)
        var unresolved: [String] = []
        for type in types {
            guard let video = prepared.videos[type] else { continue }
            validator.checkTakes(of: prepared, video, for: type, problem: { path, message in
                unresolved.append("\(prepared.source(of: path, for: type)) (\(type.rawValue)): \(message)")
            }, warning: { path, message in
                unresolved.append("\(prepared.source(of: path, for: type)) (\(type.rawValue)): \(message)")
            }, reported: { _ in false })
        }
        guard unresolved.isEmpty else {
            throw RetakeError(.failed, "In the new takes, nothing was written:\n" + unresolved.joined(separator: "\n"))
        }

        let defaults = captionDefaults(prepared, types: types, among: Set(convertedPaths.keys), log: log)
        guard !defaults.isEmpty else { return Result(text: newText, changes: changes) }
        changes = changes.filter { line in !defaults.contains { line.hasPrefix("\($0): ") } }
            + defaults.sorted().map { "\($0): \(convertedPaths[$0]!) is when the caption \($0.hasSuffix(".from") ? "starts" : "ends") anyway; it's dropped" }
        return Result(text: JSONWriter.fitting(dropping(.object(root), defaults, at: "")), changes: changes)
    }

    /// The paths, among `paths`, of captions' `from`s and `to`s that are their caption's default on
    /// every device type: as its clip has faded in, or as the next starts to fade in over it, to a
    /// sixtieth of a second. Saying nothing says the same, and goes on saying it however the takes'
    /// timing changes. Nothing, unless every type's video plans.
    static func captionDefaults(_ edit: EditFile, types: [DeviceType], among paths: Set<String>, log: (String, DeviceType) -> TakeLog?) -> Set<String> {
        guard !paths.isEmpty else { return [] }
        var same: [String: Bool] = [:]
        for type in types {
            guard let video = edit.videos[type] else { return [] }
            var timelines: [String: TakeTimeline] = [:]
            for scene in video.scenes { if let found = log(scene, type) { timelines[scene] = TakeTimeline(found) } }
            guard let plan = try? CutPlan.make(video, timelines: timelines) else { return [] }
            for (index, (clip, placement)) in zip(video.clips, plan.placements).enumerated() {
                guard let timeline = timelines[clip.take] else { return [] }
                let next = plan.placements.indices.contains(index + 1) ? plan.placements[index + 1].crossfade : 0
                for (captionIndex, caption) in clip.captions.enumerated() {
                    let at = JSONPath.root.appending("clips").appending(index).appending("captions").appending(captionIndex)
                    let ends = [("from", caption.from, placement.start + placement.crossfade), ("to", caption.to?.clip == nil ? caption.to?.anchor : nil, placement.end - next)]
                    for (key, anchor, moment) in ends {
                        let source = edit.source(of: at.appending(key), for: type).description
                        guard let anchor, paths.contains(source), let time = try? timeline.time(of: anchor) else { continue }
                        same[source] = (same[source] ?? true) && abs(placement.videoTime(time) - moment) < 1.0 / 60
                    }
                }
            }
        }
        return Set(same.filter(\.value).keys)
    }

    /// `value` without the entries at `paths`, written as `converted` names them.
    static func dropping(_ value: JSONValue, _ paths: Set<String>, at path: String) -> JSONValue {
        switch value {
        case .array(let values):
            return .array(values.enumerated().map { dropping($1, paths, at: "\(path)[\($0)]") })
        case .object(let object):
            return .object(JSONObject(object.entries.compactMap { entry in
                let at = path.isEmpty ? entry.key : "\(path).\(entry.key)"
                return paths.contains(at) ? nil : .init(key: entry.key, value: dropping(entry.value, paths, at: at))
            }))
        default:
            return value
        }
    }

    /// `seconds` into the take as an anchor: the latest step starting at or before it, and the
    /// seconds after that step's start; before every step, the seconds after the take's start.
    static func anchor(for seconds: Double, in log: TakeLog) -> JSONValue {
        let steps = log.steps.sorted { $0.number < $1.number }
        guard let step = steps.last(where: { $0.start <= seconds + 0.0005 }) else {
            return seconds == 0 ? .object(JSONObject([.init(key: "step", value: .string("start"))]))
                : .object(JSONObject([.init(key: "step", value: .string("start")), .init(key: "offset", value: .number((seconds * 1000).rounded() / 1000))]))
        }
        let offset = ((seconds - step.start) * 1000).rounded() / 1000
        var entries: [JSONObject.Entry] = [.init(key: "step", value: step.id.map(JSONValue.string) ?? .number(Double(step.number)))]
        if offset != 0 {
            entries += [.init(key: "offset", value: .number(offset)), .init(key: "edge", value: .string("start"))]
        }
        return .object(JSONObject(entries))
    }
}
