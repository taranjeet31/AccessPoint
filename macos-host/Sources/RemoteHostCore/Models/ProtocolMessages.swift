import Foundation

// MARK: - Ice Candidate Payload

public struct IceCandidatePayload: Codable, Equatable, Sendable {
    public let candidate: String
    public let sdpMid: String?
    public let sdpMLineIndex: Int32?

    public init(candidate: String, sdpMid: String? = nil, sdpMLineIndex: Int32? = nil) {
        self.candidate = candidate
        self.sdpMid = sdpMid
        self.sdpMLineIndex = sdpMLineIndex
    }
}

// MARK: - Signaling Inbound / Outbound Messages

public enum SignalingMessage: Codable, Sendable {
    // Device -> Server
    case register(role: String, deviceId: String, deviceName: String)
    case createPairingCode
    case pair(code: String, deviceId: String, deviceName: String)
    case approvePair(peerDeviceId: String)
    case denyPair(peerDeviceId: String)
    case resumeSession(authToken: String, peerDeviceId: String)
    case offer(targetDeviceId: String, sdp: String)
    case answer(targetDeviceId: String, sdp: String)
    case iceCandidate(targetDeviceId: String, candidate: IceCandidatePayload)
    case endSession(targetDeviceId: String)
    case requestTurnCredentials

    // Server -> Device
    case registered(deviceId: String)
    case pairingCode(code: String, expiresInSec: Int)
    case pairRequest(fromDeviceId: String, fromDeviceName: String)
    case paired(peerDeviceId: String, peerDeviceName: String, authToken: String)
    case pairDenied
    case pairExpired
    case relayOffer(fromDeviceId: String, sdp: String)
    case relayAnswer(fromDeviceId: String, sdp: String)
    case relayIceCandidate(fromDeviceId: String, candidate: IceCandidatePayload)
    case peerDisconnected(peerDeviceId: String)
    case turnCredentials(urls: [String], username: String, credential: String, ttlSec: Int)
    case error(code: String, message: String)

    enum CodingKeys: String, CodingKey {
        case type
        case role
        case deviceId
        case deviceName
        case code
        case expiresInSec
        case fromDeviceId
        case fromDeviceName
        case peerDeviceId
        case peerDeviceName
        case authToken
        case targetDeviceId
        case sdp
        case candidate
        case urls
        case username
        case credential
        case ttlSec
        case message
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "register":
            let role = try container.decode(String.self, forKey: .role)
            let deviceId = try container.decode(String.self, forKey: .deviceId)
            let deviceName = try container.decode(String.self, forKey: .deviceName)
            self = .register(role: role, deviceId: deviceId, deviceName: deviceName)

        case "create_pairing_code":
            self = .createPairingCode

        case "pairing_code":
            let code = try container.decode(String.self, forKey: .code)
            let expiresInSec = try container.decode(Int.self, forKey: .expiresInSec)
            self = .pairingCode(code: code, expiresInSec: expiresInSec)

        case "pair":
            let code = try container.decode(String.self, forKey: .code)
            let deviceId = try container.decode(String.self, forKey: .deviceId)
            let deviceName = try container.decode(String.self, forKey: .deviceName)
            self = .pair(code: code, deviceId: deviceId, deviceName: deviceName)

        case "pair_request":
            let fromDeviceId = try container.decode(String.self, forKey: .fromDeviceId)
            let fromDeviceName = try container.decode(String.self, forKey: .fromDeviceName)
            self = .pairRequest(fromDeviceId: fromDeviceId, fromDeviceName: fromDeviceName)

        case "approve_pair":
            let peerDeviceId = try container.decode(String.self, forKey: .peerDeviceId)
            self = .approvePair(peerDeviceId: peerDeviceId)

        case "deny_pair":
            let peerDeviceId = try container.decode(String.self, forKey: .peerDeviceId)
            self = .denyPair(peerDeviceId: peerDeviceId)

        case "paired":
            let peerDeviceId = try container.decode(String.self, forKey: .peerDeviceId)
            let peerDeviceName = try container.decode(String.self, forKey: .peerDeviceName)
            let authToken = try container.decode(String.self, forKey: .authToken)
            self = .paired(peerDeviceId: peerDeviceId, peerDeviceName: peerDeviceName, authToken: authToken)

