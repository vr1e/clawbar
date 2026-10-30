import AppKit
import SwiftUI
import ClawBarShared

/// The card pinned to the window's top-left, scaled by k.
struct WidgetRootView: View {
    let app: AppModel
    let animation: AnimationModel
    let layout: LayoutModel

    var body: some View {
        CardView(app: app, animation: animation, layout: layout)
            .environment(\.uiScale, app.scale)
            .fixedSize()
            // While the window catches up with a new size, the card stays at the top-left.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// The panel's content view: hosts the card and takes every hit itself, so tooltips and the cursor live on one
/// view SwiftUI never manages. The panel routes clicks before views see them; the card has no gestures.
final class CardHostView: HostView<WidgetRootView> {
    convenience init(root: WidgetRootView) {
        // A real size from the start, so the first layout pass measures the card.
        self.init(rootView: root, size: CGSize(width: CardView.width, height: 300))
        // The window follows the card's measured size; SwiftUI must not resize it on its own.
        hosting.sizingOptions = []
    }

    override var isFlipped: Bool { true }
}

enum TooltipID: Hashable {
    case part(CardPart.ID)
    case hearts, sky
}

struct TooltipRegion: Equatable {
    var id: TooltipID
    /// Card space.
    var rect: CGRect
}

/// AppKit tooltips that ask for their text when shown, so a tooltip never goes stale and is only
/// re-registered when the regions move (re-registering would close one that is showing).
final class TooltipRegistrar: NSObject, NSViewToolTipOwner {
    private weak var view: NSView?
    private(set) var regions: [TooltipRegion] = []
    private var tags: [NSView.ToolTipTag: TooltipID] = [:]
    var text: (TooltipID) -> String = { _ in "" }

    init(view: NSView) {
        self.view = view
    }

    func update(_ new: [TooltipRegion]) {
        guard new != regions, let view else { return }
        view.removeAllToolTips()
        tags = [:]
        for r in new where !r.rect.isEmpty {
            let rect = view.isFlipped ? r.rect : CGRect(x: r.rect.minX, y: view.bounds.height - r.rect.maxY, width: r.rect.width, height: r.rect.height)
            tags[view.addToolTip(rect, owner: self, userData: nil)] = r.id
        }
        regions = new
    }

    func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint, userData data: UnsafeMutableRawPointer?) -> String {
        tags[tag].map(text) ?? ""
    }
}
