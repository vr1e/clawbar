// English is the original's (i18n.ps1), adapted for macOS, plus ClawBar's new keys. German is written new: short, in
// the words a German macOS app uses, with English's placeholders and the Mac's unit symbols (4d 15h, 2h 05min).
extension L10nKey {
    /// An exhaustive switch whose arms need both languages: a key missing either does not compile.
    var strings: L10nStrings {
        switch self {
        // Shown in place of the reset line, two lines at most; the break keeps the command whole.
        case .errNoClaude: .text(
            en: "Claude Code was not found. Install it:\ncurl -fsSL https://claude.ai/install.sh | bash",
            de: "Claude Code nicht gefunden. Installieren:\ncurl -fsSL https://claude.ai/install.sh | bash"
        )

        case .uiDetails: .text(en: "Details", de: "Details ein-/ausblenden")
        case .uiHide: .text(en: "Hide", de: "Ausblenden")
        case .uiExit: .text(en: "Quit", de: "Beenden")
        case .uiWeek: .text(en: "WEEK", de: "WOCHE")
        case .uiModelWeek: .text(en: "{0} · WEEK", de: "{0} · WOCHE")
        case .uiSessions: .text(en: "SESSIONS", de: "SITZUNGEN")
        case .uiOpenStatus: .text(en: "Open status.claude.com", de: "status.claude.com öffnen")
        case .uiDay: .text(en: "LAST 24 HOURS · THIS COMPUTER", de: "LETZTE 24 STUNDEN · DIESER MAC")
        case .uiWeek7: .text(en: "LAST 7 DAYS", de: "LETZTE 7 TAGE")
        case .uiHist: .text(en: "LIMITS · 7 DAYS", de: "LIMITS · 7 TAGE")
        case .histSession: .text(en: "5h", de: "5h")
        case .histWeek: .text(en: "week", de: "Woche")
        case .histEmpty: .text(en: "the history starts now", de: "der Verlauf beginnt jetzt")
        case .uiProjects: .text(en: "PROJECTS · 7 DAYS", de: "PROJEKTE · 7 TAGE")
        case .histProjTip: .text(
            en: "Share of the week's usage on this computer, estimated from tokens and model prices",
            de: "Anteil an der Nutzung dieser Woche auf diesem Mac, geschätzt aus Tokens und Modellpreisen"
        )
        case .histCounting: .text(en: "counting...", de: "wird gezählt …")
        case .histUnpriced: .text(
            en: "{0} priced as the closest model listed",
            de: "{0} zum Preis des nächsten bekannten Modells geschätzt"
        )
        case .uiPortOf: .text(
            en: "macOS port of clawd-usage-winwidget {0}, with some features of later releases (MIT)",
            de: "macOS-Portierung von clawd-usage-winwidget {0}, mit einigen Funktionen späterer Versionen (MIT)"
        )

        case .spanD: .text(en: "{0}d {1}h", de: "{0}d {1}h")
        case .spanH: .text(en: "{0}h {1:00}m", de: "{0}h {1:00}min")
        case .spanM: .text(en: "{0}m", de: "{0}min")

        case .loading: .text(en: "loading...", de: "wird geladen …")
        case .noData: .text(en: "no data", de: "keine Daten")
        case .error: .text(en: "error", de: "Fehler")
        case .stale: .text(en: "stale", de: "veraltet")
        case .resetIn: .text(en: "resets in {0}", de: "wird in {0} zurückgesetzt")
        case .resetClosed: .text(en: "window closed", de: "Zeitfenster abgelaufen")
        case .period: .text(en: "{0}  ·  {1}", de: "{0}  ·  {1}")
        case .pluralSession: .plural(en: ("session", "sessions"), de: ("Sitzung", "Sitzungen"))
        case .pluralRequest: .plural(en: ("request", "requests"), de: ("Anfrage", "Anfragen"))
        case .pluralReply: .plural(en: ("reply", "replies"), de: ("Antwort", "Antworten"))

        case .trayNoData: .text(en: "ClawBar: no data", de: "ClawBar: keine Daten")
        case .traySession: .text(en: "{0}% of session", de: "Sitzung {0}%")
        case .trayWeek: .text(en: "week {0}%", de: "Woche {0}%")
        // English spells out 'tomorrow': the original's 'tmrw' only saved room for the tray's 63 characters.
        case .clockTomorrow: .text(en: "tomorrow {0}", de: "morgen {0}")
        case .clockDate: .text(en: "{0} {1} {2}", de: "{0} {1}. {2}")
        // macOS's own short forms in German, with the period.
        case .wd0: .text(en: "Sun", de: "So.")
        case .wd1: .text(en: "Mon", de: "Mo.")
        case .wd2: .text(en: "Tue", de: "Di.")
        case .wd3: .text(en: "Wed", de: "Mi.")
        case .wd4: .text(en: "Thu", de: "Do.")
        case .wd5: .text(en: "Fri", de: "Fr.")
        case .wd6: .text(en: "Sat", de: "Sa.")

        // German words that read right for any count; "in Arbeit" would push 19 sessions past the row's 236 pt.
        case .sessNone: .text(en: "none running", de: "keine offen")
        case .sessBusy: .text(en: "{0} working", de: "{0} aktiv")
        case .sessWait: .text(en: "{0} waiting", de: "{0} wartend")

        case .stLoading: .text(en: "status: loading...", de: "Status: wird geladen …")
        case .stOffline: .text(en: "status: no connection", de: "Status: keine Verbindung")
        case .stOk: .text(en: "All Claude systems operational", de: "Alle Claude-Systeme betriebsbereit")
        case .stMaint: .text(en: "scheduled maintenance", de: "geplante Wartung")
        case .stIssues: .text(en: "some issues", de: "einige Störungen")
        case .compDegradedPerformance: .text(en: "degraded", de: "eingeschränkt")
        case .compPartialOutage: .text(en: "partial outage", de: "teilweiser Ausfall")
        case .compMajorOutage: .text(en: "major outage", de: "schwerer Ausfall")
        case .compUnderMaintenance: .text(en: "maintenance", de: "Wartung")

        case .verUpdating: .text(en: "updating...", de: "wird aktualisiert …")
        case .verAvailable: .text(en: "{0} available  ·  what's new?", de: "{0} verfügbar  ·  was ist neu?")
        case .verLatest: .text(en: "latest", de: "aktuell")
        case .verUpdateFailed: .text(en: "update failed", de: "Update fehlgeschlagen")
        case .verFailExit: .text(en: "claude update exited with code {0}", de: "claude update endete mit Code {0}")
        case .verFailTimeout: .text(
            en: "claude update did not finish in 15 minutes",
            de: "claude update war nach 15 Minuten nicht fertig"
        )
        case .verFailUnchanged: .text(
            en: "claude update finished, but Claude Code is still {0}",
            de: "claude update ist fertig, aber Claude Code ist noch {0}"
        )
        case .verHintHomebrew: .text(
            en: "Installed with Homebrew: update with brew upgrade claude-code",
            de: "Mit Homebrew installiert: Update mit brew upgrade claude-code"
        )
        case .verHintNpm: .text(
            en: "Installed with npm: update with npm install -g @anthropic-ai/claude-code",
            de: "Mit npm installiert: Update mit npm install -g @anthropic-ai/claude-code"
        )
        case .chgHead: .text(en: "What's new: {0} → {1}", de: "Neuerungen: {0} → {1}")
        case .chgLoading: .text(en: "loading the changelog...", de: "Änderungsprotokoll wird geladen …")
        case .chgMore: .text(en: "…and {0} more", de: "… und {0} weitere")
        case .chgEmpty: .text(en: "nothing in the CHANGELOG yet", de: "noch nichts im CHANGELOG")
        case .chgClick: .text(en: "Click to update", de: "Klicken zum Aktualisieren")
        case .chgOpen: .text(
            en: "Click for the Claude Code changelog",
            de: "Klicken für das Änderungsprotokoll von Claude Code"
        )

        case .accOut: .text(en: "not logged in: claude /login", de: "nicht angemeldet: claude /login")

        case .issueNoLimits: .text(
            en: "/usage shows no plan limits. Signed in with an API key?",
            de: "/usage zeigt keine Planlimits. Mit einem API-Schlüssel angemeldet?"
        )
        // Also in place of the reset line: what happened, then when the checks resume.
        case .issueFlagRejected: .text(
            en: "claude rejects {0}\nChecks paused until Claude Code updates",
            de: "claude lehnt {0} ab\nAbfrage pausiert bis zum nächsten Update"
        )
        case .issueModelReached: .text(
            en: "/usage called the model (turns: {0}, ${1})\nChecks paused until Claude Code updates",
            de: "/usage: Modell erreicht (Turns: {0}, {1} $)\nAbfrage pausiert bis zum nächsten Update"
        )

        case .statCacheMiss: .text(en: "{0}% >{1}-token cache misses", de: "{0}% Cache-Misses >{1} Tokens")
        case .statBigCtx: .text(en: "{0}% at >{1} context", de: "{0}% bei Kontext >{1}")
        case .statSubagents: .text(en: "{0}% subagent-heavy sessions", de: "{0}% Subagent-lastige Sitzungen")
        case .statParallel: .text(en: "{0}% with {1}+ sessions in parallel", de: "{0}% bei {1}+ parallelen Sitzungen")
        case .statLong: .text(en: "{0}% sessions {1}h+", de: "{0}% Sitzungen ab {1}h")
        case .statMaxEffort: .text(en: "{0}% at max effort", de: "{0}% bei maximalem Aufwand")
        case .statWorkflows: .text(en: "{0}% from workflows", de: "{0}% aus Workflows")
        case .statAlwaysOn: .text(en: "{0}% always-on context >{1}", de: "{0}% Dauerkontext >{1}")
        case .statToolResults: .text(en: "{0}% tool results >{1}", de: "{0}% Tool-Ergebnisse >{1}")
        case .statSkills: .text(en: "skills: {0}", de: "Skills: {0}")
        case .statAgents: .text(en: "subagents: {0}", de: "Subagents: {0}")
        case .statPlugins: .text(en: "plugins: {0}", de: "Plugins: {0}")
        case .statMcp: .text(en: "MCP: {0}", de: "MCP: {0}")
        case .statMore: .text(en: "+{0} more", de: "+{0} weitere")

        case .menuShow: .text(en: "Show widget", de: "Widget einblenden")
        case .menuHide: .text(en: "Hide widget", de: "Widget ausblenden")
        case .menuRefresh: .text(en: "Refresh now", de: "Jetzt aktualisieren")
        case .menuBigger: .text(en: "Larger", de: "Größer")
        case .menuSmaller: .text(en: "Smaller", de: "Kleiner")
        case .menuTopmost: .text(en: "Always on top", de: "Immer im Vordergrund")
        case .menuLogin: .text(en: "Launch at login", de: "Beim Anmelden öffnen")
        case .menuClawd: .text(en: "Clawd in menu bar", de: "Clawd in der Menüleiste")
        case .menuConfig: .text(en: "Open config.json", de: "config.json öffnen")
        case .menuLanguage: .text(en: "Language", de: "Sprache")
        case .menuShown: .text(en: "Show in widget", de: "Im Widget zeigen")
        case .setShowMascot: .text(en: "Clawd", de: "Clawd")
        case .setShowSky: .text(en: "Sky and weather behind him", de: "Himmel und Wetter hinter ihm")
        case .setShowStatus: .text(en: "Anthropic status", de: "Anthropic-Status")
        case .setShowSessions: .text(en: "Running sessions", de: "Laufende Sitzungen")
        case .setShowAccount: .text(en: "Plan and account", de: "Plan und Konto")
        case .setShowStats: .text(
            en: "Last 24 hours and 7 days (details)",
            de: "Letzte 24 Stunden und 7 Tage (Details)"
        )
        case .setShowHistory: .text(
            en: "7-day chart and top projects (details)",
            de: "7-Tage-Verlauf und Top-Projekte (Details)"
        )
        case .menuQuit: .text(en: "Quit ClawBar", de: "ClawBar beenden")
        case .menuPlay: .text(en: "Play Clawd Run…", de: "Clawd Run spielen …")

        case .uiPlay: .text(en: "Play Clawd Run while you wait", de: "Clawd Run spielen, bis es weitergeht")
        case .uiPlayTip: .text(
            en: "The session limit is used up. Jump over the bugs with Clawd until it resets.",
            de: "Das Sitzungslimit ist aufgebraucht. Spring mit Clawd über die Bugs, bis es zurückgesetzt wird."
        )
        case .gameTitle: .text(en: "Clawd Run", de: "Clawd Run")
        case .gameStart: .text(en: "Press Space or click to jump", de: "Leertaste oder Klick zum Springen")
        case .gameOver: .text(en: "GAME OVER", de: "SPIEL VORBEI")
        case .gameRestart: .text(en: "Space or click to run again", de: "Leertaste oder Klick für eine neue Runde")
        case .gamePaused: .text(
            en: "Paused · Space or click to go on",
            de: "Pause · Leertaste oder Klick zum Weiterspielen"
        )
        case .gameHint: .text(
            en: "Space/↑ jump · ↓ duck · Esc close",
            de: "Leertaste/↑ springen · ↓ ducken · Esc schließen"
        )
        case .gameBack: .text(
            en: "The limit has reset: back to work!",
            de: "Das Limit ist zurückgesetzt: zurück an die Arbeit!"
        )

        case .health0: .text(en: "out of strength", de: "völlig kraftlos")
        case .health1: .text(en: "barely alive", de: "halb tot")
        case .health2: .text(en: "exhausted", de: "erschöpft")
        case .health3: .text(en: "tired", de: "müde")
        case .health4: .text(en: "a bit tired", de: "etwas müde")
        case .health5: .text(en: "fine", de: "fit")
        case .health6: .text(en: "full of energy", de: "voller Energie")
        case .heartsLeft: .text(en: "{0} · {1}% of the session limit left", de: "{0} · {1}% des Sitzungslimits übrig")

        case .moodSleep: .text(en: "sleeping", de: "schläft")
        case .moodDoze: .text(en: "dozing", de: "döst")
        case .moodIdle: .text(en: "wandering", de: "spaziert herum")
        case .moodWork: .text(en: "working", de: "arbeitet")
        case .moodWait: .text(en: "waiting for you", de: "wartet auf dich")
        case .moodDead: .text(en: "limit reached", de: "Limit erreicht")

        case .actJump: .text(en: "jump", de: "Springen")
        case .actLook: .text(en: "looks around", de: "Umschauen")
        case .actCelebrate: .text(en: "celebrate", de: "Feiern")
        case .actSkip: .text(en: "skip", de: "Hüpfen")
        case .actSpin: .text(en: "spin", de: "Pirouette")
        case .actPeekaboo: .text(en: "peekaboo", de: "Kuckuck")
        case .actDrop: .text(en: "drops in", de: "Herabfallen")
        case .actWaddle: .text(en: "waddle", de: "Watscheln")
        case .actPeek: .text(en: "peek", de: "Spähen")
        case .actWink: .text(en: "wink", de: "Zwinkern")
        case .actBoop: .text(en: "boop", de: "Stupsen")
        case .actTap: .text(en: "tap dance", de: "Stepptanz")
        case .actSneeze: .text(en: "sneeze", de: "Niesen")
        case .actTurn: .text(en: "turn around", de: "Umdrehen")
        case .actCoinHop: .text(en: "coin hop", de: "Münzsprung")
        case .actWave: .text(en: "wave", de: "Winken")
        case .actStretch: .text(en: "stretch", de: "Strecken")
        case .actYawn: .text(en: "yawn", de: "Gähnen")
        case .actStumble: .text(en: "stumble", de: "Stolpern")
        case .actSoul: .text(en: "soul leaves", de: "Seelenflug")
        case .actBurrow: .text(en: "burrows in", de: "Eingraben")
        case .actUnburrow: .text(en: "climbs out of the burrow", de: "Aus dem Bau klettern")
        case .actStir: .text(en: "peeks out of the burrow", de: "Aus dem Bau lugen")

        case .mmHead: .text(en: "Developer mode", de: "Entwicklermodus")
        case .mmAuto: .text(en: "Auto (live data)", de: "Automatisch (Live-Daten)")
        case .mmState: .text(en: "State", de: "Zustand")
        case .mmAnim: .text(en: "Animation", de: "Animationen")
        case .mmSweat: .text(en: "Sweating near the limit", de: "Schwitzt nahe am Limit")
        case .mmHearts: .text(en: "Hearts", de: "Herzen")
        case .mmByLimit: .text(en: "from the limit", de: "nach Limit")
        case .mmDrain: .text(en: "Play losing hearts", de: "Herzverlust abspielen")
        case .mmSky: .text(en: "Sky", de: "Himmel")
        case .mmByClock: .text(en: "by the clock", de: "nach Uhrzeit")
        case .mmWxLive: .text(en: "live weather", de: "Live-Wetter")
        case .mmDemo: .text(en: "Show everything in turn", de: "Alles nacheinander zeigen")
        case .tagSweat: .text(en: "sweating near the limit", de: "schwitzt nahe am Limit")
        case .tagDemo: .text(en: "demo {0}/{1} · {2}", de: "Demo {0}/{1} · {2}")

        case .phaseDawn: .text(en: "dawn", de: "Morgendämmerung")
        case .phaseDay: .text(en: "day", de: "Tag")
        case .phaseDusk: .text(en: "dusk", de: "Abenddämmerung")
        case .phaseNight: .text(en: "night", de: "Nacht")

        case .wxClear: .text(en: "clear", de: "klar")
        case .wxMostlyClear: .text(en: "mostly clear", de: "überwiegend klar")
        case .wxPartly: .text(en: "partly cloudy", de: "teils bewölkt")
        case .wxOvercast: .text(en: "overcast", de: "bedeckt")
        case .wxFog: .text(en: "fog", de: "Nebel")
        case .wxDrizzle: .text(en: "drizzle", de: "Nieselregen")
        case .wxIceDrizzle: .text(en: "freezing drizzle", de: "gefrierender Nieselregen")
        case .wxRain: .text(en: "rain", de: "Regen")
        case .wxIceRain: .text(en: "freezing rain", de: "gefrierender Regen")
        case .wxSnow: .text(en: "snow", de: "Schnee")
        case .wxGrains: .text(en: "snow grains", de: "Schneegriesel")
        case .wxShowers: .text(en: "rain showers", de: "Regenschauer")
        case .wxSnowShowers: .text(en: "snow showers", de: "Schneeschauer")
        case .wxStorm: .text(en: "thunderstorm", de: "Gewitter")
        case .wxCode: .text(en: "code {0}", de: "Code {0}")

        case .skyWind: .text(en: "wind {0} m/s", de: "Wind {0} m/s")
        case .skyNoData: .text(en: "weather: no data", de: "Wetter: keine Daten")
        case .skySun: .text(en: "sunrise {0} · sunset {1}", de: "Sonnenaufgang {0} · Sonnenuntergang {1}")
        case .skyMoon: .text(en: "moon: {0}, {1}% lit", de: "Mond: {0}, {1} % beleuchtet")
        case .skyMoonName0: .text(en: "new moon", de: "Neumond")
        case .skyMoonName1: .text(en: "waxing crescent", de: "zunehmende Sichel")
        case .skyMoonName2: .text(en: "first quarter", de: "erstes Viertel")
        case .skyMoonName3: .text(en: "waxing gibbous", de: "zunehmender Mond")
        case .skyMoonName4: .text(en: "full moon", de: "Vollmond")
        case .skyMoonName5: .text(en: "waning gibbous", de: "abnehmender Mond")
        case .skyMoonName6: .text(en: "last quarter", de: "letztes Viertel")
        case .skyMoonName7: .text(en: "waning crescent", de: "abnehmende Sichel")
        }
    }
}
