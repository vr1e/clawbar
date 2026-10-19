import SwiftUI
import ClawBarShared

/// widget.xaml's card in base units × k. Holds no NSViewRepresentable, so ImageRenderer can draw it.
struct CardView: View {
    let app: AppModel
    let animation: AnimationModel
    let layout: LayoutModel
    @Environment(\.uiScale) private var k

    static let width = 262.0
    static let content = 236.0

    var body: some View {
        let v = app.view
        VStack(alignment: .leading, spacing: 0) {
            HeaderRow(v: v, animation: animation, layout: layout)
                .padding(.bottom, 6 * k)
            PercentRow(v: v, mascot: app.mascotVisible, sky: app.skyVisible, animation: animation, layout: layout)
                .padding(.bottom, 4 * k)
            Bar(fraction: v.sessionFraction, color: v.sessionBarColor, height: 6, radius: 3)
                .padding(.bottom, 7 * k)
            // An empty TextBlock keeps its line box in WPF, so the card keeps its height without a reset time.
            WText(v.resetText.isEmpty ? " " : v.resetText, 11, color: v.resetColor, wraps: true)
                .frame(width: Self.content * k, alignment: .leading)
                .publish(.reset, to: layout)
                .padding(.bottom, (v.playText.isEmpty ? 9 : 6) * k)
            if !v.playText.isEmpty {
                PlayButton(text: v.playText)
                    .publish(.play, to: layout)
                    .padding(.bottom, 10 * k)
            }
            BarLabelRow(row: v.week)
                .padding(.bottom, 4 * k)
            Bar(fraction: v.week.fraction, color: v.week.color, height: 4, radius: 2)
                .padding(.bottom, 7 * k)
            ForEach(Array(v.modelWeeks.enumerated()), id: \.offset) { i, row in
                BarLabelRow(row: row)
                    .padding(.bottom, 4 * k)
                Bar(fraction: row.fraction, color: row.color, height: 4, radius: 2)
                    .padding(.bottom, i == v.modelWeeks.count - 1 ? 0 : 7 * k)
            }
            if v.sessionsVisible {
                SessionsRow(v: v, layout: layout)
                    .padding(.top, 10 * k)
            }
            if v.statusVisible {
                StatusRow(v: v, layout: layout)
                    .padding(.top, 10 * k)
            }
            if v.detailsExpanded {
                DetailsBlock(v: v, layout: layout)
                    .padding(.top, 11 * k)
            }
            FooterRow(v: v, layout: layout)
                .padding(.top, 7 * k)
        }
        .frame(width: Self.content * k, alignment: .leading)
        // Padding 12/10/12/11 inside a 1-wide border.
        .padding(EdgeInsets(top: 11 * k, leading: 13 * k, bottom: 12 * k, trailing: 13 * k))
        .background {
            // WPF fills only inside the border, so the rim shows #33FFFFFF over whatever is behind the window.
            let outer = RoundedRectangle(cornerRadius: 10 * k)
            ZStack {
                outer.inset(by: 1 * k).fill(Color(rgba: Palette.card))
                outer.strokeBorder(Color(rgba: Palette.border), lineWidth: 1 * k)
            }
        }
        .coordinateSpace(.named(CardSpace.name))
        .onGeometryChange(for: CGSize.self) { $0.size } action: { layout.setCardSize($0) }
    }
}

/// CLAUDE USAGE on the left; hearts, ▾/▴, – and ✕ on the right.
private struct HeaderRow: View {
    let v: WidgetViewState
    let animation: AnimationModel
    let layout: LayoutModel
    @Environment(\.uiScale) private var k

    var body: some View {
        // One Grid cell: the title centred vertically against the glyph stack, whose tallest line is the 13-pt "–".
        ZStack(alignment: .leading) {
            WText(v.title, 9.5, weight: .semibold, color: Palette.muted)
            HStack(alignment: .top, spacing: 0) {
                Spacer(minLength: 0)
                HeartsView(animation: animation, layout: layout)
                    .frame(height: WPFLineBox.height * 13 * k)
                WText(v.detailsGlyph, 11, color: Palette.muted)
                    .publish(.details, to: layout)
                    .padding(.trailing, 9 * k)
                WText("–", 13, color: Palette.muted)
                    .publish(.hide, to: layout)
                    .padding(.trailing, 9 * k)
                WText("✕", 11, color: Palette.muted)
                    .publish(.exit, to: layout)
            }
        }
        .frame(width: CardView.content * k)
    }
}

