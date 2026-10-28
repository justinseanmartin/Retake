import Foundation

/// A built `.app`, as `embed`, `install` and `check` read it.
public struct AppBundle: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public var infoPlist: URL { url.appending(path: "Info.plist") }
    public var frameworks: URL { url.appending(path: "Frameworks", directoryHint: .isDirectory) }

    /// The key under which `embed` records what it added, in the app's `Info.plist`.
    public static let recordKey = "Retake"

    /// What an earlier `embed` recorded, by any version of Retake.
    public struct EmbedRecord: Equatable, Sendable {
        public var retakeVersion: String
        public var supportContract: Int
        public var buttonHeistVersion: String
        /// What it added, relative to the app: `Frameworks/TheInsideJob.framework`.
        public var added: [String]

        public init(retakeVersion: String, supportContract: Int, buttonHeistVersion: String, added: [String]) {
            self.retakeVersion = retakeVersion
            self.supportContract = supportContract
            self.buttonHeistVersion = buttonHeistVersion
            self.added = added
        }

        var plist: [String: Any] {
            [
                "Version": retakeVersion,
                "SupportContract": supportContract,
                "ButtonHeistVersion": buttonHeistVersion,
                "Added": added,
            ]
        }

        init?(plist: Any?) {
            guard let plist = plist as? [String: Any] else { return nil }
            retakeVersion = plist["Version"] as? String ?? "unknown"
            supportContract = plist["SupportContract"] as? Int ?? 0
            buttonHeistVersion = plist["ButtonHeistVersion"] as? String ?? "unknown"
            added = plist["Added"] as? [String] ?? []
        }
    }

    /// The app's `Info.plist`, as a dictionary, and the format it's written in.
    func readInfo() throws(RetakeError) -> (info: [String: Any], format: PropertyListSerialization.PropertyListFormat) {
        guard let data = FileManager.default.contents(atPath: infoPlist.path) else {
            throw RetakeError(.usage, "\(url.path) isn't an app: it has no Info.plist.")
        }
        var format = PropertyListSerialization.PropertyListFormat.binary
        guard let info = try? PropertyListSerialization.propertyList(from: data, options: [], format: &format) as? [String: Any] else {
            throw RetakeError(.failed, "\(infoPlist.path) can't be read.")
        }
        return (info, format)
    }

    func writeInfo(_ info: [String: Any], format: PropertyListSerialization.PropertyListFormat) throws(RetakeError) {
        do {
            let data = try PropertyListSerialization.data(fromPropertyList: info, format: format, options: 0)
            try data.write(to: infoPlist, options: .atomic)
        } catch {
            throw RetakeError(.failed, "Couldn't write \(infoPlist.path): \(error.localizedDescription)")
        }
    }

    public var bundleID: String? { (try? readInfo().info["CFBundleIdentifier"]) as? String }

    /// The app's version and build, `CFBundleShortVersionString` and `CFBundleVersion`.
    public var version: (version: String?, build: String?) {
        let info = (try? readInfo().info) ?? [:]
        return (info["CFBundleShortVersionString"] as? String, info["CFBundleVersion"] as? String)
    }

    public var embedRecord: EmbedRecord? {
        EmbedRecord(plist: (try? readInfo().info)?[Self.recordKey])
    }

    /// Whether the app is built for iOS devices, rather than a simulator or the Mac.
    public var isForDevices: Bool {
        guard let info = try? readInfo().info else { return false }
        let platforms = info["CFBundleSupportedPlatforms"] as? [String] ?? []
        return platforms.contains("iPhoneOS") || info["DTPlatformName"] as? String == "iphoneos"
    }

    /// The app's executables: its own, and its `*.debug.dylib`, which a Debug build splits its code
    /// into, then each framework's. Fails (1) for a folder or `Info.plist` that's there but can't be
    /// read, since what can't be read can't be cleared.
    public func executables() throws(RetakeError) -> [URL] {
        var found: [URL] = []
        if FileManager.default.fileExists(atPath: infoPlist.path), let name = try readInfo().info["CFBundleExecutable"] as? String {
            found.append(url.appending(path: name))
        }
        found += try Self.listing(url).filter { $0.hasSuffix(".debug.dylib") }.map { url.appending(path: $0) }
        for entry in try Self.listing(frameworks) {
            let item = self.frameworks.appending(path: entry)
            if entry.hasSuffix(".framework") {
                found.append(item.appending(path: String(entry.dropLast(".framework".count))))
            } else if entry.hasSuffix(".dylib") {
                found.append(item)
            }
        }
        return found.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// A folder's entries, sorted: none when it isn't there, and a failure (1) when it's there but
    /// can't be listed, as in a sandboxed build phase that wasn't given it.
    static func listing(_ folder: URL) throws(RetakeError) -> [String] {
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isFolder), isFolder.boolValue else { return [] }
        do {
            return try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
        } catch {
            throw RetakeError(.failed, "Couldn't read \(folder.path), so what's in it can't be checked: \(error.localizedDescription)")
        }
    }
}

