import SwiftUI
import ClawBarShared

/// widget.xaml's card in base units × k. Holds no NSViewRepresentable, so ImageRenderer can draw it.
struct CardView: View {
    let app: AppModel
    let animation: AnimationModel
    let layout: LayoutModel
    @Environment(\.uiScale) private var k

    static let width = 262.0
    static let content = PlayArea.content

    var body: some View {
        let v = app.view
        VStack(alignment: .leading, spacing: 0) {
            HeaderRow(v: v, animation: animation, layout: layout)
                .padding(.bottom, 6 * k)
            PercentRow(v: v, mascot: app.mascotVisible, sky: app.skyVisible, animation: animation, layout: layout)
                .padding(.bottom, 4 * k)
            Bar(fraction: v.mainFraction, color: v.mainBarColor, height: 6, radius: 3)
                .padding(.bottom, 7 * k)
            // An empty TextBlock keeps its line box in WPF, so the card keeps its height without a reset time.
            WText(v.resetText.isEmpty ? " " : v.resetText, 11, color: v.resetColor, wraps: true)
                .frame(width: Self.content * k, alignment: .leading)
                .publish(.part(.reset), to: layout)
                .padding(.bottom, (v.shows(.play) ? 6 : 9) * k)
            if v.shows(.play) {
                PlayButton(text: v.playText)
                    .publish(.part(.play), to: layout)
                    .padding(.bottom, 10 * k)
            }
            BarLabelRow(row: v.otherLimit, palette: v.palette)
                .padding(.bottom, 4 * k)
            Bar(fraction: v.otherLimit.fraction, color: v.otherLimit.color, height: 4, radius: 2)
                .padding(.bottom, 7 * k)
            ForEach(Array(v.modelWeeks.enumerated()), id: \.offset) { i, row in
                BarLabelRow(row: row, palette: v.palette)
                    .padding(.bottom, 4 * k)
                Bar(fraction: row.fraction, color: row.color, height: 4, radius: 2)
                    .padding(.bottom, i == v.modelWeeks.count - 1 ? 0 : 7 * k)
            }
            if v.shows(.sessions) {
                SessionsRow(v: v, layout: layout)
                    .padding(.top, 10 * k)
            }
            if v.shows(.status) {
                StatusRow(v: v, layout: layout)
                    .padding(.top, 10 * k)
            }
            if v.detailsExpanded {
                DetailsBlock(v: v, app: app, layout: layout)
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
                outer.inset(by: 1 * k).fill(Color(rgba: v.palette.background))
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
            WText(v.title, 9.5, weight: .semibold, color: v.palette.muted)
            HStack(alignment: .top, spacing: 0) {
                Spacer(minLength: 0)
                HeartsView(animation: animation, layout: layout, heartOff: v.palette.heartOff)
                    .frame(height: WPFLineBox.height * 13 * k)
                WText(v.detailsGlyph, 11, color: v.palette.muted)
                    .publish(.part(.details), to: layout)
                    .padding(.trailing, 9 * k)
                WText("–", 13, color: v.palette.muted)
                    .publish(.part(.hide), to: layout)
                    .padding(.trailing, 9 * k)
                WText("✕", 11, color: v.palette.muted)
                    .publish(.part(.exit), to: layout)
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
                MascotView(animation: animation, layout: layout, captionColor: v.palette.label)
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
            WText("%", 14, color: v.palette.muted)
                .padding(.leading, 2 * k)
                .alignmentGuide(.lastTextBaseline) { d in d[.lastTextBaseline] + rise }
        }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(CardSpace.name)) } action: { r in
            layout.set(.number, r)
            layout.setNumberWidth(r.width / scale)
        }
    }
}

/// A rounded track with a left-aligned fill of `fraction × width`.
private struct Bar: View {
    let fraction: Double
    let color: RGBA
    let height: Double
    let radius: Double
    var width = CardView.content
    @Environment(\.uiScale) private var k

    var body: some View {
        let f = fraction.isFinite ? min(1, max(0, fraction)) : 0
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: radius * k).fill(Color(rgba: Palette.track))
            RoundedRectangle(cornerRadius: radius * k).fill(Color(rgba: color))
                .frame(width: f * width * k)
        }
        .frame(width: width * k, height: height * k)
    }
}

/// Clawd Run's button, the width of the bars: a pixel Clawd and the label in his orange on a faint tint of it.
private struct PlayButton: View {
    let text: String
    @Environment(\.uiScale) private var k

    static let sprite: [DrawOp] = [
        .rects(PixelArt.rects(PixelArt.clawdStanding, value: "#", px: 1, py: 1), Palette.clawdBody, opacity: 1),
        .rects(PixelArt.rects(PixelArt.clawdStanding, value: "o", px: 1, py: 1), Palette.clawdEyes, opacity: 1),
    ]

