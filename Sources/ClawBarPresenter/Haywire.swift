import ClawBarShared

/// cyberpunk.ps1's Set-RelicHaywire on the presented view state: numbers jump, captions crumble into junk and the
/// bars twitch. Only plain texts: the chart's legend, a coloured mark and its name in one line, stays, as upstream
/// leaves a TextBlock of several runs alone. The menu bar item and the tooltips stay too.
public enum Haywire {
    /// `$RelicJunk`.
    static let junk = Array("#%&@$!?/\\|<>~^*=+0123456789░▒▓█¤§ÆØ")

    /// The scene's haywire, the same for the same value; none leaves the view as it is.
    public static func scramble(_ view: WidgetViewState, _ haywire: SceneHaywire?) -> WidgetViewState {
        haywire.map { scramble(view, strength: $0.strength, random: SeededRandomSource(seed: $0.seed)) } ?? view
    }

    public static func scramble(_ view: WidgetViewState, strength p: Double, random: any RandomSource) -> WidgetViewState {
        var v = view
        func s(_ text: inout String) { text = scramble(text, strength: p, random: random) }
        func row(_ r: inout BarRow) {
            s(&r.label)
            s(&r.value)
        }
        let texts: [WritableKeyPath<WidgetViewState, String>] = [
            \.title, \.detailsGlyph, \.pctText, \.resetText, \.playText, \.sessionsLabel, \.sessionsText, \.statusText,
            \.statusLine2, \.dayLabel, \.dayMain, \.dayExtra, \.week7Label, \.week7Main, \.week7Extra, \.versionText,
            \.appVersionText, \.accountText, \.stampText,
        ]
        for text in texts { s(&v[keyPath: text]) }
        row(&v.otherLimit)
        for i in v.modelWeeks.indices { row(&v.modelWeeks[i]) }
        if var h = v.history {
            s(&h.label)
            for i in h.days.indices { s(&h.days[i].text) }
            s(&h.caption)
            v.history = h
        }
        if var projects = v.projects {
            s(&projects.label)
            for i in projects.rows.indices {
                s(&projects.rows[i].name)
                s(&projects.rows[i].share)
            }
            s(&projects.caption)
            v.projects = projects
        }
        // The session, week and model-week bars, as upstream's three.
        v.mainFraction = random.nextDouble()
        v.otherLimit.fraction = random.nextDouble()
        for i in v.modelWeeks.indices { v.modelWeeks[i].fraction = random.nextDouble() }
        return v
    }

    /// Every digit a random digit; any other character but a space junk with probability `p`.
    static func scramble(_ text: String, strength p: Double, random: any RandomSource) -> String {
        String(text.map { ch -> Character in
            if ch.isASCII, ch.isNumber { return Character(String(random.nextInt(10))) }
            if !ch.isWhitespace, random.nextDouble() < p { return junk[random.nextInt(junk.count)] }
            return ch
        })
    }
}
