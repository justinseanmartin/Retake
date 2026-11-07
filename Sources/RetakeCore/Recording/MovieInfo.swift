import AVFoundation
import Foundation

/// What `retake info` reads back out of a movie Retake wrote: a take's fields, or a video's record,
/// from a master's fields or an `.mp4`'s description. See Documentation/cli.md, "Movie metadata".
public enum MovieInfo: Equatable, Sendable {
    /// A take's fields, laid out as `fields(take:)` does.
    case take(JSONValue)
    /// A video's record, laid out as the `.mp4`'s description holds it.
    case video(JSONValue)

    public var isTake: Bool {
        if case .take = self { true } else { false }
    }

    public var json: JSONValue {
        switch self {
        case .take(let record), .video(let record): record
        }
    }

    /// What Retake wrote into `movie`. Fails (1) for a movie that can't be read, or that Retake
    /// didn't write.
    public static func read(_ movie: URL) async throws(RetakeError) -> MovieInfo {
        guard FileManager.default.fileExists(atPath: movie.path) else {
            throw RetakeError(.failed, "There's no \(movie.lastPathComponent) at \(movie.deletingLastPathComponent().path).")
        }
        var fields: [String: String] = [:]
        var description: String?
        do {
            let asset = AVURLAsset(url: movie)
            for item in try await asset.load(.metadata) {
                guard let value = try await item.load(.stringValue) else { continue }
                if item.keySpace == .quickTimeMetadata, let key = item.key as? String {
                    fields[key] = value
                } else if item.commonKey == .commonKeyDescription {
                    description = value
                }
            }
        } catch {
            throw RetakeError(.failed, "Couldn't read \(movie.lastPathComponent): \(error.localizedDescription)")
        }
        if let info = info(fields: fields, description: description) { return info }
        throw RetakeError(.failed, "\(movie.lastPathComponent) wasn't written by Retake: it has none of Retake's metadata.")
    }

    /// The take or video the fields and description say, or nil when they aren't Retake's.
    static func info(fields: [String: String], description: String?) -> MovieInfo? {
        if fields["retake.scene"] != nil { return .take(take(fields)) }
        if fields["retake.edit"] != nil { return .video(video(fields)) }
        if let description, case .object(let record)? = try? JSONParser.parse(description),
           record["edit"] != nil, record["retake"] != nil {
            return .video(.object(record))
        }
        return nil
    }

    /// A take's fields as one object, its keys as a take's step log names them.
    static func take(_ fields: [String: String]) -> JSONValue {
        func string(_ key: String) -> JSONValue? { fields[key].map(JSONValue.string) }
        return TakeLog.object([
            ("retake", TakeLog.object([("version", string("retake.version"))])),
            ("scene", string("retake.scene")),
            ("deviceType", string("retake.device.type")),
            ("set", string("retake.set")),
            ("state", string("retake.state")),
            ("recordedAt", string("com.apple.quicktime.creationdate")),
            ("bundleID", string("retake.app.bundle-id")),
            ("app", TakeLog.object([("version", string("retake.app.version")), ("build", string("retake.app.build"))])),
            ("device", TakeLog.object([
                ("model", string("retake.device.model")), ("marketingName", string("com.apple.quicktime.model")), ("os", string("retake.device.os")),
            ])),
            ("buttonHeist", TakeLog.object([("version", string("retake.buttonheist.version")), ("commit", string("retake.buttonheist.commit"))])),
        ])
    }

    /// A master's fields as the `.mp4`'s description holds the same record.
    static func video(_ fields: [String: String]) -> JSONValue {
        func list(_ key: String) -> JSONValue { fields[key].flatMap { try? JSONParser.parse($0) } ?? .array([]) }
        return TakeLog.object([
            ("retake", TakeLog.object([("version", fields["retake.version"].map(JSONValue.string))])),
            ("edit", fields["retake.edit"].map(JSONValue.string)),
            ("deviceType", fields["retake.device.type"].map(JSONValue.string)),
            ("bundleID", fields["retake.app.bundle-id"].map(JSONValue.string)),
            ("appVersions", list("retake.app.versions")),
            ("devices", list("retake.devices")),
            ("buttonHeistVersions", list("retake.buttonheist.versions")),
            ("takes", list("retake.takes")),
        ])
    }