        case "pair_denied":
            self = .pairDenied

        case "pair_expired":
            self = .pairExpired

        case "resume_session":
            let authToken = try container.decode(String.self, forKey: .authToken)
            let peerDeviceId = try container.decode(String.self, forKey: .peerDeviceId)
            self = .resumeSession(authToken: authToken, peerDeviceId: peerDeviceId)

        case "registered":
            let deviceId = try container.decode(String.self, forKey: .deviceId)
            self = .registered(deviceId: deviceId)

        case "offer":
            let sdp = try container.decode(String.self, forKey: .sdp)
            if let fromDeviceId = try container.decodeIfPresent(String.self, forKey: .fromDeviceId) {
                self = .relayOffer(fromDeviceId: fromDeviceId, sdp: sdp)
            } else {
                let targetDeviceId = try container.decode(String.self, forKey: .targetDeviceId)
                self = .offer(targetDeviceId: targetDeviceId, sdp: sdp)
            }

        case "answer":
            let sdp = try container.decode(String.self, forKey: .sdp)
            if let fromDeviceId = try container.decodeIfPresent(String.self, forKey: .fromDeviceId) {
                self = .relayAnswer(fromDeviceId: fromDeviceId, sdp: sdp)
            } else {
                let targetDeviceId = try container.decode(String.self, forKey: .targetDeviceId)
                self = .answer(targetDeviceId: targetDeviceId, sdp: sdp)
            }

        case "ice_candidate":
            let candidate = try container.decode(IceCandidatePayload.self, forKey: .candidate)
            if let fromDeviceId = try container.decodeIfPresent(String.self, forKey: .fromDeviceId) {
                self = .relayIceCandidate(fromDeviceId: fromDeviceId, candidate: candidate)
            } else {
                let targetDeviceId = try container.decode(String.self, forKey: .targetDeviceId)
                self = .iceCandidate(targetDeviceId: targetDeviceId, candidate: candidate)
            }

        case "end_session":
            let targetDeviceId = try container.decode(String.self, forKey: .targetDeviceId)
            self = .endSession(targetDeviceId: targetDeviceId)

        case "peer_disconnected":
            let peerDeviceId = try container.decode(String.self, forKey: .peerDeviceId)
            self = .peerDisconnected(peerDeviceId: peerDeviceId)

        case "request_turn_credentials":
            self = .requestTurnCredentials

        case "turn_credentials":
            let urls = try container.decode([String].self, forKey: .urls)
            let username = try container.decode(String.self, forKey: .username)
            let credential = try container.decode(String.self, forKey: .credential)
            let ttlSec = try container.decode(Int.self, forKey: .ttlSec)
            self = .turnCredentials(urls: urls, username: username, credential: credential, ttlSec: ttlSec)

        case "error":
            let code = try container.decode(String.self, forKey: .code)
            let message = try container.decode(String.self, forKey: .message)
            self = .error(code: code, message: message)

        default:
            throw DecodingError.dataCorruptedNamed("Unknown message type: \(type)", codingPath: container.codingPath)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .register(let role, let deviceId, let deviceName):
            try container.encode("register", forKey: .type)
            try container.encode(role, forKey: .role)
            try container.encode(deviceId, forKey: .deviceId)
            try container.encode(deviceName, forKey: .deviceName)

        case .createPairingCode:
            try container.encode("create_pairing_code", forKey: .type)

        case .pairingCode(let code, let expiresInSec):
            try container.encode("pairing_code", forKey: .type)
            try container.encode(code, forKey: .code)
            try container.encode(expiresInSec, forKey: .expiresInSec)

        case .pair(let code, let deviceId, let deviceName):
            try container.encode("pair", forKey: .type)
            try container.encode(code, forKey: .code)
            try container.encode(deviceId, forKey: .deviceId)
            try container.encode(deviceName, forKey: .deviceName)

