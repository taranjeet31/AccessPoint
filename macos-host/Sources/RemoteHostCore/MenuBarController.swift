import AppKit
import SwiftUI
import WebRTC

@MainActor
public final class MenuBarController: NSObject, SignalingClientDelegate, WebRTCClientDelegate {
    private var statusItem: NSStatusItem?
    private var pairingWindow: NSWindow?

    public let signalingClient: SignalingClient
    public let webRTCClient: WebRTCClient
    public let screenCaptureManager: ScreenCaptureManager
    public let inputInjector: InputInjector
    public let keychainStore: KeychainStore
    public let permissionManager: PermissionManager
    public let sessionIndicator: SessionIndicatorWindow

    @Published public var pairingCode: String = ""
    @Published public var remainingSeconds: Int = 300
    @Published public var pendingRequestDeviceName: String?
    @Published public var pendingRequestDeviceId: String?

    private var activePeerDeviceId: String?
    private var activePeerDeviceName: String?
    private var countdownTimer: Timer?

    public override init() {
        self.signalingClient = SignalingClient()
        self.webRTCClient = WebRTCClient()
        self.screenCaptureManager = ScreenCaptureManager()
        self.inputInjector = InputInjector.shared
        self.keychainStore = KeychainStore.shared
        self.permissionManager = PermissionManager.shared
        self.sessionIndicator = SessionIndicatorWindow.shared
        super.init()

        self.signalingClient.delegate = self
        self.webRTCClient.delegate = self
        self.screenCaptureManager.delegate = self
    }

    public func start() {
        setupStatusItem()
        signalingClient.connect()
        signalingClient.requestTurnCredentials()

        // Check permissions at startup
        if !permissionManager.isAccessibilityGranted {
            _ = permissionManager.requestAccessibilityPermission()
        }
        if !permissionManager.isScreenRecordingGranted {
            _ = permissionManager.requestScreenRecordingPermission()
        }
    }

