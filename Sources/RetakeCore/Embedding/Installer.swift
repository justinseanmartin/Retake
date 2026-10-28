import Foundation

/// What `retake install` does: gets the app, built if need be, embeds Retake in a copy of it, and
/// installs that on the device. See docs/cli.md, "retake install".
public enum Installer {
    /// Where the app comes from, the first that applies: `--app`, `--scheme`, then `retake.json`'s
    /// `build`.
    public enum Source: Equatable, Sendable {
        case app(URL)
        case scheme(ProjectSettings.SchemeBuild, root: URL)
        case command(ProjectSettings.CommandBuild, root: URL)
    }

    /// The source for what the command line and the project give; misuse (2) with none.
    public static func source(
        app: URL?,
        scheme: ProjectSettings.SchemeBuild?,
        project: Project,
    ) throws(RetakeError) -> Source {
        if let app { return .app(app) }
        if let scheme { return .scheme(scheme, root: project.root) }
        switch project.settings.build {
        case .scheme(let build)?: return .scheme(build, root: project.root)
        case .command(let build)?: return .command(build, root: project.root)
        case nil:
            throw RetakeError(.usage, "Nothing says how to get the app: give --app or --scheme, or \"build\" in \(project.configuration.lastPathComponent).")
        }
    }

    /// Where `install` keeps its builds: the project's folder in `~/Library/Caches/retake/builds/`,
    /// outside the project, since a build rewrites thousands of files each time.
    public static func buildFolder(_ project: Project, cache: URL = RetakeCache.root) -> URL {
        RetakeCache.builds(for: project, in: cache)
    }

    /// Where the embedded copy it installs goes, replaced each time.
    public static func installedFolder(_ project: Project, cache: URL = RetakeCache.root) -> URL {
        buildFolder(project, cache: cache).appending(path: "installed", directoryHint: .isDirectory)
    }

    /// The output directory's record of the app `install` last embedded, for "Finding the app".
    public static func installedRecord(_ project: Project) -> URL {
        project.output.appending(path: "installed.json")
    }

    /// Records the bundle ID of the app `install` embedded, in the output directory.
    public static func recordInstalled(bundleID: String, in project: Project) throws(RetakeError) {
        let record = installedRecord(project)
        do {
            try FileManager.default.createDirectory(at: project.output, withIntermediateDirectories: true)
            try Data(JSONWriter.write(.object(JSONObject([.init(key: "bundleID", value: .string(bundleID))]))).utf8).write(to: record, options: .atomic)
        } catch {
            throw RetakeError(.failed, "Couldn't write \(project.displayPath(record)): \(error.localizedDescription)")
        }
    }

    /// The bundle ID `install` last recorded, if it has, read strictly; a record that isn't one fails (1).
    static func installedBundleID(_ project: Project) throws(RetakeError) -> String? {
        let record = installedRecord(project)
        guard let data = FileManager.default.contents(atPath: record.path) else { return nil }
        let reader = JSONReader(file: project.displayPath(record))
        guard let value = reader.parse(String(decoding: data, as: UTF8.self)), var object = reader.object(value, at: .root) else {
            throw RetakeError(.failed, reader.problems.map(\.description).joined(separator: "\n"))
        }
        let id = object.required("bundleID", reader.nonEmptyString)
        object.finish()
        guard reader.problems.isEmpty else { throw RetakeError(.failed, reader.problems.map(\.description).joined(separator: "\n")) }
        return id
    }

    /// The app's bundle ID, as docs/cli.md, "Finding the app", gives it: the configuration file's
    /// `bundleID`, else the one `install` last embedded; misuse (2) with neither.
    public static func bundleID(for project: Project) throws(RetakeError) -> String {
        if let id = project.settings.bundleID { return id }
        if let id = try installedBundleID(project) { return id }
        throw RetakeError(
            .usage,
            "Retake doesn't know the app's bundle ID: give \"bundleID\" in \(project.configuration.lastPathComponent), or run `retake install`, "
                + "which records it in \(project.displayPath(installedRecord(project))).",
        )
    }

    /// The arguments that build a scheme for a device with `xcodebuild`, its products under
    /// `derivedData`, or that read its build settings.
    public static func xcodebuildArguments(
        _ build: ProjectSettings.SchemeBuild,
        udid: String,
        derivedData: URL,
        allowProvisioningUpdates: Bool,
        showingSettings: Bool = false,
    ) -> [String] {
        var arguments = ["xcodebuild"]
        switch build.container {
        case .workspace(let path)?: arguments += ["-workspace", path]
        case .project(let path)?: arguments += ["-project", path]
        case nil: break
        }
        arguments += [
            "-scheme", build.scheme,
            "-configuration", build.configuration ?? "Debug",
            "-destination", "id=\(udid)",
            "-derivedDataPath", derivedData.path,
        ]
        if allowProvisioningUpdates || build.allowProvisioningUpdates { arguments.append("-allowProvisioningUpdates") }
        // A Debug build at -Onone can stutter where the app as its users have it wouldn't.
        if build.optimize { arguments += ["SWIFT_OPTIMIZATION_LEVEL=-O", "GCC_OPTIMIZATION_LEVEL=s"] }
        arguments.append(showingSettings ? "-showBuildSettings" : "build")
        if showingSettings { arguments.append("-json") }
        return arguments
    }

