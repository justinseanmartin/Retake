import CryptoKit
import Foundation

/// What an app is signed with, and signing what `embed` adds with the same.
public enum Signing {
    /// The identity an app was signed with: its leaf certificate's SHA-1, which `codesign -s`
    /// takes; nil for an app that isn't signed.
    public static func identity(of app: URL) -> String? {
        let prefix = FileManager.default.temporaryDirectory.appending(path: "retake-cert-\(UUID().uuidString)-").path
        defer {
            for index in 0..<4 { try? FileManager.default.removeItem(atPath: prefix + String(index)) }
        }
        guard let result = try? Subprocess.run("/usr/bin/codesign", ["-d", "--extract-certificates=\(prefix)", app.path]),
              result.status == 0, let leaf = FileManager.default.contents(atPath: prefix + "0") else { return nil }
        return Insecure.SHA1.hash(data: leaf).map { String(format: "%02X", $0) }.joined()
    }

    /// The entitlements an app was signed with, nil for an app that isn't signed.
    public static func entitlements(of app: URL) -> [String: Any]? {
        guard let result = try? Subprocess.run("/usr/bin/codesign", ["-d", "--entitlements", "-", "--xml", app.path]),
              result.status == 0, !result.output.isEmpty else { return nil }
        return (try? PropertyListSerialization.propertyList(from: result.output, format: nil)) as? [String: Any]
    }

    /// A provisioning profile's contents, from its signed envelope.
    public static func profile(at url: URL) throws(RetakeError) -> [String: Any] {
        guard let result = try? Subprocess.run("/usr/bin/security", ["cms", "-D", "-i", url.path]), result.status == 0,
              let profile = (try? PropertyListSerialization.propertyList(from: result.output, format: nil)) as? [String: Any] else {
            throw RetakeError(.environment, "\(url.path) isn't a provisioning profile that can be read.")
        }
        return profile
    }

    /// The entitlements to sign an app that has none with, from a development profile: its app ID
    /// for the bundle ID, its team, `get-task-allow`, and the app's own keychain group.
    public static func entitlements(fromProfile profile: [String: Any], bundleID: String) throws(RetakeError) -> [String: Any] {
        guard let granted = profile["Entitlements"] as? [String: Any],
              let team = granted["com.apple.developer.team-identifier"] as? String,
              let appID = granted["application-identifier"] as? String else {
            throw RetakeError(.environment, "The provisioning profile names no team or app ID.")
        }
        let wanted = "\(team).\(bundleID)"
        guard appID == wanted || (appID.hasSuffix("*") && wanted.hasPrefix(String(appID.dropLast()))) else {
            throw RetakeError(.environment, "The provisioning profile is for \(appID), which doesn't cover \(bundleID).")
        }
        guard granted["get-task-allow"] as? Bool == true else {
            throw RetakeError(.environment, "The provisioning profile isn't for development (no get-task-allow), so Retake can't launch an app signed with it.")
        }
        return [
            "application-identifier": wanted,
            "com.apple.developer.team-identifier": team,
            "get-task-allow": true,
            "keychain-access-groups": [wanted],
        ]
    }

    /// Whether entitlements are a development build's, which a debugger and Retake can launch.
    public static func isDevelopment(_ entitlements: [String: Any]) -> Bool {
        entitlements["get-task-allow"] as? Bool == true
    }

    /// Signs `item` with `identity`, and for the app, `entitlements`.
    public static func sign(_ item: URL, identity: String, entitlements: [String: Any]? = nil) throws(RetakeError) {
        var arguments = ["-f", "-s", identity]
        var file: URL?
        if let entitlements {
            let url = FileManager.default.temporaryDirectory.appending(path: "retake-entitlements-\(UUID().uuidString).plist")
            guard let data = try? PropertyListSerialization.data(fromPropertyList: entitlements, format: .xml, options: 0),
                  (try? data.write(to: url)) != nil else {
                throw RetakeError(.failed, "Couldn't write the entitlements to sign \(item.lastPathComponent) with.")
            }
            file = url
            arguments += ["--entitlements", url.path, "--generate-entitlement-der"]
        }
        defer { if let file { try? FileManager.default.removeItem(at: file) } }
        let result: Subprocess.Result
        do {
            result = try Subprocess.run("/usr/bin/codesign", arguments + [item.path])
        } catch {
            throw RetakeError(.environment, "Couldn't run codesign, which comes with Xcode: \(error.localizedDescription)")
        }
        guard result.status == 0 else {
            throw RetakeError(.environment, "codesign couldn't sign \(item.lastPathComponent) with \(identity): \(result.errorText.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
    }

    /// That the app's signature, and everything it seals, is valid.
    public static func verify(_ app: URL) throws(RetakeError) {
        guard let result = try? Subprocess.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path]), result.status == 0 else {
            throw RetakeError(.failed, "The re-signed app doesn't verify: codesign --verify --deep --strict \(app.path)")
        }
    }
}
