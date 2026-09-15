import Foundation
import WebRTC
import CoreMedia
import CoreVideo

@MainActor
public protocol WebRTCClientDelegate: AnyObject {
    func webRTCClient(_ client: WebRTCClient, didDiscoverLocalIceCandidate candidate: IceCandidatePayload)
    func webRTCClient(_ client: WebRTCClient, didChangeConnectionState state: RTCPeerConnectionState)
    func webRTCClient(_ client: WebRTCClient, didReceiveControlMessage message: ControlChannelMessage)
    func webRTCClientDidOpenDataChannel(_ client: WebRTCClient)
    func webRTCClientDidCloseDataChannel(_ client: WebRTCClient)
}

public final class WebRTCClient: NSObject, RTCPeerConnectionDelegate, RTCDataChannelDelegate, @unchecked Sendable {
    public weak var delegate: WebRTCClientDelegate?

    private let factory: RTCPeerConnectionFactory
    private var peerConnection: RTCPeerConnection?
    private var videoSource: RTCVideoSource?
    private var localVideoTrack: RTCVideoTrack?
    private var controlDataChannel: RTCDataChannel?

    private var currentIceServers: [RTCIceServer] = [
        RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302", "stun:stun1.l.google.com:19302"])
    ]

    private let jsonEncoder = JSONEncoder()
    private let jsonDecoder = JSONDecoder()

    public override init() {
        RTCInitializeSSL()
        let videoEncoderFactory = RTCDefaultVideoEncoderFactory()
        let videoDecoderFactory = RTCDefaultVideoDecoderFactory()
        self.factory = RTCPeerConnectionFactory(
            encoderFactory: videoEncoderFactory,
            decoderFactory: videoDecoderFactory
        )
        super.init()
        setupLocalMediaTracks()
    }

    private func setupLocalMediaTracks() {
        let videoSource = factory.videoSource()
        let videoTrack = factory.videoTrack(with: videoSource, trackId: "video0")
        self.videoSource = videoSource
        self.localVideoTrack = videoTrack
    }

