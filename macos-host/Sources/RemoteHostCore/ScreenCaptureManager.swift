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

        // Stream configuration matching full display pixel dimensions
        let config = SCStreamConfiguration()
        config.width = widthPx
        config.height = heightPx
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

    private var axObserver: AXObserver?
    private var currentWindowID: CGWindowID?
    public private(set) var currentWindowFrame: CGRect?
    public private(set) var currentWindowProcessID: pid_t?

    public func startWindowCapture(windowID: CGWindowID) async throws {
        let shareableContent = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let window = shareableContent.windows.first(where: { $0.windowID == windowID }) else {
            throw NSError(domain: "ScreenCaptureManager", code: -2, userInfo: [NSLocalizedDescriptionKey: "Window with ID \(windowID) not found"])
        }

        await stopCapture()

        let scale = Double(NSScreen.main?.backingScaleFactor ?? 2.0)
        let widthPx = Int(Double(window.frame.width) * scale)
        let heightPx = Int(Double(window.frame.height) * scale)

        self.currentDisplayWidthPx = max(widthPx, 100)
        self.currentDisplayHeightPx = max(heightPx, 100)
        self.currentScaleFactor = scale
        self.currentWindowID = windowID
        self.currentWindowFrame = window.frame
        self.currentWindowProcessID = window.owningApplication?.processID

        let filter: SCContentFilter
        if #available(macOS 14.0, *) {
            filter = SCContentFilter(desktopIndependentWindow: window)
        } else if let display = shareableContent.displays.first, let app = window.owningApplication {
            filter = SCContentFilter(display: display, including: [app], exceptingWindows: [])
        } else if let display = shareableContent.displays.first {
            filter = SCContentFilter(display: display, excludingWindows: [])
        } else {
            throw NSError(domain: "ScreenCaptureManager", code: -3, userInfo: [NSLocalizedDescriptionKey: "No display found for window content filter"])
        }

        let config = SCStreamConfiguration()
        config.width = max(widthPx, 100)
        config.height = max(heightPx, 100)
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        config.queueDepth = 3
        config.showsCursor = true

        let newStream = SCStream(filter: filter, configuration: config, delegate: self)
        try newStream.addStreamOutput(self, type: .screen, sampleHandlerQueue: captureQueue)

        try await newStream.startCapture()
        self.stream = newStream
        self.isCapturing = true

        setupAXObserver(for: window)

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

    private func setupAXObserver(for window: SCWindow) {
        removeAXObserver()
        guard let pid = window.owningApplication?.processID else { return }

        var observer: AXObserver?
        let axApp = AXUIElementCreateApplication(pid)

        let callback: AXObserverCallback = { observer, element, notification, refcon in
            guard let refcon = refcon else { return }
            let manager = Unmanaged<ScreenCaptureManager>.fromOpaque(refcon).takeUnretainedValue()
            Task { @MainActor in
                manager.handleAXNotification(notification: notification as String)
            }
        }

        guard AXObserverCreate(pid, callback, &observer) == .success, let observer = observer else {
            return
        }

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        AXObserverAddNotification(observer, axApp, kAXWindowMovedNotification as CFString, refcon)
        AXObserverAddNotification(observer, axApp, kAXWindowResizedNotification as CFString, refcon)
        AXObserverAddNotification(observer, axApp, kAXUIElementDestroyedNotification as CFString, refcon)

        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        self.axObserver = observer
    }

    private func removeAXObserver() {
        if let observer = axObserver {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
            self.axObserver = nil
        }
    }

    @MainActor
    private func handleAXNotification(notification: String) {
        if notification == (kAXUIElementDestroyedNotification as String) {
            print("[ScreenCaptureManager] AX Window destroyed, falling back to display capture")
            Task {
                try? await startCapture()
            }
        } else {
            Task {
                guard let windowID = self.currentWindowID else { return }
                if let shareableContent = try? await SCShareableContent.current,
                   let window = shareableContent.windows.first(where: { $0.windowID == windowID }) {
                    self.currentWindowFrame = window.frame
                    let scale = self.currentScaleFactor
                    let widthPx = Int(Double(window.frame.width) * scale)
                    let heightPx = Int(Double(window.frame.height) * scale)
                    if widthPx != self.currentDisplayWidthPx || heightPx != self.currentDisplayHeightPx {
                        self.currentDisplayWidthPx = widthPx
                        self.currentDisplayHeightPx = heightPx
                        self.delegate?.screenCaptureManager(
                            self,
                            didChangeDisplayInfo: widthPx,
                            heightPx: heightPx,
                            scaleFactor: scale
                        )
                    }
                }
            }
        }
    }

    public func stopCapture() async {
        removeAXObserver()
        currentWindowID = nil
        currentWindowFrame = nil
        currentWindowProcessID = nil

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
