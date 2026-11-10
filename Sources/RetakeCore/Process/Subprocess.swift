import Foundation

/// Runs a tool Retake drives — `xcodebuild`, `devicectl`, `codesign` — to completion, capturing what
/// it prints.
public enum Subprocess {
    public struct Result: Sendable {
        public var status: Int32
        public var output: Data
        public var error: Data

        public var outputText: String { String(decoding: output, as: UTF8.self) }
        public var errorText: String { String(decoding: error, as: UTF8.self) }
    }

    /// Runs `executable` with `arguments`, in `directory` if given. Throws only when it can't be
    /// started; a non-zero status is the result's to report.
    public static func run(
        _ executable: String,
        _ arguments: [String],
        in directory: URL? = nil,
        environment: [String: String]? = nil,
    ) throws -> Result {
        let process = Process()
        process.executableURL = URL(filePath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = directory
        if let environment {
            process.environment = ProcessInfo.processInfo.environment.merging(environment) { $1 }
        }
        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error
        process.standardInput = FileHandle.nullDevice
        try process.run()
        // Both pipes are drained while it runs, so a tool that prints a lot can't fill one and stall.
        // Each on a thread of its own, not a Dispatch queue: this is called from Swift concurrency's
        // threads, and with each of them waiting here, as on a CI machine with 3 cores, a queue's
        // reader was seen never to run, so none of them returned.
        let collected = Collected()
        let group = DispatchGroup()
        for (pipe, keyPath) in [(output, \Collected.output), (error, \Collected.error)] {
            group.enter()
            Thread.detachNewThread {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                collected.set(keyPath, data)
                group.leave()
            }
        }
        process.waitUntilExit()
        group.wait()
        return Result(status: process.terminationStatus, output: collected.output, error: collected.error)
    }

    /// `xcrun <tool> …`, for the tools Xcode provides.
    public static func xcrun(_ arguments: [String], in directory: URL? = nil) throws -> Result {
        try run("/usr/bin/xcrun", arguments, in: directory)
    }
}

private final class Collected: @unchecked Sendable {
    private let lock = NSLock()
    var output = Data()
    var error = Data()

    func set(_ keyPath: ReferenceWritableKeyPath<Collected, Data>, _ data: Data) {
        lock.withLock { self[keyPath: keyPath] = data }
    }
}
