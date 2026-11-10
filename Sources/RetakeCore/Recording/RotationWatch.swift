import CoreVideo
import Foundation

/// When the rotation a turn draws has finished, from how much each frame of the device's screen
/// differs from the one before. A rotation moves the whole screen, by more than 5 levels of 255 a
/// frame on average, where a still screen's frames differ by at most 0.6 in the stream's
/// compression; so it's over once `quietFor` passes with no frame differing by over `movingAbove`.
/// A turn that draws nothing, for a frame showing nothing that turns, is over at `startWithin`.
public enum RotationWatch {
    public static let movingAbove = 2.0
    public static let quietFor = 0.15
    public static let startWithin = 2.0
    public static let timeout = 3.0

    /// Whether the rotation is over at `now`, from each frame's arrival and how much it differed
    /// from the one before, infinitely for one of another size, the turn having been asked for at
    /// `asked`, each in seconds on one clock.
    public static func isOver(_ frames: [(at: Double, difference: Double)], asked: Double, now: Double) -> Bool {
        if now - asked >= timeout { return true }
        let moving = frames.filter { $0.at >= asked && $0.difference > movingAbove }
        guard let last = moving.last else { return now - asked >= startWithin }
        return now - last.at >= quietFor
    }

    /// The average difference between two frames' samples, from a grid over each; infinite for
    /// frames of different sizes.
    static func difference(_ a: [UInt8], _ b: [UInt8]) -> Double {
        guard a.count == b.count, a.count > 8, a.prefix(8) == b.prefix(8) else { return .infinity }
        var total = 0
        for index in 8..<a.count { total += abs(Int(a[index]) - Int(b[index])) }
        return Double(total) / Double(a.count - 8)
    }

    /// Samples across and down.
    static let grid = 32

    /// A BGRA frame's size, then its blue, green and red at each point of a grid.
    static func samples(_ pixels: CVPixelBuffer) -> [UInt8] {
        CVPixelBufferLockBaseAddress(pixels, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixels, .readOnly) }
        let width = CVPixelBufferGetWidth(pixels), height = CVPixelBufferGetHeight(pixels), row = CVPixelBufferGetBytesPerRow(pixels)
        var samples = withUnsafeBytes(of: (UInt32(width), UInt32(height))) { Array($0) }
        guard CVPixelBufferGetPixelFormatType(pixels) == kCVPixelFormatType_32BGRA, let base = CVPixelBufferGetBaseAddress(pixels) else { return samples }
        let bytes = base.assumingMemoryBound(to: UInt8.self)
        for y in 0..<grid {
            for x in 0..<grid {
                let at = bytes + (y * height / grid) * row + (x * width / grid) * 4
                samples += [at[0], at[1], at[2]]
            }
        }
        return samples
    }
}
