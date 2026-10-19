/// Every UI string key. Raw values are the original's dotted keys where one exists.
public enum L10nKey: String, CaseIterable, Sendable {
    case errNoClaude = "err.noClaude"

    // Card
    case uiDetails = "ui.details"
    case uiHide = "ui.hide"
    case uiExit = "ui.exit"
    case uiWeek = "ui.week"
    /// `{0} · WEEK` with the upper-cased model name: FABLE · WEEK, SONNET · WEEK.
    case uiModelWeek = "ui.modelWeek"
    case uiSessions = "ui.sessions"
    case uiOpenStatus = "ui.openStatus"
    case uiDay = "ui.day"
    case uiWeek7 = "ui.week7"
    /// Tooltip of the ClawBar version line; {0} is the original's version.
    case uiPortOf = "ui.portOf"

    case spanD = "span.d"
    case spanH = "span.h"
    case spanM = "span.m"

    case loading
    case noData
    case error
    case stale
    case resetIn = "reset.in"
    case resetClosed = "reset.closed"
    /// `{0}  ·  {1}` with the counted requests and sessions.
    case period
    case pluralSession = "plural.session"
    case pluralRequest = "plural.request"

    // Menu bar item tooltip
    case trayNoData = "tray.noData"
    case traySession = "tray.session"
    case trayWeek = "tray.week"

    case sessNone = "sess.none"
    case sessBusy = "sess.busy"
    case sessWait = "sess.wait"

    case stLoading = "st.loading"
    case stOffline = "st.offline"
    case stOk = "st.ok"
    case stMaint = "st.maint"
    case stIssues = "st.issues"
    case compDegradedPerformance = "comp.degraded_performance"
    case compPartialOutage = "comp.partial_outage"
    case compMajorOutage = "comp.major_outage"
    case compUnderMaintenance = "comp.under_maintenance"

    case verUpdating = "ver.updating"
    case verAvailable = "ver.available"
    case verLatest = "ver.latest"
    case verUpdateFailed = "ver.updateFailed"
    /// First tooltip line of a failed update; {0} is the exit code.
    case verFailExit = "ver.failExit"
    case verFailTimeout = "ver.failTimeout"
    /// {0} is the version claude update left in place.
    case verFailUnchanged = "ver.failUnchanged"
    case verHintHomebrew = "ver.hintHomebrew"
    case verHintNpm = "ver.hintNpm"
    case chgHead = "chg.head"
    case chgLoading = "chg.loading"
    case chgMore = "chg.more"
    case chgEmpty = "chg.empty"
    case chgClick = "chg.click"
    case chgOpen = "chg.open"

    case accOut = "acc.out"

    // Usage probe issues
    case issueNoLimits = "issue.noLimits"
    /// {0} is the option Claude Code rejected.
    case issueFlagRejected = "issue.flagRejected"
    /// {0} turns, {1} cost in USD, already formatted.
    case issueModelReached = "issue.modelReached"

    // Stat lines of the 24 h / 7 d blocks
    case statCacheMiss = "stat.cacheMiss"
    case statBigCtx = "stat.bigCtx"
    case statSubagents = "stat.subagents"
    case statParallel = "stat.parallel"
    case statLong = "stat.long"
    case statMaxEffort = "stat.maxEffort"
    case statWorkflows = "stat.workflows"
    case statAlwaysOn = "stat.alwaysOn"
    case statToolResults = "stat.toolResults"
    case statSkills = "stat.skills"
    case statAgents = "stat.agents"
    case statPlugins = "stat.plugins"
    case statMcp = "stat.mcp"
    /// The trailing `+N more` of a Top list.
    case statMore = "stat.more"

    // Status item menu
    case menuShow = "menu.show"
    case menuHide = "menu.hide"
    case menuRefresh = "menu.refresh"
    case menuBigger = "menu.bigger"
    case menuSmaller = "menu.smaller"
    case menuTopmost = "menu.topmost"
    case menuLogin = "menu.login"
    case menuConfig = "menu.config"
    case menuLanguage = "menu.language"
    /// The Show in widget submenu; its items are the original's Settings switches.
    case menuShown = "menu.shown"
    case setShowMascot = "set.showMascot"
    case setShowSky = "set.showSky"
    case setShowStatus = "set.showStatus"
    case setShowSessions = "set.showSessions"
    case setShowAccount = "set.showAccount"
    case setShowStats = "set.showStats"
    case menuQuit = "menu.quit"
    /// Shown only while the session limit is used up.
    case menuPlay = "menu.play"

