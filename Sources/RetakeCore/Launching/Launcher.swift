import Foundation

/// The app, launched for a take, and attached to until it's stopped.
public final class LaunchedApp: @unchecked Sendable {
    public let plan: LaunchPlan
    public let device: Device
    public let report: LaunchReport
    /// The device's address on the CoreDevice tunnel, which The Button Heist's client connects to.
    public let tunnelAddress: String
    /// The app's console, for when something goes wrong.
    public let consoleLog: URL
    private let console: Process

    init(plan: LaunchPlan, device: Device, report: LaunchReport, tunnelAddress: String, consoleLog: URL, console: Process) {
        self.plan = plan
        self.device = device
        self.report = report
        self.tunnelAddress = tunnelAddress
        self.consoleLog = consoleLog
        self.console = console
    }

    /// The Button Heist's server in the app, as its client takes it: `[address]:port`.
    public var endpoint: String { "[\(tunnelAddress)]:\(plan.port)" }

    /// Detaches from the app's console; the app keeps running until it's launched again.
    public func stop() {
        if console.isRunning { console.terminate() }
        console.waitUntilExit()
    }
}

/// Launching the app on a device for a take, and the launch that cleans up after a run. See
/// docs/cli.md, "retake record", steps 1 and 2, and "retake clean".
public enum Launcher {
    /// How long to wait for the support library's report before deciding it didn't load.
    public static let reportTimeout = 15.0

    /// Turns the device, stages the set's files, launches the app attached to its console, and
    /// waits for the support library to report this take: an environment problem (3) when it
    /// doesn't, since the app then wasn't embedded, or was by an incompatible Retake.
    public static func launch(_ plan: LaunchPlan, on device: Device, logs: URL) throws(RetakeError) -> LaunchedApp {
        try devicectl(["devicectl", "device", "orientation", "set", "--device", device.udid, LaunchPlan.devicectlName(plan.orientation)], "turn \(device.name) to \(plan.orientation.rawValue)")
        for staged in plan.staging {
            try devicectl(
                ["devicectl", "device", "copy", "to", "--device", device.udid, "--domain-type", "appDataContainer",
                 "--domain-identifier", plan.bundleID, "--source", staged.source.path, "--destination", staged.destination],
                "copy \(staged.source.lastPathComponent) to the device",
            )
        }

        let consoleLog = logs.appending(path: "\(plan.take).log")
        let console = Process()
        do {
            try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: consoleLog.path, contents: nil)
            let handle = try FileHandle(forWritingTo: consoleLog)
            console.executableURL = URL(filePath: "/usr/bin/xcrun")
            console.arguments = plan.launchArguments(udid: device.udid)
            console.standardOutput = handle
            console.standardError = handle
            console.standardInput = FileHandle.nullDevice
            try console.run()
        } catch {
            throw RetakeError(.environment, "Couldn't launch the app with devicectl: \(error.localizedDescription)")
        }

