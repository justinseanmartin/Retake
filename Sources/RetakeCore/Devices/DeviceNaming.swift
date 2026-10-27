import Foundation

/// What `retake devices add` does: names a connected device, recording both its identities.
public enum DeviceNaming {
    /// How long to wait for a device's screen to be offered for capture.
    public static let captureTimeout = 5.0

    /// The alias `name` for `given` (a UDID or a device's name), or with nothing given, the one
    /// iPhone or iPad connected by USB, or `ask`'s choice among several.
    public static func alias(
        _ name: String,
        for given: String?,
        in directory: DeviceDirectory,
        finder: CaptureDeviceFinder,
        ask: ([Device]) -> Device? = { _ in nil },
    ) throws(RetakeError) -> DeviceAlias {
        guard DeviceAliases.isValidName(name) else {
            throw RetakeError(.usage, "\"\(name)\" can't be an alias: use letters, digits, \"-\" and \"_\", such as ipad or test-iphone.")
        }
        if let existing = directory.aliases[name] {
            throw RetakeError(.usage, "\"\(name)\" already names \(existing.deviceName); `retake devices remove \(name)` first.")
        }

        let device: Device
        if let given {
            switch directory.match(given) {
            case .alias(let alias, _)?:
                throw RetakeError(.usage, "\"\(given)\" is an alias already, for \(alias.deviceName); give a device's UDID or name.")
            case .device(let found)?:
                device = found
            case nil:
                throw RetakeError(.usage, "\"\(given)\" isn't the UDID or name of a device devicectl knows.")
            }
            guard device.isRecordable else {
                let why = device.type == nil ? "isn't an iPhone or iPad" : device.state != .connected ? "isn't connected" : "isn't connected by USB"
                throw RetakeError(.environment, "\(device.name) \(why); only an iPhone or iPad connected by USB can be named and recorded.")
            }
        } else {
            switch directory.recordable.count {
            case 0:
                throw RetakeError(.environment, "No iPhone or iPad is connected by USB.")
            case 1:
                device = directory.recordable[0]
            default:
                guard let chosen = ask(directory.recordable) else {
                    throw RetakeError(
                        .usage,
                        "Several devices are connected; say which to name, by UDID or name:\n"
                            + directory.recordable.map { "  \($0.name) (\($0.udid))" }.joined(separator: "\n"),
                    )
                }
                device = chosen
            }
        }

        let screens = finder.captureDevices(waitingFor: device.name, timeout: captureTimeout).filter { $0.name == device.name }
        guard let screen = screens.first else {
            throw RetakeError(
                .environment,
                "\(device.name) isn't offered for screen capture. Unlock it, and trust this Mac if it asks. If another app "
                    + "was recording it moments ago, macOS may still be releasing it: wait ten seconds and try again.",
            )
        }
        if screens.count > 1 {
            throw RetakeError(
                .environment,
                "Several screens are offered for capture as \"\(device.name)\"; rename one of the devices so they can be told apart.",
            )
        }
        return DeviceAlias(name: name, udid: device.udid, captureID: screen.uniqueID, deviceName: device.name, type: device.type, model: device.model)
    }

    /// The devices `init` offers to name: those connected by USB that no alias names yet.
    public static func unnamed(in directory: DeviceDirectory) -> [Device] {
        directory.recordable.filter { device in !directory.aliases.aliases.contains { $0.udid == device.udid } }
    }

    /// The alias `init` suggests for `device`: its type, `ipad`, or `ipad2` and on when that's taken.
    public static func suggestedName(for device: Device, besides aliases: DeviceAliases) -> String? {
        guard let type = device.type?.rawValue else { return nil }
        if aliases[type] == nil { return type }
        var number = 2
        while aliases["\(type)\(number)"] != nil { number += 1 }
        return "\(type)\(number)"
    }

    /// The devices `init` offers to name once asked for another: unnamed ones connected since,
    /// leaving out those it has offered already, named or skipped.
    public static func newlyConnected(in directory: DeviceDirectory, besides offered: Set<String>) -> [Device] {
        unnamed(in: directory).filter { !offered.contains($0.udid) }
    }
}
