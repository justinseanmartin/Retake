import Foundation

/// What `retake conform` does: pins an edit to the latest successful take of each scene it uses,
/// turning any time still in plain seconds into an anchor against the take it was cut from, and
/// checks every anchor resolves in the new takes before the edit is rewritten. See Documentation/cli.md,
/// "retake conform".
public enum Conformer {
    public struct Result: Sendable {
        /// The edit's new text, laid out as before.
        public var text: String
        /// What changed, a line each, for a person.
        public var changes: [String]
    }

    /// The conformed edit `name`, for each of its device types, or only `types`. Fails (1), with
    /// nothing to write, for an edit that can't be read, a scene with no successful take, a time in
    /// seconds whose take isn't here to turn it into an anchor, or an anchor or element that doesn't
    /// resolve in the new takes; misuse (2) for a type the edit doesn't name.
    public static func conform(_ name: String, types requested: [DeviceType]? = nil, in project: Project) throws(RetakeError) -> Result {
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

        // Times in seconds become anchors, against the takes the edit pinned when they were cut.
        let oldPins = edit.takes.mapValues { Dictionary($0.map { ($0.name, $0.value) }, uniquingKeysWith: { first, _ in first }) }
        func log(_ scene: String, _ type: DeviceType) -> TakeLog? {
            oldPins[type]?[scene].flatMap { number in TakeStore.takes(of: scene, for: [type], in: project).first { $0.number == number }?.recorded }
        }
        var problems: [String] = []
        func converted(_ value: JSONValue, at path: String, scene: String?, type: DeviceType?) -> JSONValue {
            switch value {
            case .array(let values):
                return .array(values.enumerated().map { converted($1, at: "\(path)[\($0)]", scene: scene, type: type) })
            case .object(let object):
                let scene = object["take"].flatMap { if case .string(let take) = $0 { take } else { nil } } ?? scene
                return .object(JSONObject(object.entries.map { entry in
                    let at = path.isEmpty ? entry.key : "\(path).\(entry.key)"
                    if let override = DeviceType(rawValue: entry.key) {
                        return .init(key: entry.key, value: converted(entry.value, at: at, scene: scene, type: override))
                    }
                    guard ["from", "to", "at"].contains(entry.key), case .number(let seconds) = entry.value, let scene else {
                        return .init(key: entry.key, value: converted(entry.value, at: at, scene: scene, type: type))
                    }
                    // A time in an override is its type's; one shared by every type, the first's with a take.
                    let candidates = type.map { [$0] } ?? edit.devices
                    guard let source = candidates.lazy.compactMap({ type in log(scene, type).map { ($0, type) } }).first else {
                        problems.append("\(at): \(JSONReader.format(seconds)) s needs the take it was cut from to become an anchor, and no take of \(scene) it pinned is here.")
                        return entry
                    }
                    let anchor = anchor(for: seconds, in: source.0)
                    changes.append("\(at): \(JSONReader.format(seconds)) s into \(scene) take \(source.0.take) (\(source.1.rawValue)) becomes \(JSONWriter.compact(anchor))")
                    return .init(key: entry.key, value: anchor)
                }))
            default:
                return value
            }
        }
        var pins = root["takes"].flatMap { if case .object(let object) = $0 { object } else { nil } } ?? JSONObject()
        root = JSONObject(root.entries.map { entry in
            entry.key == "clips" ? .init(key: "clips", value: converted(entry.value, at: "clips", scene: nil, type: nil)) : entry
        })
        guard problems.isEmpty else { throw RetakeError(.failed, problems.joined(separator: "\n")) }

        // Each scene each type plays, or takes a still from, pinned to its latest successful take.
        guard let interim = EditFile.read(JSONWriter.write(.object(root)), with: JSONReader(file: project.displayPath(url))) else {
            throw RetakeError(.failed, "\(project.displayPath(url)) can't be read once its times are anchors.")
        }
        for type in types {
            guard let video = interim.videos[type] else { continue }
            let scenes = video.clips.flatMap { [$0.take] + $0.stills.map(\.take) }.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
            var typePins: [JSONObject.Entry] = []
            for scene in scenes {
                guard let latest = TakeStore.takes(of: scene, for: [type], in: project).last(where: { !$0.failed }) else {
                    throw RetakeError(.failed, "There's no successful \(type.rawValue) take of \(scene) to pin; record it.")
                }
                typePins.append(.init(key: scene, value: .number(Double(latest.number))))
                let was = oldPins[type]?[scene]
                if was != latest.number {
                    changes.append("takes.\(type.rawValue).\(scene): \(was.map { "take \($0)" } ?? "nothing") becomes take \(latest.number)")
                }
            }
            let value = JSONValue.object(JSONObject(typePins))
            if let index = pins.entries.firstIndex(where: { $0.key == type.rawValue }) {
                pins.entries[index].value = value
            } else {
                pins.entries.append(.init(key: type.rawValue, value: value))
            }
        }
        if let index = root.entries.firstIndex(where: { $0.key == "takes" }) {
            root.entries[index].value = .object(pins)
        } else {
            let after = root.entries.firstIndex { $0.key == "devices" }.map { $0 + 1 } ?? root.entries.count
            root.entries.insert(.init(key: "takes", value: .object(pins)), at: after)
        }
        // One of Retake's own schemas is brought up to this Retake's; any other is the project's.
        if let index = root.entries.firstIndex(where: { $0.key == "$schema" }),
           root.entries[index].value.stringValue.flatMap(SchemaReference.init(url:)) != nil {
            root.entries[index].value = .string(SchemaReference.current("edit").url)
        }

        // Every anchor and element resolves in the new takes, or nothing is written.
        let newText = JSONWriter.fitting(.object(root))
        let reader = JSONReader(file: project.displayPath(url))
        guard let conformed = EditFile.read(newText, with: reader) else {
            throw RetakeError(.failed, reader.problems.map(\.description).joined(separator: "\n"))
        }
        let validator = ProjectValidator(files: files, offline: false)
        var unresolved: [String] = []
        for type in types {
            guard let video = conformed.videos[type] else { continue }
            validator.checkTakes(of: conformed, video, for: type, problem: { path, message in
                unresolved.append("\(conformed.source(of: path, for: type)) (\(type.rawValue)): \(message)")
            }, warning: { path, message in
                unresolved.append("\(conformed.source(of: path, for: type)) (\(type.rawValue)): \(message)")
            }, reported: { _ in false })
        }
        guard unresolved.isEmpty else {
            throw RetakeError(.failed, "In the new takes, nothing was written:\n" + unresolved.joined(separator: "\n"))
        }
        return Result(text: newText, changes: changes)
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
