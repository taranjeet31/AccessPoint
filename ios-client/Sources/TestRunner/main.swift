import Foundation
import CoreGraphics
import RemoteControllerCore

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

print("🧪 Starting iOS Controller Test Suite...")

// MARK: - 1. Protocol Messages Tests
print("  [1/4] Testing Protocol Serialization & Deserialization...")

let encoder = JSONEncoder()
let decoder = JSONDecoder()

// Register message (Role: Controller)
let register = SignalingMessage.register(role: "controller", deviceId: "iphone-123", deviceName: "Alex's iPhone")
let registerData = try! encoder.encode(register)
let decodedRegister = try! decoder.decode(SignalingMessage.self, from: registerData)
if case .register(let role, let deviceId, let deviceName) = decodedRegister {
    assertEqual(role, "controller", "Register role")
    assertEqual(deviceId, "iphone-123", "Register deviceId")
    assertEqual(deviceName, "Alex's iPhone", "Register deviceName")
} else {
    assertTrue(false, "Decoded message is not register")
}

// Pair message
let pair = SignalingMessage.pair(code: "482913", deviceId: "iphone-123", deviceName: "Alex's iPhone")
let pairData = try! encoder.encode(pair)
let decodedPair = try! decoder.decode(SignalingMessage.self, from: pairData)
if case .pair(let code, let deviceId, let deviceName) = decodedPair {
    assertEqual(code, "482913", "Pair code")
    assertEqual(deviceId, "iphone-123", "Pair deviceId")
    assertEqual(deviceName, "Alex's iPhone", "Pair deviceName")
} else {
    assertTrue(false, "Decoded message is not pair")
}

// Offer / Answer
let offer = SignalingMessage.offer(targetDeviceId: "mac-host-1", sdp: "v=0\r\no=- ...")
let offerData = try! encoder.encode(offer)
let decodedOffer = try! decoder.decode(SignalingMessage.self, from: offerData)
if case .offer(let target, let sdp) = decodedOffer {
    assertEqual(target, "mac-host-1", "Offer target")
    assertEqual(sdp, "v=0\r\no=- ...", "Offer sdp")
} else {
    assertTrue(false, "Decoded message is not offer")
}

// Control Channel Messages
let moveMsg = ControlChannelMessage.mouseMove(x: 0.75, y: 0.25)
let moveData = try! encoder.encode(moveMsg)
let decodedMove = try! decoder.decode(ControlChannelMessage.self, from: moveData)
assertEqual(decodedMove, moveMsg, "Control mouseMove message")

let textMsg = ControlChannelMessage.textInput(text: "Antigravity Remote")
let textData = try! encoder.encode(textMsg)
let decodedText = try! decoder.decode(ControlChannelMessage.self, from: textData)
assertEqual(decodedText, textMsg, "Control textInput message")
print("  ✓ Protocol Messages tests passed.")

// MARK: - 2. Gesture Normalization & Content Rect Tests
print("  [2/4] Testing Aspect Ratio Letterboxing & Touch Normalization...")

let gestureCtrl = GestureController()
// Set 16:9 Mac display: 3840 x 2160
gestureCtrl.updateDisplayInfo(widthPx: 3840, heightPx: 2160, scaleFactor: 2.0)
assertTrue(gestureCtrl.hasReceivedDisplayInfo, "Has received display info")

// Viewport: iPhone 15 Pro portrait (393 x 852) -> Aspect ~ 0.46 (much taller than 16:9)
let portraitViewSize = CGSize(width: 393, height: 852)
let letterboxedRect = gestureCtrl.calculateContentRect(in: portraitViewSize)

// 16:9 width is 393, height is 393 * 9 / 16 = 221.0625
assertEqual(letterboxedRect.width, 393.0, "Letterbox width")
assertTrue(abs(letterboxedRect.height - 221.0625) < 0.01, "Letterbox height")
assertTrue(letterboxedRect.minY > 0, "Top black bar exists")

