/// How a command ended, as its exit status; see docs/cli.md, "Exit status".
public enum ExitStatus: Int32, Comparable, Sendable {
    /// Done.
    case done = 0
    /// The command failed: a step didn't run, a render failed, a check found a problem.
    case failed = 1
    /// The command was used wrongly: an unknown option, a missing argument, a name that doesn't exist.
    case usage = 2
    /// The environment isn't right: no device, a device on Wi-Fi, no signing identity, or an app that
    /// wasn't embedded, or was embedded by an incompatible Retake.
    case environment = 3

    /// The worse of two outcomes, for a command that does several things and exits with the worst.
    /// A higher status is worse: an environment problem outranks a misuse, which outranks a failure.
    public static func < (lhs: ExitStatus, rhs: ExitStatus) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// An error a command reports to the person running it, with the exit status it ends the command with.
public struct RetakeError: Error, CustomStringConvertible, Sendable {
    public var status: ExitStatus
    public var message: String

    public init(_ status: ExitStatus, _ message: String) {
        self.status = status
        self.message = message
    }

    public var description: String { message }

    /// A command whose contract is written but whose implementation isn't yet.
    public static func notImplemented(_ command: String) -> RetakeError {
        RetakeError(.failed, "`retake \(command)` isn't implemented yet.")
    }
}
