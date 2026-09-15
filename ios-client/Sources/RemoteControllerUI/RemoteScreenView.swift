import SwiftUI
import WebRTC
import RemoteControllerCore

public struct RemoteScreenView: View {
    public let videoTrack: RTCVideoTrack?
    public let gestureController: GestureController
    public let isReconnecting: Bool
    public let windowID: UInt32?
    public let windowTitle: String?
    public let onSendControlMessage: (ControlChannelMessage) -> Void
    public let onSendShortcut: (MacShortcut) -> Void
    public let onOpenAppPicker: (() -> Void)?
    public let onDisconnect: () -> Void

    @State private var isKeyboardActive: Bool = false
    @State private var interactionMode: InteractionMode = .touch
    @State private var viewSize: CGSize = .zero
    @State private var isDragging = false

    // Pinch-to-Zoom & Pan state
    @State private var zoomScale: CGFloat = 1.0
    @State private var currentMagnification: CGFloat = 1.0
    @State private var panOffset: CGSize = .zero
    @State private var currentPanOffset: CGSize = .zero

    // Precision Pointer Trackpad state
    @State private var pointerPositionNormalized: CGPoint = CGPoint(x: 0.5, y: 0.5)

    public init(
        videoTrack: RTCVideoTrack?,
        gestureController: GestureController,
        isReconnecting: Bool,
        windowID: UInt32? = nil,
        windowTitle: String? = nil,
        onSendControlMessage: @escaping (ControlChannelMessage) -> Void,
        onSendShortcut: @escaping (MacShortcut) -> Void,
        onOpenAppPicker: (() -> Void)? = nil,
        onDisconnect: @escaping () -> Void
    ) {
        self.videoTrack = videoTrack
        self.gestureController = gestureController
        self.isReconnecting = isReconnecting
        self.windowID = windowID
        self.windowTitle = windowTitle
        self.onSendControlMessage = onSendControlMessage
        self.onSendShortcut = onSendShortcut
        self.onOpenAppPicker = onOpenAppPicker
        self.onDisconnect = onDisconnect
    }

    private var effectiveZoomScale: CGFloat {
        min(max(zoomScale * currentMagnification, 1.0), 4.0)
    }

    private var effectivePanOffset: CGSize {
        CGSize(
            width: panOffset.width + currentPanOffset.width,
            height: panOffset.height + currentPanOffset.height
        )
    }

    private func unzoomedLocation(from location: CGPoint, in size: CGSize) -> CGPoint {
        guard effectiveZoomScale > 1.0 else { return location }
        let center = CGPoint(x: size.width / 2.0, y: size.height / 2.0)
        let unzoomedX = (location.x - center.x - effectivePanOffset.width) / effectiveZoomScale + center.x
        let unzoomedY = (location.y - center.y - effectivePanOffset.height) / effectiveZoomScale + center.y
        return CGPoint(x: unzoomedX, y: unzoomedY)
    }

    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.edgesIgnoringSafeArea(.all)

                // Video rendering view with scale & offset
                VideoStreamView(videoTrack: videoTrack)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .scaleEffect(effectiveZoomScale)
                    .offset(effectivePanOffset)
                    .clipped()

                // Virtual Pointer Overlay (Trackpad mode)
                if interactionMode == .pointer {
                    let contentRect = gestureController.calculateContentRect(in: geometry.size)
                    let cursorViewX = contentRect.minX + pointerPositionNormalized.x * contentRect.width
                    let cursorViewY = contentRect.minY + pointerPositionNormalized.y * contentRect.height

                    ZStack {
                        Circle()
                            .fill(Color.blue.opacity(0.3))
                            .frame(width: 32, height: 32)
                        Image(systemName: "cursorarrow")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                            .shadow(color: .black, radius: 4, x: 1, y: 2)
                    }
                    .position(x: cursorViewX, y: cursorViewY)
                    .allowsHitTesting(false)
                }

