import Foundation

/// A device `devicectl` knows, as Retake needs it: who it is, what it is, and how it's connected.
public struct Device: Equatable, Sendable {
    public var udid: String
    /// Its name, as `devicectl` reports it: `Sam’s iPad (2)`, curly apostrophe and all.
    public var name: String
    /// `iphone` or `ipad`; nil for a device Retake can't record, such as a watch.
    public var type: DeviceType?
    /// Its hardware identifier, such as `iPad13,4`.
    public var model: String?
    /// Its marketing name, such as `iPad Pro (11-inch) (3rd generation)`.
    public var marketingName: String?
    public var osVersion: String?
    public var osBuild: String?
    public var transport: Transport
    public var state: State
    public var isPaired: Bool
    /// Its address on the CoreDevice tunnel, for The Button Heist's client to reach the app over.
    public var tunnelAddress: String?

    public enum Transport: String, Sendable {
        case wired
        case network
        case unknown
    }

    public enum State: String, Sendable {
        case connected
        case disconnected
        case unavailable
    }

    public init(
        udid: String,
        name: String,
        type: DeviceType?,
        model: String? = nil,
        marketingName: String? = nil,
        osVersion: String? = nil,
        osBuild: String? = nil,
        transport: Transport = .wired,
        state: State = .connected,
        isPaired: Bool = true,
        tunnelAddress: String? = nil,
    ) {
        self.udid = udid
        self.name = name
        self.type = type
        self.model = model
        self.marketingName = marketingName
        self.osVersion = osVersion
        self.osBuild = osBuild
        self.transport = transport
        self.state = state
        self.isPaired = isPaired
        self.tunnelAddress = tunnelAddress
    }

    /// Connected now, by USB: the only way a device's screen can be recorded.
    public var isConnectedByUSB: Bool { state == .connected && transport == .wired }

    /// An iPhone or iPad Retake could record, connected by USB.
    public var isRecordable: Bool { isConnectedByUSB && type != nil }

    /// The iOS version and build, as metadata records it: `26.6.2 (23G90)`.
    public var osDescription: String? {
        guard let osVersion else { return nil }
        return osBuild.map { "\(osVersion) (\($0))" } ?? osVersion
    }
}

/// What Retake asks of the devices attached to the Mac, behind a seam so commands can be tested
/// without one.
public protocol DeviceControl: Sendable {
    /// The physical devices `devicectl` knows, connected or not; simulators are left out.
    func devices() throws(RetakeError) -> [Device]
}

/// `xcrun devicectl`, reading its JSON output.
public struct Devicectl: DeviceControl {
    public init() {}

    public func devices() throws(RetakeError) -> [Device] {
        let data = try run(["list", "devices"])
        do {
            return try DeviceList.parse(data)
        } catch {
            throw RetakeError(.environment, "devicectl's list of devices couldn't be read: \(error.message)")
        }
    }

    /// The device's screen in points, portrait: its primary display's native size over its point
    /// scale, as `devicectl device info displays` reports them; nil when it can't say.
    public func screenPoints(of device: Device) -> CGSize? {
        (try? run(["device", "info", "displays", "--device", device.udid])).flatMap(Self.screenPoints(fromDisplays:))
    }

    public static func screenPoints(fromDisplays data: Data) -> CGSize? {
        guard let value = try? JSONParser.parse(String(decoding: data, as: UTF8.self)),
              case .array(let displays)? = value[path: "result", "displays"] else { return nil }
        let primary = displays.first { $0[path: "primary"] == .bool(true) } ?? displays.first
        guard case .array(let size)? = primary?[path: "nativeSize"], size.count == 2,
              case .number(let first) = size[0], case .number(let second) = size[1],
              case .number(let scale)? = primary?[path: "pointScale"], scale > 0 else { return nil }
        return CGSize(width: min(first, second) / scale, height: max(first, second) / scale)
    }

