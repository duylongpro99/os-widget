import AppKit
import SwiftUI

/// The popup window. It keeps the flags of the focus experiment: a non-activating utility panel at the
/// floating level, shown with `orderFrontRegardless()` and never activating the app. It also refuses to
/// become key, so clicking a button inside it does not take keyboard focus from the frontmost app.
/// Changing the style mask or the level means checking focus by hand again.
final class PopupPanel: NSPanel {
    static let width: CGFloat = 340

    private let hostingView: PopupHostingView

    init(onPointerInside: @escaping (Bool) -> Void) {
        hostingView = PopupHostingView(rootView: AnyView(EmptyView()))
        hostingView.onPointerInside = onPointerInside
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 120),
            styleMask: [.nonactivatingPanel, .titled, .closable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        title = "OS Widget"
        level = .floating
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        contentView = hostingView
    }

    /// Called instead of closing when the user clicks the title bar's close button, so the owner can
    /// hide the panel and stop its timer itself.
    var onCloseRequest: (() -> Void)?

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func close() {
        if let onCloseRequest {
            onCloseRequest()
        } else {
            super.close()
        }
    }

    /// Replaces the content and resizes the panel to fit it at the fixed width.
    func setContent(_ view: AnyView) {
        hostingView.rootView = view
        let height = hostingView.fittingSize.height
        setContentSize(NSSize(width: Self.width, height: max(height, 60)))
    }

    /// Puts the top edge of the panel just under `anchor`, centred on it and kept inside the visible
    /// frame of the screen that holds it. Without an anchor the panel goes to the top right corner of
    /// the primary screen.
    func place(under anchor: NSRect?) {
        let size = frame.size
        let margin: CGFloat = 8
        if let anchor,
           let screen = NSScreen.screens.first(where: { $0.frame.intersects(anchor) }) ?? NSScreen.screens.first {
            let visible = screen.visibleFrame
            var origin = NSPoint(x: anchor.midX - size.width / 2, y: anchor.minY - margin - size.height)
            origin.x = min(max(origin.x, visible.minX + margin), visible.maxX - margin - size.width)
            origin.y = min(max(origin.y, visible.minY + margin), visible.maxY - size.height)
            setFrameOrigin(origin)
        } else if let visible = NSScreen.screens.first?.visibleFrame {
            setFrameOrigin(NSPoint(x: visible.maxX - margin - size.width, y: visible.maxY - margin - size.height))
        }
    }
}

/// Hosts the SwiftUI content. The first click on a button acts even though the panel never becomes
/// key, and a tracking area reports when the pointer enters or leaves the panel.
private final class PopupHostingView: NSHostingView<AnyView> {
    var onPointerInside: ((Bool) -> Void)?
    private var trackingArea: NSTrackingArea?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        onPointerInside?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onPointerInside?(false)
    }
}
