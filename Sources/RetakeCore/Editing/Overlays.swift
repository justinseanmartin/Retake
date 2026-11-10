import CoreGraphics
import Foundation

/// What's drawn over a video's picture, each thing placed on the video's clock and on its canvas:
/// captions, the take's touches, spotlights, blurs and stills. Worked out from the edit, its cut
/// plan and its takes' step logs, apart from the drawing, so it can be tested. See README.md, "What a
/// clip can do".
public struct Overlays: Equatable, Sendable {
    public struct Caption: Equatable, Sendable {
        public var text: String
        public var color: Color
        /// Its center, as a share of the video's height from the top.
        public var y: Double
        public var symbol: Edit.Symbol?
        public var start: Double
        public var end: Double
    }

    /// A touch the take made: a tap by point, or a drag from one point to another over `duration`.
    public struct Touch: Equatable, Sendable {
        public var from: CGPoint
        public var to: CGPoint?
        public var start: Double
        public var duration: Double
        public var color: Color = .white
    }

    public struct Spotlight: Equatable, Sendable {
        public var rect: CGRect
        public var color: Color
        public var start: Double
        public var end: Double
    }

    public struct Blur: Equatable, Sendable {
        public var rect: CGRect
        /// The Gaussian sigma, in canvas pixels: the edit's `radius`, in screen points, scaled as the
        /// rectangle is.
        public var sigma: Double
        public var start: Double
        public var end: Double
    }

    /// A frame of a take, popped in over its clip: the `take` scene's take at `at` seconds,
    /// cropped to `crop`, the `index`th of `count` in its clip.
    public struct Still: Equatable, Sendable {
        public var take: String
        public var at: Double
        public var crop: CGRect
        public var index: Int
        public var count: Int
        public var start: Double
        public var end: Double
        /// Whether it pops out at `end`, rather than staying to its clip's.
        public var popsOut = false
    }

    public var captions: [Caption] = []
    public var touches: [Touch] = []
    public var spotlights: [Spotlight] = []
    public var blurs: [Blur] = []
    public var stills: [Still] = []
    /// A clip's stillsBackground, from when it fades in to the clip's end.
    public var stillsBackgrounds: [StillsBackground] = []

    public struct StillsBackground: Equatable, Sendable {
        public var color: Color
        public var start: Double
        public var end: Double
    }

    /// A clip's card, covering the canvas from `start` to `end`, fading in over `fadeIn` and out over
    /// `fadeOut`.
    public var cards: [Card] = []

    public struct Card: Equatable, Sendable {
        public var color: Color
        public var start: Double
        public var end: Double
        public var fadeIn: Double
        public var fadeOut: Double
    }

