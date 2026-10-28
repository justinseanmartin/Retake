import Foundation

/// The device a command uses, and what chose it; see Documentation/cli.md, "Choosing a device".
public struct DeviceChoice: Equatable, Sendable {
    public enum Source: Equatable, Sendable {
        /// `--device`.
        case commandLine
        /// An environment variable, `RETAKE_DEVICE`.
        case environment(variable: String)
        /// The configuration file's `device`.
        case configuration(file: URL)
        /// Nothing named one, and only one is connected by USB.
        case onlyConnected
    }

    /// An alias, a UDID or a device's name, as given; the one connected device's UDID for `onlyConnected`.
    public var device: String
    public var source: Source

    public init(device: String, source: Source) {
        self.device = device
        self.source = source
    }

    /// The first that applies: what the command line or the environment names, then the configuration
    /// file's device, then the one device connected. Nil when none applies: nothing names one, and
    /// none or several are connected.
    public static func choose(
        named: (device: String, variable: String?)?,
        configuration: (device: String, file: URL)?,
        connected: [String],
    ) -> DeviceChoice? {
        if let named {
            let source: Source = named.variable.map { .environment(variable: $0) } ?? .commandLine
            return DeviceChoice(device: named.device, source: source)
        }
        if let configuration {
            return DeviceChoice(device: configuration.device, source: .configuration(file: configuration.file))
        }
        if connected.count == 1 {
            return DeviceChoice(device: connected[0], source: .onlyConnected)
        }
        return nil
    }

    /// What chose it, for `retake devices`: `from RETAKE_DEVICE`, `from retake.json`.
    public var reason: String {
        switch source {
        case .commandLine: "from --device"
        case .environment(let variable): "from \(variable)"
        case .configuration(let file): "from \(file.lastPathComponent)"
        case .onlyConnected: "the only one connected"
        }
    }

    /// After `devices add` names a device, a note when the environment still names another, so the
    /// commands that follow in the same shell won't use the device just named. Nil when the variable
    /// isn't set, or names this device by its new alias, its UDID or its name.
    public static func noteAfterNaming(
        alias: String,
        udid: String,
        name: String,
        environmentDevice: (device: String, variable: String)?,
    ) -> String? {
        guard let environmentDevice, ![alias, udid, name].contains(environmentDevice.device) else { return nil }
        return "Commands in this shell still use \"\(environmentDevice.device)\" (\(environmentDevice.variable)); "
            + "pass --device \(alias) to use this one."
    }
}
