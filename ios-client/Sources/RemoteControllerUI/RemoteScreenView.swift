import SwiftUI
import WebRTC
import RemoteControllerCore

public struct RemoteScreenView: View {
    public let videoTrack: RTCVideoTrack?
    public let gestureController: GestureController
    public let isReconnecting: Bool
    public let onSendControlMessage: (ControlChannelMessage) -> Void
    public let onSendShortcut: (MacShortcut) -> Void
    public let onDisconnect: () -> Void

    @State private var isKeyboardActive: Bool = false
    @State private var viewSize: CGSize = .zero
    @State private var isDragging = false

    public init(
        videoTrack: RTCVideoTrack?,
        gestureController: GestureController,
        isReconnecting: Bool,
        onSendControlMessage: @escaping (ControlChannelMessage) -> Void,
        onSendShortcut: @escaping (MacShortcut) -> Void,
        onDisconnect: @escaping () -> Void
    ) {
        self.videoTrack = videoTrack
        self.gestureController = gestureController
        self.isReconnecting = isReconnecting
        self.onSendControlMessage = onSendControlMessage
        self.onSendShortcut = onSendShortcut
        self.onDisconnect = onDisconnect
    }

    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.edgesIgnoringSafeArea(.all)

                // Video rendering view
                VideoStreamView(videoTrack: videoTrack)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()

                // Transparent gesture capture overlay
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        SpatialTapGesture()
                            .onEnded { value in
                                if let msgs = gestureController.handleSingleTap(at: value.location, in: geometry.size) {
                                    for msg in msgs {
                                        onSendControlMessage(msg)
                                    }
                                }
                            }
                    )
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 4)
                            .onChanged { value in
                                if !isDragging {
                                    isDragging = true
                                    if let msg = gestureController.handleDragStart(at: value.startLocation, in: geometry.size) {
                                        onSendControlMessage(msg)
                                    }
                                }
                                if let msg = gestureController.handleDragMove(at: value.location, in: geometry.size) {
                                    onSendControlMessage(msg)
                                }
                            }
                            .onEnded { value in
                                isDragging = false
                                if let msg = gestureController.handleDragEnd(at: value.location, in: geometry.size) {
                                    onSendControlMessage(msg)
                                }
                            }
                    )

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
                        onSendShortcut: { shortcut in
                            onSendShortcut(shortcut)
                        },
                        onDisconnect: onDisconnect
                    )
                    .padding(.bottom, 20)
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
}