    public func updateIceServers(urls: [String], username: String, credential: String) {
        var servers = [RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302"])]
        if !urls.isEmpty {
            let turnServer = RTCIceServer(
                urlStrings: urls,
                username: username.isEmpty ? nil : username,
                credential: credential.isEmpty ? nil : credential
            )
            servers.append(turnServer)
        }
        self.currentIceServers = servers

        if let peerConnection = peerConnection {
            let config = RTCConfiguration()
            config.iceServers = self.currentIceServers
            config.sdpSemantics = .unifiedPlan
            peerConnection.setConfiguration(config)
        }
    }

    public func preparePeerConnection() {
        closePeerConnection()

        let config = RTCConfiguration()
        config.iceServers = self.currentIceServers
        config.sdpSemantics = .unifiedPlan
        config.continualGatheringPolicy = .gatherContinually

        let constraints = RTCMediaConstraints(
            mandatoryConstraints: [
                "OfferToReceiveVideo": "false",
                "OfferToReceiveAudio": "false"
            ],
            optionalConstraints: [
                "DtlsSrtpKeyAgreement": "true"
            ]
        )

        guard let pc = factory.peerConnection(with: config, constraints: constraints, delegate: self) else {
            print("[WebRTCClient] Failed to create peer connection")
            return
        }

        self.peerConnection = pc

        if let localVideoTrack = localVideoTrack {
            pc.add(localVideoTrack, streamIds: ["stream0"])
            applyEncodingParameters()
        }
    }

    public func applyEncodingParameters(maxBitrateBps: Int = 8_000_000, minBitrateBps: Int = 3_000_000) {
        guard let pc = peerConnection else { return }
        for sender in pc.senders {
            guard sender.track?.kind == "video" else { continue }
            let parameters = sender.parameters
            parameters.degradationPreference = NSNumber(value: RTCDegradationPreference.maintainResolution.rawValue)
            for encoding in parameters.encodings {
                encoding.maxBitrateBps = NSNumber(value: maxBitrateBps)
                encoding.minBitrateBps = NSNumber(value: minBitrateBps)
                encoding.scaleResolutionDownBy = NSNumber(value: 1.0)
            }
            sender.parameters = parameters
            print("[WebRTCClient] Applied encoding parameters: degradationPreference=maintainResolution, scaleResolutionDownBy=1.0, maxBitrate=\(maxBitrateBps) bps, minBitrate=\(minBitrateBps) bps")
        }
    }

    private func preferH264(inSdp sdp: String) -> String {
        var lines = sdp.components(separatedBy: "\r\n")
        var mVideoIndex = -1
        var h264Payloads: [String] = []
        var rtpMapPayloads: [String: String] = [:]

        for (idx, line) in lines.enumerated() {
            if line.hasPrefix("m=video ") {
                mVideoIndex = idx
            } else if line.hasPrefix("a=rtpmap:") {
                let parts = line.dropFirst(9).components(separatedBy: " ")
                if parts.count >= 2 {
                    let pt = parts[0]
                    let codecInfo = parts[1]
                    rtpMapPayloads[pt] = codecInfo
                    if codecInfo.lowercased().hasPrefix("h264") {
                        h264Payloads.append(pt)
                    }
                }
            }
        }

        guard mVideoIndex != -1, !h264Payloads.isEmpty else { return sdp }

        let mLineParts = lines[mVideoIndex].components(separatedBy: " ")
        guard mLineParts.count > 3 else { return sdp }

        let header = mLineParts[0..<3]
        let payloads = mLineParts[3...]

        var newPayloads: [String] = []
        for h264Pt in h264Payloads {
            if payloads.contains(h264Pt) {
                newPayloads.append(h264Pt)
            }
        }
        for pt in payloads {
            if !newPayloads.contains(pt) {
                newPayloads.append(pt)
            }
        }

        lines[mVideoIndex] = (header + newPayloads).joined(separator: " ")
        return lines.joined(separator: "\r\n")
    }

    public func handleRemoteOffer(sdp: String, completion: @escaping (Result<String, Error>) -> Void) {
        preparePeerConnection()

        guard let pc = peerConnection else {
            completion(.failure(NSError(domain: "WebRTCClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "PeerConnection not initialized"])))
            return
        }

        print("[WebRTCClient] Remote offer SDP:\n\(sdp)")

        let remoteDescription = RTCSessionDescription(type: .offer, sdp: sdp)
        pc.setRemoteDescription(remoteDescription) { [weak self] error in
            guard let self = self else { return }
            if let error = error {
                completion(.failure(error))
                return
            }

            let constraints = RTCMediaConstraints(
                mandatoryConstraints: [
                    "OfferToReceiveVideo": "false",
                    "OfferToReceiveAudio": "false"
                ],
                optionalConstraints: nil
            )

            pc.answer(for: constraints) { [weak self] answer, answerError in
                guard let self = self else { return }
                if let answerError = answerError {
                    completion(.failure(answerError))
                    return
                }

                guard let answer = answer else {
                    completion(.failure(NSError(domain: "WebRTCClient", code: -2, userInfo: [NSLocalizedDescriptionKey: "Answer generation returned nil"])))
                    return
                }

                let preferredSdp = self.preferH264(inSdp: answer.sdp)
                let preferredAnswer = RTCSessionDescription(type: .answer, sdp: preferredSdp)

                print("[WebRTCClient] Local answer SDP (H.264 preferred):\n\(preferredSdp)")

                pc.setLocalDescription(preferredAnswer) { [weak self] setLocalError in
                    guard let self = self else { return }
                    if let setLocalError = setLocalError {
                        completion(.failure(setLocalError))
                    } else {
                        self.applyEncodingParameters()
                        completion(.success(preferredSdp))
                    }
                }
            }
        }
    }

    public func addRemoteIceCandidate(_ candidate: IceCandidatePayload) {
        guard let pc = peerConnection else { return }
        let rtcCandidate = RTCIceCandidate(
            sdp: candidate.candidate,
            sdpMLineIndex: candidate.sdpMLineIndex ?? 0,
            sdpMid: candidate.sdpMid
        )
        pc.add(rtcCandidate) { error in
            if let error = error {
                print("[WebRTCClient] Error adding remote ICE candidate: \(error)")
            }
        }
    }

    public func feedVideoFrame(pixelBuffer: CVPixelBuffer, timestamp: CMTime) {
        guard let videoSource = videoSource else { return }
        let rtcPixelBuffer = RTCCVPixelBuffer(pixelBuffer: pixelBuffer)
        let timeStampNs = Int64(CMTimeGetSeconds(timestamp) * 1_000_000_000)
        let frame = RTCVideoFrame(buffer: rtcPixelBuffer, rotation: ._0, timeStampNs: timeStampNs)
        videoSource.capturer(RTCVideoCapturer(), didCapture: frame)
    }

    public func sendControlMessage(_ message: ControlChannelMessage) {
        guard let channel = controlDataChannel, channel.readyState == .open else {
            return
        }

        do {
            let data = try jsonEncoder.encode(message)
            let buffer = RTCDataBuffer(data: data, isBinary: false)
            channel.sendData(buffer)
        } catch {
            print("[WebRTCClient] Error encoding control message: \(error)")
        }
    }

    public func closePeerConnection() {
        controlDataChannel?.close()
        controlDataChannel = nil
        peerConnection?.close()
        peerConnection = nil
    }

    // MARK: - RTCPeerConnectionDelegate

    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}

    public func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {}

    public func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}

    public func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}

    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        print("[WebRTCClient] ICE connection state: \(newState.rawValue)")
    }

    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}

    public func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        let payload = IceCandidatePayload(
            candidate: candidate.sdp,
            sdpMid: candidate.sdpMid,
            sdpMLineIndex: candidate.sdpMLineIndex
        )
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.webRTCClient(self, didDiscoverLocalIceCandidate: payload)
        }
    }

    public func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}

    public func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        if dataChannel.label == "control" {
            self.controlDataChannel = dataChannel
            dataChannel.delegate = self
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.webRTCClientDidOpenDataChannel(self)
            }
        }
    }

    // MARK: - RTCDataChannelDelegate

    public func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {
        if dataChannel.readyState == .open {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.webRTCClientDidOpenDataChannel(self)
            }
        } else if dataChannel.readyState == .closed {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.webRTCClientDidCloseDataChannel(self)
            }
        }
    }

    public func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {
        do {
            let message = try jsonDecoder.decode(ControlChannelMessage.self, from: buffer.data)
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.webRTCClient(self, didReceiveControlMessage: message)
            }
        } catch {
            print("[WebRTCClient] Failed to decode control message from data channel: \(error)")
        }
    }
}