                // Transparent gesture capture overlay
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        SpatialTapGesture()
                            .onEnded { value in
                                let targetLoc = unzoomedLocation(from: value.location, in: geometry.size)

                                switch interactionMode {
                                case .touch:
                                    if let msgs = gestureController.handleSingleTap(at: targetLoc, in: geometry.size) {
                                        for msg in msgs { onSendControlMessage(msg) }
                                    }
                                case .pointer:
                                    let norm = gestureController.normalizePoint(targetLoc, in: geometry.size)
                                    pointerPositionNormalized = CGPoint(x: norm.x, y: norm.y)
                                    onSendControlMessage(.mouseDown(button: "left", x: norm.x, y: norm.y))
                                    onSendControlMessage(.mouseUp(button: "left", x: norm.x, y: norm.y))
                                case .scroll:
                                    break
                                }
                            }
                    )
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 3)
                            .onChanged { value in
                                let contentRect = gestureController.calculateContentRect(in: geometry.size)
                                let targetLoc = unzoomedLocation(from: value.location, in: geometry.size)
                                let targetStartLoc = unzoomedLocation(from: value.startLocation, in: geometry.size)

                                switch interactionMode {
                                case .touch:
                                    if !isDragging {
                                        isDragging = true
                                        if let msg = gestureController.handleDragStart(at: targetStartLoc, in: geometry.size) {
                                            onSendControlMessage(msg)
                                        }
                                    }
                                    if let msg = gestureController.handleDragMove(at: targetLoc, in: geometry.size) {
                                        onSendControlMessage(msg)
                                    }
                                case .pointer:
                                    if contentRect.width > 0 && contentRect.height > 0 {
                                        let deltaX = value.translation.width / contentRect.width
                                        let deltaY = value.translation.height / contentRect.height
                                        let newX = min(max(pointerPositionNormalized.x + deltaX * 0.03, 0.0), 1.0)
                                        let newY = min(max(pointerPositionNormalized.y + deltaY * 0.03, 0.0), 1.0)
                                        pointerPositionNormalized = CGPoint(x: newX, y: newY)
                                        onSendControlMessage(.mouseMove(x: newX, y: newY))
                                    }
                                case .scroll:
                                    if contentRect.height > 0 {
                                        let normDy = Double(-value.translation.height / contentRect.height * 0.15)
                                        let normDx = Double(value.translation.width / contentRect.width * 0.15)
                                        onSendControlMessage(.scroll(dx: normDx, dy: normDy))
                                    }
                                }
                            }
                            .onEnded { value in
                                let targetLoc = unzoomedLocation(from: value.location, in: geometry.size)
                                if interactionMode == .touch && isDragging {
                                    isDragging = false
                                    if let msg = gestureController.handleDragEnd(at: targetLoc, in: geometry.size) {
                                        onSendControlMessage(msg)
                                    }
                                }
                            }
                    )
                    .simultaneousGesture(
                        MagnificationGesture()
                            .onChanged { amount in
                                currentMagnification = amount
                            }
                            .onEnded { amount in
                                zoomScale = min(max(zoomScale * amount, 1.0), 4.0)
                                currentMagnification = 1.0
                                if zoomScale == 1.0 {
                                    panOffset = .zero
                                }
                            }
                    )

                // Top Floating macOS Window Control Bar
                VStack {
                    topToolbarView
                    Spacer()
                }

                // Hidden Soft Keyboard Bridge
                SoftKeyboardBridge(
                    isKeyboardActive: $isKeyboardActive,
                    onTextInput: { text in
                        onSendControlMessage(.textInput(text: text))
                    },
                    onSpecialKey: { keyCode in
                        onSendControlMessage(.keyDown(keyCode: keyCode, modifiers: []))
                        onSendControlMessage(.keyUp(keyCode: keyCode, modifiers: []))
                    }
                )
                .frame(width: 0, height: 0)
                .opacity(0)

                // Reconnecting Overlay
                if isReconnecting {
                    VStack(spacing: 8) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        Text("Reconnecting to Mac...")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    .padding(16)
                    .background(Color.black.opacity(0.8))
                    .cornerRadius(12)
                }

                // Bottom Floating Control Bar
                VStack {
                    Spacer()
                    ControlBarView(
                        isKeyboardActive: $isKeyboardActive,
                        interactionMode: $interactionMode,
                        onSendShortcut: { shortcut in
                            onSendShortcut(shortcut)
                        },
                        onOpenAppPicker: onOpenAppPicker,
                        onDisconnect: onDisconnect
                    )
                    .padding(.bottom, 16)
                }
            }
            .onAppear {
                self.viewSize = geometry.size
            }
            .onChange(of: geometry.size) { newSize in
                self.viewSize = newSize
            }
        }
    }

    // MARK: - Top Window Toolbar

    private var topToolbarView: some View {
        HStack(spacing: 12) {
            // macOS Window Traffic Lights
            HStack(spacing: 6) {
                Button(action: {
                    if let winID = windowID {
                        onSendControlMessage(.windowAction(windowID: winID, action: "close"))
                    }
                }) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 12, height: 12)
                }
                Button(action: {
                    if let winID = windowID {
                        onSendControlMessage(.windowAction(windowID: winID, action: "minimize"))
                    }
                }) {
                    Circle()
                        .fill(Color.yellow)
                        .frame(width: 12, height: 12)
                }
                Button(action: {
                    if let winID = windowID {
                        onSendControlMessage(.windowAction(windowID: winID, action: "zoom"))
                    }
                }) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 12, height: 12)
                }
            }

            // Window Title / App Name
            Text(windowTitle ?? "Mac Desktop")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)

            Spacer()

            // Quick Window Presets / Actions Menu
            if let winID = windowID {
                Menu {
                    Button(action: {
                        onSendControlMessage(.windowAction(windowID: winID, action: "resize_fill"))
                    }) {
                        Label("Fill Screen", systemImage: "arrow.up.left.and.arrow.down.right")
                    }
                    Button(action: {
                        onSendControlMessage(.windowAction(windowID: winID, action: "resize_center"))
                    }) {
                        Label("Center Window", systemImage: "rectangle.center.inset.filled")
                    }
                    Divider()
                    Button(action: {
                        if zoomScale > 1.0 {
                            zoomScale = 1.0
                            panOffset = .zero
                        } else {
                            zoomScale = 2.0
                        }
                    }) {
                        Label(zoomScale > 1.0 ? "Reset Zoom (1.0x)" : "Zoom 2.0x", systemImage: "plus.magnifyingglass")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white.opacity(0.8))
                }
            }

            // Zoom Reset indicator if zoomed
            if effectiveZoomScale > 1.05 {
                Button(action: {
                    zoomScale = 1.0
                    panOffset = .zero
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 10, weight: .bold))
                        Text(String(format: "%.1fx", effectiveZoomScale))
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                    }
                    .foregroundColor(.amberGold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.amberGold.opacity(0.2))
                    .cornerRadius(6)
                }
            }

            // Back to Apps switcher button
            if let onOpenAppPicker = onOpenAppPicker {
                Button(action: onOpenAppPicker) {
                    HStack(spacing: 4) {
                        Image(systemName: "square.grid.2x2")
                        Text("Apps")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.blue.opacity(0.8))
                    .cornerRadius(8)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(white: 0.1).opacity(0.85))
                .shadow(color: Color.black.opacity(0.4), radius: 8, x: 0, y: 4)
        )
        .padding(.horizontal, 12)
        .padding(.top, 48)
    }
}

private extension Color {
    static let amberGold = Color(red: 1.0, green: 0.75, blue: 0.2)
}