        case .pairRequest(let fromDeviceId, let fromDeviceName):
            try container.encode("pair_request", forKey: .type)
            try container.encode(fromDeviceId, forKey: .fromDeviceId)
            try container.encode(fromDeviceName, forKey: .fromDeviceName)

        case .approvePair(let peerDeviceId):
            try container.encode("approve_pair", forKey: .type)
            try container.encode(peerDeviceId, forKey: .peerDeviceId)

        case .denyPair(let peerDeviceId):
            try container.encode("deny_pair", forKey: .type)
            try container.encode(peerDeviceId, forKey: .peerDeviceId)

        case .paired(let peerDeviceId, let peerDeviceName, let authToken):
            try container.encode("paired", forKey: .type)
            try container.encode(peerDeviceId, forKey: .peerDeviceId)
            try container.encode(peerDeviceName, forKey: .peerDeviceName)
            try container.encode(authToken, forKey: .authToken)

        case .pairDenied:
            try container.encode("pair_denied", forKey: .type)

        case .pairExpired:
            try container.encode("pair_expired", forKey: .type)

        case .resumeSession(let authToken, let peerDeviceId):
            try container.encode("resume_session", forKey: .type)
            try container.encode(authToken, forKey: .authToken)
            try container.encode(peerDeviceId, forKey: .peerDeviceId)

        case .registered(let deviceId):
            try container.encode("registered", forKey: .type)
            try container.encode(deviceId, forKey: .deviceId)

        case .offer(let targetDeviceId, let sdp):
            try container.encode("offer", forKey: .type)
            try container.encode(targetDeviceId, forKey: .targetDeviceId)
            try container.encode(sdp, forKey: .sdp)

        case .relayOffer(let fromDeviceId, let sdp):
            try container.encode("offer", forKey: .type)
            try container.encode(fromDeviceId, forKey: .fromDeviceId)
            try container.encode(sdp, forKey: .sdp)

        case .answer(let targetDeviceId, let sdp):
            try container.encode("answer", forKey: .type)
            try container.encode(targetDeviceId, forKey: .targetDeviceId)
            try container.encode(sdp, forKey: .sdp)

        case .relayAnswer(let fromDeviceId, let sdp):
            try container.encode("answer", forKey: .type)
            try container.encode(fromDeviceId, forKey: .fromDeviceId)
            try container.encode(sdp, forKey: .sdp)

        case .iceCandidate(let targetDeviceId, let candidate):
            try container.encode("ice_candidate", forKey: .type)
            try container.encode(targetDeviceId, forKey: .targetDeviceId)
            try container.encode(candidate, forKey: .candidate)

        case .relayIceCandidate(let fromDeviceId, let candidate):
            try container.encode("ice_candidate", forKey: .type)
            try container.encode(fromDeviceId, forKey: .fromDeviceId)
            try container.encode(candidate, forKey: .candidate)

        case .endSession(let targetDeviceId):
            try container.encode("end_session", forKey: .type)
            try container.encode(targetDeviceId, forKey: .targetDeviceId)

        case .peerDisconnected(let peerDeviceId):
            try container.encode("peer_disconnected", forKey: .type)
            try container.encode(peerDeviceId, forKey: .peerDeviceId)

        case .requestTurnCredentials:
            try container.encode("request_turn_credentials", forKey: .type)

        case .turnCredentials(let urls, let username, let credential, let ttlSec):
            try container.encode("turn_credentials", forKey: .type)
            try container.encode(urls, forKey: .urls)
            try container.encode(username, forKey: .username)
            try container.encode(credential, forKey: .credential)
            try container.encode(ttlSec, forKey: .ttlSec)

        case .error(let code, let message):
            try container.encode("error", forKey: .type)
            try container.encode(code, forKey: .code)
            try container.encode(message, forKey: .message)
        }
    }
}

// MARK: - Remote App & Window Models

public struct RemoteApp: Codable, Equatable, Sendable, Identifiable {
    public var id: String { bundleID }
    public let bundleID: String
    public let name: String
    public let iconPNG: String?
    public let windows: [RemoteWindow]