    /// The app a scheme builds, from `xcodebuild -showBuildSettings -json`: the one target whose
    /// product is an application.
    public static func builtApp(fromSettings data: Data) throws(RetakeError) -> URL {
        guard case .array(let targets)? = try? JSONParser.parse(String(decoding: data, as: UTF8.self)) else {
            throw RetakeError(.failed, "xcodebuild's build settings couldn't be read.")
        }
        let apps: [URL] = targets.compactMap { target in
            guard target[path: "buildSettings", "PRODUCT_TYPE"]?.stringValue == "com.apple.product-type.application",
                  let folder = target[path: "buildSettings", "TARGET_BUILD_DIR"]?.stringValue,
                  let name = target[path: "buildSettings", "FULL_PRODUCT_NAME"]?.stringValue else { return nil }
            return URL(filePath: folder, directoryHint: .isDirectory).appending(path: name, directoryHint: .isDirectory)
        }
        switch apps.count {
        case 1: return apps[0]
        case 0: throw RetakeError(.failed, "The scheme builds no app.")
        default:
            throw RetakeError(
                .failed,
                "The scheme builds several apps (\(apps.map(\.lastPathComponent).joined(separator: ", "))); give a scheme that builds one, or --app.",
            )
        }
    }

    /// Whether `xcodebuild`'s or `codesign`'s output says the device isn't on the team's profiles.
    public static func isUnregisteredDevice(_ output: String) -> Bool {
        let signs = [
            "doesn't include the currently selected device",
            "does not include the currently selected device",
            "isn't registered",
            "is not registered",
            "Unregistered device",
            "doesn't include the device",
        ]
        return signs.contains { output.localizedCaseInsensitiveContains($0) }
    }

    /// Gets the app from `source` for `device`: as it is, built with `xcodebuild`, or built by the
    /// project's command.
    public static func app(from source: Source, for device: Device, project: Project, allowProvisioningUpdates: Bool) throws(RetakeError) -> URL {
        switch source {
        case .app(let url):
            return url
        case .scheme(let build, let root):
            let derivedData = buildFolder(project).appending(path: "DerivedData", directoryHint: .isDirectory)
            let arguments = xcodebuildArguments(build, udid: device.udid, derivedData: derivedData, allowProvisioningUpdates: allowProvisioningUpdates)
            let result: Subprocess.Result
            do {
                result = try Subprocess.xcrun(arguments, in: root)
            } catch {
                throw RetakeError(.environment, "Couldn't run xcodebuild: \(error.localizedDescription)")
            }
            guard result.status == 0 else {
                let output = result.outputText + result.errorText
                if isUnregisteredDevice(output) {
                    throw RetakeError(
                        .environment,
                        "The build can't be signed for \(device.name) (\(device.udid)), which isn't on the team's profiles. "
                            + "Register it in Xcode, or give --allow-provisioning-updates to let xcodebuild do it.",
                    )
                }
                let errors = output.split(separator: "\n").filter { $0.contains("error:") }.suffix(8)
                throw RetakeError(.failed, "xcodebuild couldn't build \(build.scheme):\n" + (errors.isEmpty ? output.split(separator: "\n").suffix(15) : errors).joined(separator: "\n"))
            }
            let settings = xcodebuildArguments(build, udid: device.udid, derivedData: derivedData, allowProvisioningUpdates: false, showingSettings: true)
            guard let listed = try? Subprocess.xcrun(settings, in: root), listed.status == 0 else {
                throw RetakeError(.failed, "xcodebuild couldn't say where it built \(build.scheme).")
            }
            return try builtApp(fromSettings: listed.output)
        case .command(let build, let root):
            let result: Subprocess.Result
            do {
                result = try Subprocess.run("/bin/sh", ["-c", build.command], in: root, environment: ["RETAKE_DEVICE_UDID": device.udid])
            } catch {
                throw RetakeError(.failed, "Couldn't run the build command: \(error.localizedDescription)")
            }
            guard result.status == 0 else {
                throw RetakeError(.failed, "The build command exited \(result.status):\n" + (result.outputText + result.errorText).split(separator: "\n").suffix(15).joined(separator: "\n"))
            }
            let app = root.appending(path: build.app, directoryHint: .isDirectory)
            guard FileManager.default.fileExists(atPath: app.path) else {
                throw RetakeError(.failed, "The build command finished, but there's no app at \(build.app).")
            }
            return app
        }
    }

    /// Installs `app` on `device`.
    public static func install(_ app: URL, on device: Device) throws(RetakeError) {
        guard let result = try? Subprocess.xcrun(["devicectl", "device", "install", "app", "--device", device.udid, app.path]) else {
            throw RetakeError(.environment, "Couldn't run devicectl.")
        }
        guard result.status == 0 else {
            let output = result.outputText + result.errorText
            if isUnregisteredDevice(output) {
                throw RetakeError(.environment, "\(device.name) (\(device.udid)) isn't on the profile the app is signed with; register it, and sign the app again.")
            }
            throw RetakeError(.failed, "devicectl couldn't install \(app.lastPathComponent):\n" + output.split(separator: "\n").suffix(10).joined(separator: "\n"))
        }
    }
}
