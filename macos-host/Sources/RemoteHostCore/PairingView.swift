import SwiftUI
import CoreImage.CIFilterBuiltins

public struct PairingView: View {
    @Binding public var pairingCode: String
    @Binding public var remainingSeconds: Int
    public let onRefreshCode: () -> Void
    public let onApproveRequest: (String) -> Void
    public let onDenyRequest: (String) -> Void

    @Binding public var pendingRequestDeviceName: String?
    @Binding public var pendingRequestDeviceId: String?

    public init(
        pairingCode: Binding<String>,
        remainingSeconds: Binding<Int>,
        pendingRequestDeviceName: Binding<String?>,
        pendingRequestDeviceId: Binding<String?>,
        onRefreshCode: @escaping () -> Void,
        onApproveRequest: @escaping (String) -> Void,
        onDenyRequest: @escaping (String) -> Void
    ) {
        self._pairingCode = pairingCode
        self._remainingSeconds = remainingSeconds
        self._pendingRequestDeviceName = pendingRequestDeviceName
        self._pendingRequestDeviceId = pendingRequestDeviceId
        self.onRefreshCode = onRefreshCode
        self.onApproveRequest = onApproveRequest
        self.onDenyRequest = onDenyRequest
    }

    public var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 4) {
                Text("Pair iOS Controller")
                    .font(.system(size: 18, weight: .bold))
                Text("Scan the QR code or enter the 6-digit code on your iPhone")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            // QR Code
            if let qrImage = generateQRCode(from: pairingCode.isEmpty ? "000000" : pairingCode) {
                Image(nsImage: qrImage)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 160, height: 160)
                    .padding(8)
                    .background(Color.white)
                    .cornerRadius(12)
                    .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
            }

            // 6-digit code display
            VStack(spacing: 8) {
                if !pairingCode.isEmpty {
                    Text(formattedCode(pairingCode))
                        .font(.system(size: 32, weight: .heavy, design: .monospaced))
                        .kerning(4)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(8)
                } else {
                    ProgressView()
                        .frame(height: 48)
                }

                HStack {
                    Image(systemName: "clock")
                        .font(.system(size: 11))
                    Text(timeString(from: remainingSeconds))
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                }
                .foregroundColor(remainingSeconds < 30 ? .red : .secondary)
            }

            // Incoming Pair Request Prompt
            if let reqName = pendingRequestDeviceName, let reqId = pendingRequestDeviceId {
                VStack(spacing: 12) {
                    Text("Connection Request")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.orange)

                    Text("\"\(reqName)\" is requesting to pair with this Mac.")
                        .font(.system(size: 12))
                        .multilineTextAlignment(.center)

                    HStack(spacing: 16) {
                        Button("Deny") {
                            onDenyRequest(reqId)
                        }
                        .buttonStyle(.bordered)

                        Button("Approve") {
                            onApproveRequest(reqId)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                    }
                }
                .padding()
                .background(Color.orange.opacity(0.12))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.orange.opacity(0.4), lineWidth: 1)
                )
            }

            // Bottom controls
            HStack {
                Button(action: onRefreshCode) {
                    Label("New Code", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundColor(.accentColor)
            }
        }
        .padding(24)
        .frame(width: 320)
    }

    private func formattedCode(_ code: String) -> String {
        guard code.count == 6 else { return code }
        let firstHalf = code.prefix(3)
        let secondHalf = code.suffix(3)
        return "\(firstHalf) \(secondHalf)"
    }

    private func timeString(from totalSeconds: Int) -> String {
        let minutes = max(totalSeconds, 0) / 60
        let seconds = max(totalSeconds, 0) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func generateQRCode(from string: String) -> NSImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.setValue(Data(string.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")

        guard let outputImage = filter.outputImage else { return nil }
        guard let cgImage = context.createCGImage(outputImage, from: outputImage.extent) else { return nil }

        return NSImage(cgImage: cgImage, size: NSSize(width: 160, height: 160))
    }
}
