import CoreMedia
import IOSurface
import ScreenCaptureKit

/// A ScreenCaptureKit stream of one window, delivering each complete frame's IOSurface on
/// the main actor.
@MainActor
final class WindowCapture: NSObject {
    private let window: SCWindow
    private var stream: SCStream?
    /// Keeps the surface of the frame currently on screen alive until the next one lands.
    private var lastBuffer: CMSampleBuffer?

    var onFrame: ((IOSurface) -> Void)?
    /// The system ended the stream on its own, for example on a display change.
    var onStopped: (() -> Void)?

    init(window: SCWindow) {
        self.window = window
    }

    func start(pointSize: CGSize, scale: CGFloat) async throws {
        guard stream == nil else { return }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let stream = SCStream(filter: filter, configuration: Self.configuration(pointSize: pointSize, scale: scale), delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: .main)
        try await stream.startCapture()
        self.stream = stream
        Log.capture.info("started for window \(self.window.windowID) at \(Int(pointSize.width))x\(Int(pointSize.height))@\(scale)")
    }

    func stop() async {
        guard let stream else { return }
        self.stream = nil
        do {
            try await stream.stopCapture()
        } catch {
            Log.capture.error("stopCapture: \(error.localizedDescription)")
        }
        lastBuffer = nil
        Log.capture.info("stopped for window \(self.window.windowID)")
    }

    func resize(pointSize: CGSize, scale: CGFloat) async {
        guard let stream else { return }
        do {
            try await stream.updateConfiguration(Self.configuration(pointSize: pointSize, scale: scale))
        } catch {
            Log.capture.error("updateConfiguration: \(error.localizedDescription)")
        }
    }

    private static func configuration(pointSize: CGSize, scale: CGFloat) -> SCStreamConfiguration {
        let config = SCStreamConfiguration()
        config.width = Int(pointSize.width * scale)
        config.height = Int(pointSize.height * scale)
        config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        config.queueDepth = 3
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = false
        config.captureResolution = .best
        config.ignoreGlobalClipSingleWindow = true
        config.ignoreShadowsSingleWindow = true
        config.includeChildWindows = true
        return config
    }

    private func handle(_ sampleBuffer: CMSampleBuffer) {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let info = attachments.first,
              let statusRaw = info[.status] as? Int,
              SCFrameStatus(rawValue: statusRaw) == .complete,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              let surface = CVPixelBufferGetIOSurface(pixelBuffer)?.takeUnretainedValue()
        else { return }
        lastBuffer = sampleBuffer
        onFrame?(surface)
    }
}

extension WindowCapture: SCStreamOutput, SCStreamDelegate {
    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen else { return }
        // Delivered on the main queue (see addStreamOutput), so the buffer never crosses a
        // thread; the compiler cannot see that through the queue parameter.
        nonisolated(unsafe) let buffer = sampleBuffer
        MainActor.assumeIsolated { handle(buffer) }
    }

    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Log.capture.error("stream stopped: \(error.localizedDescription)")
        // Only the identity is needed on the main actor, not the object itself.
        let stopped = ObjectIdentifier(stream)
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                guard let current = self.stream, ObjectIdentifier(current) == stopped else { return }
                self.stream = nil
                self.lastBuffer = nil
                self.onStopped?()
            }
        }
    }
}