/// The 40-tall row: the sky behind, the number with its superscript %, and Clawd's layer over both.
private struct PercentRow: View {
    let v: WidgetViewState
    let mascot: Bool
    let sky: Bool
    let animation: AnimationModel
    let layout: LayoutModel
    @Environment(\.uiScale) private var k

    var body: some View {
        ZStack(alignment: .topLeading) {
            if sky {
                // Bottom margin −3: the sky reaches the ground line below the row.
                SkyView(animation: animation)
                    .frame(width: CardView.content * k, height: PlayArea.height * k)
            }
            NumberView(v: v, layout: layout)
                .frame(width: CardView.content * k, height: 40 * k, alignment: .bottomLeading)
        }
        .frame(width: CardView.content * k, height: 40 * k, alignment: .topLeading)
        .publish(.percentRow, to: layout)
        .overlay(alignment: .topLeading) {
            if mascot {
                // One surface over the whole card width, 10 above the row and 6 below the ground,
                // so nothing of Clawd's is clipped; the session bar after this row draws over its lowest band.
                MascotView(animation: animation, layout: layout)
                    .frame(width: CardView.width * k, height: MascotView.height * k)
                    .offset(x: -13 * k, y: -MascotView.top * k)
                    .allowsHitTesting(false)
            }
        }
    }
}

private struct NumberView: View {
    let v: WidgetViewState
    let layout: LayoutModel
    @Environment(\.uiScale) private var k

    /// Both WPF line boxes start at the stack's top, so the % baseline is (30 − 14) × 1.079 above the number's.
    static let percentRise = (30.0 - 14.0) * WPFLineBox.baseline

    var body: some View {
        let rise = Self.percentRise * k
        let scale = k
        HStack(alignment: .lastTextBaseline, spacing: 0) {
            WText(v.pctText, 30, weight: .light, color: v.pctColor, digits: true)
            WText("%", 14, color: Palette.muted)
                .padding(.leading, 2 * k)
                .alignmentGuide(.lastTextBaseline) { d in d[.lastTextBaseline] + rise }
        }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(CardSpace.name)) } action: { r in
            layout.set(.number, r)
            layout.setNumberWidth(r.width / scale)
        }
    }
}

/// A rounded track with a left-aligned fill of `fraction × 236`.
private struct Bar: View {
    let fraction: Double
    let color: RGBA
    let height: Double
    let radius: Double
    @Environment(\.uiScale) private var k

    var body: some View {
        let f = fraction.isFinite ? min(1, max(0, fraction)) : 0
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: radius * k).fill(Color(rgba: Palette.track))
            RoundedRectangle(cornerRadius: radius * k).fill(Color(rgba: color))
                .frame(width: f * CardView.content * k)
        }
        .frame(width: CardView.content * k, height: height * k)
    }
}

/// Clawd Run's button, the width of the bars: a pixel Clawd and the label in his orange on a faint tint of it.
private struct PlayButton: View {
    let text: String
    @Environment(\.uiScale) private var k

    static let sprite = PixelArt.rects(PixelArt.clawdStanding, value: "#", px: 1, py: 1)
    static let eyes = PixelArt.rects(PixelArt.clawdStanding, value: "o", px: 1, py: 1)

    var body: some View {
        let scale = k
        HStack(alignment: .center, spacing: 7 * k) {
            Canvas { ctx, _ in
                ctx.scaleBy(x: scale, y: scale)
                var shape = Path()
                shape.addRects(Self.sprite)
                ctx.fill(shape, with: .color(Color(rgba: Palette.clawdBody)))
                var eyes = Path()
                eyes.addRects(Self.eyes)
                ctx.fill(eyes, with: .color(Color(rgba: Palette.clawdEyes)))
            }
            // The sprite's two empty bottom rows are left off, so Clawd centres on the label.
            .frame(width: 18 * k, height: 10 * k)
            WText(text, 10.5, weight: .semibold, color: Palette.clawdBody)
        }
        .frame(width: CardView.content * k, height: 24 * k)
        .background {
            let shape = RoundedRectangle(cornerRadius: 6 * k)
            ZStack {
                shape.fill(Color(rgba: Palette.clawdBody).opacity(0.14))
                shape.strokeBorder(Color(rgba: Palette.clawdBody).opacity(0.5), lineWidth: 1 * k)
            }
        }
    }
}

