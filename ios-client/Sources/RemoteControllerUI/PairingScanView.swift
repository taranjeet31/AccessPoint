import SwiftUI
import AVFoundation

#if os(iOS)
import UIKit

public struct QRCodeScannerView: UIViewControllerRepresentable {
    public let onCodeScanned: (String) -> Void

    public init(onCodeScanned: @escaping (String) -> Void) {
        self.onCodeScanned = onCodeScanned
    }

    public func makeUIViewController(context: Context) -> ScannerViewController {
        let controller = ScannerViewController()
        controller.onCodeScanned = onCodeScanned
        return controller
    }

    public func updateUIViewController(_ uiViewController: ScannerViewController, context: Context) {}
}

public class ScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    public var onCodeScanned: ((String) -> Void)?
    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupCamera()
    }

    private func setupCamera() {
        let session = AVCaptureSession()
        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video) else { return }

        guard let videoInput = try? AVCaptureDeviceInput(device: videoCaptureDevice),
              session.canAddInput(videoInput) else {
            return
        }

        session.addInput(videoInput)

        let metadataOutput = AVCaptureMetadataOutput()
        if session.canAddOutput(metadataOutput) {
            session.addOutput(metadataOutput)
            metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            metadataOutput.metadataObjectTypes = [.qr]
        }

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.frame = view.layer.bounds
        preview.videoGravity = .resizeAspectFill
        view.layer.addSublayer(preview)
        self.previewLayer = preview
        self.captureSession = session

        DispatchQueue.global(qos: .userInitiated).async {
            session.startRunning()
        }
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.layer.bounds
    }

    public func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        if let metadataObject = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
           let stringValue = metadataObject.stringValue {
            captureSession?.stopRunning()
            onCodeScanned?(stringValue)
        }
    }
}
#else
public struct QRCodeScannerView: View {
    public let onCodeScanned: (String) -> Void
    public init(onCodeScanned: @escaping (String) -> Void) {
        self.onCodeScanned = onCodeScanned
    }
    public var body: some View {
        Rectangle()
            .fill(Color.black.opacity(0.8))
            .overlay(Text("Camera scanner available on iOS").foregroundColor(.white))
    }
}
#endif

public struct PairingScanView: View {
    @State private var manualCode: String = ""
    @State private var isEditingServerURL: Bool = false
    @State private var editedServerURL: String = ""

    public let isPairingPending: Bool
    public let errorMessage: String?
    public let serverURLString: String
    public let isSignalingConnected: Bool
    public let onPairWithCode: (String) -> Void
    public let onUpdateServerURL: (String) -> Void
    public let onRetryConnect: () -> Void

    public init(
        isPairingPending: Bool,
        errorMessage: String?,
        serverURLString: String = "ws://localhost:8080/ws",
        isSignalingConnected: Bool = false,
        onPairWithCode: @escaping (String) -> Void,
        onUpdateServerURL: @escaping (String) -> Void = { _ in },
        onRetryConnect: @escaping () -> Void = {}
    ) {
        self.isPairingPending = isPairingPending
        self.errorMessage = errorMessage
        self.serverURLString = serverURLString
        self.isSignalingConnected = isSignalingConnected
        self.onPairWithCode = onPairWithCode
        self.onUpdateServerURL = onUpdateServerURL
        self.onRetryConnect = onRetryConnect
        self._editedServerURL = State(initialValue: serverURLString)
    }