    var body: some View {
        let scale = k
        HStack(alignment: .center, spacing: 7 * k) {
            Canvas { ctx, _ in
                ctx.scaleBy(x: scale, y: scale)
                DrawOpRenderer.draw(Self.sprite, in: &ctx)
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
    let palette: ThemePalette
    @Environment(\.uiScale) private var k

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            WText(row.label, 9, weight: .semibold, color: palette.label)
            Spacer(minLength: 4 * k)
            WText(row.value, 10, color: palette.muted)
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
            WText(v.sessionsLabel, 9, weight: .semibold, color: v.palette.label)
                .padding(.trailing, 8 * k)
            WText(v.sessionsText, 10, color: v.palette.muted, truncates: true)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(width: CardView.content * k)
        .publish(.part(.sessions), to: layout)
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
                    WText(v.statusLine2, 10, color: v.palette.muted, wraps: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: CardView.content * k)
        .publish(.part(.status), to: layout)
    }
}

/// The 24 h / 7 d stats, the 7-day chart and its top projects, the Claude Code version line and the ClawBar line.
private struct DetailsBlock: View {
    let v: WidgetViewState
    let app: AppModel
    let layout: LayoutModel
    @Environment(\.uiScale) private var k

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if v.statsVisible {
                Divider(k: k).padding(.bottom, 8 * k)
                period(v.dayLabel, v.dayMain, v.dayExtra)
                period(v.week7Label, v.week7Main, v.week7Extra)
            }
            if let history = v.history {
                HistoryBlock(h: history, palette: v.palette, app: app, layout: layout)
            }
            if let projects = v.projects {
                ProjectsBlock(p: projects, palette: v.palette, layout: layout)
            }
            Divider(k: k).padding(.bottom, 7 * k)
            HStack(alignment: .top, spacing: 0) {
                if v.shows(.version) {
                    // A Stretch column with a transparent background: the whole column is the link.
                    WText(v.versionText, 10, color: v.versionColor, wraps: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .publish(.part(.version), to: layout)
                } else {
                    Spacer(minLength: 0)
                }
                WText(v.appVersionText, 10, color: v.palette.label)
                    .publish(.part(.appVersion), to: layout)
                    .padding(.leading, 8 * k)
            }
            .frame(width: CardView.content * k)
        }
    }

    /// An empty extra line is left out, but its section gap stays.
    @ViewBuilder
    private func period(_ label: String, _ main: String, _ extra: String) -> some View {
        WText(label, 9, weight: .semibold, color: v.palette.label)
            .padding(.bottom, 3 * k)
        WText(main, 10.5, color: v.palette.secondary, wraps: true)
            .frame(width: CardView.content * k, alignment: .leading)
            .padding(.bottom, (extra.isEmpty ? 10 : 2) * k)
        if !extra.isEmpty {
            WText(extra, 10, color: v.palette.muted, wraps: true)
                .frame(width: CardView.content * k, alignment: .leading)
                .padding(.bottom, 10 * k)
        }
    }
}

/// widget.xaml's HistPanel: the label, the chart, a weekday under each day, and the legend or why there is none.
private struct HistoryBlock: View {
    let h: HistoryView
    let palette: ThemePalette
    let app: AppModel
    let layout: LayoutModel
    @Environment(\.uiScale) private var k

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider(k: k).padding(.bottom, 8 * k)
            WText(h.label, 9, weight: .semibold, color: palette.label)
                .padding(.bottom, 4 * k)
            HistoryChartView(h: h, weekColor: palette.accent)
                .frame(width: HistoryView.width * k, height: HistoryView.height * k)
                .overlay(alignment: .topLeading) { HistoryCursor(app: app) }
                .clipped()
                .publish(.history, to: layout)
            ZStack(alignment: .topLeading) {
                ForEach(h.days, id: \.from) { day in
                    WText(day.text, 8, color: palette.footer)
                        .frame(width: (day.to - day.from) * k)
                        .offset(x: day.from * k)
                }
            }
            .frame(width: HistoryView.width * k, height: 11 * k, alignment: .topLeading)
            HistoryCaption(h: h, palette: palette, app: app)
                .frame(width: CardView.content * k, alignment: .leading)
                .padding(.top, 1 * k)
                .padding(.bottom, 10 * k)
        }
    }
}

/// The line under the pointer, in its own view so a mouse move redraws only it.
private struct HistoryCursor: View {
    let app: AppModel
    @Environment(\.uiScale) private var k

    var body: some View {
        if let hover = app.historyHover {
            Rectangle()
                .fill(Color(rgba: Palette.chartCursor))
                .frame(width: 1 * k, height: HistoryView.height * k)
                .offset(x: (hover.x - 0.5) * k)
        }
    }
}

