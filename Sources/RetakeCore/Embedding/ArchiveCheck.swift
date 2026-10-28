import Foundation

/// What `retake check` does: looks through an `.xcarchive`, `.ipa` or `.app` for TheInsideJob and
/// Retake's support library, in its frameworks and its executables, its app extensions' included.
/// See Documentation/cli.md, "retake check".
public enum ArchiveCheck {
    /// Where each was found, relative to `url`; empty when neither is there.
    public static func check(_ url: URL, symbols: (URL) -> [String] = InsideJobDetector.definedSymbols) throws(RetakeError) -> [String] {
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder) else {
            throw RetakeError(.usage, "\(url.path) doesn't exist.")
        }
        switch url.pathExtension {
        case "app" where isFolder.boolValue:
            return findings(inApp: url, root: url, symbols: symbols)
        case "xcarchive" where isFolder.boolValue:
            let applications = url.appending(path: "Products/Applications", directoryHint: .isDirectory)
            return apps(in: applications).flatMap { findings(inApp: $0, root: url, symbols: symbols) }
        case "ipa" where !isFolder.boolValue:
            let unpacked = FileManager.default.temporaryDirectory.appending(path: "retake-check-\(UUID().uuidString)", directoryHint: .isDirectory)
            defer { try? FileManager.default.removeItem(at: unpacked) }
            guard let result = try? Subprocess.run("/usr/bin/ditto", ["-x", "-k", url.path, unpacked.path]), result.status == 0 else {
                throw RetakeError(.failed, "\(url.lastPathComponent) couldn't be unpacked as an .ipa.")
            }
            return apps(in: unpacked.appending(path: "Payload", directoryHint: .isDirectory))
                .flatMap { findings(inApp: $0, root: unpacked, symbols: symbols) }
        default:
            throw RetakeError(.usage, "\(url.lastPathComponent) isn't an .xcarchive, an .ipa or an .app.")
        }
    }

    static func apps(in folder: URL) -> [URL] {
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return entries.filter { $0.hasSuffix(".app") }.sorted().map { folder.appending(path: $0, directoryHint: .isDirectory) }
    }

    /// The app's own findings, then each of its extensions'.
    static func findings(inApp app: URL, root: URL, symbols: (URL) -> [String]) -> [String] {
        var found = InsideJobDetector.find(in: AppBundle(url: app), root: root, symbols: symbols)
        let plugins = app.appending(path: "PlugIns", directoryHint: .isDirectory)
        let extensions = (try? FileManager.default.contentsOfDirectory(atPath: plugins.path)) ?? []
        for name in extensions.sorted() where name.hasSuffix(".appex") {
            found += InsideJobDetector.find(in: AppBundle(url: plugins.appending(path: name, directoryHint: .isDirectory)), root: root, symbols: symbols)
        }
        return found
    }
}
