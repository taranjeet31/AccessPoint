import Foundation
import AppKit
import ScreenCaptureKit
import CoreGraphics

public protocol AppDiscoveryServiceDelegate: AnyObject, Sendable {
    func appDiscoveryService(_ service: AppDiscoveryService, didUpdateAppList apps: [RemoteApp])
}

public final class AppDiscoveryService: NSObject, @unchecked Sendable {
    public weak var delegate: AppDiscoveryServiceDelegate?

    private var refreshTimer: Timer?
    private var isScanning = false
    private var cachedApps: [RemoteApp] = []

    public override init() {
        super.init()
        setupNotificationObservers()
    }

    deinit {
        stop()
    }

    private func setupNotificationObservers() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(handleAppChange), name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        center.addObserver(self, selector: #selector(handleAppChange), name: NSWorkspace.didTerminateApplicationNotification, object: nil)
    }

    @objc private func handleAppChange() {
        Task {
            await refreshAppList()
        }
    }

    public func start() {
        guard refreshTimer == nil else { return }
        Task {
            await refreshAppList()
        }
        DispatchQueue.main.async { [weak self] in
            self?.refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
                Task {
                    await self?.refreshAppList()
                }
            }
        }
    }

    public func stop() {
        DispatchQueue.main.async { [weak self] in
            self?.refreshTimer?.invalidate()
            self?.refreshTimer = nil
        }
    }

    public func refreshAppList() async {
        guard !isScanning else { return }
        isScanning = true
        defer { isScanning = false }

        do {
            let runningApps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
            let shareableContent = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            let capturableWindows = shareableContent.windows.filter { window in
                window.frame.width > 50 && window.frame.height > 50
            }

            var remoteApps: [RemoteApp] = []

            for app in runningApps {
                guard let bundleID = app.bundleIdentifier, let name = app.localizedName else { continue }

                let appWindows = capturableWindows.filter { scWindow in
                    if let owningApp = scWindow.owningApplication {
                        return owningApp.bundleIdentifier == bundleID || owningApp.processID == app.processIdentifier
                    }
                    return false
                }

                guard !appWindows.isEmpty else { continue }

                var remoteWindows: [RemoteWindow] = []

                for window in appWindows {
                    let title = window.title?.isEmpty == false ? window.title! : "\(name) Window"
                    let windowID = window.windowID

                    // Fast 160px thumbnail (~2-3KB) using CGWindowList
                    let thumbnailBase64 = captureWindowThumbnail(for: windowID)

                    let remoteWindow = RemoteWindow(
                        windowID: windowID,
                        title: title,
                        frame: window.frame,
                        thumbnailJPEG: thumbnailBase64
                    )
                    remoteWindows.append(remoteWindow)
                }

                // Fast 32x32 icon PNG (~2KB)
                let iconBase64 = encodeIconToBase64(app.icon)

                let remoteApp = RemoteApp(
                    bundleID: bundleID,
                    name: name,
                    iconPNG: iconBase64,
                    windows: remoteWindows
                )
                remoteApps.append(remoteApp)
            }

            self.cachedApps = remoteApps
            let appsToDeliver = remoteApps
            print("[AppDiscoveryService] Discovered \(appsToDeliver.count) apps. Delivering payload...")
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.appDiscoveryService(self, didUpdateAppList: appsToDeliver)
            }
        } catch {
            print("[AppDiscoveryService] Failed to fetch shareable content: \(error)")
        }
    }

    private func captureWindowThumbnail(for windowID: CGWindowID) -> String? {
        guard let cgImage = CGWindowListCreateImage(.null, .optionIncludingWindow, windowID, [.boundsIgnoreFraming, .bestResolution]) else {
            return nil
        }
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        guard width > 0, height > 0 else { return nil }

        let targetWidth: CGFloat = 160
        let targetHeight = max(targetWidth * (height / width), 100)

        guard let colorSpace = cgImage.colorSpace,
              let context = CGContext(
                data: nil,
                width: Int(targetWidth),
                height: Int(targetHeight),
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: cgImage.bitmapInfo.rawValue
              ) else {
            return nil
        }

        context.interpolationQuality = .low
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))

        guard let resizedCGImage = context.makeImage() else { return nil }
        let bitmapRep = NSBitmapImageRep(cgImage: resizedCGImage)
        guard let jpegData = bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: 0.3]) else {
            return nil
        }
        return jpegData.base64EncodedString()
    }

    private func encodeIconToBase64(_ icon: NSImage?) -> String? {
        guard let icon = icon else { return nil }
        let resized = NSImage(size: NSSize(width: 32, height: 32))
        resized.lockFocus()
        icon.draw(in: NSRect(x: 0, y: 0, width: 32, height: 32), from: NSRect(origin: .zero, size: icon.size), operation: .copy, fraction: 1.0)
        resized.unlockFocus()

        guard let tiffData = resized.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
            return nil
        }
        return pngData.base64EncodedString()
    }
}