/// The hover's readout, else the legend, else why the chart is empty.
private struct HistoryCaption: View {
    let h: HistoryView
    let palette: ThemePalette
    let app: AppModel
    @Environment(\.uiScale) private var k

    var body: some View {
        let text = app.historyHover?.caption ?? h.caption
        if text.isEmpty {
            HStack(alignment: .top, spacing: 0) {
                legend(h.sessionName, HistoryChartView.sessionColor)
                // Four spaces of 10-pt text between the entries, as Set-HistLegend pads them.
                legend(h.weekName, palette.accent)
                    .padding(.leading, 11 * k)
            }
        } else {
            WText(text, 10, color: palette.muted, truncates: true)
        }
    }

    private func legend(_ name: String, _ color: RGBA) -> some View {
        HStack(alignment: .top, spacing: 0) {
            WText("━ ", 10, color: color)
            WText(name, 10, color: palette.muted)
        }
    }
}

/// widget.xaml's ProjPanel: the label, then a row per project, or `counting...` before the first scan.
private struct ProjectsBlock: View {
    let p: ProjectsView
    let palette: ThemePalette
    let layout: LayoutModel
    @Environment(\.uiScale) private var k

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The StackPanel stretches LblProj, so its tooltip spans the column.
            WText(p.label, 9, weight: .semibold, color: palette.label)
                .frame(width: CardView.content * k, alignment: .leading)
                .publish(.part(.projectsLabel), to: layout)
                .padding(.bottom, 4 * k)
            if p.rows.isEmpty {
                WText(p.caption, 10, color: palette.label)
            } else {
                // Published before the padding, so a row's tooltip leaves out the 2 below it, as the Grid's margin does.
                ForEach(Array(p.rows.enumerated()), id: \.offset) { i, row in
                    ProjectRowView(row: row, palette: palette)
                        .publish(.part(.project(i)), to: layout)
                        .padding(.bottom, 2 * k)
                }
            }
        }
        .padding(.bottom, 10 * k)
    }
}

/// Show-Projects' Grid: the name with 8 to spare, the bar centred on its track, the share right-aligned.
private struct ProjectRowView: View {
    let row: ProjectRow
    let palette: ThemePalette
    @Environment(\.uiScale) private var k

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            WText(row.name, 10, color: palette.secondary, truncates: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 8 * k)
            Bar(fraction: row.fraction, color: Palette.projectBar, height: 4, radius: 2, width: ProjectsView.trackWidth)
            WText(row.share, 10, color: palette.muted)
                .frame(width: ProjectsView.shareWidth * k, alignment: .trailing)
        }
        .frame(width: CardView.content * k)
    }
}

/// The midnights, then the week line, the session's fill and its line on top, as Draw-HistoryChart adds them.
private struct HistoryChartView: View {
    let h: HistoryView
    /// The week bar's role, so a theme's accent recolours both.
    let weekColor: RGBA
    @Environment(\.uiScale) private var k

    static let sessionColor = Palette.ok

    var body: some View {
        let scale = k
        Canvas { ctx, _ in
            ctx.scaleBy(x: scale, y: scale)
            let height = HistoryView.height
            for x in h.dayTicks {
                ctx.fill(Path(CGRect(x: x - 0.5, y: 0, width: 1, height: height)), with: .color(Color(rgba: Palette.divider)))
            }
            let stroke = StrokeStyle(lineWidth: 1.2, lineJoin: .round)
            ctx.stroke(Self.lines(h.weekRuns), with: .color(Color(rgba: weekColor)), style: stroke)
            var fill = Path()
            for run in h.sessionRuns {
                guard let first = run.first, let last = run.last else { continue }
                fill.addLines(run + [CGPoint(x: last.x, y: height), CGPoint(x: first.x, y: height)])
                fill.closeSubpath()
            }
            ctx.fill(fill, with: .color(Color(rgba: Palette.chartFill)))
            ctx.stroke(Self.lines(h.sessionRuns), with: .color(Color(rgba: Self.sessionColor)), style: stroke)
        }
    }

    static func lines(_ runs: [[CGPoint]]) -> Path {
        var path = Path()
        for run in runs { path.addLines(run) }
        return path
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
            if v.shows(.account) {
                WText(v.accountText, 9, color: v.accountColor, truncates: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .publish(.part(.account), to: layout)
                    .padding(.trailing, 8 * k)
            } else {
                Spacer(minLength: 0)
            }
            if !v.stampText.isEmpty {
                WText(v.stampText, 9, color: v.stampColor)
            }
        }
        .frame(width: CardView.content * k, height: WPFLineBox.height * 9 * k, alignment: .topLeading)
    }
}
