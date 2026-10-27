import CryptoKit
import Foundation

/// What `retake doctor` decides from what it finds: each check's outcome, the signing it needs, and
/// how the run ends. Finding things out is the command's; deciding is here, so it can be tested.
/// See docs/cli.md, "retake doctor".
public enum Doctor {
    public enum Outcome: String, Sendable {
        case passed, warned, failed, skipped
    }

    /// One check, as `doctor` reports it.
    public struct Check: Equatable, Sendable {
        /// Its name in `--json`: `tools`, `device`, `signing`, `app` or `launch`.
        public var name: String
        public var outcome: Outcome
        public var detail: String
        /// For a failed check, the status it fails with.
        public var status: ExitStatus

        public init(_ name: String, _ outcome: Outcome, _ detail: String, status: ExitStatus = .done) {
            self.name = name
            self.outcome = outcome
            self.detail = detail
            self.status = outcome == .failed && status == .done ? .failed : status
        }

        public static func failed(_ name: String, _ error: RetakeError) -> Check {
            Check(name, .failed, error.message, status: error.status)
        }

        /// A check that needs one that failed.
        public static func skipped(_ name: String, needing needed: String) -> Check {
            Check(name, .skipped, "Needs \(needed), which failed.")
        }
    }

    /// How `doctor` exits: done when nothing failed, otherwise with the first failure's status.
    public static func status(of checks: [Check]) -> ExitStatus {
        checks.first { $0.outcome == .failed }?.status ?? .done
    }

    // MARK: Signing

    /// A signing identity in the keychain, by its certificate's SHA-1, as `security` lists it.
    public struct Identity: Equatable, Sendable {
        public var sha1: String
        public var name: String

        public init(sha1: String, name: String) {
            self.sha1 = sha1
            self.name = name
        }

        /// Whether it signs for development, as running on a device needs.
        public var isDevelopment: Bool { name.hasPrefix("Apple Development:") || name.hasPrefix("iPhone Developer:") }
    }

    /// The identities in `security find-identity -v -p codesigning`'s output, each line
    /// `  1) <SHA-1> "<name>"`.
    public static func identities(fromFindIdentity output: String) -> [Identity] {
        output.split(whereSeparator: \.isNewline).compactMap { line in
            let parts = line.trimmingCharacters(in: .whitespaces).split(separator: " ", maxSplits: 2)
            guard parts.count == 3, parts[0].hasSuffix(")"), parts[1].count == 40, parts[1].allSatisfy(\.isHexDigit),
                  parts[2].hasPrefix("\""), parts[2].hasSuffix("\"") else { return nil }
            return Identity(sha1: parts[1].uppercased(), name: String(parts[2].dropFirst().dropLast()))
        }
    }

    /// What `doctor` needs of a provisioning profile.
    public struct Profile: Equatable, Sendable {
        public var name: String
        /// The app ID without its team: `com.example.notes`, `com.example.*` or `*`.
        public var appID: String
        public var isDevelopment: Bool
        public var devices: [String]
        public var allDevices: Bool
        public var expires: Date
        public var isForIOS: Bool
        /// The SHA-1s of the certificates it signs for.
        public var certificates: [String]

        public init(
            name: String, appID: String, isDevelopment: Bool, devices: [String], allDevices: Bool = false, expires: Date,
            isForIOS: Bool = true, certificates: [String],
        ) {
            self.name = name
            self.appID = appID
            self.isDevelopment = isDevelopment
            self.devices = devices
            self.allDevices = allDevices
            self.expires = expires
            self.isForIOS = isForIOS
            self.certificates = certificates
        }

        /// A profile from its contents, as `security cms -D` decodes them; nil when it names no app ID.
        public init?(_ plist: [String: Any]) {
            let entitlements = plist["Entitlements"] as? [String: Any] ?? [:]
            guard let identifier = entitlements["application-identifier"] as? String, let dot = identifier.firstIndex(of: ".") else { return nil }
            self.init(
                name: plist["Name"] as? String ?? identifier,
                appID: String(identifier[identifier.index(after: dot)...]),
                isDevelopment: entitlements["get-task-allow"] as? Bool ?? false,
                devices: plist["ProvisionedDevices"] as? [String] ?? [],
                allDevices: plist["ProvisionsAllDevices"] as? Bool ?? false,
                expires: plist["ExpirationDate"] as? Date ?? .distantPast,
                isForIOS: (plist["Platform"] as? [String])?.contains("iOS") ?? true,
                certificates: (plist["DeveloperCertificates"] as? [Data] ?? []).map { certificate in
                    Insecure.SHA1.hash(data: certificate).map { String(format: "%02X", $0) }.joined()
                },
            )
        }

        /// Whether its app ID covers `bundleID`: the same, or a wildcard whose prefix it starts with.
        public func covers(_ bundleID: String) -> Bool {
            appID == bundleID || appID == "*" || (appID.hasSuffix(".*") && bundleID.hasPrefix(appID.dropLast()))
        }
    }

    /// The profile that lets `bundleID` run on the device for development, signed by one of
    /// `identities`, the most specific and then the latest to expire; nil with why none does.
    public static func covering(
        _ profiles: [Profile], bundleID: String, udid: String, identities: [Identity], now: Date = Date(),
    ) -> (profile: Profile?, why: String) {
        let signers = Set(identities.filter(\.isDevelopment).map(\.sha1))
        let forApp = profiles.filter { $0.isForIOS && $0.isDevelopment && $0.covers(bundleID) }
        guard !forApp.isEmpty else { return (nil, "No development provisioning profile is for \(bundleID).") }
        let current = forApp.filter { $0.expires > now }
        guard !current.isEmpty else { return (nil, "Every development profile for \(bundleID) has expired.") }
        let withDevice = current.filter { $0.allDevices || $0.devices.contains(udid) }
        guard !withDevice.isEmpty else {
            return (nil, "No development profile for \(bundleID) includes the device, \(udid); it may not be registered on the team.")
        }
        let signed = withDevice.filter { !signers.isDisjoint(with: $0.certificates) }
        guard !signed.isEmpty else {
            return (nil, "No profile for \(bundleID) and the device is for a signing identity in the keychain.")
        }
        let best = signed.max { a, b in
            (a.appID.count, a.expires) < (b.appID.count, b.expires)
        }
        return (best, "")
    }
}