    public init(bundleID: String, name: String, iconPNG: String?, windows: [RemoteWindow]) {
        self.bundleID = bundleID
        self.name = name
        self.iconPNG = iconPNG
        self.windows = windows
    }
}

public struct RemoteWindow: Codable, Equatable, Sendable, Identifiable {
    public var id: UInt32 { windowID }
    public let windowID: UInt32
    public let title: String
    public let frameX: Double
    public let frameY: Double
    public let frameWidth: Double
    public let frameHeight: Double
    public let thumbnailJPEG: String?

    public init(windowID: UInt32, title: String, frame: CGRect, thumbnailJPEG: String? = nil) {
        self.windowID = windowID
        self.title = title
        self.frameX = Double(frame.origin.x)
        self.frameY = Double(frame.origin.y)
        self.frameWidth = Double(frame.size.width)
        self.frameHeight = Double(frame.size.height)
        self.thumbnailJPEG = thumbnailJPEG
    }

    public var frame: CGRect {
        CGRect(x: frameX, y: frameY, width: frameWidth, height: frameHeight)
    }
}

// MARK: - Control Channel Data Messages

public enum ControlChannelMessage: Codable, Sendable {
    case displayInfo(widthPx: Int, heightPx: Int, scaleFactor: Double)
    case mouseMove(x: Double, y: Double)
    case mouseDown(button: String, x: Double, y: Double)
    case mouseUp(button: String, x: Double, y: Double)
    case scroll(dx: Double, dy: Double)
    case keyDown(keyCode: UInt16, modifiers: [String])
    case keyUp(keyCode: UInt16, modifiers: [String])
    case textInput(text: String)
    case appList(apps: [RemoteApp])
    case selectWindow(windowID: UInt32)
    case selectScreen
    case windowInfo(windowID: UInt32, frameX: Double, frameY: Double, frameWidth: Double, frameHeight: Double)
    case windowAction(windowID: UInt32, action: String)

    enum CodingKeys: String, CodingKey {
        case type
        case widthPx
        case heightPx
        case scaleFactor
        case x
        case y
        case button
        case dx
        case dy
        case keyCode
        case modifiers
        case text
        case apps
        case windowID
        case frameX
        case frameY
        case frameWidth
        case frameHeight
        case action
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "display_info":
            let widthPx = try container.decode(Int.self, forKey: .widthPx)
            let heightPx = try container.decode(Int.self, forKey: .heightPx)
            let scaleFactor = try container.decode(Double.self, forKey: .scaleFactor)
            self = .displayInfo(widthPx: widthPx, heightPx: heightPx, scaleFactor: scaleFactor)

        case "mouse_move":
            let x = try container.decode(Double.self, forKey: .x)
            let y = try container.decode(Double.self, forKey: .y)
            self = .mouseMove(x: x, y: y)

        case "mouse_down":
            let button = try container.decode(String.self, forKey: .button)
            let x = try container.decode(Double.self, forKey: .x)
            let y = try container.decode(Double.self, forKey: .y)
            self = .mouseDown(button: button, x: x, y: y)

        case "mouse_up":
            let button = try container.decode(String.self, forKey: .button)
            let x = try container.decode(Double.self, forKey: .x)
            let y = try container.decode(Double.self, forKey: .y)
            self = .mouseUp(button: button, x: x, y: y)

        case "scroll":
            let dx = try container.decode(Double.self, forKey: .dx)
            let dy = try container.decode(Double.self, forKey: .dy)
            self = .scroll(dx: dx, dy: dy)

        case "key_down":
            let keyCode = try container.decode(UInt16.self, forKey: .keyCode)
            let modifiers = try container.decodeIfPresent([String].self, forKey: .modifiers) ?? []
            self = .keyDown(keyCode: keyCode, modifiers: modifiers)

        case "key_up":
            let keyCode = try container.decode(UInt16.self, forKey: .keyCode)
            let modifiers = try container.decodeIfPresent([String].self, forKey: .modifiers) ?? []
            self = .keyUp(keyCode: keyCode, modifiers: modifiers)

        case "text_input":
            let text = try container.decode(String.self, forKey: .text)
            self = .textInput(text: text)

