import Foundation

@MainActor
public protocol SignalingClientDelegate: AnyObject {
    func signalingClientDidConnect(_ client: SignalingClient)
    func signalingClientDidDisconnect(_ client: SignalingClient, error: Error?)
    func signalingClient(_ client: SignalingClient, didReceiveRegistered deviceId: String)
    func signalingClient(_ client: SignalingClient, didReceivePairingCode code: String, expiresInSec: Int)
    func signalingClient(_ client: SignalingClient, didReceivePairRequest fromDeviceId: String, fromDeviceName: String)
    func signalingClient(_ client: SignalingClient, didReceivePaired peerDeviceId: String, peerDeviceName: String, authToken: String)
    func signalingClientDidReceivePairDenied(_ client: SignalingClient)
    func signalingClientDidReceivePairExpired(_ client: SignalingClient)
    func signalingClient(_ client: SignalingClient, didReceiveOffer fromDeviceId: String, sdp: String)
    func signalingClient(_ client: SignalingClient, didReceiveAnswer fromDeviceId: String, sdp: String)
    func signalingClient(_ client: SignalingClient, didReceiveIceCandidate fromDeviceId: String, candidate: IceCandidatePayload)
    func signalingClient(_ client: SignalingClient, didReceivePeerDisconnected peerDeviceId: String)
    func signalingClient(_ client: SignalingClient, didReceiveTurnCredentials urls: [String], username: String, credential: String, ttlSec: Int)
    func signalingClient(_ client: SignalingClient, didReceiveError code: String, message: String)
}

public final class SignalingClient: NSObject, @unchecked Sendable {
    public weak var delegate: SignalingClientDelegate?

    public let serverURL: URL
    public let deviceId: String
    public let deviceName: String

    private var session: URLSession?
    private var webSocketTask: URLSessionWebSocketTask?
    private var isConnected = false
    private var isIntentionalClose = false
    private var reconnectAttempt = 0
    private var reconnectWorkItem: DispatchWorkItem?
    private var pingTimer: Timer?

    private let jsonEncoder = JSONEncoder()
    private let jsonDecoder = JSONDecoder()

    public init(
        serverURL: URL? = nil,
        deviceId: String = UUID().uuidString,
        deviceName: String = Host.current().localizedName ?? "MacBook Host"
    ) {
        if let serverURL = serverURL {
            self.serverURL = serverURL
        } else if let envUrlString = ProcessInfo.processInfo.environment["SIGNALING_URL"], let envUrl = URL(string: envUrlString) {
            self.serverURL = envUrl
        } else {
            self.serverURL = URL(string: "ws://localhost:8080/ws")!
        }
        self.deviceId = deviceId
        self.deviceName = deviceName
        super.init()
    }

    public func connect() {
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil

        stopPingTimer()

        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil

        session?.invalidateAndCancel()
        session = nil

        isIntentionalClose = false

        let newSession = URLSession(configuration: .default, delegate: nil, delegateQueue: OperationQueue())
        let newTask = newSession.webSocketTask(with: serverURL)

        self.session = newSession
        self.webSocketTask = newTask

        newTask.resume()

        listenForMessages(task: newTask)

        // Register host
        let registerMessage = SignalingMessage.register(
            role: "host",
            deviceId: deviceId,
            deviceName: deviceName
        )
        sendMessage(registerMessage)
    }

    public func disconnect() {
        isIntentionalClose = true
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil

        stopPingTimer()

        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil

        session?.invalidateAndCancel()
        session = nil

        isConnected = false
    }

