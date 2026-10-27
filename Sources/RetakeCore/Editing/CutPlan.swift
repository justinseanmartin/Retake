import CoreGraphics
import Foundation

/// The size and frame rate of a device type's preview, as App Store Connect specifies them. See
/// docs/cli.md, "retake cut".
public struct PreviewSpec: Equatable, Sendable {
    public var width: Int
    public var height: Int
    public var framesPerSecond: Int

    public static func of(_ type: DeviceType) -> PreviewSpec {
        switch type {
        case .iphone: PreviewSpec(width: 886, height: 1920, framesPerSecond: 30)
        case .ipad: PreviewSpec(width: 1200, height: 1600, framesPerSecond: 30)
        }
    }

    public var size: CGSize { CGSize(width: width, height: height) }
}

/// Where each of an edit's clips falls on the video's clock: the stretch of its take it plays, and
/// when and for how long, at its speed, each clip overlapping the one before by its cross-fade. The
/// editor's timing, apart from AVFoundation, so it can be tested.
public struct CutPlan: Equatable, Sendable {
    public struct Placement: Equatable, Sendable {
        /// The clip's scene, whose pinned take it plays.
        public var take: String
        /// Seconds into the take it plays from and to.
        public var from: Double
        public var to: Double
        public var speed: Double
        /// When in the video it starts, and how long it plays.
        public var start: Double
        public var duration: Double
        /// How long it cross-fades in over the clip before; 0 for a cut.
        public var crossfade: Double

        public var end: Double { start + duration }

        /// Where a moment of the take falls in the video, for one the clip plays.
        public func videoTime(_ takeTime: Double) -> Double {
            start + (takeTime - from) / speed
        }
    }

    public var placements: [Placement]

    public var duration: Double { placements.last?.end ?? 0 }

    /// The plan for `video`, each clip's anchors resolved in the take of its scene in `timelines`.
    /// Fails (1) for an anchor that doesn't resolve, a clip whose `to` isn't after its `from`, or a
    /// cross-fade longer than either clip it joins, naming the clip.
    public static func make(_ video: Edit, timelines: [String: TakeTimeline]) throws(RetakeError) -> CutPlan {
        var placements: [Placement] = []
        for (index, clip) in video.clips.enumerated() {
            let name = "clips[\(index)]"
            guard let timeline = timelines[clip.take] else {
                throw RetakeError(.failed, "\(name): there's no take of \(clip.take) to cut it from.")
            }
            let from: Double, to: Double
            do {
                from = try timeline.time(of: clip.from)
                to = try timeline.time(of: clip.to)
            } catch {
                throw RetakeError(.failed, "\(name): an anchor doesn't resolve: \(error.message).")
            }
            guard from >= 0, to <= timeline.log.duration, from < to else {
                throw RetakeError(
                    .failed,
                    "\(name) plays \(TakeTimeline.seconds(from)) to \(TakeTimeline.seconds(to)) of a take \(TakeTimeline.seconds(timeline.log.duration)) long; it must run forward, inside it.",
                )
            }
            let duration = (to - from) / clip.speed
            let crossfade = placements.isEmpty ? 0 : clip.crossfade
            if let previous = placements.last, crossfade > min(previous.duration, duration) {
                throw RetakeError(
                    .failed,
                    "\(name)'s cross-fade, \(TakeTimeline.seconds(crossfade)), is longer than it or the clip before plays.",
                )
            }
            let start = (placements.last?.end ?? 0) - crossfade
            placements.append(Placement(take: clip.take, from: from, to: to, speed: clip.speed, start: start, duration: duration, crossfade: crossfade))
        }
        return CutPlan(placements: placements)
    }
}

/// Where one clip's footage sits on the canvas: the part of its take's frame shown, and how that
/// part is scaled and placed, in pixels from the top left.
public struct ClipFraming: Equatable, Sendable {
    /// In the take's pixels.
    public var cropRect: CGRect
    /// From the take's pixels to the canvas's.
    public var transform: CGAffineTransform

    /// The app's window in a portrait frame of `capture`'s size: the whole frame, or with `aspect`,
    /// the band of that shape at its top, which the set's `aspect` laid the app out in.
    public static func window(in capture: CGSize, aspect: SetFile.Aspect?) -> CGRect {
        guard let aspect else { return CGRect(origin: .zero, size: capture) }
        let height = min(capture.height, (capture.width * aspect.height / aspect.width).rounded())
        return CGRect(x: 0, y: 0, width: capture.width, height: height)
    }

    /// The window scaled to fill `canvas`, cropping evenly on whichever axis it overflows, as
    /// a frame a little taller or wider than the preview's shape does.
    public static func filling(_ canvas: CGSize, capture: CGSize, aspect: SetFile.Aspect?) -> ClipFraming {
        let window = window(in: capture, aspect: aspect)
        let scale = max(canvas.width / window.width, canvas.height / window.height)
        let shown = CGSize(width: canvas.width / scale, height: canvas.height / scale)
        let origin = CGPoint(x: window.minX + (window.width - shown.width) / 2, y: window.minY + (window.height - shown.height) / 2)
        return ClipFraming(
            cropRect: CGRect(origin: origin, size: shown),
            transform: CGAffineTransform(translationX: -origin.x, y: -origin.y).concatenating(CGAffineTransform(scaleX: scale, y: scale)),
        )
    }

    /// The footage's frame on the canvas.
    public var canvasFrame: CGRect { cropRect.applying(transform) }
}
