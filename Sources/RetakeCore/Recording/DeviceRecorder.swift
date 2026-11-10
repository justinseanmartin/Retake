import AVFoundation
import Foundation

/// Records a USB-connected device's screen and sound, as QuickTime's "New Movie Recording" does: at
/// the size and frame rate the device sends, which on some iPads is less than its screen's, with
/// nothing shown on the device. See README.md, "Takes".
public final class DeviceRecorder: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let audioOutput = AVCaptureAudioDataOutput()
    /// The capture's queue, the only one the writer is touched on while recording.
    private let queue = DispatchQueue(label: "retake.recorder")
    private var writer: TakeWriter?
    private var facing: TakeWriter.Facing = .portrait
    /// The last frame the device sent: what a capture takes. The device sends its screen 60 times
    /// a second whether or not it changes, so the last is at most a sixtieth of a second old.
    private var latest: CVPixelBuffer?

    /// The last frame's samples, and each recent frame's arrival and difference from the one before,
    /// for `RotationWatch`; kept only while a turn is watched for.
    private var samples: [UInt8]?
    private var motion: [(at: Double, difference: Double)] = []
    /// When a turn was last asked for, which frames are watched from until it's drawn.
    private var turnAsked: Double?

    /// How long a capture waits for the first frame, when none has come yet.
    public static let firstFrameTimeout = 5.0

    /// How long to wait for the first frames after recording starts: they take 2 to 3 seconds.
    public static let firstFramesTimeout = 15.0
    /// How much must be written before recording counts as started, since the writer has failed a
    /// fifth of a second in (-12737, cause unknown).
    public static let startedAfter = 0.5

    /// Opens the device's screen for capture, by the identity `devices add` stored for it, or its
    /// name. An environment problem (3) when it isn't offered: it's on Wi-Fi, or not connected.
    public init(_ device: CaptureDevice, finder: some CaptureDeviceFinder = ScreenCaptureDevices()) throws(RetakeError) {
        _ = finder.captureDevices(waitingFor: device.name, timeout: 5)
        guard let capture = AVCaptureDevice(uniqueID: device.uniqueID)
            ?? AVCaptureDevice.DiscoverySession(deviceTypes: [.external], mediaType: .muxed, position: .unspecified).devices.first(where: { $0.localizedName == device.name })
        else {
            throw RetakeError(.environment, "\(device.name)'s screen isn't offered for recording: is it connected by USB, and unlocked?")
        }
        super.init()
        do {
            try session.addInput(AVCaptureDeviceInput(device: capture))
        } catch {
            throw RetakeError(.environment, "Couldn't open \(device.name)'s screen for recording: \(error.localizedDescription)")
        }
        session.addOutput(videoOutput)
        session.addOutput(audioOutput)
        // The device sends full-range YUV, which the encoder writes unconverted under a video-range
        // tag, stretched and oversaturated on playback. From BGRA, the encoder converts it itself.
        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        videoOutput.setSampleBufferDelegate(self, queue: queue)
        audioOutput.setSampleBufferDelegate(self, queue: queue)
    }

    /// Starts recording to `url`, returning once it has truly started; a writer that fails just
    /// after starting is started over, up to three times. With `take`, the movie says how it was
    /// made, from the take's log as it stands before recording.
    public func start(writingTo url: URL, describing take: TakeLog? = nil) async throws(RetakeError) {
        session.startRunning()
        for attempt in 1...3 {
            let writer = TakeWriter(writingTo: url, metadata: take.map(MovieMetadata.take) ?? [])
            queue.sync {
                writer.facing = facing
                self.writer = writer
            }
            let deadline = Date().addingTimeInterval(Self.firstFramesTimeout)
            while Date() < deadline {
                let (written, failed) = queue.sync { (writer.written, writer.failed) }
                if failed { break }
                if written >= Self.startedAfter { return }
                try? await Task.sleep(for: .milliseconds(20))
            }
            let failed = queue.sync { writer.failed }
            queue.sync {
                self.writer = nil
                writer.cancel()
            }
            guard failed, attempt < 3 else {
                session.stopRunning()
                throw RetakeError(.environment, failed ? "The recording failed to start three times." : "No frames arrived from the device's screen in \(Int(Self.firstFramesTimeout)) s.")
            }
        }
    }

    /// Opens the device's screen without recording it, for captures alone, returning once its first
    /// frame has arrived. `close` closes it.
    public func open() async throws(RetakeError) {
        session.startRunning()
        let deadline = Date().addingTimeInterval(Self.firstFramesTimeout)
        while Date() < deadline {
            if queue.sync(execute: { latest != nil }) { return }
            try? await Task.sleep(for: .milliseconds(20))
        }
        session.stopRunning()
        throw RetakeError(.environment, "No frames arrived from the device's screen in \(Int(Self.firstFramesTimeout)) s.")
    }

    /// Closes the screen `open` opened.
    public func close() {
        session.stopRunning()
    }

    /// The screen as it is now: the last frame the device sent, or the first, waiting for it.
    public func frame() async throws(RetakeError) -> ScreenFrame {
        let deadline = Date().addingTimeInterval(Self.firstFrameTimeout)
        repeat {
            if let latest = queue.sync(execute: { self.latest }) { return ScreenFrame(pixels: latest) }
            try? await Task.sleep(for: .milliseconds(10))
        } while Date() < deadline
        throw RetakeError(.environment, "No frames arrived from the device's screen in \(Int(Self.firstFrameTimeout)) s, so nothing could be captured.")
    }

    /// When the movie's first frame was, on the Mac's clock: now, less how long ago that was on the
    /// capture clock its frames are stamped with.
    public var startedAt: Date { Date().addingTimeInterval(-elapsed) }

    /// Seconds since the movie's first frame, on the capture clock its frames are stamped with.
    public var elapsed: Double {
        queue.sync {
            guard let start = writer?.start else { return 0 }
            return (CMClockGetTime(session.synchronizationClock ?? CMClockGetHostTimeClock()) - start).seconds
        }
    }

    /// Says which way the device is about to face, before it's turned, so frames of the new shape
    /// are stored facing as the device does.
    public func turning(to facing: TakeWriter.Facing) {
        queue.sync {
            self.facing = facing
            writer?.facing = facing
            turnAsked = ProcessInfo.processInfo.systemUptime
            motion = []
        }
    }

    /// Waits for the rotation of the turn last asked for to finish, as `RotationWatch` decides.
    public func rotated() async {
        while true {
            let (asked, motion) = queue.sync { (turnAsked, motion) }
            guard let asked, !RotationWatch.isOver(motion, asked: asked, now: ProcessInfo.processInfo.systemUptime) else { break }
            try? await Task.sleep(for: .milliseconds(20))
        }
        queue.sync {
            turnAsked = nil
            motion = []
            samples = nil
        }
    }

    /// Stops recording and finishes the movie. The capture stops even when the file can't be
    /// finished: one left running coincided with the device's screen freezing.
    public func stop() async throws(RetakeError) -> TakeWriter.Summary {
        let writer: TakeWriter? = queue.sync {
            defer { self.writer = nil }
            return self.writer
        }
        defer { session.stopRunning() }
        guard let writer else { throw RetakeError(.failed, "Nothing was recorded.") }
        return try await writer.finish()
    }

    public func captureOutput(_ output: AVCaptureOutput, didOutput sample: CMSampleBuffer, from _: AVCaptureConnection) {
        if output === videoOutput, let pixels = sample.imageBuffer {
            latest = pixels
            if turnAsked != nil {
                let samples = RotationWatch.samples(pixels)
                motion.append((ProcessInfo.processInfo.systemUptime, self.samples.map { RotationWatch.difference($0, samples) } ?? 0))
                self.samples = samples
            }
        }
        guard let writer else { return }
        if output === videoOutput {
            writer.appendVideo(sample)
        } else {
            writer.appendAudio(sample)
        }
    }
}

extension TakeWriter.Facing {
    /// Which way a scene's `orientation` faces the device.
    public init(_ orientation: SceneFile.Orientation) {
        switch orientation {
        case .portrait: self = .portrait
        case .portraitUpsideDown: self = .portraitUpsideDown
        case .landscapeLeft: self = .landscapeLeft
        case .landscapeRight: self = .landscapeRight
        }
    }
}
