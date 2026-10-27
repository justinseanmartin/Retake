import Foundation

/// What `retake embed` does: adds TheInsideJob and Retake's support library to a built,
/// development-signed app, records what it added, and re-signs it. See docs/cli.md, "retake embed".
public enum Embedder {
    public struct Result: Equatable, Sendable {
        /// The embedded app: the one given, or the copy `--output` named.
        public var app: URL
        public var record: AppBundle.EmbedRecord
        /// The identity it was signed with.
        public var identity: String
    }

    public static func embed(
        _ given: URL,
        output: URL? = nil,
        signing overrides: SigningOverrides = SigningOverrides(),
        framework: InsideJobFramework,
        support: SupportLibrary,
    ) throws(RetakeError) -> Result {
        let files = FileManager.default
        var isFolder: ObjCBool = false
        guard files.fileExists(atPath: given.path, isDirectory: &isFolder), isFolder.boolValue, given.pathExtension == "app" else {
            throw RetakeError(.usage, "\(given.path) isn't a built .app.")
        }
        guard AppBundle(url: given).isForDevices else {
            throw RetakeError(.environment, "\(given.lastPathComponent) isn't built for iOS devices; Retake records devices, not simulators.")
        }

        let url: URL
        if let output {
            url = output.standardizedFileURL
            do {
                if files.fileExists(atPath: url.path) { try files.removeItem(at: url) }
                try files.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try files.copyItem(at: given, to: url)
            } catch {
                throw RetakeError(.failed, "Couldn't copy the app to \(url.path): \(error.localizedDescription)")
            }
        } else {
            url = given.standardizedFileURL
        }
        let app = AppBundle(url: url)
        let earlier = app.embedRecord

        let found = InsideJobDetector.find(in: app, ignoring: Set(earlier?.added ?? []))
        if !found.isEmpty {
            throw RetakeError(
                .failed,
                "\(given.lastPathComponent) already contains TheInsideJob, in \(found.joined(separator: ", ")). Retake supplies its own, "
                    + "and two copies in one app can't both run: leave it out of the builds you record with.",
            )
        }

        guard let bundleID = app.bundleID else { throw RetakeError(.usage, "\(given.lastPathComponent) has no bundle ID.") }
        guard let identity = overrides.identity ?? Signing.identity(of: url) else {
            throw RetakeError(.environment, "\(given.lastPathComponent) isn't signed; give --identity and --profile to sign it with.")
        }
        var entitlements = Signing.entitlements(of: url)
        if let profile = overrides.profile {
            let contents = try Signing.profile(at: profile)
            if entitlements == nil { entitlements = try Signing.entitlements(fromProfile: contents, bundleID: bundleID) }
            do {
                let embedded = url.appending(path: "embedded.mobileprovision")
                if files.fileExists(atPath: embedded.path) { try files.removeItem(at: embedded) }
                try files.copyItem(at: profile, to: embedded)
            } catch {
                throw RetakeError(.failed, "Couldn't put the profile in the app: \(error.localizedDescription)")
            }
        }
        guard let entitlements else {
            throw RetakeError(.environment, "\(given.lastPathComponent) isn't signed for development; give --profile, with --identity, to sign it with.")
        }
        guard Signing.isDevelopment(entitlements) else {
            throw RetakeError(
                .environment,
                "\(given.lastPathComponent) isn't development-signed (no get-task-allow), so Retake couldn't launch it; build it for development, or give --profile.",
            )
        }

        let frameworkName = "TheInsideJob.framework"
        let added = ["Frameworks/\(frameworkName)", "Frameworks/\(SupportLibrary.fileName)"]
        do {
            for path in Set(earlier?.added ?? []).union(added) {
                let item = url.appending(path: path)
                if files.fileExists(atPath: item.path) { try files.removeItem(at: item) }
            }
            try files.createDirectory(at: app.frameworks, withIntermediateDirectories: true)
            try files.copyItem(at: framework.deviceFramework, to: app.frameworks.appending(path: frameworkName))
            try files.copyItem(at: support.file, to: app.frameworks.appending(path: SupportLibrary.fileName))
        } catch {
            throw RetakeError(.failed, "Couldn't add Retake's frameworks to the app: \(error.localizedDescription)")
        }

        let record = AppBundle.EmbedRecord(
            retakeVersion: RetakeVersion.current.version,
            supportContract: SupportLibrary.contractVersion,
            buttonHeistVersion: framework.version,
            added: added,
        )
        var (info, format) = try app.readInfo()
        info[AppBundle.recordKey] = record.plist
        try app.writeInfo(info, format: format)

        try Signing.sign(app.frameworks.appending(path: frameworkName), identity: identity)
        try Signing.sign(app.frameworks.appending(path: SupportLibrary.fileName), identity: identity)
        try Signing.sign(url, identity: identity, entitlements: entitlements)
        try Signing.verify(url)
        return Result(app: url, record: record, identity: identity)
    }
}
