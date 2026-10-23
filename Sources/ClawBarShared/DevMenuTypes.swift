/// A developer-menu click. The animation engine keeps the two sky overrides; everything else is Clawd's.
public enum DevAction: Sendable, Hashable {
    /// Back to live data: stops the demo and every Clawd and sky override.
    case auto
    case mood(Mood)
    case act(ClawdAct)
    case sweat(Bool)
    /// nil = from the limit.
    case hearts(Int?)
    case drain
    /// nil = by the clock.
    case skyPhase(SkyPhase?)
    /// nil = live weather.
    case skyWeather(Int?)
    case demo
}

/// One developer-menu item; the app turns the tree into an NSMenu.
public struct DevMenuNode: Sendable, Hashable {
    public var title: String
    public var checked: Bool
    public var enabled: Bool
    public var isSeparator: Bool
    public var action: DevAction?
    public var children: [DevMenuNode]

    public init(
        title: String, checked: Bool = false, enabled: Bool = true, isSeparator: Bool = false,
        action: DevAction? = nil, children: [DevMenuNode] = []
    ) {
        self.title = title
        self.checked = checked
        self.enabled = enabled
        self.isSeparator = isSeparator
        self.action = action
        self.children = children
    }

    public static let separator = DevMenuNode(title: "", enabled: false, isSeparator: true)
}