    /// What a video's takes span more than one of, as `cut` warns of it.
    public var mixed: [String] {
        guard case .video(let record) = self else { return [] }
        func count(_ key: String) -> Int {
            if case .array(let values)? = record[path: key] { values.count } else { 0 }
        }
        var spans: [String] = []
        if count("appVersions") > 1 { spans.append("builds of the app") }
        if count("devices") > 1 { spans.append("devices or iOS versions") }
        if count("buttonHeistVersions") > 1 { spans.append("Button Heists") }
        return spans
    }

    /// What `info` prints for people: a heading, then a labelled line for each part of the record.
    public var lines: [String] {
        let record = json
        func string(_ keys: String...) -> String? { record[path: keys]?.stringValue }
        func app(_ value: JSONValue?) -> String {
            [value?[path: "version"]?.stringValue, value?[path: "build"]?.stringValue.map { "(\($0))" }].compactMap(\.self).joined(separator: " ")
        }
        func device(_ value: JSONValue?) -> String {
            let model = value?[path: "model"]?.stringValue ?? "?"
            let name = value?[path: "marketingName"]?.stringValue.map { "\($0) (\(model))" } ?? model
            return "\(name), iOS \(value?[path: "os"]?.stringValue ?? "?")"
        }
        func buttonHeist(_ value: JSONValue?) -> String {
            let version = value?[path: "version"]?.stringValue ?? "?"
            return value?[path: "commit"]?.stringValue.map { "\(version), from \($0)" } ?? version
        }
        func values(_ key: String) -> [JSONValue] {
            if case .array(let values)? = record[path: key] { values } else { [] }
        }
        func row(_ label: String, _ value: String) -> String {
            "  " + label.padding(toLength: 13, withPad: " ", startingAt: 0) + value
        }

        switch self {
        case .take:
            var lines = ["Take of \(string("scene") ?? "?"), for \(string("deviceType") ?? "?")"]
            if let recorded = string("recordedAt") { lines.append(row("Recorded", recorded)) }
            lines.append(row("Set", "\(string("set") ?? "?") (\(string("state") ?? "?"))"))
            lines.append(row("App", [string("bundleID"), app(record[path: "app"])].compactMap(\.self).filter { !$0.isEmpty }.joined(separator: " ")))
            lines.append(row("Device", device(record[path: "device"])))
            lines.append(row("Button Heist", buttonHeist(record[path: "buttonHeist"])))
            lines.append(row("Retake", string("retake", "version") ?? "?"))
            return lines
        case .video:
            var lines = ["\(string("edit") ?? "?"), for \(string("deviceType") ?? "?")"]
            let apps = values("appVersions").map(app).joined(separator: ", ")
            lines.append(row("App", [string("bundleID"), apps].compactMap(\.self).filter { !$0.isEmpty }.joined(separator: " ")))
            lines.append(row("Devices", values("devices").map(device).joined(separator: "; ")))
            lines.append(row("Button Heist", values("buttonHeistVersions").map(buttonHeist).joined(separator: ", ")))
            let takes = values("takes")
            // A take by its scene and when it was recorded; a video cut when takes were numbered
            // names it by number instead.
            func name(_ take: JSONValue) -> String {
                let when = take[path: "recordedAt"]?.stringValue ?? take[path: "take"].map { "take \(JSONWriter.compact($0))" }
                return "\(take[path: "scene"]?.stringValue ?? "?")\(when.map { " (\($0))" } ?? "")"
            }
            if mixed.isEmpty {
                lines.append(row("Takes", takes.map(name).joined(separator: ", ")))
            } else {
                for (index, take) in takes.enumerated() {
                    lines.append(row(index == 0 ? "Takes" : "", "\(name(take)): \(app(take[path: "app"])), \(device(take[path: "device"])), The Button Heist \(buttonHeist(take[path: "buttonHeist"]))"))
                }
            }
            lines.append(row("Retake", string("retake", "version") ?? "?"))
            if !mixed.isEmpty { lines.append("  Its takes span more than one of: \(mixed.joined(separator: ", ")).") }
            return lines
        }
    }
}
