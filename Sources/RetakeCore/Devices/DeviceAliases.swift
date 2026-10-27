import Foundation

/// A name a person gives one of their devices, standing for both its identities: its UDID, for
/// installing and launching, and its screen-capture device, for recording. Kept for every project in
/// `~/Library/Caches/retake/devices.json`, never in a repository, since devices belong to people.
/// See README.md, "Devices".
public struct DeviceAlias: Equatable, Sendable {
    public var name: String
    public var udid: String
    /// The screen-capture device's unique ID, which isn't the UDID.
    public var captureID: String
    /// What the device was when it was named, to show while it isn't connected.
    public var deviceName: String
    public var type: DeviceType?
    public var model: String?

    public init(name: String, udid: String, captureID: String, deviceName: String, type: DeviceType?, model: String?) {
        self.name = name
        self.udid = udid
        self.captureID = captureID
        self.deviceName = deviceName
        self.type = type
        self.model = model
    }
}

/// The aliases file.
public struct DeviceAliases: Equatable, Sendable {
    public var aliases: [DeviceAlias]

    public init(_ aliases: [DeviceAlias] = []) {
        self.aliases = aliases
    }

    public subscript(name: String) -> DeviceAlias? {
        aliases.first { $0.name == name }
    }

    /// `~/Library/Caches/retake/devices.json`.
    public static var defaultFile: URL { RetakeCache.root.appending(path: "devices.json") }

    /// The aliases in `file`, none when it doesn't exist yet.
    public static func load(from file: URL) throws(RetakeError) -> DeviceAliases {
        guard let data = FileManager.default.contents(atPath: file.path) else { return DeviceAliases() }
        let reader = JSONReader(file: file.path)
        guard let value = reader.parse(String(decoding: data, as: UTF8.self)), var root = reader.object(value, at: .root) else {
            throw RetakeError(.failed, reader.problems.map(\.description).joined(separator: "\n"))
        }
        let entries = root.optional("aliases") { value, path in
            reader.dictionary(value, at: path) { value, path -> DeviceAlias? in
                guard case .key(let name)? = path.components.last, var object = reader.object(value, at: path) else { return nil }
                defer { object.finish() }
                let udid = object.required("udid", reader.nonEmptyString)
                let capture = object.required("captureID", reader.nonEmptyString)
                let deviceName = object.optional("deviceName", reader.string)
                let type = object.optional("type") { reader.choice($0, at: $1, as: DeviceType.self) }
                let model = object.optional("model", reader.string)
                guard let udid, let capture else { return nil }
                return DeviceAlias(name: name, udid: udid, captureID: capture, deviceName: deviceName ?? udid, type: type, model: model)
            }?.map(\.value)
        }
        root.finish()
        guard reader.problems.isEmpty else {
            throw RetakeError(.failed, reader.problems.map(\.description).joined(separator: "\n"))
        }
        return DeviceAliases(entries ?? [])
    }

    public func save(to file: URL) throws(RetakeError) {
        let entries = aliases.map { alias in
            var fields: [JSONObject.Entry] = [
                .init(key: "udid", value: .string(alias.udid)),
                .init(key: "captureID", value: .string(alias.captureID)),
                .init(key: "deviceName", value: .string(alias.deviceName)),
            ]
            if let type = alias.type { fields.append(.init(key: "type", value: .string(type.rawValue))) }
            if let model = alias.model { fields.append(.init(key: "model", value: .string(model))) }
            return JSONObject.Entry(key: alias.name, value: .object(JSONObject(fields)))
        }
        let text = JSONWriter.write(.object(JSONObject([.init(key: "aliases", value: .object(JSONObject(entries)))])))
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: file, options: .atomic)
        } catch {
            throw RetakeError(.failed, "Couldn't save device aliases to \(file.path): \(error.localizedDescription)")
        }
    }

    /// Letters, digits, `-` and `_`, so an alias is never mistaken for a device's name or UDID.
    public static func isValidName(_ name: String) -> Bool {
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
        return !name.isEmpty && name.allSatisfy(allowed.contains)
    }
}