    // Clawd Run, the game for a used-up session limit
    /// The card's button under the reset line.
    case uiPlay = "ui.play"
    case uiPlayTip = "ui.playTip"
    case gameTitle = "game.title"
    case gameStart = "game.start"
    case gameOver = "game.over"
    case gameRestart = "game.restart"
    case gamePaused = "game.paused"
    case gameHint = "game.hint"
    /// The caption once the limit has reset while the game is open.
    case gameBack = "game.back"

    // Hearts
    case health0 = "health.0"
    case health1 = "health.1"
    case health2 = "health.2"
    case health3 = "health.3"
    case health4 = "health.4"
    case health5 = "health.5"
    case health6 = "health.6"
    case heartsLeft = "hearts.left"

    // Clawd
    case moodSleep = "mood.sleep"
    case moodDoze = "mood.doze"
    case moodIdle = "mood.idle"
    case moodWork = "mood.work"
    case moodWait = "mood.wait"
    case moodDead = "mood.dead"

    case actJump = "act.jump"
    case actLook = "act.look"
    case actCelebrate = "act.celebrate"
    case actSkip = "act.skip"
    case actSpin = "act.spin"
    case actPeekaboo = "act.peekaboo"
    case actDrop = "act.drop"
    case actWaddle = "act.waddle"
    case actPeek = "act.peek"
    case actWink = "act.wink"
    case actBoop = "act.boop"
    case actTap = "act.tap"
    case actSneeze = "act.sneeze"
    case actTurn = "act.turn"
    case actCoinHop = "act.coin-hop"
    case actWave = "act.wave"
    case actStretch = "act.stretch"
    case actYawn = "act.yawn"
    case actStumble = "act.stumble"
    case actSoul = "act.soul"
    case actBurrow = "act.burrow"
    case actUnburrow = "act.unburrow"
    case actStir = "act.stir"

    // Developer menu
    case mmHead = "mm.head"
    case mmAuto = "mm.auto"
    case mmState = "mm.state"
    case mmAnim = "mm.anim"
    case mmSweat = "mm.sweat"
    case mmHearts = "mm.hearts"
    case mmByLimit = "mm.byLimit"
    case mmDrain = "mm.drain"
    case mmSky = "mm.sky"
    case mmByClock = "mm.byClock"
    case mmWxLive = "mm.wxLive"
    case mmDemo = "mm.demo"
    case tagSweat = "tag.sweat"
    case tagDemo = "tag.demo"

    // Sky
    case phaseDawn = "phase.dawn"
    case phaseDay = "phase.day"
    case phaseDusk = "phase.dusk"
    case phaseNight = "phase.night"

    case wxClear = "wx.clear"
    case wxMostlyClear = "wx.mostlyClear"
    case wxPartly = "wx.partly"
    case wxOvercast = "wx.overcast"
    case wxFog = "wx.fog"
    case wxDrizzle = "wx.drizzle"
    case wxIceDrizzle = "wx.iceDrizzle"
    case wxRain = "wx.rain"
    case wxIceRain = "wx.iceRain"
    case wxSnow = "wx.snow"
    case wxGrains = "wx.grains"
    case wxShowers = "wx.showers"
    case wxSnowShowers = "wx.snowShowers"
    case wxStorm = "wx.storm"
    /// An unknown WMO code; {0} is the code.
    case wxCode = "wx.code"

    case skyWind = "sky.wind"
    case skyNoData = "sky.noData"
    case skySun = "sky.sun"
    /// `{0}, {1}% lit` with a moon name and the percentage.
    case skyMoon = "sky.moon"
    /// The original's `sky.moonNames`, from the new moon round to the waning crescent.
    case skyMoonName0 = "sky.moonNames.0"
    case skyMoonName1 = "sky.moonNames.1"
    case skyMoonName2 = "sky.moonNames.2"
    case skyMoonName3 = "sky.moonNames.3"
    case skyMoonName4 = "sky.moonNames.4"
    case skyMoonName5 = "sky.moonNames.5"
    case skyMoonName6 = "sky.moonNames.6"
    case skyMoonName7 = "sky.moonNames.7"
}
