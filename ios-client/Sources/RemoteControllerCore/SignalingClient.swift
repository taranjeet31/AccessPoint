import Foundation

@MainActor
public protocol SignalingClientDelegate: AnyObject {
    func signalingClientDidConnect(_ client: SignalingClient)
    func signalingClientDidDisconnect(_ client: SignalingClient, error: Error?)
    func signalingClient(_ client: SignalingClient, didReceiveRegistered deviceId: String)
    func signalingClient(_ client: SignalingClient, didReceivePaired peerDeviceId: String, peerDeviceName: String, authToken: String)
    func signalingClientDidReceivePairDenied(_ client: SignalingClient)
    func signalingClientDidReceivePairExpired(_ client: SignalingClient)
    func signalingClient(_ client: SignalingClient, didReceiveAnswer fromDeviceId: String, sdp: String)
    func signalingClient(_ client: SignalingClient, didReceiveIceCandidate fromDeviceId: String, candidate: IceCandidatePayload)
    func signalingClient(_ client: SignalingClient, didReceivePeerDisconnected peerDeviceId: String)
    func signalingClient(_ client: SignalingClient, didReceiveTurnCredentials urls: [String], username: String, credential: String, ttlSec: Int)
    func signalingClient(_ client: SignalingClient, didReceiveError code: String, message: String)
}

public final class SignalingClient: NSObject, @unchecked Sendable {
    public weak var delegate: SignalingClientDelegate?

    public private(set) var serverURL: URL
    public let deviceId: String
    public let deviceName: String

    public var isCurrentlyConnected: Bool { isConnected }

    private var session: URLSession?
    private var webSocketTask: URLSessionWebSocketTask?
    private var isConnected = false
    private var isIntentionalClose = false
    private var reconnectAttempt = 0
    private var reconnectWorkItem: DispatchWorkItem?

    private let jsonEncoder = JSONEncoder()
    private let jsonDecoder = JSONDecoder()

    public static func normalizeSignalingURL(_ input: String) -> URL? {
        var str = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if str.isEmpty { return nil }

        str = str.replacingOccurrences(of: "\"", with: "").replacingOccurrences(of: "'", with: "")

        if str.hasPrefix("http://") {
            str = "ws://" + str.dropFirst("http://".count)
        } else if str.hasPrefix("https://") {
            str = "ws://" + str.dropFirst("https://".count)
        } else if str.hasPrefix("wss://") {
            let body = String(str.dropFirst("wss://".count))
            if body.contains(":8080") || body.range(of: #"^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}"#, options: .regularExpression) != nil || body.hasPrefix("localhost") {
                str = "ws://" + body
            }
        } else if !str.hasPrefix("ws://") {
            str = "ws://" + str
        }

        guard var components = URLComponents(string: str) else { return nil }

        if components.port == nil {
            let host = components.host ?? ""
            let isIP = host.range(of: #"^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$"#, options: .regularExpression) != nil
            if isIP || host == "localhost" {
                components.port = 8080
            }
        }

        if components.path.isEmpty || components.path == "/" {
            components.path = "/ws"
        }

        return components.url
    }

    public init(
        serverURL: URL? = nil,
        deviceId: String = UUID().uuidString,
        deviceName: String = "iOS iPhone Controller"
    ) {
        if let serverURL = serverURL {
            self.serverURL = serverURL
        } else if let envUrlString = ProcessInfo.processInfo.environment["SIGNALING_URL"], let envUrl = SignalingClient.normalizeSignalingURL(envUrlString) {
            self.serverURL = envUrl
        } else {
            self.serverURL = URL(string: "ws://localhost:8080/ws")!
        }
        self.deviceId = deviceId
        self.deviceName = deviceName
        super.init()
    }

    public func updateServerURL(_ newURL: URL) {
        guard serverURL != newURL else { return }
        reconnect(withServerURL: newURL)
    }

    public func reconnect(withServerURL newURL: URL? = nil) {
        disconnect()
        if let newURL = newURL {
            self.serverURL = newURL
        }
        connect()
    }

    public func connect() {
        isIntentionalClose = false
        reconnectAttempt = 0
        reconnectWorkItem?.cancel()

        session = URLSession(configuration: .default, delegate: nil, delegateQueue: OperationQueue())
        webSocketTask = session?.webSocketTask(with: serverURL)
        webSocketTask?.resume()

        listenForMessages()

        // Register controller
        let registerMessage = SignalingMessage.register(
            role: "controller",
            deviceId: deviceId,
            deviceName: deviceName
        )
        sendMessage(registerMessage)
    }

    public func disconnect() {
        isIntentionalClose = true
        reconnectWorkItem?.cancel()
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        session = nil
        isConnected = false
    }

    private func listenForMessages() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let message):
                if !self.isConnected {
                    self.isConnected = true
                    self.reconnectAttempt = 0
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

                // Continue listening
                self.listenForMessages()

            case .failure(let error):
                self.isConnected = false
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
            print("[SignalingClient-iOS] Failed to decode message: \(error). Raw: \(text)")
        }
    }

    @MainActor
    private func dispatchMessage(_ msg: SignalingMessage) {
        switch msg {
        case .registered(let devId):
            delegate?.signalingClient(self, didReceiveRegistered: devId)

        case .paired(let peerDeviceId, let peerDeviceName, let authToken):
            delegate?.signalingClient(self, didReceivePaired: peerDeviceId, peerDeviceName: peerDeviceName, authToken: authToken)

        case .pairDenied:
            delegate?.signalingClientDidReceivePairDenied(self)

        case .pairExpired:
            delegate?.signalingClientDidReceivePairExpired(self)

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
                    print("[SignalingClient-iOS] Failed to send message: \(error)")
                }
            }
        } catch {
            print("[SignalingClient-iOS] Failed to encode message: \(error)")
        }
    }

    // MARK: - Action helpers

    public func pair(code: String) {
        sendMessage(.pair(code: code, deviceId: deviceId, deviceName: deviceName))
    }

    public func resumeSession(authToken: String, peerDeviceId: String) {
        sendMessage(.resumeSession(authToken: authToken, peerDeviceId: peerDeviceId))
    }

    public func sendOffer(targetDeviceId: String, sdp: String) {
        sendMessage(.offer(targetDeviceId: targetDeviceId, sdp: sdp))
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

    public func scheduleReconnect() {
        reconnectAttempt += 1
        let delay = min(pow(2.0, Double(reconnectAttempt)), 30.0)
        print("[SignalingClient-iOS] Reconnecting in \(delay) seconds (attempt \(reconnectAttempt))...")

        let item = DispatchWorkItem { [weak self] in
            self?.connect()
        }
        reconnectWorkItem = item
        DispatchQueue.global().asyncAfter(deadline: .now() + delay, execute: item)
    }
}