        let deadline = Date().addingTimeInterval(reportTimeout)
        var report: LaunchReport?
        while Date() < deadline {
            if let found = readReport(bundleID: plan.bundleID, from: device), found.take == plan.take {
                report = found
                break
            }
            if !console.isRunning { break }
            Thread.sleep(forTimeInterval: 0.5)
        }
        guard let report else {
            if console.isRunning { console.terminate() }
            let log = (try? String(contentsOf: consoleLog, encoding: .utf8)) ?? ""
            let detail = log.split(separator: "\n").suffix(6).joined(separator: "\n")
            throw RetakeError(
                .environment,
                "The app didn't start with Retake's support library: embed it again with `retake embed` or `retake install`."
                    + (detail.isEmpty ? "" : "\nIts console said:\n\(detail)"),
            )
        }
        try report.check(take: plan.take)
        let tunnel = (try? Devicectl().devices().first { $0.udid == device.udid }?.tunnelAddress) ?? device.tunnelAddress
        guard let tunnel else {
            console.terminate()
            throw RetakeError(.environment, "\(device.name) has no CoreDevice tunnel to reach the app over.")
        }
        return LaunchedApp(plan: plan, device: device, report: report, tunnelAddress: tunnel, consoleLog: consoleLog, console: console)
    }

    /// The launch that deletes takes' homes and staged files from the device, then closes the app
    /// iOS opens again after it.
    public static func cleanUp(bundleID: String, on device: Device) throws(RetakeError) {
        let take = "cleanup-\(UUID().uuidString.prefix(8).lowercased())"
        let environment = JSONWriter.write(.object(JSONObject([
            .init(key: "DYLD_INSERT_LIBRARIES", value: .string("@executable_path/Frameworks/\(SupportLibrary.fileName)")),
            .init(key: "RETAKE_CLEANUP", value: .string("1")),
            .init(key: "RETAKE_TAKE", value: .string(take)),
        ]))).split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: " ")
        try devicectl(
            ["devicectl", "device", "process", "launch", "--device", device.udid, "--terminate-existing", "--environment-variables", environment, bundleID],
            "launch the app to clean up",
        )
        let deadline = Date().addingTimeInterval(reportTimeout)
        var cleaned = false
        while Date() < deadline, !cleaned {
            if let report = readReport(bundleID: bundleID, from: device), report.take == take, report.cleanedUp { cleaned = true } else {
                Thread.sleep(forTimeInterval: 0.5)
            }
        }
        guard cleaned else {
            throw RetakeError(.environment, "The app didn't clean up: embed it again with `retake embed` or `retake install`.")
        }
        // iOS opens the app again a moment after the cleanup launch exits; it's closed once it has.
        let reopening = Date().addingTimeInterval(reopenTimeout)
        while Date() < reopening {
            if terminate(bundleID: bundleID, on: device) > 0 { return }
            Thread.sleep(forTimeInterval: 0.5)
        }
    }

    /// How long to wait for iOS to open the app again after a cleanup launch.
    public static let reopenTimeout = 6.0

    /// The support library's last report, copied back from the device.
    static func readReport(bundleID: String, from device: Device) -> LaunchReport? {
        let local = FileManager.default.temporaryDirectory.appending(path: "retake-report-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: local) }
        guard let result = try? Subprocess.xcrun([
            "devicectl", "device", "copy", "from", "--device", device.udid, "--domain-type", "appDataContainer",
            "--domain-identifier", bundleID, "--source", SupportLibrary.reportPath, "--destination", local.path, "--quiet",
        ]), result.status == 0, let data = FileManager.default.contents(atPath: local.path) else { return nil }
        return LaunchReport.parse(data)
    }

    /// Ends the app's processes on the device, found by where it's installed, returning how many.
    @discardableResult
    static func terminate(bundleID: String, on device: Device) -> Int {
        let devicectl = Devicectl()
        guard let apps = try? devicectl.run(["device", "info", "apps", "--device", device.udid, "--bundle-id", bundleID]),
              let appsValue = try? JSONParser.parse(String(decoding: apps, as: UTF8.self)),
              case .array(let listed)? = appsValue[path: "result", "apps"],
              let installed = listed.first?[path: "url"]?.stringValue,
              let processes = try? devicectl.run(["device", "info", "processes", "--device", device.udid]),
              let processesValue = try? JSONParser.parse(String(decoding: processes, as: UTF8.self)),
              case .array(let running)? = processesValue[path: "result", "runningProcesses"] else { return 0 }
        let prefix = URL(string: installed)?.path ?? installed
        var ended = 0
        for process in running {
            guard let executable = process[path: "executable"]?.stringValue,
                  (URL(string: executable)?.path ?? executable).hasPrefix(prefix),
                  case .number(let pid)? = process[path: "processIdentifier"] else { continue }
            _ = try? Subprocess.xcrun(["devicectl", "device", "process", "terminate", "--device", device.udid, "--pid", String(Int(pid))])
            ended += 1
        }
        return ended
    }

    /// Runs `devicectl`, as an environment problem (3) when it fails.
    static func devicectl(_ arguments: [String], _ what: String) throws(RetakeError) {
        let result: Subprocess.Result
        do {
            result = try Subprocess.xcrun(arguments)
        } catch {
            throw RetakeError(.environment, "Couldn't run devicectl to \(what): \(error.localizedDescription)")
        }
        guard result.status == 0 else {
            let detail = result.errorText.trimmingCharacters(in: .whitespacesAndNewlines)
            throw RetakeError(.environment, "devicectl couldn't \(what)\(detail.isEmpty ? "." : ": \(detail)")")
        }
    }
}
