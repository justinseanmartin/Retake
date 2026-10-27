import Foundation

/// The devices a command can use: what `devicectl` sees, and the aliases a person has given.
public struct DeviceDirectory: Sendable {
    public var devices: [Device]
    public var aliases: DeviceAliases

    public init(devices: [Device], aliases: DeviceAliases) {
        self.devices = devices
        self.aliases = aliases
    }

    /// The iPhones and iPads connected now by USB, the only ones that can be recorded.
    public var recordable: [Device] { devices.filter(\.isRecordable) }

    /// What a device's name in a command stands for: an alias, a UDID, or a device's name, in that
    /// order, as docs/cli.md, "Choosing a device", gives them.
    public enum Match: Equatable, Sendable {
        case alias(DeviceAlias, connected: Device?)
        case device(Device)
    }

    public func match(_ given: String) -> Match? {
        if let alias = aliases[given] {
            return .alias(alias, connected: devices.first { $0.udid == alias.udid })
        }
        if let device = devices.first(where: { $0.udid == given }) ?? devices.first(where: { $0.name == given }) {
            return .device(device)
        }
        return nil
    }

    /// The device a command uses, connected by USB, from what chose it; otherwise a failure saying
    /// why: misuse (2) for a name that's nothing, an environment problem (3) for a device that isn't
    /// connected by USB, or for none or several connected with nothing chosen.
    public func resolve(_ choice: DeviceChoice?) throws(RetakeError) -> Device {
        guard let choice else {
            if recordable.isEmpty {
                throw RetakeError(.environment, "No iPhone or iPad is connected by USB.")
            }
            throw RetakeError(
                .environment,
                "Several devices are connected; name one with --device or RETAKE_DEVICE:\n"
                    + recordable.map { "  \($0.name) (\($0.udid))" }.joined(separator: "\n"),
            )
        }
        guard let match = match(choice.device) else {
            throw RetakeError(.usage, "\"\(choice.device)\" (\(choice.reason)) isn't an alias, a UDID, or the name of a device devicectl knows.")
        }
        let device: Device?
        let described: String
        switch match {
        case .alias(let alias, let connected):
            device = connected
            described = "\"\(alias.name)\" (\(alias.deviceName))"
        case .device(let found):
            device = found
            described = "\"\(found.name)\""
        }
        guard let device, device.state == .connected else {
            throw RetakeError(.environment, "\(described) isn't connected.")
        }
        guard device.transport == .wired else {
            throw RetakeError(.environment, "\(described) is connected over the network; Retake records only devices connected by USB.")
        }
        guard device.type != nil else {
            throw RetakeError(.environment, "\(described) isn't an iPhone or iPad.")
        }
        return device
    }
}
