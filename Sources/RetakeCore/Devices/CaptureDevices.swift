import AVFoundation
import CoreMediaIO
import Foundation

/// A device's screen, as the Mac offers it for capture: only devices connected by USB are.
public struct CaptureDevice: Equatable, Sendable {
    /// The device's name, as `devicectl` reports it too.
    public var name: String
    /// AVFoundation's unique ID for it, which isn't the device's UDID.
    public var uniqueID: String

    public init(name: String, uniqueID: String) {
        self.name = name
        self.uniqueID = uniqueID
    }
}

/// Finding screen-capture devices, behind a seam so commands can be tested without one.
public protocol CaptureDeviceFinder: Sendable {
    /// The screens offered for capture, waiting up to `timeout` seconds for one named `name`, when
    /// given, to appear; they appear a moment after capture devices are allowed.
    func captureDevices(waitingFor name: String?, timeout: Double) -> [CaptureDevice]
}

/// AVFoundation's external capture devices, after asking CoreMediaIO to offer iOS screens.
public struct ScreenCaptureDevices: CaptureDeviceFinder {
    public init() {}

    public func captureDevices(waitingFor name: String?, timeout: Double) -> [CaptureDevice] {
        CaptureRelease.waitUntilReleased()
        Self.allowScreenCaptureDevices()
        CaptureRelease.markReleaseAtExit()
        let deadline = Date().addingTimeInterval(timeout)
        var devices: [CaptureDevice] = []
        repeat {
            devices = AVCaptureDevice.DiscoverySession(deviceTypes: [.external], mediaType: .muxed, position: .unspecified)
                .devices.map { CaptureDevice(name: $0.localizedName, uniqueID: $0.uniqueID) }
            if let name, devices.contains(where: { $0.name == name }) { return devices }
            if name == nil, !devices.isEmpty, Date().addingTimeInterval(timeout / 2) > deadline { return devices }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        } while Date() < deadline
        return devices
    }

    /// iOS devices' screens are offered as capture devices only once this is set, per process.
    public static func allowScreenCaptureDevices() {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyAllowScreenCaptureDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain),
        )
        var allow: UInt32 = 1
        CMIOObjectSetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &allow)
    }
}

/// macOS takes some seconds to release iOS screens after a process that allowed them exits, and a
/// process that asks for them in that time is never offered them, however long it waits (5 seconds
/// after was too soon, 8 seconds enough, on macOS 26). So each Retake that uses them notes when it
/// exits, and the next waits out the rest of that time before asking.
public enum CaptureRelease {
    /// How long after a process exits its screens are released.
    public static let releaseTime = 8.0

    static var marker: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appending(path: "retake/screen-capture-released")
    }

    /// Waits until `releaseTime` has passed since a Retake that used the screens exited.
    static func waitUntilReleased() {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: marker.path),
              let released = attributes[.modificationDate] as? Date else { return }
        let remaining = released.addingTimeInterval(releaseTime).timeIntervalSinceNow
        if remaining > 0, remaining <= releaseTime { Thread.sleep(forTimeInterval: remaining) }
    }

    /// Notes when this process exits, for the next to wait from.
    static func markReleaseAtExit() {
        guard !registered.exchange(true) else { return }
        atexit {
            let marker = CaptureRelease.marker
            try? FileManager.default.createDirectory(at: marker.deletingLastPathComponent(), withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: marker.path, contents: nil)
            try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: marker.path)
        }
    }

    private static let registered = AtomicFlag()
}

/// A flag set once, from any thread.
final class AtomicFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    /// Sets the flag, returning what it was.
    func exchange(_ newValue: Bool) -> Bool {
        lock.withLock {
            defer { value = newValue }
            return value
        }
    }
}
