/// The kind of device a scene is written for and a video is rendered for, asked of the device itself.
/// It picks the scenes a command plays, those naming it among their `devices`, and the folders it
/// writes to, such as `output/takes/<type>/`.
public enum DeviceType: String, CaseIterable, Codable, Sendable {
    case iphone
    case ipad
}

extension DeviceType {
    /// A file's `devices`: device types, at least one, each once.
    static func readList(_ value: JSONValue, at path: JSONPath, _ reader: JSONReader) -> [DeviceType]? {
        guard let devices = reader.array(value, at: path, element: { reader.choice($0, at: $1, as: DeviceType.self) }) else { return nil }
        if case .array(let values) = value, values.isEmpty {
            reader.problem("needs at least one device type: \(DeviceType.allCases.map(\.rawValue).joined(separator: ", "))", at: path)
        }
        var seen = Set<DeviceType>()
        for (index, device) in devices.enumerated() where !seen.insert(device).inserted {
            reader.problem("\"\(device.rawValue)\" is given more than once", at: path.appending(index))
        }
        return devices
    }
}
