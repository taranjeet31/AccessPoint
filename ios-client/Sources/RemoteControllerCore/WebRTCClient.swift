import Foundation
import WebRTC

@MainActor
public protocol WebRTCClientDelegate: AnyObject {
    func webRTCClient(_ client: WebRTCClient, didDiscoverLocalIceCandidate candidate: IceCandidatePayload)
    func webRTCClient(_ client: WebRTCClient, didChangeConnectionState state: RTCIceConnectionState)
    func webRTCClient(_ client: WebRTCClient, didReceiveRemoteVideoTrack videoTrack: RTCVideoTrack)
    func webRTCClient(_ client: WebRTCClient, didReceiveControlMessage message: ControlChannelMessage)
    func webRTCClientDidOpenDataChannel(_ client: WebRTCClient)
    func webRTCClientDidCloseDataChannel(_ client: WebRTCClient)
}

public final class WebRTCClient: NSObject, RTCPeerConnectionDelegate, RTCDataChannelDelegate, @unchecked Sendable {
    public weak var delegate: WebRTCClientDelegate?

    private let factory: RTCPeerConnectionFactory
    private var peerConnection: RTCPeerConnection?
    private var controlDataChannel: RTCDataChannel?
    public private(set) var remoteVideoTrack: RTCVideoTrack?

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

    public func createOffer(restartIce: Bool = false, completion: @escaping (Result<String, Error>) -> Void) {
        if peerConnection == nil || restartIce {
            setupPeerConnection()
        }

        guard let pc = peerConnection else {
            completion(.failure(NSError(domain: "WebRTCClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "PeerConnection not initialized"])))
            return
        }

        // Create data channel before offer (controller initiates data channel)
        if controlDataChannel == nil {
            let dataChannelConfig = RTCDataChannelConfiguration()
            dataChannelConfig.isOrdered = true
            let channel = pc.dataChannel(forLabel: "control", configuration: dataChannelConfig)
            channel?.delegate = self
            self.controlDataChannel = channel
        }

        let mandatoryConstraints: [String: String] = [
            "OfferToReceiveVideo": "true",
            "OfferToReceiveAudio": "false",
            "IceRestart": restartIce ? "true" : "false"
        ]

        let constraints = RTCMediaConstraints(
            mandatoryConstraints: mandatoryConstraints,
            optionalConstraints: [
                "DtlsSrtpKeyAgreement": "true"
            ]
        )

        pc.offer(for: constraints) { [weak self] offer, error in
            guard self != nil else { return }
            if let error = error {
                completion(.failure(error))
                return
            }

            guard let offer = offer else {
                completion(.failure(NSError(domain: "WebRTCClient", code: -2, userInfo: [NSLocalizedDescriptionKey: "Offer generation returned nil"])))
                return
            }

            pc.setLocalDescription(offer) { setLocalError in
                if let setLocalError = setLocalError {
                    completion(.failure(setLocalError))
                } else {
                    completion(.success(offer.sdp))
                }
            }
        }
    }

    private func setupPeerConnection() {
        closePeerConnection()

        let config = RTCConfiguration()
        config.iceServers = self.currentIceServers
        config.sdpSemantics = .unifiedPlan
        config.continualGatheringPolicy = .gatherContinually

        let constraints = RTCMediaConstraints(
            mandatoryConstraints: [
                "OfferToReceiveVideo": "true",
                "OfferToReceiveAudio": "false"
            ],
            optionalConstraints: [
                "DtlsSrtpKeyAgreement": "true"
            ]
        )

        guard let pc = factory.peerConnection(with: config, constraints: constraints, delegate: self) else {
            print("[WebRTCClient-iOS] Failed to create peer connection")
            return
        }

        self.peerConnection = pc
    }

    public func handleRemoteAnswer(sdp: String, completion: @escaping (Error?) -> Void) {
        guard let pc = peerConnection else {
            completion(NSError(domain: "WebRTCClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "PeerConnection not initialized"]))
            return
        }

        let remoteDescription = RTCSessionDescription(type: .answer, sdp: sdp)
        pc.setRemoteDescription(remoteDescription) { error in
            completion(error)
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
                print("[WebRTCClient-iOS] Error adding remote ICE candidate: \(error)")
            }
        }
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
            print("[WebRTCClient-iOS] Error encoding control message: \(error)")
        }
    }

    public func closePeerConnection() {
        controlDataChannel?.close()
        controlDataChannel = nil
        peerConnection?.close()
        peerConnection = nil
        remoteVideoTrack = nil
    }

    // MARK: - RTCPeerConnectionDelegate

    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}

    public func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        print("[WebRTCClient-iOS] Received stream with \(stream.videoTracks.count) video tracks")
        if let track = stream.videoTracks.first {
            self.remoteVideoTrack = track
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.webRTCClient(self, didReceiveRemoteVideoTrack: track)
            }
        }
    }

    public func peerConnection(_ peerConnection: RTCPeerConnection, didAdd receiver: RTCRtpReceiver, streams: [RTCMediaStream]) {
        print("[WebRTCClient-iOS] Received RTP receiver with track: \(String(describing: receiver.track))")
        if let track = receiver.track as? RTCVideoTrack {
            self.remoteVideoTrack = track
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.webRTCClient(self, didReceiveRemoteVideoTrack: track)
            }
        }
    }

    public func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}

    public func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}

    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.webRTCClient(self, didChangeConnectionState: newState)
        }
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
            print("[WebRTCClient-iOS] Failed to decode control message from data channel: \(error)")
        }
    }
}
