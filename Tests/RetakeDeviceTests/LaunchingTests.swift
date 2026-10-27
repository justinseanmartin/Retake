import Foundation
import RetakeCore
import Testing

/// Checks only a device can make, against the example app installed on it with `retake install`.
/// They run when RETAKE_TEST_DEVICE names a device (an alias, a UDID or a name), and are skipped
/// otherwise, so `swift test` never needs one; unlike unit tests, they take seconds each.
let testDevice = ProcessInfo.processInfo.environment["RETAKE_TEST_DEVICE"].flatMap { $0.isEmpty ? nil : $0 }

/// The example project, its device, and its app's bundle ID.
struct ExampleOnDevice {
    let project: Project
    let device: Device
    let bundleID: String
    let files: ProjectFiles

    init() throws {
        let root = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../../Examples/RetakeNotes").standardizedFileURL
        project = try Project.locate(configuration: nil, currentDirectory: root)
        let directory = DeviceDirectory(devices: try Devicectl().devices(), aliases: try DeviceAliases.load(from: DeviceAliases.defaultFile()))
        device = try directory.resolve(DeviceChoice(device: testDevice!, source: .environment(variable: "RETAKE_TEST_DEVICE")))
        bundleID = try Installer.bundleID(for: project)
        files = ProjectFiles(project: project)
    }

    func plan(scene name: String) throws -> LaunchPlan {
        let report = ProjectFiles.Report()
        let scene = try #require(files.readScene(name, for: device.type!, into: report))
        let set = try #require(files.resolveSet(scene.set!, into: report))
        return LaunchPlan.make(project: project, set: set, scene: scene, type: device.type!, bundleID: bundleID, take: "\(name)-\(UUID().uuidString.prefix(6))")
    }
}

/// Every device suite, nested here so they run one at a time: they share one device, and one
/// launch ends another's.
@Suite(.enabled(if: testDevice != nil, "RETAKE_TEST_DEVICE names no device"), .serialized)
struct OnDevice {}

extension OnDevice {
    @Suite struct LaunchingTests {
        @Test func aSceneLaunchesOnItsSetAndTheLibraryReportsIn() throws {
            let example = try ExampleOnDevice()
            for scene in ["first-launch", "create-note"] {
                let plan = try example.plan(scene: scene)
                let launched = try Launcher.launch(plan, on: example.device, logs: example.project.output.appending(path: "logs"))
                defer { launched.stop() }
                #expect(launched.report.take == plan.take)
                #expect(launched.report.contract == SupportLibrary.contractVersion)
                #expect(launched.report.state == "clean")
                #expect(launched.endpoint.hasPrefix("[") && launched.endpoint.hasSuffix("]:\(plan.port)"))
            }
        }

        @Test func cleaningUpLeavesNoTakeOnTheDevice() throws {
            let example = try ExampleOnDevice()
            let launched = try Launcher.launch(try example.plan(scene: "create-note"), on: example.device, logs: example.project.output.appending(path: "logs"))
            launched.stop()
            try Launcher.cleanUp(bundleID: example.bundleID, on: example.device)
            let listing = try Subprocess.xcrun([
                "devicectl", "device", "info", "files", "--device", example.device.udid, "--domain-type", "appDataContainer",
                "--domain-identifier", example.bundleID, "--subdirectory", "tmp",
            ])
            #expect(!listing.outputText.contains("RetakeTakes"))
            #expect(!listing.outputText.contains("RetakeSet"))
        }
    }
}
