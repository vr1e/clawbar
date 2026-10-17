import AppKit
import ClawBarData
import ClawBarShared
import os

enum CLIRunner {
    /// The exit status; `.run` only returns when the app quits.
    static func run(_ mode: CLIMode) -> Int32 {
        switch mode {
        case .run: AppMain.run()
        case .version:
            print(AppInfo.title)
            return 0
        case .diagnose: Diagnose.run()
        case .snapshot(let dir): return SnapshotMode.run(dir: URL(fileURLWithPath: dir))
        case .record(let scenario, let gif): return Recorder.run(scenario, gif: URL(fileURLWithPath: gif))
        case .dumpState: return RemoteControl.dumpState(paths: .live())
        case .command(let c): return RemoteControl.send(c, paths: .live())
        case .makeIcon(let dir): return IconMaker.run(dir: URL(fileURLWithPath: dir))
        }
    }
}

enum AppMain {
    static func run() -> Never {
        let paths = AppPaths.live()
        let lock: InstanceLock
        switch InstanceLock.acquire(paths.lockFile) {
        case .acquired(let l):
            lock = l
        case .held:
            // Already running: bring its widget up instead of starting a second one.
            IPC.post(IPC.show, to: paths)
            exit(0)
        case .failed(let e):
            // Never start unlocked: two instances would both write config.json and state.json.
            startFailed("cannot lock \(paths.lockFile.path): \(String(cString: strerror(e)))", paths: paths)
            exit(1)
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = AppDelegate(paths: paths, lock: lock)
        app.delegate = delegate
        // kill, pkill and Ctrl-C quit like the menu does, so children and the widget's position are looked after.
        let signals = TerminationSignals([SIGTERM, SIGINT]) { NSApp.terminate(nil) }
        withExtendedLifetime((delegate, signals)) { app.run() }
        exit(0)
    }

    /// A start that fails before any window leaves a trace: stderr for a terminal, the unified log for a login
    /// item, and error.log when its folder is writable.
    private static func startFailed(_ message: String, paths: AppPaths) {
        FileHandle.standardError.write(Data("ClawBar: \(message)\n".utf8))
        Logger(subsystem: AppInfo.bundleID, category: "start").error("\(message, privacy: .public)")
        ErrorLog(url: paths.errorLog).append("start: \(message)", now: Date(), timeZone: .current)
    }
}

/// Turns signals into a handler call on the main queue; the default action would end the app on the spot.
final class TerminationSignals {
    private let signals: [Int32]
    private var sources: [DispatchSourceSignal] = []

    init(_ signals: [Int32], handler: @escaping @MainActor () -> Void) {
        self.signals = signals
        for s in signals {
            signal(s, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: s, queue: .main)
            source.setEventHandler { MainActor.assumeIsolated { handler() } }
            source.resume()
            sources.append(source)
        }
    }

    func cancel() {
        sources.forEach { $0.cancel() }
        sources = []
        for s in signals { signal(s, SIG_DFL) }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let paths: AppPaths
    private let lock: InstanceLock
    private var controller: AppController?

    init(paths: AppPaths, lock: InstanceLock) {
        self.paths = paths
        self.lock = lock
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let c = AppController(paths: paths)
        controller = c
        c.start()
    }

    /// Opening the app again from Finder or `open` while it runs shows the widget.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        controller?.showWidget()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.stop()
        lock.release()
    }
}

/// `--diagnose`: every probe once, printed redacted.
enum Diagnose {
    static func run() -> Never {
        let paths = AppPaths.live()
        let config = ConfigStore(paths: paths).load()
        Task { @MainActor in
            let report = await Diagnostics.run(config: config, paths: paths)
            print(Redact.text(report.text))
            exit(0)
        }
        // The main run loop, not only the main queue: probes may rely on run-loop sources.
        RunLoop.main.add(Timer(timeInterval: 3600, repeats: true) { _ in }, forMode: .default)
        RunLoop.main.run()
        exit(0)
    }
}

/// `--command` and `--dump-state`: talk to the instance that holds the lock on the same AppPaths root.
enum RemoteControl {
    static func send(_ c: RemoteCommand, paths: AppPaths) -> Int32 {
        guard InstanceLock.isHeld(paths.lockFile) else {
            FileHandle.standardError.write(Data("ClawBar is not running\n".utf8))
            return 1
        }
        IPC.send(c, to: paths)
        print("sent \(c.wire)")
        return 0
    }

    static func dumpState(paths: AppPaths, timeout: TimeInterval = 5) -> Int32 {
        guard InstanceLock.isHeld(paths.lockFile) else {
            FileHandle.standardError.write(Data("ClawBar is not running\n".utf8))
            return 1
        }
        let nonce = UUID().uuidString
        let file = IPC.dumpFile(paths)
        IPC.post(IPC.dumpState, to: paths, userInfo: [IPC.nonceKey: nonce])
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let text = try? String(contentsOf: file, encoding: .utf8), let body = answer(text, nonce: nonce) {
                print(body, terminator: "")
                return 0
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        FileHandle.standardError.write(Data("ClawBar did not answer within \(Int(timeout)) s\n".utf8))
        return 1
    }

    /// The dump without its nonce line, when it answers this request.
    static func answer(_ text: String, nonce: String) -> String? {
        let first = "nonce: \(nonce)\n"
        guard text.hasPrefix(first) else { return nil }
        return String(text.dropFirst(first.count))
    }
}