    public var body: some View {
        ZStack {
            Color(white: 0.08).edgesIgnoringSafeArea(.all)

            ScrollView {
                VStack(spacing: 20) {
                    // Header & Signaling Server Badge
                    VStack(spacing: 8) {
                        Text("Connect to Mac")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.white)

                        // Status Badge & Server URL display
                        HStack(spacing: 8) {
                            Button(action: {
                                isEditingServerURL.toggle()
                            }) {
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(isSignalingConnected ? Color.green : Color.red)
                                        .frame(width: 8, height: 8)

                                    Text(isSignalingConnected ? "Signaling Connected" : "Signaling Disconnected")
                                        .font(.system(size: 11, weight: .semibold))

                                    Image(systemName: "gearshape.fill")
                                        .font(.system(size: 11))
                                }
                                .foregroundColor(isSignalingConnected ? .green : Color.orange)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                                .background(Color.white.opacity(0.08))
                                .cornerRadius(12)
                            }

                            if !isSignalingConnected {
                                Button(action: {
                                    onRetryConnect()
                                }) {
                                    Label("Reconnect", systemImage: "arrow.clockwise")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 4)
                                        .background(Color.blue)
                                        .cornerRadius(12)
                                }
                            }
                        }

                        if isEditingServerURL {
                            VStack(spacing: 8) {
                                HStack {
                                    TextField("ws://192.168.1.x:8080/ws", text: $editedServerURL)
                                        .font(.system(size: 12, design: .monospaced))
                                        .padding(8)
                                        .background(Color(white: 0.16))
                                        .foregroundColor(.white)
                                        .cornerRadius(6)

                                    Button("Save") {
                                        onUpdateServerURL(editedServerURL)
                                        isEditingServerURL = false
                                    }
                                    .font(.system(size: 12, weight: .bold))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Color.blue)
                                    .foregroundColor(.white)
                                    .cornerRadius(6)
                                }
                                .padding(.horizontal, 24)

                                Text("Current: \(serverURLString)")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.top, 4)
                        } else {
                            Text("Scan the QR code displayed on your Mac Host, or enter the 6-digit code below.")
                                .font(.system(size: 13))
                                .foregroundColor(Color(white: 0.7))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                        }
                    }
                    .padding(.top, 32)

                    // Camera QR Scanner Container
                    ZStack {
                        QRCodeScannerView { scannedCode in
                            onPairWithCode(scannedCode)
                        }
                        .frame(width: 220, height: 220)
                        .cornerRadius(16)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.accentColor.opacity(0.8), lineWidth: 2)
                        )

                        // Target scanning guide frame
                        Image(systemName: "viewfinder")
                            .font(.system(size: 160, weight: .ultraLight))
                            .foregroundColor(.white.opacity(0.5))
                    }

                    // Or divider
                    HStack {
                        Rectangle().fill(Color.white.opacity(0.2)).frame(height: 1)
                        Text("OR ENTER CODE")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                        Rectangle().fill(Color.white.opacity(0.2)).frame(height: 1)
                    }
                    .padding(.horizontal, 40)

                    // Manual 6-digit code entry
                    VStack(spacing: 12) {
                        TextField("Enter 6-digit code", text: $manualCode)
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            #endif
                            .multilineTextAlignment(.center)
                            .font(.system(size: 22, weight: .bold, design: .monospaced))
                            .padding(.vertical, 10)
                            .padding(.horizontal, 20)
                            .background(Color(white: 0.18))
                            .foregroundColor(.white)
                            .cornerRadius(10)
                            .frame(maxWidth: 260)
                            .onChange(of: manualCode) { newValue in
                                let filtered = newValue.filter { $0.isNumber }
                                if filtered.count > 6 {
                                    manualCode = String(filtered.prefix(6))
                                } else {
                                    manualCode = filtered
                                }
                            }

                        Button(action: {
                            if manualCode.count == 6 {
                                onPairWithCode(manualCode)
                            }
                        }) {
                            if isPairingPending {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .frame(maxWidth: 260, minHeight: 44)
                            } else {
                                Text("Connect")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: 260, minHeight: 44)
                            }
                        }
                        .background(manualCode.count == 6 ? Color.blue : Color.gray.opacity(0.5))
                        .cornerRadius(10)
                        .disabled(manualCode.count != 6 || isPairingPending)
                    }

                    if let err = errorMessage {
                        Text(err)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.red)
                            .padding(.horizontal, 20)
                            .multilineTextAlignment(.center)
                    }

                    Spacer()
                }
            }
            .onAppear {
                editedServerURL = serverURLString
            }
            .onChange(of: serverURLString) { newValue in
                editedServerURL = newValue
            }
        }
    }
}
