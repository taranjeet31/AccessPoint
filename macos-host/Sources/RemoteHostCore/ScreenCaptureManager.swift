import Foundation
import ScreenCaptureKit
import CoreMedia
import CoreVideo
import AppKit

public protocol ScreenCaptureManagerDelegate: AnyObject, Sendable {
    func screenCaptureManager(_ manager: ScreenCaptureManager, didOutputPixelBuffer pixelBuffer: CVPixelBuffer, timestamp: CMTime)
    func screenCaptureManager(_ manager: ScreenCaptureManager, didChangeDisplayInfo widthPx: Int, heightPx: Int, scaleFactor: Double)
    func screenCaptureManager(_ manager: ScreenCaptureManager, didFailWithError error: Error)
}

public final class ScreenCaptureManager: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    public weak var delegate: ScreenCaptureManagerDelegate?

    private var stream: SCStream?
    private let captureQueue = DispatchQueue(label: "com.remotehost.screencapture", qos: .userInteractive)
    private var isCapturing = false

    public private(set) var currentDisplayWidthPx: Int = 1920
    public private(set) var currentDisplayHeightPx: Int = 1080
    public private(set) var currentScaleFactor: Double = 2.0

    public override init() {
        super.init()
    }

    public func startCapture() async throws {
        guard !isCapturing else { return }

        // Get shareable content
        let shareableContent = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)

        guard let display = shareableContent.displays.first else {
            throw NSError(domain: "ScreenCaptureManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "No available display found for capture"])
        }

        let mainScreen = NSScreen.main
        let scale = Double(mainScreen?.backingScaleFactor ?? 2.0)
        let widthPx = Int(Double(display.width) * (scale > 1.0 ? scale : 1.0))
        let heightPx = Int(Double(display.height) * (scale > 1.0 ? scale : 1.0))

        currentDisplayWidthPx = widthPx
        currentDisplayHeightPx = heightPx
        currentScaleFactor = scale

        // Create content filter for the display
        let filter = SCContentFilter(display: display, excludingWindows: [])

        // Stream configuration
        let config = SCStreamConfiguration()
        config.width = display.width
        config.height = display.height
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30) // 30 fps
        config.queueDepth = 3
        config.showsCursor = true

        let newStream = SCStream(filter: filter, configuration: config, delegate: self)
        try newStream.addStreamOutput(self, type: .screen, sampleHandlerQueue: captureQueue)

        try await newStream.startCapture()
        self.stream = newStream
        self.isCapturing = true

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.screenCaptureManager(
                self,
                didChangeDisplayInfo: self.currentDisplayWidthPx,
                heightPx: self.currentDisplayHeightPx,
                scaleFactor: self.currentScaleFactor
            )
        }
    }

    public func stopCapture() async {
        guard isCapturing, let stream = stream else { return }
        do {
            try await stream.stopCapture()
        } catch {
            print("[ScreenCaptureManager] Error stopping capture: \(error)")
        }
        self.stream = nil
        self.isCapturing = false
    }

    // MARK: - SCStreamOutput

    public func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let presentationTimestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        delegate?.screenCaptureManager(self, didOutputPixelBuffer: pixelBuffer, timestamp: presentationTimestamp)
    }

    // MARK: - SCStreamDelegate

    public func stream(_ stream: SCStream, didStopWithError error: Error) {
        print("[ScreenCaptureManager] Stream stopped with error: \(error)")
        isCapturing = false
        delegate?.screenCaptureManager(self, didFailWithError: error)
    }
}
