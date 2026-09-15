import Foundation
import RemoteHostCore
import CoreGraphics

func assertTrue(_ condition: Bool, _ message: String) {
    if !condition {
        print("❌ Assertion Failed: \(message)")
        exit(1)
    }
}

func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
    if actual != expected {
        print("❌ Assertion Failed: \(message). Expected \(expected), got \(actual)")
        exit(1)
    }
}

print("🧪 Starting macOS Host Test Suite...")

// MARK: - 1. Protocol Messages Tests
print("  [1/3] Testing Protocol Serialization & Deserialization...")

let encoder = JSONEncoder()
let decoder = JSONDecoder()

// Register message
let register = SignalingMessage.register(role: "host", deviceId: "mac-123", deviceName: "My Mac")
let registerData = try! encoder.encode(register)
let decodedRegister = try! decoder.decode(SignalingMessage.self, from: registerData)
if case .register(let role, let deviceId, let deviceName) = decodedRegister {
    assertEqual(role, "host", "Register role")
    assertEqual(deviceId, "mac-123", "Register deviceId")
    assertEqual(deviceName, "My Mac", "Register deviceName")
} else {
    assertTrue(false, "Decoded message is not register")
}

// Pairing Code
let codeJson = """
{"type":"pairing_code","code":"482913","expiresInSec":300}
""".data(using: .utf8)!
let decodedCode = try! decoder.decode(SignalingMessage.self, from: codeJson)
if case .pairingCode(let code, let expiresInSec) = decodedCode {
    assertEqual(code, "482913", "Pairing code")
    assertEqual(expiresInSec, 300, "Expires in seconds")
} else {
    assertTrue(false, "Decoded message is not pairingCode")
}

// Paired
let pairedJson = """
{"type":"paired","peerDeviceId":"iphone-456","peerDeviceName":"Alex's iPhone","authToken":"jwt.token.here"}
""".data(using: .utf8)!
let decodedPaired = try! decoder.decode(SignalingMessage.self, from: pairedJson)
if case .paired(let peerId, let peerName, let token) = decodedPaired {
    assertEqual(peerId, "iphone-456", "Paired peerDeviceId")
    assertEqual(peerName, "Alex's iPhone", "Paired peerDeviceName")
    assertEqual(token, "jwt.token.here", "Paired authToken")
} else {
    assertTrue(false, "Decoded message is not paired")
}

// Control Channel: Display Info
let displayJson = """
{"type":"display_info","widthPx":3024,"heightPx":1964,"scaleFactor":2.0}
""".data(using: .utf8)!
let decodedDisplay = try! decoder.decode(ControlChannelMessage.self, from: displayJson)
if case .displayInfo(let width, let height, let scale) = decodedDisplay {
    assertEqual(width, 3024, "Display width")
    assertEqual(height, 1964, "Display height")
    assertEqual(scale, 2.0, "Display scale factor")
} else {
    assertTrue(false, "Decoded message is not displayInfo")
}

// Control Channel: Mouse Move
let moveJson = """
{"type":"mouse_move","x":0.534,"y":0.221}
""".data(using: .utf8)!
let decodedMove = try! decoder.decode(ControlChannelMessage.self, from: moveJson)
if case .mouseMove(let x, let y) = decodedMove {
    assertEqual(x, 0.534, "Mouse x")
    assertEqual(y, 0.221, "Mouse y")
} else {
    assertTrue(false, "Decoded message is not mouseMove")
}

// Control Channel: Key Down
let keyJson = """
{"type":"key_down","keyCode":53,"modifiers":["shift","cmd"]}
""".data(using: .utf8)!
let decodedKey = try! decoder.decode(ControlChannelMessage.self, from: keyJson)
if case .keyDown(let code, let modifiers) = decodedKey {
    assertEqual(code, 53, "Key code")
    assertEqual(modifiers, ["shift", "cmd"], "Key modifiers")
} else {
    assertTrue(false, "Decoded message is not keyDown")
}

// Control Channel: Text Input
let textJson = """
{"type":"text_input","text":"hello world"}
""".data(using: .utf8)!
let decodedText = try! decoder.decode(ControlChannelMessage.self, from: textJson)
if case .textInput(let text) = decodedText {
    assertEqual(text, "hello world", "Text input text")
} else {
    assertTrue(false, "Decoded message is not textInput")
}
print("  ✓ Protocol Messages tests passed.")

// MARK: - 2. Input Injector Tests
print("  [2/3] Testing Input Injector Coordinate Transformations...")
let injector = InputInjector()
injector.updateDisplayInfo(widthPx: 3024, heightPx: 1964, scaleFactor: 2.0)

assertEqual(injector.screenWidthPoints, 1512.0, "Screen width in points")
assertEqual(injector.screenHeightPoints, 982.0, "Screen height in points")

let center = injector.convertNormalizedPoint(x: 0.5, y: 0.5)
assertEqual(center.x, 756.0, "Center x point")
assertEqual(center.y, 491.0, "Center y point")

let clampedMin = injector.convertNormalizedPoint(x: -0.5, y: -0.5)
assertEqual(clampedMin.x, 0.0, "Clamped min x")
assertEqual(clampedMin.y, 0.0, "Clamped min y")

let clampedMax = injector.convertNormalizedPoint(x: 1.5, y: 1.5)
assertEqual(clampedMax.x, 1512.0, "Clamped max x")
assertEqual(clampedMax.y, 982.0, "Clamped max y")

let flags = injector.mapModifiers(["shift", "cmd", "alt", "ctrl"])
assertTrue(flags.contains(.maskShift), "Modifier shift")
assertTrue(flags.contains(.maskCommand), "Modifier command")
assertTrue(flags.contains(.maskAlternate), "Modifier alternate")
assertTrue(flags.contains(.maskControl), "Modifier control")
print("  ✓ Input Injector tests passed.")

// MARK: - 3. Keychain Store Tests
print("  [3/3] Testing Keychain Store Persistence...")
let keychain = KeychainStore(service: "com.remotehost.test.runner")
let testPeer = "test-peer-\(UUID().uuidString)"
let testToken = "test.jwt.token.string.123"

keychain.clearAllTokens()
let saved = keychain.saveToken(testToken, forPeerDeviceId: testPeer)
assertTrue(saved, "Keychain save token")

import AppKit

let retrieved = keychain.getToken(forPeerDeviceId: testPeer)
assertEqual(retrieved, testToken, "Keychain get token")

let deleted = keychain.deleteToken(forPeerDeviceId: testPeer)
assertTrue(deleted, "Keychain delete token")

let retrievedAfterDelete = keychain.getToken(forPeerDeviceId: testPeer)
assertEqual(retrievedAfterDelete, nil, "Keychain get token after deletion")
keychain.clearAllTokens()
print("  ✓ Keychain Store tests passed.")

// MARK: - 4. UI Layout & Constraint Tests
print("  [4/4] Testing AppKit UI Layout & Constraint Update Pass...")

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

Task { @MainActor in
    let controller = MenuBarController()
    controller.showPairingWindow()

    SessionIndicatorWindow.shared.show(peerName: "Test Device") {}

    for window in app.windows {
        window.contentView?.needsUpdateConstraints = true
        window.contentView?.updateConstraintsForSubtreeIfNeeded()
        window.layoutIfNeeded()
    }
    print("  ✓ UI Layout tests passed.")
    print("\n🎉 All macOS Host unit and integration tests passed successfully!")
    exit(0)
}

RunLoop.main.run(until: Date(timeIntervalSinceNow: 1.0))