/// WEEK and the model weeks: the label left, the value right, in one Grid cell.
private struct BarLabelRow: View {
    let row: BarRow
    @Environment(\.uiScale) private var k

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            WText(row.label, 9, weight: .semibold, color: Palette.label)
            Spacer(minLength: 4 * k)
            WText(row.value, 10, color: Palette.muted)
        }
        .frame(width: CardView.content * k)
    }
}

private struct SessionsRow: View {
    let v: WidgetViewState
    let layout: LayoutModel
    @Environment(\.uiScale) private var k

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            WText(v.sessionsLabel, 9, weight: .semibold, color: Palette.label)
                .padding(.trailing, 8 * k)
            WText(v.sessionsText, 10, color: Palette.muted, truncates: true)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(width: CardView.content * k)
        .publish(.sessions, to: layout)
    }
}

private struct StatusRow: View {
    let v: WidgetViewState
    let layout: LayoutModel
    @Environment(\.uiScale) private var k

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Circle()
                .fill(Color(rgba: v.statusDotColor))
                .frame(width: 7 * k, height: 7 * k)
                .padding(.top, 4 * k)
                .padding(.trailing, 6 * k)
            VStack(alignment: .leading, spacing: 0) {
                WText(v.statusText, 10.5, color: v.statusTextColor, wraps: true)
                if !v.statusLine2.isEmpty {
                    WText(v.statusLine2, 10, color: Palette.muted, wraps: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: CardView.content * k)
        .publish(.status, to: layout)
    }
}

/// The 24 h / 7 d stats, the Claude Code version line and the ClawBar line.
private struct DetailsBlock: View {
    let v: WidgetViewState
    let layout: LayoutModel
    @Environment(\.uiScale) private var k

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if v.statsVisible {
                Divider(k: k).padding(.bottom, 8 * k)
                period(v.dayLabel, v.dayMain, v.dayExtra)
                period(v.week7Label, v.week7Main, v.week7Extra)
            }
            Divider(k: k).padding(.bottom, 7 * k)
            HStack(alignment: .top, spacing: 0) {
                if v.versionText.isEmpty {
                    Spacer(minLength: 0)
                } else {
                    // A Stretch column with a transparent background: the whole column is the link.
                    WText(v.versionText, 10, color: v.versionColor, wraps: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .publish(.version, to: layout)
                }
                WText(v.appVersionText, 10, color: Palette.label)
                    .publish(.appVersion, to: layout)
                    .padding(.leading, 8 * k)
            }
            .frame(width: CardView.content * k)
        }
    }

    /// An empty extra line is left out, but its section gap stays.
    @ViewBuilder
    private func period(_ label: String, _ main: String, _ extra: String) -> some View {
        WText(label, 9, weight: .semibold, color: Palette.label)
            .padding(.bottom, 3 * k)
        WText(main, 10.5, color: Palette.secondary, wraps: true)
            .frame(width: CardView.content * k, alignment: .leading)
            .padding(.bottom, (extra.isEmpty ? 10 : 2) * k)
        if !extra.isEmpty {
            WText(extra, 10, color: Palette.muted, wraps: true)
                .frame(width: CardView.content * k, alignment: .leading)
                .padding(.bottom, 10 * k)
        }
    }
}

private struct Divider: View {
    let k: Double

    var body: some View {
        Rectangle()
            .fill(Color(rgba: Palette.divider))
            .frame(width: CardView.content * k, height: 1 * k)
    }
}

/// Account on the left (ellipsis), the last update's time on the right; one 9-pt line even when empty.
private struct FooterRow: View {
    let v: WidgetViewState
    let layout: LayoutModel
    @Environment(\.uiScale) private var k

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if v.accountText.isEmpty {
                Spacer(minLength: 0)
            } else {
                WText(v.accountText, 9, color: v.accountColor, truncates: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .publish(.account, to: layout)
                    .padding(.trailing, 8 * k)
            }
            if !v.stampText.isEmpty {
                WText(v.stampText, 9, color: v.stampColor)
            }
        }
        .frame(width: CardView.content * k, height: WPFLineBox.height * 9 * k, alignment: .topLeading)
    }
}
