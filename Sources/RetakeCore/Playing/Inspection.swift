import ButtonHeist
import Foundation

/// Printing what's on screen, once or whenever it changes. See docs/cli.md, "retake inspect".
public struct Inspection: Sendable {
    /// Waits between looks at the screen.
    public var pause: @Sendable (Double) async -> Void
    /// Whether watching should end, checked between looks: the person pressed Control-C.
    public var stopped: @Sendable () -> Bool
    /// Called with what's on screen, first as it is, then each time it has changed and settled.
    public var show: @Sendable ([ScreenElement]) -> Void

    /// How often `--watch` looks at the screen.
    public static let watchInterval = 0.25

    public init(
        pause: @escaping @Sendable (Double) async -> Void = { seconds in try? await Task.sleep(for: .seconds(seconds)) },
        stopped: @escaping @Sendable () -> Bool = { false },
        show: @escaping @Sendable ([ScreenElement]) -> Void,
    ) {
        self.pause = pause
        self.stopped = stopped
        self.show = show
    }

    /// The set `inspect` launches on: the one named, or `retake.json`'s `defaultSet`.
    public static func set(_ name: String?, in project: Project) throws(RetakeError) -> ResolvedSet {
        if let name { return try AppSession.set(name, in: project, namedBy: "--set") }
        guard let name = project.settings.defaultSet else {
            throw RetakeError(.usage, "Give --set, or a defaultSet in \(project.configuration.lastPathComponent), to launch the app on.")
        }
        return try AppSession.set(name, in: project, namedBy: "\(project.configuration.lastPathComponent)'s defaultSet")
    }

    /// Launches the app on `set` and shows what's on screen, then with `watch`, shows it again each
    /// time it changes, until stopped. The app opens upright, as a scene's take does unless it says
    /// otherwise; it can be turned by hand while watching.
    public static func run(_ set: ResolvedSet, in project: Project, on device: Device, watch: Bool, inspection: Inspection, report: @escaping @Sendable (Player.Event) -> Void) async throws(RetakeError) {
        let scene = SceneFile(steps: [])
        try await AppSession.run("inspect", in: project, set: set, scene: scene, on: device, report: report) { driver, _ throws(RetakeError) in
            try await inspection.look(on: driver, watching: watch)
        }
    }

    /// How long the first look waits for the app to settle after launch before showing it anyway.
    public static let settleTimeout = 3.0

    /// Shows the screen once it has looked the same twice running, so an app still laying itself out
    /// after launch isn't shown half drawn. Then with `watching`, looks again every `watchInterval`
    /// and shows it each time a change has held the same way.
    @ButtonHeistActor
    public func look(on driver: some AppDriver, watching: Bool) async throws(RetakeError) {
        var shown = try await driver.elements()
        for _ in 0..<Int(Self.settleTimeout / Self.watchInterval) {
            await pause(Self.watchInterval)
            let now = try await driver.elements()
            if now == shown { break }
            shown = now
        }
        show(shown)
        guard watching else { return }
        var changed: [ScreenElement]?
        while !stopped() {
            await pause(Self.watchInterval)
            if stopped() { return }
            let now = try await driver.elements()
            if now == shown {
                changed = nil
            } else if now == changed {
                shown = now
                show(now)
                changed = nil
            } else {
                changed = now
            }
        }
    }
}
