// Writes the README's poster for a video: its frame at a time, with a play button over it, as a
// JPEG, since GitHub plays no video in a README and links from an image instead.
//
// Usage: swift Scripts/showcase-poster.swift <movie> <poster.jpg> [<seconds>]
import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let arguments = CommandLine.arguments
guard arguments.count == 3 || arguments.count == 4 else {
    FileHandle.standardError.write(Data("Usage: swift Scripts/showcase-poster.swift <movie> <poster.jpg> [<seconds>]\n".utf8))
    exit(2)
}
let movie = URL(fileURLWithPath: arguments[1])
let poster = URL(fileURLWithPath: arguments[2])
let seconds = arguments.count == 4 ? Double(arguments[3]) ?? 0 : 0

let generator = AVAssetImageGenerator(asset: AVURLAsset(url: movie))
generator.appliesPreferredTrackTransform = true
generator.requestedTimeToleranceBefore = .zero
generator.requestedTimeToleranceAfter = .zero
let frame = try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)).image

let width = frame.width, height = frame.height
guard let context = CGContext(
    data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue,
) else { fatalError("couldn't make a \(width)×\(height) image") }
context.draw(frame, in: CGRect(x: 0, y: 0, width: width, height: height))

let diameter = CGFloat(min(width, height)) * 0.16
// Centred in the frame, where a play button is looked for.
let center = CGPoint(x: CGFloat(width) / 2, y: CGFloat(height) / 2)
context.setShadow(offset: .zero, blur: diameter * 0.15, color: CGColor(gray: 0, alpha: 0.4))
context.setFillColor(CGColor(gray: 0, alpha: 0.6))
context.fillEllipse(in: CGRect(x: center.x - diameter / 2, y: center.y - diameter / 2, width: diameter, height: diameter))
context.setShadow(offset: .zero, blur: 0)
// The triangle sits a little right of the middle, where it looks centred.
let side = diameter * 0.42
let left = center.x - side * 0.36
context.setFillColor(CGColor(gray: 1, alpha: 1))
context.move(to: CGPoint(x: left, y: center.y - side / 2))
context.addLine(to: CGPoint(x: left, y: center.y + side / 2))
context.addLine(to: CGPoint(x: left + side * 0.87, y: center.y))
context.closePath()
context.fillPath()

guard let image = context.makeImage(),
      let destination = CGImageDestinationCreateWithURL(poster as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
else { fatalError("couldn't write \(poster.path)") }
CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
guard CGImageDestinationFinalize(destination) else { fatalError("couldn't write \(poster.path)") }