    /// The overlays of `video`, as `plan` places its clips, each framed as `framings` says (from
    /// `EditComposition`), its anchors and elements resolved in its scene's take in `timelines`.
    /// Fails (1), naming where, for an anchor or element that doesn't resolve, a caption that ends
    /// before it starts.
    public static func make(
        _ video: Edit, plan: CutPlan, framings: [[(at: Double, framing: ClipFraming)]], timelines: [String: TakeTimeline],
    ) throws(RetakeError) -> Overlays {
        var overlays = Overlays()
        let indices = Dictionary(video.clips.enumerated().compactMap { index, clip in clip.id.map { ($0, index) } }, uniquingKeysWith: { first, _ in first })
        for (index, clip) in video.clips.enumerated() {
            let name = "clips[\(index)]"
            let placement = plan.placements[index]
            guard let timeline = timelines[clip.take] else { throw RetakeError(.failed, "\(name): there's no take of \(clip.take) to cut it from.") }
            func time(_ anchor: Anchor?, _ what: String, in timeline: TakeTimeline? = nil, of placement: CutPlan.Placement? = nil) throws(RetakeError) -> Double? {
                guard let anchor else { return nil }
                do {
                    return (placement ?? plan.placements[index]).videoTime(try (timeline ?? timelines[clip.take]!).time(of: anchor))
                } catch {
                    throw RetakeError(.failed, "\(name).\(what): \(error.message).")
                }
            }
            func framing(at videoTime: Double) -> ClipFraming {
                framings[index].last { $0.at <= videoTime + 1e-9 }?.framing ?? framings[index][0].framing
            }
            func region(_ region: Edit.Region, at videoTime: Double, padding: Double = 0, _ what: String) throws(RetakeError) -> CGRect {
                let points: CGRect
                switch region {
                case .rect(let rect):
                    let takeTime = placement.from + (videoTime - placement.start) * placement.speed
                    points = rect.within(CGRect(origin: .zero, size: timeline.screen(at: takeTime)))
                case .element(let element, let part):
                    let takeTime = placement.from + (videoTime - placement.start) * placement.speed
                    let found: ScreenElement
                    do {
                        found = try timeline.element(element, at: takeTime)
                    } catch {
                        throw RetakeError(.failed, "\(name).\(what).element: \(error.message).")
                    }
                    // `element(_:at:)` finds only what's on screen, so it has a frame.
                    let frame = found.frame ?? ScreenElement.Rect(x: 0, y: 0, width: 0, height: 0)
                    let whole = CGRect(x: frame.x, y: frame.y, width: frame.width, height: frame.height)
                    points = part?.within(whole) ?? whole
                }
                return framing(at: videoTime).canvasRect(points.insetBy(dx: -padding, dy: -padding))
            }

            // A caption that doesn't say when keeps clear of the cross-fades: it comes up once its
            // clip has faded in, and goes as the next one starts to fade in over it.
            func shown(until index: Int) -> Double {
                let next = plan.placements.indices.contains(index + 1) ? plan.placements[index + 1].crossfade : 0
                return plan.placements[index].end - next
            }
            for (captionIndex, caption) in clip.captions.enumerated() {
                let what = "captions[\(captionIndex)]"
                let start = try time(caption.from, "\(what).from") ?? placement.start + placement.crossfade
                var end = shown(until: index)
                if let to = caption.to {
                    if let later = to.clip {
                        guard let laterIndex = indices[later], laterIndex > index else {
                            throw RetakeError(.failed, "\(name).\(what).to: there's no later clip \"\(later)\".")
                        }
                        let laterPlacement = plan.placements[laterIndex]
                        end = try time(to.anchor, "\(what).to", in: timelines[video.clips[laterIndex].take], of: laterPlacement) ?? shown(until: laterIndex)
                    } else {
                        end = try time(to.anchor, "\(what).to") ?? shown(until: index)
                    }
                }
                guard end > start else { throw RetakeError(.failed, "\(name).\(what) ends before it starts.") }
                overlays.captions.append(Caption(text: caption.text, color: caption.color, y: caption.y, symbol: caption.symbol, start: start, end: end))
            }

            if clip.touches {
                var stepColors: [Int: Color] = [:]
                for (colorIndex, entry) in clip.touchColors.enumerated() {
                    let what = "\(name).touchColors[\(colorIndex)]"
                    let start: Double
                    do {
                        start = try timeline.place(of: entry.step).start
                    } catch {
                        throw RetakeError(.failed, "\(what).step: \(error.message).")
                    }
                    guard let step = timeline.steps.first(where: { $0.start == start && $0.touch != nil }),
                          step.start >= placement.from, step.start < placement.to else {
                        throw RetakeError(.failed, "\(what).step: it doesn't touch the screen within the clip.")
                    }
                    stepColors[step.number] = entry.color
                }
                for step in timeline.log.steps where step.start >= placement.from && step.start < placement.to {
                    guard let touch = step.touch else { continue }
                    let at = placement.videoTime(step.start)
                    let toCanvas = framing(at: at).pointsToCanvas
                    overlays.touches.append(Touch(
                        from: CGPoint(x: touch.x, y: touch.y).applying(toCanvas),
                        to: step.touchEnd.map { CGPoint(x: $0.x, y: $0.y).applying(toCanvas) },
                        start: at, duration: (step.touchDuration ?? (step.end - step.start)) / placement.speed,
                        color: stepColors[step.number] ?? clip.touchColor ?? video.touchColor,
                    ))
                }
            }

            if let spotlight = clip.spotlight {
                let start = try time(spotlight.from, "spotlight.from") ?? placement.start
                let end = try time(spotlight.to, "spotlight.to") ?? placement.end
                let rect = try region(spotlight.region, at: start, padding: spotlight.padding, "spotlight")
                overlays.spotlights.append(Spotlight(rect: rect, color: spotlight.color, start: start, end: end))
            }
            for (blurIndex, blur) in clip.blurs.enumerated() {
                let what = "blurs[\(blurIndex)]"
                let start = try time(blur.from, "\(what).from") ?? placement.start
                let end = try time(blur.to, "\(what).to") ?? placement.end
                let rect = try region(blur.region, at: start, what)
                // The region found, its framing turns points into canvas pixels.
                let toCanvas = framing(at: start).pointsToCanvas
                let scale = sqrt(abs(toCanvas.a * toCanvas.d - toCanvas.b * toCanvas.c))
                overlays.blurs.append(Blur(rect: rect, sigma: blur.radius * scale, start: start, end: end))
            }

            let stillsIn = try time(clip.stillsIn, "stillsIn") ?? placement.start + Overlays.firstStill
            let stillsOut = try time(clip.stillsOut, "stillsOut")
            for (stillIndex, still) in clip.stills.enumerated() {
                guard let stillTimeline = timelines[still.take] else {
                    throw RetakeError(.failed, "\(name).stills[\(stillIndex)]: there's no take of \(still.take) to take it from.")
                }
                let at: Double
                do {
                    at = try stillTimeline.time(of: still.at)
                } catch {
                    throw RetakeError(.failed, "\(name).stills[\(stillIndex)].at: \(error.message).")
                }
                // They pop in one after another, from stillsIn or as the clip starts, and stay to its
                // end, or pop out one after another in the same order.
                let start = stillsIn + Double(stillIndex) * Overlays.stillsApart
                let end = stillsOut.map { min($0 + Double(stillIndex) * Overlays.stillsApart, placement.end) } ?? placement.end
                guard end > start + OverlayLayers.stillPopOut else {
                    throw RetakeError(.failed, "\(name).stillsOut: stills[\(stillIndex)] would pop out before it has popped in, at \(TakeTimeline.seconds(start)) into the video.")
                }
                overlays.stills.append(Still(
                    take: still.take, at: at, crop: framings[index][0].framing.cropRect, index: stillIndex, count: clip.stills.count,
                    start: start, end: end, popsOut: stillsOut != nil,
                ))
            }
            if let card = clip.card {
                // Over the whole clip, it fades with the cross-fades either side, so it comes in as
                // the clip's picture would; over a stretch of its own, it fades quickly.
                let fadeOut = plan.placements.indices.contains(index + 1) ? plan.placements[index + 1].crossfade : 0
                let start = try time(card.from, "card.from") ?? placement.start
                let end = try time(card.to, "card.to") ?? placement.end
                guard end > start else { throw RetakeError(.failed, "\(name).card ends before it starts.") }
                overlays.cards.append(Card(
                    color: card.color, start: start, end: end,
                    fadeIn: card.from == nil ? placement.crossfade : min(Overlays.cardFade, (end - start) / 2),
                    fadeOut: card.to == nil ? fadeOut : min(Overlays.cardFade, (end - start) / 2),
                ))
            }
            if let color = clip.stillsBackground, !clip.stills.isEmpty {
                // Faded in by the time the first still pops in.
                overlays.stillsBackgrounds.append(StillsBackground(color: color, start: max(stillsIn - OverlayLayers.stillsBackgroundFade, placement.start), end: placement.end))
            }
        }
        return overlays
    }

    /// Seconds a card over a stretch of its own takes to fade in, and out.
    static let cardFade = 0.25
    /// Seconds into its clip the first still pops in.
    static let firstStill = 0.35
    /// Seconds between one still popping in, or out, and the next.
    static let stillsApart = 0.22
}