// Touch dead center of the letterboxed video
let centerTouch = CGPoint(x: 393.0 / 2.0, y: letterboxedRect.midY)
let normCenter = gestureCtrl.normalizePoint(centerTouch, in: portraitViewSize)
assertTrue(abs(normCenter.x - 0.5) < 0.001, "Center normalized X")
assertTrue(abs(normCenter.y - 0.5) < 0.001, "Center normalized Y")

// Touch outside video in top black bar
let topBlackBarTouch = CGPoint(x: 100, y: 10)
let normTop = gestureCtrl.normalizePoint(topBlackBarTouch, in: portraitViewSize)
assertEqual(normTop.y, 0.0, "Clamped to top edge of video")

// Test Single Tap translation
let tapMsgs = gestureCtrl.handleSingleTap(at: centerTouch, in: portraitViewSize)
assertTrue(tapMsgs != nil && tapMsgs!.count == 2, "Single tap generated 2 messages (down and up)")
if let msgs = tapMsgs {
    if case .mouseDown(let btn, let x, _) = msgs[0] {
        assertEqual(btn, "left", "Tap mouseDown button")
        assertTrue(abs(x - 0.5) < 0.001, "Tap mouseDown X")
    }
    if case .mouseUp(let btn, _, _) = msgs[1] {
        assertEqual(btn, "left", "Tap mouseUp button")
    }
}

// Test Two Finger Tap (Right Click) translation
let rightTapMsgs = gestureCtrl.handleTwoFingerTap(at: centerTouch, in: portraitViewSize)
assertTrue(rightTapMsgs != nil && rightTapMsgs!.count == 2, "Right tap generated 2 messages")
if let msgs = rightTapMsgs {
    if case .mouseDown(let btn, _, _) = msgs[0] {
        assertEqual(btn, "right", "Right tap mouseDown button")
    }
}
print("  ✓ Gesture Normalization tests passed.")

// MARK: - 3. Virtual Keycodes & Shortcuts Tests
print("  [3/4] Testing Virtual Keycodes & Shortcut Definitions...")
assertEqual(MacVirtualKeyCode.escape.code, 53, "Esc keycode")
assertEqual(MacVirtualKeyCode.tab.code, 48, "Tab keycode")
assertEqual(MacVirtualKeyCode.delete.code, 51, "Delete/Backspace keycode")
assertEqual(MacVirtualKeyCode.c.code, 8, "C keycode")
assertEqual(MacVirtualKeyCode.v.code, 9, "V keycode")
assertEqual(MacVirtualKeyCode.z.code, 6, "Z keycode")

assertEqual(MacShortcut.cmdC.modifiers, ["cmd"], "Cmd+C modifier")
assertEqual(MacShortcut.cmdTab.modifiers, ["cmd"], "Cmd+Tab modifier")
print("  ✓ Virtual Keycodes & Shortcuts tests passed.")

// MARK: - 4. Keychain Store Tests
print("  [4/4] Testing Keychain Store...")
let keychain = KeychainStore(service: "com.remotecontroller.test.runner")
let peerId = "mac-host-\(UUID().uuidString)"
let token = "test.controller.jwt.token"

keychain.clearAllTokens()
let saved = keychain.saveToken(token, forPeerDeviceId: peerId)
assertTrue(saved, "Save token")
let retrieved = keychain.getToken(forPeerDeviceId: peerId)
assertEqual(retrieved, token, "Retrieve token")
let deleted = keychain.deleteToken(forPeerDeviceId: peerId)
assertTrue(deleted, "Delete token")
let retrievedAfter = keychain.getToken(forPeerDeviceId: peerId)
assertEqual(retrievedAfter, nil, "Retrieve after delete")
keychain.clearAllTokens()
print("  ✓ Keychain Store tests passed.")

print("\n🎉 All iOS Controller unit and integration tests passed successfully!")
