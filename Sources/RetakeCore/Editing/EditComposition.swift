import AVFoundation
import CoreGraphics

/// A video's picture as AVFoundation plays it: each clip's stretch of its take, laid out as a cut
/// plan places it, at its speed, framed on the preview's canvas, and cross-fading where the plan
/// says. Clips alternate between two video tracks, so one can fade in over the end of the one
/// before. Where the device turned during a clip, its framing changes as the frames change shape.
/// Sound, and what's drawn over the picture, come with later parts of the editor.
public struct EditComposition: @unchecked Sendable {
    public let composition: AVMutableComposition
    public let videoComposition: AVMutableVideoComposition
    public let plan: CutPlan
    /// Where each clip's footage sits on the canvas, for what's drawn over it, from when in the video:
    /// one framing a clip, or more where the device turned.
    public let framings: [[(at: Double, framing: ClipFraming)]]
    /// When in the video each turn is blurred, as its clip's `turnBlur` says; the export blurs them.
    public let turnBlurs: [ClosedRange<Double>]

    static let timescale: CMTimeScale = 600

    static func time(_ seconds: Double) -> CMTime {
        CMTime(seconds: seconds, preferredTimescale: timescale)
    }

    /// The composition of `plan`, each clip from the movie of its take in `movies`, framed by its
    /// take's step log in `logs` (its `aspect`, and the shapes its frames took), on a canvas of
    /// `spec`'s size behind which is `background`. A take without a log is framed as one shape,
    /// filling the screen.
    public static func make(
        _ plan: CutPlan,
        movies: [String: URL],
        logs: [String: TakeLog] = [:],
        spec: PreviewSpec,
        background: Color,
    ) async throws(RetakeError) -> EditComposition {
        let composition = AVMutableComposition()
        let tracks = try (0..<2).map { _ throws(RetakeError) in try addTrack(to: composition) }
        var framings: [[(at: Double, framing: ClipFraming)]] = []
        var turnBlurs: [ClosedRange<Double>] = []
        // A track doesn't keep its asset alive, and inserting from one whose asset is gone fails.
        var assets: [AVURLAsset] = []
        do {
            for (index, placement) in plan.placements.enumerated() {
                guard let movie = movies[placement.take] else {
                    throw RetakeError(.failed, "There's no movie of \(placement.take)'s take to cut from.")
                }
                let asset = AVURLAsset(url: movie)
                assets.append(asset)
                guard let source = try await asset.loadTracks(withMediaType: .video).first else {
                    throw RetakeError(.failed, "\(movie.lastPathComponent) has no picture.")
                }
                let size = try await source.load(.naturalSize)
                let log = logs[placement.take]
                let stretches = Self.stretches(of: placement, shapes: log?.shapes ?? [])
                framings.append(stretches.map { at, turn in
                    (placement.videoTime(at), ClipFraming.framing(spec.size, stored: size, turned: turn, aspect: log?.aspect, turns: placement.turns, screen: log?.screen))
                })
                if let blur = placement.turnBlur {
                    for (at, _) in stretches.dropFirst() {
                        let moment = placement.videoTime(at)
                        turnBlurs.append(max(placement.start, moment - blur / 2)...min(placement.end, moment + blur / 2))
                    }
                }
                let range = CMTimeRange(start: time(placement.from), end: time(placement.to))
                let at = time(placement.start)
                try tracks[index % 2].insertTimeRange(range, of: source, at: at)
                tracks[index % 2].scaleTimeRange(CMTimeRange(start: at, duration: range.duration), toDuration: time(placement.duration))
            }
        } catch let error as RetakeError {
            throw error
        } catch {
            throw RetakeError(.failed, "Couldn't lay the clips out: \(error.localizedDescription)")
        }

        withExtendedLifetime(assets) {}

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = spec.size
        videoComposition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(spec.framesPerSecond))
        videoComposition.instructions = instructions(plan, tracks: tracks, framings: framings, background: background)
        return EditComposition(composition: composition, videoComposition: videoComposition, plan: plan, framings: framings, turnBlurs: turnBlurs)
    }

    /// The stretches of the clip's take it plays in each shape, from where in the take each starts,
    /// with how its frames were turned: the shape in force at the clip's `from`, then each change
    /// before its `to`.
    static func stretches(of placement: CutPlan.Placement, shapes: [TakeWriter.ShapeChange]) -> [(at: Double, turn: Int)] {
        let sorted = shapes.sorted { $0.at < $1.at }
        let first = sorted.last { $0.at <= placement.from }?.turn ?? 0
        return [(placement.from, first)] + sorted.filter { $0.at > placement.from && $0.at < placement.to }.map { ($0.at, $0.turn) }
    }

    /// One instruction for each stretch a clip plays alone, and one for each cross-fade, the clip
    /// coming in on top and fading in over the one going out.
    static func instructions(
        _ plan: CutPlan, tracks: [AVMutableCompositionTrack], framings: [[(at: Double, framing: ClipFraming)]], background: Color,
    ) -> [AVVideoCompositionInstruction] {
        func layer(_ index: Int) -> AVMutableVideoCompositionLayerInstruction {
            let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: tracks[index % 2])
            for (number, (at, framing)) in framings[index].enumerated() {
                let when = number == 0 ? .zero : time(at)
                layer.setTransform(framing.transform, at: when)
                layer.setCropRectangle(framing.cropRect, at: when)
            }
            return layer
        }
        func instruction(_ range: CMTimeRange, _ layers: [AVMutableVideoCompositionLayerInstruction]) -> AVMutableVideoCompositionInstruction {
            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = range
            instruction.layerInstructions = layers
            instruction.backgroundColor = CGColor(srgbRed: background.red, green: background.green, blue: background.blue, alpha: background.alpha)
            return instruction
        }

        var instructions: [AVVideoCompositionInstruction] = []
        var cursor = time(0)
        for (index, placement) in plan.placements.enumerated() {
            let next = plan.placements.indices.contains(index + 1) ? plan.placements[index + 1] : nil
            let fadeOut = next?.crossfade ?? 0
            let alone = CMTimeRange(start: cursor, end: time(placement.end - fadeOut))
            instructions.append(instruction(alone, [layer(index)]))
            if fadeOut > 0 {
                let overlap = CMTimeRange(start: alone.end, end: time(placement.end))
                let incoming = layer(index + 1)
                incoming.setOpacityRamp(fromStartOpacity: 0, toEndOpacity: 1, timeRange: overlap)
                instructions.append(instruction(overlap, [incoming, layer(index)]))
            }
            cursor = time(placement.end)
        }
        return instructions
    }

    static func addTrack(to composition: AVMutableComposition) throws(RetakeError) -> AVMutableCompositionTrack {
        guard let track = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw RetakeError(.failed, "Couldn't add a video track to the composition.")
        }
        return track
    }
}
