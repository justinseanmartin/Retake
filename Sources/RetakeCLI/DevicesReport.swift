import Foundation
import RetakeCore

extension DeviceDirectory {
    /// The devices devicectl sees now, and this person's aliases.
    static func current() throws(RetakeError) -> DeviceDirectory {
        DeviceDirectory(devices: try Devicectl().devices(), aliases: try DeviceAliases.load(from: DeviceAliases.defaultFile()))
    }
}

/// `retake devices --json`: the connected devices, the aliases, and which device commands would use.
struct DevicesReport {
    let directory: DeviceDirectory
    let shown: [Device]
    let choice: DeviceChoice?

    var json: JSONValue {
        func optional(_ value: String?) -> JSONValue { value.map(JSONValue.string) ?? .null }
        let devices = shown.map { device in
            JSONValue.object(JSONObject([
                .init(key: "name", value: .string(device.name)),
                .init(key: "udid", value: .string(device.udid)),
                .init(key: "type", value: optional(device.type?.rawValue)),
                .init(key: "model", value: optional(device.model)),
                .init(key: "marketingName", value: optional(device.marketingName)),
                .init(key: "os", value: optional(device.osDescription)),
                .init(key: "wired", value: .bool(device.transport == .wired)),
            ]))
        }
        let aliases = directory.aliases.aliases.map { alias in
            JSONValue.object(JSONObject([
                .init(key: "alias", value: .string(alias.name)),
                .init(key: "udid", value: .string(alias.udid)),
                .init(key: "deviceName", value: .string(alias.deviceName)),
                .init(key: "type", value: optional(alias.type?.rawValue)),
                .init(key: "connected", value: .bool(directory.devices.contains { $0.udid == alias.udid && $0.isConnectedByUSB })),
            ]))
        }
        let uses: JSONValue = choice.map { choice in
            .object(JSONObject([
                .init(key: "device", value: .string(choice.device)),
                .init(key: "reason", value: .string(choice.reason)),
            ]))
        } ?? .null
        return .object(JSONObject([
            .init(key: "devices", value: .array(devices)),
            .init(key: "aliases", value: .array(aliases)),
            .init(key: "uses", value: uses),
        ]))
    }
}