    private func setupStatusItem() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
            button.image = NSImage(systemSymbolName: "display.and.arrow.down", accessibilityDescription: "Remote Host")?.withSymbolConfiguration(config)
        }
        self.statusItem = statusItem
        updateMenu()
    }

    public func updateMenu() {
        let menu = NSMenu()

        // Status Header
        let statusTitle: String
        if let peer = activePeerDeviceName {
            statusTitle = "● Active Session: \(peer)"
        } else {
            statusTitle = "Status: Ready (Idle)"
        }
        let statusMenuItem = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)

        menu.addItem(NSMenuItem.separator())

        // Pair New Device
        let pairItem = NSMenuItem(title: "Pair New Device...", action: #selector(showPairingWindow), keyEquivalent: "p")
        pairItem.target = self
        menu.addItem(pairItem)

        // End Session
        let endSessionItem = NSMenuItem(title: "End Session", action: #selector(endActiveSession), keyEquivalent: "e")
        endSessionItem.target = self
        endSessionItem.isEnabled = (activePeerDeviceId != nil)
        menu.addItem(endSessionItem)

        menu.addItem(NSMenuItem.separator())

        // Permissions Submenu
        let permItem = NSMenuItem(title: "Permissions", action: nil, keyEquivalent: "")
        let permMenu = NSMenu()

        let screenRecStatus = permissionManager.isScreenRecordingGranted ? "✓ Screen Recording: Granted" : "⚠️ Screen Recording: Missing"
        let screenRecItem = NSMenuItem(title: screenRecStatus, action: #selector(openScreenRecordingSettings), keyEquivalent: "")
        screenRecItem.target = self
        permMenu.addItem(screenRecItem)

        let accStatus = permissionManager.isAccessibilityGranted ? "✓ Accessibility: Granted" : "⚠️ Accessibility: Missing"
        let accItem = NSMenuItem(title: accStatus, action: #selector(openAccessibilitySettings), keyEquivalent: "")
        accItem.target = self
        permMenu.addItem(accItem)

        permItem.submenu = permMenu
        menu.addItem(permItem)

        menu.addItem(NSMenuItem.separator())

        // Quit
        let quitItem = NSMenuItem(title: "Quit Remote Host", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    @objc public func showPairingWindow() {
        if pairingWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 340, height: 440),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Pair Remote Controller"
            window.center()
            window.isReleasedWhenClosed = false

            let pairingView = PairingView(
                pairingCode: Binding(get: { self.pairingCode }, set: { self.pairingCode = $0 }),
                remainingSeconds: Binding(get: { self.remainingSeconds }, set: { self.remainingSeconds = $0 }),
                pendingRequestDeviceName: Binding(get: { self.pendingRequestDeviceName }, set: { self.pendingRequestDeviceName = $0 }),
                pendingRequestDeviceId: Binding(get: { self.pendingRequestDeviceId }, set: { self.pendingRequestDeviceId = $0 }),
                onRefreshCode: { [weak self] in
                    self?.signalingClient.createPairingCode()
                },
                onApproveRequest: { [weak self] peerId in
                    self?.approvePairRequest(peerId)
                },
                onDenyRequest: { [weak self] peerId in
                    self?.denyPairRequest(peerId)
                }
            )

            window.contentView = NSHostingView(rootView: pairingView)
            self.pairingWindow = window
        }

        signalingClient.createPairingCode()
        pairingWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc public func endActiveSession() {
        if let peerId = activePeerDeviceId {
            signalingClient.endSession(targetDeviceId: peerId)
        }
        cleanupActiveSession()
    }

    private func cleanupActiveSession() {
        activePeerDeviceId = nil
        activePeerDeviceName = nil
        sessionIndicator.hide()
        Task {
            await screenCaptureManager.stopCapture()
        }
        webRTCClient.closePeerConnection()
        updateMenu()
    }

    @objc private func openScreenRecordingSettings() {
        permissionManager.openScreenRecordingSettings()
    }

    @objc private func openAccessibilitySettings() {
        permissionManager.openAccessibilitySettings()
    }

    @objc private func quitApp() {
        endActiveSession()
        signalingClient.disconnect()
        NSApp.terminate(nil)
    }

    private func startCountdown(seconds: Int) {
        countdownTimer?.invalidate()
        remainingSeconds = seconds
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            Task { @MainActor in
                guard let self = self else {
                    timer.invalidate()
                    return
                }
                if self.remainingSeconds > 0 {
                    self.remainingSeconds -= 1
                } else {
                    timer.invalidate()
                }
            }
        }
    }

    // MARK: - Pairing actions

    private func approvePairRequest(_ peerId: String) {
        signalingClient.approvePair(peerDeviceId: peerId)
        pendingRequestDeviceId = nil
        pendingRequestDeviceName = nil
    }

    private func denyPairRequest(_ peerId: String) {
        signalingClient.denyPair(peerDeviceId: peerId)
        pendingRequestDeviceId = nil
        pendingRequestDeviceName = nil
    }

    // MARK: - SignalingClientDelegate

    public func signalingClientDidConnect(_ client: SignalingClient) {
        print("[Host] Signaling connected")
    }

    public func signalingClientDidDisconnect(_ client: SignalingClient, error: Error?) {
        print("[Host] Signaling disconnected: \(String(describing: error))")
    }

    public func signalingClient(_ client: SignalingClient, didReceiveRegistered deviceId: String) {
        print("[Host] Registered with signaling server as: \(deviceId)")
    }

    public func signalingClient(_ client: SignalingClient, didReceivePairingCode code: String, expiresInSec: Int) {
        self.pairingCode = code
        startCountdown(seconds: expiresInSec)
    }

    public func signalingClient(_ client: SignalingClient, didReceivePairRequest fromDeviceId: String, fromDeviceName: String) {
        self.pendingRequestDeviceId = fromDeviceId
        self.pendingRequestDeviceName = fromDeviceName
        showPairingWindow()
    }

    public func signalingClient(_ client: SignalingClient, didReceivePaired peerDeviceId: String, peerDeviceName: String, authToken: String) {
        self.activePeerDeviceId = peerDeviceId
        self.activePeerDeviceName = peerDeviceName

        // Store token in Keychain
        keychainStore.saveToken(authToken, forPeerDeviceId: peerDeviceId)

        // Close pairing window
        pairingWindow?.orderOut(nil)

        // Prepare WebRTC & start screen capture
        webRTCClient.preparePeerConnection()
        Task {
            do {
                try await screenCaptureManager.startCapture()
            } catch {
                print("[Host] Failed to start screen capture: \(error)")
            }
        }

        updateMenu()
    }

    public func signalingClientDidReceivePairDenied(_ client: SignalingClient) {
        print("[Host] Pairing was denied")
    }

    public func signalingClientDidReceivePairExpired(_ client: SignalingClient) {
        print("[Host] Pairing code expired")
    }

    public func signalingClient(_ client: SignalingClient, didReceiveOffer fromDeviceId: String, sdp: String) {
        webRTCClient.handleRemoteOffer(sdp: sdp) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let answerSdp):
                self.signalingClient.sendAnswer(targetDeviceId: fromDeviceId, sdp: answerSdp)
            case .failure(let error):
                print("[Host] Failed to handle offer: \(error)")
            }
        }
    }

    public func signalingClient(_ client: SignalingClient, didReceiveAnswer fromDeviceId: String, sdp: String) {}

    public func signalingClient(_ client: SignalingClient, didReceiveIceCandidate fromDeviceId: String, candidate: IceCandidatePayload) {
        webRTCClient.addRemoteIceCandidate(candidate)
    }

    public func signalingClient(_ client: SignalingClient, didReceivePeerDisconnected peerDeviceId: String) {
        if activePeerDeviceId == peerDeviceId {
            cleanupActiveSession()
        }
    }

    public func signalingClient(_ client: SignalingClient, didReceiveTurnCredentials urls: [String], username: String, credential: String, ttlSec: Int) {
        webRTCClient.updateIceServers(urls: urls, username: username, credential: credential)
    }

    public func signalingClient(_ client: SignalingClient, didReceiveError code: String, message: String) {
        print("[Host] Signaling error [\(code)]: \(message)")
    }

    // MARK: - WebRTCClientDelegate

    public func webRTCClient(_ client: WebRTCClient, didDiscoverLocalIceCandidate candidate: IceCandidatePayload) {
        guard let peerId = activePeerDeviceId else { return }
        signalingClient.sendIceCandidate(targetDeviceId: peerId, candidate: candidate)
    }

    public func webRTCClient(_ client: WebRTCClient, didChangeConnectionState state: RTCPeerConnectionState) {
        print("[Host] WebRTC connection state: \(state.rawValue)")
        if state == .failed || state == .closed || state == .disconnected {
            // Keep active state for transient disconnects or cleanup on permanent failure
        }
    }

    public func webRTCClient(_ client: WebRTCClient, didReceiveControlMessage message: ControlChannelMessage) {
        inputInjector.handleControlMessage(message)
    }

    public func webRTCClientDidOpenDataChannel(_ client: WebRTCClient) {
        // Send initial display info
        let displayInfo = ControlChannelMessage.displayInfo(
            widthPx: screenCaptureManager.currentDisplayWidthPx,
            heightPx: screenCaptureManager.currentDisplayHeightPx,
            scaleFactor: screenCaptureManager.currentScaleFactor
        )
        webRTCClient.sendControlMessage(displayInfo)

        // Show on-screen session indicator
        if let peerName = activePeerDeviceName {
            sessionIndicator.show(peerName: peerName) { [weak self] in
                self?.endActiveSession()
            }
        }
    }

    public func webRTCClientDidCloseDataChannel(_ client: WebRTCClient) {
        sessionIndicator.hide()
    }

}

extension MenuBarController: ScreenCaptureManagerDelegate {
    public nonisolated func screenCaptureManager(_ manager: ScreenCaptureManager, didOutputPixelBuffer pixelBuffer: CVPixelBuffer, timestamp: CoreMedia.CMTime) {
        webRTCClient.feedVideoFrame(pixelBuffer: pixelBuffer, timestamp: timestamp)
    }

    public nonisolated func screenCaptureManager(_ manager: ScreenCaptureManager, didChangeDisplayInfo widthPx: Int, heightPx: Int, scaleFactor: Double) {
        Task { @MainActor in
            self.inputInjector.updateDisplayInfo(widthPx: widthPx, heightPx: heightPx, scaleFactor: scaleFactor)
            let displayInfo = ControlChannelMessage.displayInfo(
                widthPx: widthPx,
                heightPx: heightPx,
                scaleFactor: scaleFactor
            )
            self.webRTCClient.sendControlMessage(displayInfo)
        }
    }

    public nonisolated func screenCaptureManager(_ manager: ScreenCaptureManager, didFailWithError error: Error) {
        print("[Host] Screen capture failed: \(error)")
    }
}
