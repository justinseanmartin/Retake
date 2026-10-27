import AVFoundation
import CoreGraphics

/// A video's picture as AVFoundation plays it: each clip's stretch of its take, laid out as a cut
/// plan places it, at its speed, framed on the preview's canvas, and cross-fading where the plan
/// says. Clips alternate between two video tracks, so one can fade in over the end of the one
/// before. Sound, turns and what's drawn over the picture come with later parts of the editor.
public struct EditComposition: @unchecked Sendable {
    public let composition: AVMutableComposition
    public let videoComposition: AVMutableVideoComposition
    public let plan: CutPlan
    /// Where each clip's footage sits on the canvas, for what's drawn over it.
    public let framings: [ClipFraming]

    static let timescale: CMTimeScale = 600

    static func time(_ seconds: Double) -> CMTime {
        CMTime(seconds: seconds, preferredTimescale: timescale)
    }

    /// The composition of `plan`, each clip from the movie of its take in `movies` and framed by
    /// its take's `aspect`, on a canvas of `spec`'s size behind which is `background`.
    public static func make(
        _ plan: CutPlan,
        movies: [String: URL],
        aspects: [String: SetFile.Aspect] = [:],
        spec: PreviewSpec,
        background: Color,
    ) async throws(RetakeError) -> EditComposition {
        let composition = AVMutableComposition()
        let tracks = try (0..<2).map { _ throws(RetakeError) in try addTrack(to: composition) }
        var framings: [ClipFraming] = []
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
                framings.append(.filling(spec.size, capture: size, aspect: aspects[placement.take]))
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
        return EditComposition(composition: composition, videoComposition: videoComposition, plan: plan, framings: framings)
    }

    /// One instruction for each stretch a clip plays alone, and one for each cross-fade, the clip
    /// coming in on top and fading in over the one going out.
    static func instructions(
        _ plan: CutPlan, tracks: [AVMutableCompositionTrack], framings: [ClipFraming], background: Color,
    ) -> [AVVideoCompositionInstruction] {
        func layer(_ index: Int) -> AVMutableVideoCompositionLayerInstruction {
            let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: tracks[index % 2])
            layer.setTransform(framings[index].transform, at: .zero)
            layer.setCropRectangle(framings[index].cropRect, at: .zero)
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
