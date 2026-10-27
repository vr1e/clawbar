import SwiftUI
import ClawBarShared

/// The global scale k. A hand-written key, because @Entry needs the missing SwiftUI macro plugin.
nonisolated struct UIScaleKey: EnvironmentKey {
    static let defaultValue: Double = 1.0
}

extension EnvironmentValues {
    var uiScale: Double {
        get { self[UIScaleKey.self] }
        set { self[UIScaleKey.self] = newValue }
    }
}

extension Color {
    init(rgba c: RGBA) {
        self.init(.sRGB, red: Double(c.r) / 255, green: Double(c.g) / 255, blue: Double(c.b) / 255, opacity: c.alpha)
    }
}

/// A WPF TextBlock: SF in Segoe UI's line box (1.33 em per line, baseline 1.079 em below the top),
/// so rows keep widget.xaml's heights and baselines. `size` is in base units.
struct WText: View {
    let text: String
    let size: Double
    var weight: Font.Weight = .regular
    let color: RGBA
    /// TextWrapping="Wrap": as many lines as the width needs.
    var wraps = false
    /// TextTrimming="CharacterEllipsis": one line cut with an ellipsis.
    var truncates = false
    var digits = false
    @Environment(\.uiScale) private var k

    init(
        _ text: String, _ size: Double, weight: Font.Weight = .regular, color: RGBA, wraps: Bool = false,
        truncates: Bool = false, digits: Bool = false
    ) {
        self.text = text
        self.size = size
        self.weight = weight
        self.color = color
        self.wraps = wraps
        self.truncates = truncates
        self.digits = digits
    }

    var body: some View {
        let s = size * k
        var t = Text(text).font(.system(size: s, weight: weight)).foregroundColor(Color(rgba: color))
        if digits { t = t.monospacedDigit() }
        return t
            .lineLimit(wraps ? nil : 1)
            .truncationMode(.tail)
            .fixedSize(horizontal: !(wraps || truncates), vertical: true)
            .modifier(WPFLineSpacing(size: s))
    }
}

/// Exact WPF line pitch where SwiftUI offers it (macOS 26), an approximation before.
struct WPFLineSpacing: ViewModifier {
    let size: Double

    /// Where SwiftUI puts the first baseline in an exact line box, in ems (measured; see TextMetricsTests).
    static let exactBaseline = 1.0

    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            let shift = (WPFLineBox.baseline - Self.exactBaseline) * size
            content
                .lineHeight(.exact(points: WPFLineBox.height * size))
                .padding(.top, shift)
                .padding(.bottom, -shift)
        } else {
            // SF's own line is about 1.18 em with its baseline at 0.97 em.
            content
                .lineSpacing((WPFLineBox.height - 1.1777) * size)
                .padding(.top, (WPFLineBox.baseline - 0.9668) * size)
                .padding(.bottom, (WPFLineBox.height - WPFLineBox.baseline - 0.2109) * size)
        }
    }
}

extension View {
    /// Reports this view's frame in card space under `id`. A hidden part's rect may linger: the regions read only the
    /// parts the view state shows, which also survives ImageRenderer tearing its views down.
    func publish(_ id: HitID, to layout: LayoutModel) -> some View {
        onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .named(CardSpace.name))
        } action: { rect in
            layout.set(id, rect)
        }
    }
}
