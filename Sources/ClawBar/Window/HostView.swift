import AppKit
import SwiftUI

/// A window's content view that hosts SwiftUI and takes every hit itself, so AppKit handles the events and SwiftUI
/// only draws.
class HostView<Content: View>: NSView {
    let hosting: NSHostingView<Content>

    init(rootView: Content, size: CGSize) {
        hosting = NSHostingView(rootView: rootView)
        super.init(frame: CGRect(origin: .zero, size: size))
        hosting.frame = bounds
        hosting.autoresizingMask = [.width, .height]
        addSubview(hosting)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override func hitTest(_ point: NSPoint) -> NSView? {
        frame.contains(point) ? self : nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