/// Finding TheInsideJob, or Retake's support library, in an app: by the name of a framework or
/// library it carries, and by TheInsideJob's symbols in its executables, which a static link leaves.
public enum InsideJobDetector {
    /// Where TheInsideJob or the support library is, relative to `root`; empty when it isn't there.
    /// `ignoring` are paths Retake itself added, which an earlier embed recorded.
    /// Fails (1) for any part of the app it can't read, rather than taking it to be clear.
    public static func find(
        in app: AppBundle, root: URL? = nil, ignoring: Set<String> = [], symbols: (URL) throws(RetakeError) -> [String] = definedSymbols,
    ) throws(RetakeError) -> [String] {
        let base = root ?? app.url
        func relative(_ url: URL) -> String {
            let path = url.standardizedFileURL.path
            let prefix = base.standardizedFileURL.path + "/"
            return path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : path
        }
        let appRelative = { (url: URL) -> String in
            let path = url.standardizedFileURL.path
            let prefix = app.url.standardizedFileURL.path + "/"
            return path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : path
        }
        var found: [String] = []
        for name in try AppBundle.listing(app.frameworks) where isRetakeName(name) {
            let item = app.frameworks.appending(path: name)
            if !ignoring.contains(appRelative(item)) { found.append(relative(item)) }
        }
        for executable in try app.executables() {
            let path = appRelative(executable)
            if ignoring.contains(where: { path.hasPrefix($0) }) { continue }
            if found.contains(where: { relative(executable).hasPrefix($0) }) { continue }
            if try symbols(executable).contains(where: isTheInsideJobSymbol) {
                found.append("\(relative(executable)) (TheInsideJob linked into it)")
            }
        }
        return found
    }

    /// TheInsideJob's framework, under its release name or the name a build of it gives, and
    /// Retake's support library.
    static func isRetakeName(_ name: String) -> Bool {
        name.contains("TheInsideJob") || name.hasPrefix("RetakeInsideJob") || name == SupportLibrary.fileName
    }

    /// A symbol of TheInsideJob's own module: Swift mangles a module named TheInsideJob as
    /// `12TheInsideJob`, so another Button Heist module that merely mentions it doesn't match.
    static func isTheInsideJobSymbol(_ symbol: String) -> Bool {
        symbol.contains("12TheInsideJob")
    }

    /// The symbols `executable` defines, from `nm`; a failure (1) when `nm` can't read them.
    public static func definedSymbols(_ executable: URL) throws(RetakeError) -> [String] {
        guard let result = try? Subprocess.xcrun(["nm", "-U", "-j", executable.path]), result.status == 0 else {
            throw RetakeError(.failed, "Couldn't read the symbols of \(executable.path), so it can't be checked for TheInsideJob.")
        }
        return result.outputText.split(separator: "\n").map(String.init)
    }
}
