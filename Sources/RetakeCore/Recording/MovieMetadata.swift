import AVFoundation
import Foundation

/// What Retake writes into each movie about how it was made, as QuickTime metadata, which
/// AVFoundation and `ffprobe` read. See Documentation/cli.md, "Movie metadata".
public enum MovieMetadata {
    /// A take's fields, from its step log as far as it's known when recording starts: nothing
    /// about its steps, nor whether it failed. Nothing personal: not the device's name, nor its UDID.
    public static func take(_ log: TakeLog) -> [AVMetadataItem] {
        var fields: [(String, String?)] = [
            ("com.apple.quicktime.software", "Retake \(log.retake)"),
            ("com.apple.quicktime.make", "Apple"),
            ("com.apple.quicktime.model", log.device.marketingName),
            ("com.apple.quicktime.creationdate", ISO8601DateFormatter().string(from: log.recordedAt)),
            ("retake.version", log.retake),
            ("retake.scene", log.scene),
            ("retake.set", log.set),
            ("retake.state", log.state.rawValue),
            ("retake.app.bundle-id", log.app.bundleID),
            ("retake.app.version", log.app.version),
            ("retake.app.build", log.app.build),
            ("retake.buttonheist.version", log.buttonHeist.version),
            ("retake.buttonheist.commit", log.buttonHeist.commit),
            ("retake.device.model", log.device.model),
            ("retake.device.type", log.deviceType.rawValue),
            ("retake.device.os", log.device.os),
        ]
        fields.removeAll { $0.1 == nil }
        return fields.map { item($0.0, $0.1!) }
    }

    /// What a video records of how it was made: the Retake that rendered it, its edit and device
    /// type, and each of its takes, with the distinct app builds, devices and Button Heists among
    /// them, in the order the video first shows them. See Documentation/cli.md, "A video's fields".
    public struct Video: Equatable, Sendable {
        public var retake: String
        public var edit: String
        public var type: DeviceType
        public var bundleID: String
        public var renderedAt: Date
        /// Each clip's take, in the order the video plays them, each once. The record names each
        /// by its scene, device type and when it was recorded, which `status` compares with the
        /// scene's take now.
        public var takes: [TakeLog]

        public init(retake: String = RetakeVersion.current.version, edit: String, type: DeviceType, bundleID: String, renderedAt: Date = Date(), takes: [TakeLog]) {
            self.retake = retake
            self.edit = edit
            self.type = type
            self.bundleID = bundleID
            self.renderedAt = renderedAt
            self.takes = takes
        }

        static func distinct(_ values: [JSONValue]) -> [JSONValue] {
            values.reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
        }

        public var appVersions: [JSONValue] {
            Self.distinct(takes.map { TakeLog.object([("version", $0.app.version.map(JSONValue.string)), ("build", $0.app.build.map(JSONValue.string))]) })
        }

        public var devices: [JSONValue] {
            Self.distinct(takes.map { take in
                TakeLog.object([
                    ("model", .string(take.device.model)), ("marketingName", take.device.marketingName.map(JSONValue.string)), ("os", .string(take.device.os)),
                ])
            })
        }

        public var buttonHeistVersions: [JSONValue] {
            Self.distinct(takes.map { TakeLog.object([("version", .string($0.buttonHeist.version)), ("commit", $0.buttonHeist.commit.map(JSONValue.string))]) })
        }

        public var takeRecords: [JSONValue] {
            takes.map { take in
                TakeLog.object([
                    ("scene", .string(take.scene)), ("deviceType", .string(take.deviceType.rawValue)),
                    ("recordedAt", .string(ISO8601DateFormatter().string(from: take.recordedAt))), ("retake", .string(take.retake)),
                    ("app", TakeLog.object([("version", take.app.version.map(JSONValue.string)), ("build", take.app.build.map(JSONValue.string))])),
                    ("device", TakeLog.object([("model", .string(take.device.model)), ("os", .string(take.device.os))])),
                    ("buttonHeist", TakeLog.object([("version", .string(take.buttonHeist.version)), ("commit", take.buttonHeist.commit.map(JSONValue.string))])),
                ])
            }
        }

        /// The whole record as one JSON object, as the `.mp4`'s description holds it.
        public var json: JSONValue {
            .object(JSONObject([
                .init(key: "retake", value: .object(JSONObject([.init(key: "version", value: .string(retake))]))),
                .init(key: "edit", value: .string(edit)),
                .init(key: "deviceType", value: .string(type.rawValue)),
                .init(key: "bundleID", value: .string(bundleID)),
                .init(key: "appVersions", value: .array(appVersions)),
                .init(key: "devices", value: .array(devices)),
                .init(key: "buttonHeistVersions", value: .array(buttonHeistVersions)),
                .init(key: "takes", value: .array(takeRecords)),
            ]))
        }

        /// Whether the takes span more than one app build, device or Button Heist, which `cut` warns of.
        public var mixed: [String] {
            var spans: [String] = []
            if appVersions.count > 1 { spans.append("builds of the app") }
            if devices.count > 1 { spans.append("devices or iOS versions") }
            if buttonHeistVersions.count > 1 { spans.append("Button Heists") }
            return spans
        }
    }

    /// A video's fields, for the ProRes master, as QuickTime metadata.
    public static func video(_ video: Video) -> [AVMetadataItem] {
        [
            ("com.apple.quicktime.software", "Retake \(video.retake)"),
            ("com.apple.quicktime.creationdate", ISO8601DateFormatter().string(from: video.renderedAt)),
            ("retake.version", video.retake),
            ("retake.edit", video.edit),
            ("retake.device.type", video.type.rawValue),
            ("retake.app.bundle-id", video.bundleID),
            ("retake.app.versions", JSONWriter.compact(.array(video.appVersions))),
            ("retake.devices", JSONWriter.compact(.array(video.devices))),
            ("retake.buttonheist.versions", JSONWriter.compact(.array(video.buttonHeistVersions))),
            ("retake.takes", JSONWriter.compact(.array(video.takeRecords))),
        ].map { item($0.0, $0.1) }
    }

    /// A video's fields for an `.mp4`, which keeps only the common identifiers AVFoundation writes
    /// as ISO user data: the software, and the whole record as JSON in the description.
    public static func preview(_ video: Video) -> [AVMetadataItem] {
        func common(_ identifier: AVMetadataIdentifier, _ value: String) -> AVMetadataItem {
            let item = AVMutableMetadataItem()
            item.identifier = identifier
            item.value = value as NSString
            item.dataType = kCMMetadataBaseDataType_UTF8 as String
            return item
        }
        return [
            common(.commonIdentifierSoftware, "Retake \(video.retake)"),
            common(.commonIdentifierDescription, JSONWriter.compact(video.json)),
        ]
    }

    static func item(_ key: String, _ value: String) -> AVMetadataItem {
        let item = AVMutableMetadataItem()
        item.keySpace = .quickTimeMetadata
        item.key = key as NSString
        item.value = value as NSString
        item.dataType = kCMMetadataBaseDataType_UTF8 as String
        return item
    }

    /// The fields in a movie, by key.
    public static func read(_ movie: URL) async throws -> [String: String] {
        var fields: [String: String] = [:]
        for item in try await AVURLAsset(url: movie).loadMetadata(for: .quickTimeMetadata) {
            if let key = item.key as? String, let value = try await item.load(.stringValue) { fields[key] = value }
        }
        return fields
    }
}
