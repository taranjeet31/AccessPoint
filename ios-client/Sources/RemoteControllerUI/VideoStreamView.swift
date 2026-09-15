import SwiftUI
import WebRTC

#if os(iOS)
import UIKit

public struct VideoStreamView: UIViewRepresentable {
    public let videoTrack: RTCVideoTrack?

    public init(videoTrack: RTCVideoTrack?) {
        self.videoTrack = videoTrack
    }

    public func makeUIView(context: Context) -> RTCMTLVideoView {
        let view = RTCMTLVideoView(frame: .zero)
        view.videoContentMode = .scaleAspectFit
        view.backgroundColor = .black
        if let track = videoTrack {
            track.add(view)
        }
        return view
    }

    public func updateUIView(_ uiView: RTCMTLVideoView, context: Context) {
        if let track = videoTrack {
            track.add(uiView)
        }
    }
}

#elseif os(macOS)
import AppKit

public struct VideoStreamView: NSViewRepresentable {
    public let videoTrack: RTCVideoTrack?

    public init(videoTrack: RTCVideoTrack?) {
        self.videoTrack = videoTrack
    }

    public func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        return view
    }

    public func updateNSView(_ nsView: NSView, context: Context) {}
}
#endif