    /// Runs `devicectl` with `arguments`, returning the JSON it writes.
    public func run(_ arguments: [String]) throws(RetakeError) -> Data {
        let output = FileManager.default.temporaryDirectory.appending(path: "retake-devicectl-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: output) }
        let result: Subprocess.Result
        do {
            result = try Subprocess.xcrun(["devicectl"] + arguments + ["--json-output", output.path, "--quiet"])
        } catch {
            throw RetakeError(.environment, "Couldn't run devicectl, which comes with Xcode: \(error.localizedDescription)")
        }
        guard result.status == 0, let data = FileManager.default.contents(atPath: output.path) else {
            let detail = result.errorText.trimmingCharacters(in: .whitespacesAndNewlines)
            throw RetakeError(.environment, "devicectl \(arguments.joined(separator: " ")) failed\(detail.isEmpty ? "." : ": \(detail)")")
        }
        return data
    }
}

/// Reads `devicectl list devices`' JSON: its `properties`, or the older fields it still writes
/// beside them and marks deprecated.
public enum DeviceList {
    public struct Failure: Error, Sendable {
        public var message: String
    }

    public static func parse(_ data: Data) throws(Failure) -> [Device] {
        let value: JSONValue
        do {
            value = try JSONParser.parse(String(decoding: data, as: UTF8.self))
        } catch {
            throw Failure(message: error.description)
        }
        guard case .array(let entries)? = value[path: "result", "devices"] else {
            throw Failure(message: "it has no result.devices")
        }
        return entries.compactMap(device)
    }

    static func device(_ entry: JSONValue) -> Device? {
        func string(_ new: [String], _ old: [String]) -> String? {
            entry[path: new].flatMap(\.stringValue) ?? entry[path: old].flatMap(\.stringValue)
        }
        guard string(["properties", "hardware", "reality"], ["hardwareProperties", "reality"]) != "simulated",
              let udid = string(["properties", "hardware", "udid"], ["hardwareProperties", "udid"]) else { return nil }
        let name = string(["properties", "state", "name"], ["deviceProperties", "name"]) ?? udid
        let type: DeviceType? = switch string(["properties", "hardware", "deviceType"], ["hardwareProperties", "deviceType"]) {
        case "iPhone": .iphone
        case "iPad": .ipad
        default: nil
        }
        let transport: Device.Transport = switch string(["properties", "connection", "transportType"], ["connectionProperties", "transportType"]) {
        case "wired": .wired
        case "localNetwork", "network": .network
        default: .unknown
        }
        let state: Device.State = switch string(["properties", "connection", "state"], ["connectionProperties", "tunnelState"]) {
        case "connected": .connected
        case "disconnected": .disconnected
        default: .unavailable
        }
        return Device(
            udid: udid,
            name: name,
            type: type,
            model: string(["properties", "hardware", "productType"], ["hardwareProperties", "productType"]),
            marketingName: string(["properties", "hardware", "marketingName"], ["hardwareProperties", "marketingName"]),
            osVersion: string(["properties", "software", "osVersionNumber", "stringValue"], ["deviceProperties", "osVersionNumber"]),
            osBuild: string(["properties", "software", "osBuildVersions", "buildVersion", "name"], ["deviceProperties", "osBuildUpdate"]),
            transport: transport,
            state: state,
            isPaired: string(["properties", "connection", "pairingState"], ["connectionProperties", "pairingState"]) == "paired",
            tunnelAddress: string(["properties", "connection", "tunnelIPAddressString"], ["connectionProperties", "tunnelIPAddress"]),
        )
    }
}

extension JSONValue {
    /// The value at a path of object keys, if every key is there.
    public subscript(path keys: [String]) -> JSONValue? {
        var current: JSONValue? = self
        for key in keys {
            guard case .object(let object)? = current else { return nil }
            current = object[key]
        }
        return current
    }

    public subscript(path keys: String...) -> JSONValue? { self[path: keys] }

    public var stringValue: String? {
        if case .string(let string) = self { string } else { nil }
    }
}
