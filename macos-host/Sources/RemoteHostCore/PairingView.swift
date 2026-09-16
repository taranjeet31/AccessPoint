import SwiftUI
import CoreImage.CIFilterBuiltins

public struct PairingView: View {
    @ObservedObject public var controller: MenuBarController

    public init(controller: MenuBarController) {
        self.controller = controller
    }

    private var reachableServerUrl: String {
        let rawUrl = controller.signalingClient.serverURL.absoluteString
        guard let url = URL(string: rawUrl),
              let host = url.host,
              (host == "localhost" || host == "127.0.0.1") else {
            return rawUrl
        }
        if let reachableIP = getLocalIPAddress() {
            var comp = URLComponents(url: url, resolvingAgainstBaseURL: false)
            comp?.host = reachableIP
            return comp?.url?.absoluteString ?? rawUrl
        }
        return rawUrl
    }

    private var qrCodePayload: String {
        let code = controller.pairingCode.isEmpty ? "000000" : controller.pairingCode
        return "{\"code\":\"\(code)\",\"serverUrl\":\"\(reachableServerUrl)\"}"
    }

    private func getLocalIPAddress() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        var tailscaleIP: String?
        var lanIP: String?

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ptr.pointee
            let addrFamily = interface.ifa_addr.pointee.sa_family
            if addrFamily == UInt8(AF_INET) {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                            &hostname, socklen_t(hostname.count),
                            nil, socklen_t(0), NI_NUMERICHOST)
                let ip = String(cString: hostname)
                if !ip.hasPrefix("127.") {
                    if ip.hasPrefix("100.") {
                        tailscaleIP = ip
                    } else if lanIP == nil {
                        lanIP = ip
                    }
                }
            }
        }
        return tailscaleIP ?? lanIP
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
            if let qrImage = generateQRCode(from: qrCodePayload) {
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
                if !controller.pairingCode.isEmpty {
                    Text(formattedCode(controller.pairingCode))
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
                    Text(timeString(from: controller.remainingSeconds))
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                }
                .foregroundColor(controller.remainingSeconds < 30 ? .red : .secondary)
            }

            // Incoming Pair Request Prompt
            if let reqName = controller.pendingRequestDeviceName, let reqId = controller.pendingRequestDeviceId {
                VStack(spacing: 12) {
                    Text("Connection Request")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.orange)

                    Text("\"\(reqName)\" is requesting to pair with this Mac.")
                        .font(.system(size: 12))
                        .multilineTextAlignment(.center)

                    HStack(spacing: 16) {
                        Button("Deny") {
                            controller.denyPairRequest(reqId)
                        }
                        .buttonStyle(.bordered)

                        Button("Approve") {
                            controller.approvePairRequest(reqId)
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
            VStack(spacing: 6) {
                Button(action: {
                    controller.refreshPairingCode()
                }) {
                    Label("New Code", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundColor(.accentColor)

                Text("Signaling URL: \(reachableServerUrl)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        }
        .padding(24)
        .frame(width: 340, height: 460)
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

    private static let ciContext = CIContext()

    private func generateQRCode(from string: String) -> NSImage? {
        guard !string.isEmpty,
              let data = string.data(using: .utf8),
              let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let outputImage = filter.outputImage else { return nil }
        let transform = CGAffineTransform(scaleX: 5, y: 5)
        let scaledImage = outputImage.transformed(by: transform)
        guard let cgImage = Self.ciContext.createCGImage(scaledImage, from: scaledImage.extent) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: 160, height: 160))
    }
}