        case "app_list":
            let apps = try container.decode([RemoteApp].self, forKey: .apps)
            self = .appList(apps: apps)

        case "select_window":
            let windowID = try container.decode(UInt32.self, forKey: .windowID)
            self = .selectWindow(windowID: windowID)

        case "select_screen":
            self = .selectScreen

        case "window_info":
            let windowID = try container.decode(UInt32.self, forKey: .windowID)
            let frameX = try container.decode(Double.self, forKey: .frameX)
            let frameY = try container.decode(Double.self, forKey: .frameY)
            let frameWidth = try container.decode(Double.self, forKey: .frameWidth)
            let frameHeight = try container.decode(Double.self, forKey: .frameHeight)
            self = .windowInfo(windowID: windowID, frameX: frameX, frameY: frameY, frameWidth: frameWidth, frameHeight: frameHeight)

        case "window_action":
            let windowID = try container.decode(UInt32.self, forKey: .windowID)
            let action = try container.decode(String.self, forKey: .action)
            self = .windowAction(windowID: windowID, action: action)

        default:
            throw DecodingError.dataCorruptedNamed("Unknown control message type: \(type)", codingPath: container.codingPath)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .displayInfo(let widthPx, let heightPx, let scaleFactor):
            try container.encode("display_info", forKey: .type)
            try container.encode(widthPx, forKey: .widthPx)
            try container.encode(heightPx, forKey: .heightPx)
            try container.encode(scaleFactor, forKey: .scaleFactor)

        case .mouseMove(let x, let y):
            try container.encode("mouse_move", forKey: .type)
            try container.encode(x, forKey: .x)
            try container.encode(y, forKey: .y)

        case .mouseDown(let button, let x, let y):
            try container.encode("mouse_down", forKey: .type)
            try container.encode(button, forKey: .button)
            try container.encode(x, forKey: .x)
            try container.encode(y, forKey: .y)

        case .mouseUp(let button, let x, let y):
            try container.encode("mouse_up", forKey: .type)
            try container.encode(button, forKey: .button)
            try container.encode(x, forKey: .x)
            try container.encode(y, forKey: .y)

        case .scroll(let dx, let dy):
            try container.encode("scroll", forKey: .type)
            try container.encode(dx, forKey: .dx)
            try container.encode(dy, forKey: .dy)

        case .keyDown(let keyCode, let modifiers):
            try container.encode("key_down", forKey: .type)
            try container.encode(keyCode, forKey: .keyCode)
            try container.encode(modifiers, forKey: .modifiers)

        case .keyUp(let keyCode, let modifiers):
            try container.encode("key_up", forKey: .type)
            try container.encode(keyCode, forKey: .keyCode)
            try container.encode(modifiers, forKey: .modifiers)

        case .textInput(let text):
            try container.encode("text_input", forKey: .type)
            try container.encode(text, forKey: .text)

        case .appList(let apps):
            try container.encode("app_list", forKey: .type)
            try container.encode(apps, forKey: .apps)

        case .selectWindow(let windowID):
            try container.encode("select_window", forKey: .type)
            try container.encode(windowID, forKey: .windowID)

        case .selectScreen:
            try container.encode("select_screen", forKey: .type)

        case .windowInfo(let windowID, let frameX, let frameY, let frameWidth, let frameHeight):
            try container.encode("window_info", forKey: .type)
            try container.encode(windowID, forKey: .windowID)
            try container.encode(frameX, forKey: .frameX)
            try container.encode(frameY, forKey: .frameY)
            try container.encode(frameWidth, forKey: .frameWidth)
            try container.encode(frameHeight, forKey: .frameHeight)

        case .windowAction(let windowID, let action):
            try container.encode("window_action", forKey: .type)
            try container.encode(windowID, forKey: .windowID)
            try container.encode(action, forKey: .action)
        }
    }
}

private extension DecodingError {
    static func dataCorruptedNamed(_ description: String, codingPath: [CodingKey]) -> DecodingError {
        return DecodingError.dataCorrupted(
            DecodingError.Context(codingPath: codingPath, debugDescription: description)
        )
    }
}
