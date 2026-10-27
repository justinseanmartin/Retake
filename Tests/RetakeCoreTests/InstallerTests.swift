import Foundation
import RetakeCore
import Testing

struct InstallerTests {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "RetakeInstall-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func project(_ settings: ProjectSettings = ProjectSettings()) -> Project {
        Project(configuration: root.appending(path: "retake.json"), settings: settings)
    }

    @Test func theAppComesFromTheFirstThatApplies() throws {
        let configured = project(ProjectSettings(build: .command(.init(command: "make app", app: "build/Notes.app"))))
        let given = URL(filePath: "/builds/Notes.app")
        #expect(try Installer.source(app: given, scheme: .init(scheme: "Notes"), project: configured) == .app(given))
        #expect(try Installer.source(app: nil, scheme: .init(scheme: "Notes"), project: configured) == .scheme(.init(scheme: "Notes"), root: root))
        #expect(try Installer.source(app: nil, scheme: nil, project: configured) == .command(.init(command: "make app", app: "build/Notes.app"), root: root))
        #expect(throws: RetakeError.self) { try Installer.source(app: nil, scheme: nil, project: project()) }
    }

    @Test func xcodebuildBuildsTheSchemeForTheDeviceUnderTheOutputDirectory() {
        let build = ProjectSettings.SchemeBuild(scheme: "Notes", container: .workspace("Notes.xcworkspace"), configuration: nil, allowProvisioningUpdates: false)
        let derivedData = URL(filePath: "/p/output/build/DerivedData")
        #expect(Installer.xcodebuildArguments(build, udid: "00008103-1", derivedData: derivedData, allowProvisioningUpdates: false) == [
            "xcodebuild", "-workspace", "Notes.xcworkspace", "-scheme", "Notes", "-configuration", "Debug",
            "-destination", "id=00008103-1", "-derivedDataPath", "/p/output/build/DerivedData", "build",
        ])
        let allowed = ProjectSettings.SchemeBuild(scheme: "Notes", configuration: "Preview", allowProvisioningUpdates: true)
        let arguments = Installer.xcodebuildArguments(allowed, udid: "u", derivedData: derivedData, allowProvisioningUpdates: false, showingSettings: true)
        #expect(arguments.contains("-allowProvisioningUpdates") && arguments.suffix(2) == ["-showBuildSettings", "-json"])
        #expect(arguments.contains("Preview"))
    }

    @Test func theBuiltAppIsTheSchemesOneApplication() throws {
        let settings = #"""
            [{"target": "NotesKit", "buildSettings": {"PRODUCT_TYPE": "com.apple.product-type.framework", "TARGET_BUILD_DIR": "/b", "FULL_PRODUCT_NAME": "NotesKit.framework"}},
             {"target": "Notes", "buildSettings": {"PRODUCT_TYPE": "com.apple.product-type.application", "TARGET_BUILD_DIR": "/b/Debug-iphoneos", "FULL_PRODUCT_NAME": "Notes.app"}}]
            """#
        #expect(try Installer.builtApp(fromSettings: Data(settings.utf8)).path == "/b/Debug-iphoneos/Notes.app")
        let two = #"[{"buildSettings": {"PRODUCT_TYPE": "com.apple.product-type.application", "TARGET_BUILD_DIR": "/b", "FULL_PRODUCT_NAME": "A.app"}}, {"buildSettings": {"PRODUCT_TYPE": "com.apple.product-type.application", "TARGET_BUILD_DIR": "/b", "FULL_PRODUCT_NAME": "B.app"}}]"#
        #expect(throws: RetakeError.self) { try Installer.builtApp(fromSettings: Data(two.utf8)) }
        #expect(throws: RetakeError.self) { try Installer.builtApp(fromSettings: Data("[]".utf8)) }
    }

    @Test func anUnregisteredDeviceIsRecognised() {
        #expect(Installer.isUnregisteredDevice(#"error: Provisioning profile "iOS Team Provisioning Profile: com.example.notes" doesn't include the currently selected device "Sam’s iPad" (identifier 00008103-1)."#))
        #expect(!Installer.isUnregisteredDevice("error: Signing for \"Notes\" requires a development team."))
    }

    @Test func theCommandBuildsTheAppWithTheDevicesUDID() throws {
        let device = Device(udid: "00008103-0000000000000001", name: "Sam’s iPad", type: .ipad)
        let build = ProjectSettings.CommandBuild(command: #"mkdir -p out/Notes.app && echo "$RETAKE_DEVICE_UDID" > out/udid"#, app: "out/Notes.app")
        let app = try Installer.app(from: .command(build, root: root), for: device, project: project(), allowProvisioningUpdates: false)
        #expect(app.path == root.appending(path: "out/Notes.app").path)
        #expect(try String(contentsOf: root.appending(path: "out/udid"), encoding: .utf8) == "00008103-0000000000000001\n")
        #expect(throws: RetakeError.self) {
            try Installer.app(from: .command(.init(command: "exit 3", app: "x.app"), root: root), for: device, project: project(), allowProvisioningUpdates: false)
        }
        #expect(throws: RetakeError.self) {
            try Installer.app(from: .command(.init(command: "true", app: "missing.app"), root: root), for: device, project: project(), allowProvisioningUpdates: false)
        }
    }

    @Test func theBundleIDIsTheProjectsOrTheInstalledApps() throws {
        #expect(try Installer.bundleID(for: project(ProjectSettings(bundleID: "com.example.named"))) == "com.example.named")
        #expect(throws: RetakeError.self) { try Installer.bundleID(for: project()) }
        try Installer.recordInstalled(bundleID: "com.example.installed", in: project())
        #expect(try Installer.bundleID(for: project()) == "com.example.installed")
        try Data(#"{ "bundleId": "x" }"#.utf8).write(to: Installer.installedRecord(project()))
        #expect(throws: RetakeError.self, "a record that isn't one") { try Installer.bundleID(for: project()) }
    }

    @Test func buildsAreKeptOutsideTheProjectInAFolderOfItsOwn() {
        let cache = URL(filePath: "/caches/retake", directoryHint: .isDirectory)
        let notes = Project(configuration: URL(filePath: "/work/Notes/Retake/retake.json"))
        let other = Project(configuration: URL(filePath: "/clone/Notes/Retake/retake.json"))
        let folder = Installer.buildFolder(notes, cache: cache)
        #expect(folder.path.hasPrefix("/caches/retake/builds/Notes-Retake-"))
        #expect(folder != Installer.buildFolder(other, cache: cache), "another clone of the same project")
        #expect(folder == Installer.buildFolder(notes, cache: cache), "the same each time")
        #expect(Installer.installedFolder(notes, cache: cache).path == folder.appending(path: "installed").path)
    }
}
