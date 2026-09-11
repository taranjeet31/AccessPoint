import SwiftUI
import WebRTC
import RemoteControllerCore
import RemoteControllerUI

@main
struct RemoteControllerApp: App {
    @StateObject private var coordinator = ControllerCoordinator()

    var body: some Scene {
        WindowGroup {
            if coordinator.isSessionActive {
                RemoteScreenView(
                    videoTrack: coordinator.remoteVideoTrack,
                    gestureController: coordinator.gestureController,
                    isReconnecting: coordinator.isReconnecting,
                    onSendControlMessage: { msg in
                        coordinator.sendControlMessage(msg)
                    },
                    onSendShortcut: { shortcut in
                        coordinator.sendShortcut(shortcut)
                    },
                    onDisconnect: {
                        coordinator.disconnectSession()
                    }
                )
            } else {
                PairingScanView(
                    isPairingPending: coordinator.isPairingPending,
                    errorMessage: coordinator.pairingErrorMessage,
                    onPairWithCode: { code in
                        coordinator.pairWithCode(code)
                    }
                )
            }
        }
    }
}

@MainActor
final class ControllerCoordinator: ObservableObject, SignalingClientDelegate, WebRTCClientDelegate, NetworkMonitorDelegate {
    @Published public var isSessionActive = false
    @Published public var isPairingPending = false
    @Published public var isReconnecting = false
    @Published public var pairingErrorMessage: String?
    @Published public var remoteVideoTrack: RTCVideoTrack?

    public let signalingClient: SignalingClient
    public let webRTCClient: WebRTCClient
    public let gestureController: GestureController
    public let keychainStore: KeychainStore
    public let networkMonitor: NetworkMonitor

    private var currentPeerDeviceId: String?
    private var currentAuthToken: String?

    public init() {
        self.signalingClient = SignalingClient()
        self.webRTCClient = WebRTCClient()
        self.gestureController = GestureController()
        self.keychainStore = KeychainStore.shared
        self.networkMonitor = NetworkMonitor.shared

        self.signalingClient.delegate = self
        self.webRTCClient.delegate = self
        self.networkMonitor.delegate = self

        self.networkMonitor.start()
        self.signalingClient.connect()
        self.signalingClient.requestTurnCredentials()

        // Check if previously paired device exists in UserDefaults / Keychain
        if let savedPeer = UserDefaults.standard.string(forKey: "last_paired_peer_id"),
           let token = keychainStore.getToken(forPeerDeviceId: savedPeer) {
            self.currentPeerDeviceId = savedPeer
            self.currentAuthToken = token
            self.isPairingPending = true
            self.signalingClient.resumeSession(authToken: token, peerDeviceId: savedPeer)
        }
    }

    public func pairWithCode(_ code: String) {
        pairingErrorMessage = nil
        isPairingPending = true
        signalingClient.pair(code: code)
    }

    public func disconnectSession() {
        if let peerId = currentPeerDeviceId {
            signalingClient.endSession(targetDeviceId: peerId)
        }
        cleanupSession()
    }

    public func unpairDevice() {
        if let peerId = currentPeerDeviceId {
            keychainStore.deleteToken(forPeerDeviceId: peerId)
            UserDefaults.standard.removeObject(forKey: "last_paired_peer_id")
        }
        disconnectSession()
    }

    private func cleanupSession() {
        isSessionActive = false
        isPairingPending = false
        isReconnecting = false
        remoteVideoTrack = nil
        webRTCClient.closePeerConnection()
    }

    public func sendControlMessage(_ message: ControlChannelMessage) {
        webRTCClient.sendControlMessage(message)
    }

    public func sendShortcut(_ shortcut: MacShortcut) {
        let keyDown = ControlChannelMessage.keyDown(keyCode: shortcut.keyCode, modifiers: shortcut.modifiers)
        let keyUp = ControlChannelMessage.keyUp(keyCode: shortcut.keyCode, modifiers: shortcut.modifiers)
        webRTCClient.sendControlMessage(keyDown)
        webRTCClient.sendControlMessage(keyUp)
    }

    // MARK: - SignalingClientDelegate

    public func signalingClientDidConnect(_ client: SignalingClient) {
        print("[Controller] Signaling connected")
        if isReconnecting, let token = currentAuthToken, let peerId = currentPeerDeviceId {
            signalingClient.resumeSession(authToken: token, peerDeviceId: peerId)
        }
    }

    public func signalingClientDidDisconnect(_ client: SignalingClient, error: Error?) {
        print("[Controller] Signaling disconnected: \(String(describing: error))")
        if isSessionActive {
            isReconnecting = true
        }
    }