    private func startPingTimer() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.stopPingTimer()
            self.pingTimer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: true) { [weak self] _ in
                guard let self = self, self.isConnected, let task = self.webSocketTask else { return }
                task.sendPing { error in
                    if let error = error {
                        print("[SignalingClient] Ping error: \(error)")
                    }
                }
            }
        }
    }

    private func stopPingTimer() {
        pingTimer?.invalidate()
        pingTimer = nil
    }

    private func listenForMessages(task: URLSessionWebSocketTask) {
        task.receive { [weak self, weak task] result in
            guard let self = self, let currentTask = task, currentTask === self.webSocketTask else {
                // Ignore callbacks from old/orphaned tasks
                return
            }

            switch result {
            case .success(let message):
                if !self.isConnected {
                    self.isConnected = true
                    self.reconnectAttempt = 0
                    self.startPingTimer()
                    DispatchQueue.main.async {
                        self.delegate?.signalingClientDidConnect(self)
                    }
                }

                switch message {
                case .string(let text):
                    self.handleIncomingText(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self.handleIncomingText(text)
                    }
                @unknown default:
                    break
                }

                // Continue listening on current task
                self.listenForMessages(task: currentTask)

            case .failure(let error):
                self.isConnected = false
                self.stopPingTimer()
                DispatchQueue.main.async {
                    self.delegate?.signalingClientDidDisconnect(self, error: error)
                }
                if !self.isIntentionalClose {
                    self.scheduleReconnect()
                }
            }
        }
    }

    private func handleIncomingText(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }

        do {
            let msg = try jsonDecoder.decode(SignalingMessage.self, from: data)
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.dispatchMessage(msg)
            }
        } catch {
            print("[SignalingClient] Failed to decode message: \(error). Raw: \(text)")
        }
    }

    @MainActor
    private func dispatchMessage(_ msg: SignalingMessage) {
        switch msg {
        case .registered(let devId):
            delegate?.signalingClient(self, didReceiveRegistered: devId)

        case .pairingCode(let code, let expiresInSec):
            delegate?.signalingClient(self, didReceivePairingCode: code, expiresInSec: expiresInSec)

        case .pairRequest(let fromDeviceId, let fromDeviceName):
            delegate?.signalingClient(self, didReceivePairRequest: fromDeviceId, fromDeviceName: fromDeviceName)

        case .paired(let peerDeviceId, let peerDeviceName, let authToken):
            delegate?.signalingClient(self, didReceivePaired: peerDeviceId, peerDeviceName: peerDeviceName, authToken: authToken)

        case .pairDenied:
            delegate?.signalingClientDidReceivePairDenied(self)

        case .pairExpired:
            delegate?.signalingClientDidReceivePairExpired(self)

        case .relayOffer(let fromDeviceId, let sdp):
            delegate?.signalingClient(self, didReceiveOffer: fromDeviceId, sdp: sdp)

        case .relayAnswer(let fromDeviceId, let sdp):
            delegate?.signalingClient(self, didReceiveAnswer: fromDeviceId, sdp: sdp)

        case .relayIceCandidate(let fromDeviceId, let candidate):
            delegate?.signalingClient(self, didReceiveIceCandidate: fromDeviceId, candidate: candidate)

        case .peerDisconnected(let peerDeviceId):
            delegate?.signalingClient(self, didReceivePeerDisconnected: peerDeviceId)

        case .turnCredentials(let urls, let username, let credential, let ttlSec):
            delegate?.signalingClient(self, didReceiveTurnCredentials: urls, username: username, credential: credential, ttlSec: ttlSec)

        case .error(let code, let message):
            delegate?.signalingClient(self, didReceiveError: code, message: message)

        default:
            break
        }
    }

    public func sendMessage(_ message: SignalingMessage) {
        do {
            let data = try jsonEncoder.encode(message)
            guard let text = String(data: data, encoding: .utf8) else { return }
            let wsMessage = URLSessionWebSocketTask.Message.string(text)
            webSocketTask?.send(wsMessage) { error in
                if let error = error {
                    print("[SignalingClient] Failed to send message: \(error)")
                }
            }
        } catch {
            print("[SignalingClient] Failed to encode message: \(error)")
        }
    }

    // MARK: - Action helpers

    public func createPairingCode() {
        sendMessage(.createPairingCode)
    }

    public func approvePair(peerDeviceId: String) {
        sendMessage(.approvePair(peerDeviceId: peerDeviceId))
    }

    public func denyPair(peerDeviceId: String) {
        sendMessage(.denyPair(peerDeviceId: peerDeviceId))
    }

    public func sendAnswer(targetDeviceId: String, sdp: String) {
        sendMessage(.answer(targetDeviceId: targetDeviceId, sdp: sdp))
    }

    public func sendIceCandidate(targetDeviceId: String, candidate: IceCandidatePayload) {
        sendMessage(.iceCandidate(targetDeviceId: targetDeviceId, candidate: candidate))
    }

    public func endSession(targetDeviceId: String) {
        sendMessage(.endSession(targetDeviceId: targetDeviceId))
    }

    public func requestTurnCredentials() {
        sendMessage(.requestTurnCredentials)
    }

    // MARK: - Reconnection

    private func scheduleReconnect() {
        reconnectAttempt += 1
        let delay = min(pow(2.0, Double(reconnectAttempt)), 30.0)
        print("[SignalingClient] Reconnecting in \(delay) seconds (attempt \(reconnectAttempt))...")

        let item = DispatchWorkItem { [weak self] in
            self?.connect()
        }
        reconnectWorkItem = item
        DispatchQueue.global().asyncAfter(deadline: .now() + delay, execute: item)
    }
}
