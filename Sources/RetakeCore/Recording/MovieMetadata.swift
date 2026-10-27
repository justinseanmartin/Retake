import AVFoundation
import Foundation

/// What Retake writes into each movie about how it was made, as QuickTime metadata, which
/// AVFoundation and `ffprobe` read. See docs/cli.md, "Movie metadata".
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
            ("retake.take", String(log.take)),
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