    public func signalingClient(_ client: SignalingClient, didReceiveRegistered deviceId: String) {
        print("[Controller] Registered as: \(deviceId)")
    }

    public func signalingClient(_ client: SignalingClient, didReceivePaired peerDeviceId: String, peerDeviceName: String, authToken: String) {
        self.currentPeerDeviceId = peerDeviceId
        self.currentAuthToken = authToken
        self.isPairingPending = false
        self.isSessionActive = true
        self.isReconnecting = false
        self.pairingErrorMessage = nil

        // Save token to Keychain
        keychainStore.saveToken(authToken, forPeerDeviceId: peerDeviceId)
        UserDefaults.standard.set(peerDeviceId, forKey: "last_paired_peer_id")

        // Controller initiates offer per protocol contract
        webRTCClient.createOffer { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let offerSdp):
                self.signalingClient.sendOffer(targetDeviceId: peerDeviceId, sdp: offerSdp)
            case .failure(let error):
                print("[Controller] Error creating WebRTC offer: \(error)")
            }
        }
    }

    public func signalingClientDidReceivePairDenied(_ client: SignalingClient) {
        isPairingPending = false
        pairingErrorMessage = "Pairing request was denied by the Mac host."
    }

    public func signalingClientDidReceivePairExpired(_ client: SignalingClient) {
        isPairingPending = false
        pairingErrorMessage = "Pairing code has expired. Please enter a fresh code."
    }

    public func signalingClient(_ client: SignalingClient, didReceiveAnswer fromDeviceId: String, sdp: String) {
        webRTCClient.handleRemoteAnswer(sdp: sdp) { error in
            if let error = error {
                print("[Controller] Failed to handle answer: \(error)")
            }
        }
    }

    public func signalingClient(_ client: SignalingClient, didReceiveIceCandidate fromDeviceId: String, candidate: IceCandidatePayload) {
        webRTCClient.addRemoteIceCandidate(candidate)
    }

    public func signalingClient(_ client: SignalingClient, didReceivePeerDisconnected peerDeviceId: String) {
        if currentPeerDeviceId == peerDeviceId {
            cleanupSession()
        }
    }

    public func signalingClient(_ client: SignalingClient, didReceiveTurnCredentials urls: [String], username: String, credential: String, ttlSec: Int) {
        webRTCClient.updateIceServers(urls: urls, username: username, credential: credential)
    }

    public func signalingClient(_ client: SignalingClient, didReceiveError code: String, message: String) {
        print("[Controller] Signaling error [\(code)]: \(message)")
        isPairingPending = false
        pairingErrorMessage = "Error: \(message)"
    }

    // MARK: - WebRTCClientDelegate

    public func webRTCClient(_ client: WebRTCClient, didDiscoverLocalIceCandidate candidate: IceCandidatePayload) {
        guard let peerId = currentPeerDeviceId else { return }
        signalingClient.sendIceCandidate(targetDeviceId: peerId, candidate: candidate)
    }

    public func webRTCClient(_ client: WebRTCClient, didChangeConnectionState state: RTCIceConnectionState) {
        print("[Controller] WebRTC ICE state: \(state.rawValue)")
        if state == .connected || state == .completed {
            isReconnecting = false
        } else if state == .disconnected || state == .failed {
            isReconnecting = true
        }
    }

    public func webRTCClient(_ client: WebRTCClient, didReceiveRemoteVideoTrack videoTrack: RTCVideoTrack) {
        self.remoteVideoTrack = videoTrack
    }

    public func webRTCClient(_ client: WebRTCClient, didReceiveControlMessage message: ControlChannelMessage) {
        if case .displayInfo(let width, let height, let scale) = message {
            gestureController.updateDisplayInfo(widthPx: width, heightPx: height, scaleFactor: scale)
        }
    }

    public func webRTCClientDidOpenDataChannel(_ client: WebRTCClient) {
        print("[Controller] Control data channel opened")
    }

    public func webRTCClientDidCloseDataChannel(_ client: WebRTCClient) {
        print("[Controller] Control data channel closed")
    }

    // MARK: - NetworkMonitorDelegate

    public func networkMonitorDidChangePath(_ monitor: NetworkMonitor, isConnected: Bool, isCellular: Bool) {
        print("[Controller] Network path changed: connected=\(isConnected), cellular=\(isCellular)")
        if isConnected && isSessionActive {
            // Initiate ICE restart offer on network interface handoff
            if let peerId = currentPeerDeviceId {
                webRTCClient.createOffer(restartIce: true) { [weak self] result in
                    guard let self = self else { return }
                    if case .success(let sdp) = result {
                        self.signalingClient.sendOffer(targetDeviceId: peerId, sdp: sdp)
                    }
                }
            }
        }
    }
}
