import Foundation
import CoreGraphics

public final class GestureController: @unchecked Sendable {
    public var displayWidthPx: Int = 0
    public var displayHeightPx: Int = 0
    public var displayScaleFactor: Double = 1.0

    public var hasReceivedDisplayInfo: Bool {
        return displayWidthPx > 0 && displayHeightPx > 0
    }

    public init() {}

    public func updateDisplayInfo(widthPx: Int, heightPx: Int, scaleFactor: Double) {
        self.displayWidthPx = widthPx
        self.displayHeightPx = heightPx
        self.displayScaleFactor = scaleFactor > 0 ? scaleFactor : 1.0
    }

    /**
     * Calculates the exact aspect-fit content rectangle of the video within the view's viewport.
     */
    public func calculateContentRect(in viewSize: CGSize) -> CGRect {
        guard viewSize.width > 0, viewSize.height > 0 else { return .zero }
        let videoWidth = CGFloat(displayWidthPx > 0 ? displayWidthPx : 1920)
        let videoHeight = CGFloat(displayHeightPx > 0 ? displayHeightPx : 1080)
        let videoAspect = videoWidth / videoHeight
        let viewAspect = viewSize.width / viewSize.height

        var contentWidth = viewSize.width
        var contentHeight = viewSize.height
        var originX: CGFloat = 0
        var originY: CGFloat = 0

        if videoAspect > viewAspect {
            // Letterbox (black bars top & bottom)
            contentHeight = viewSize.width / videoAspect
            originY = (viewSize.height - contentHeight) / 2.0
        } else {
            // Pillarbox (black bars left & right)
            contentWidth = viewSize.height * videoAspect
            originX = (viewSize.width - contentWidth) / 2.0
        }

        return CGRect(x: originX, y: originY, width: contentWidth, height: contentHeight)
    }

    /**
     * Converts a touch point in view coordinates to normalized [0.0, 1.0] relative to video content rect.
     */
    public func normalizePoint(_ point: CGPoint, in viewSize: CGSize) -> (x: Double, y: Double) {
        let contentRect = calculateContentRect(in: viewSize)
        guard contentRect.width > 0, contentRect.height > 0 else {
            return (0.5, 0.5)
        }

        let clampedX = min(max(point.x, contentRect.minX), contentRect.maxX)
        let clampedY = min(max(point.y, contentRect.minY), contentRect.maxY)

        let normX = Double((clampedX - contentRect.minX) / contentRect.width)
        let normY = Double((clampedY - contentRect.minY) / contentRect.height)

        return (min(max(normX, 0.0), 1.0), min(max(normY, 0.0), 1.0))
    }

    // MARK: - Gesture Translation

    public func handleSingleTap(at point: CGPoint, in viewSize: CGSize) -> [ControlChannelMessage]? {
        guard hasReceivedDisplayInfo else { return nil }
        let norm = normalizePoint(point, in: viewSize)
        return [
            .mouseDown(button: "left", x: norm.x, y: norm.y),
            .mouseUp(button: "left", x: norm.x, y: norm.y)
        ]
    }

    public func handleTwoFingerTap(at point: CGPoint, in viewSize: CGSize) -> [ControlChannelMessage]? {
        guard hasReceivedDisplayInfo else { return nil }
        let norm = normalizePoint(point, in: viewSize)
        return [
            .mouseDown(button: "right", x: norm.x, y: norm.y),
            .mouseUp(button: "right", x: norm.x, y: norm.y)
        ]
    }

    public func handleDragStart(at point: CGPoint, in viewSize: CGSize) -> ControlChannelMessage? {
        guard hasReceivedDisplayInfo else { return nil }
        let norm = normalizePoint(point, in: viewSize)
        return .mouseDown(button: "left", x: norm.x, y: norm.y)
    }

    public func handleDragMove(at point: CGPoint, in viewSize: CGSize) -> ControlChannelMessage? {
        guard hasReceivedDisplayInfo else { return nil }
        let norm = normalizePoint(point, in: viewSize)
        return .mouseMove(x: norm.x, y: norm.y)
    }

    public func handleDragEnd(at point: CGPoint, in viewSize: CGSize) -> ControlChannelMessage? {
        guard hasReceivedDisplayInfo else { return nil }
        let norm = normalizePoint(point, in: viewSize)
        return .mouseUp(button: "left", x: norm.x, y: norm.y)
    }

    public func handleTwoFingerScroll(deltaX: CGFloat, deltaY: CGFloat, in viewSize: CGSize) -> ControlChannelMessage? {
        guard hasReceivedDisplayInfo else { return nil }
        let contentRect = calculateContentRect(in: viewSize)
        guard contentRect.width > 0, contentRect.height > 0 else { return nil }

        let normalizedDx = Double(deltaX / contentRect.width)
        let normalizedDy = Double(deltaY / contentRect.height)

        return .scroll(dx: normalizedDx, dy: normalizedDy)
    }
}
