import AppKit
import DuoControl
import DuoKit
import SwiftUI

@main
struct DuoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    // A plain `let`: the Command Line Tools lack the SwiftUI macro plugin behind @State, and the
    // model is an @Observable class that lives as long as the app.
    private let model: AppModel
    private let options: LaunchOptions

    init() {
        // Before anything reads Duo's folder: a scripted run without DUO_SUPPORT_DIR gets a
        // temporary one, never the user's (C-21, F-89).
        let launchEnvironment = ProcessInfo.processInfo.environment
        SupportFolder.prepareForLaunch()
        // A test launch a script started runs in the background: never in the user's way (F-227).
        TestBackground.isOn = TestBackground.decide(arguments: CommandLine.arguments, environment: launchEnvironment,
                                                    isolated: SupportFolder.isIsolated)
        DuoFocus.startBackground()
        let options = LaunchOptions()
        self.options = options
        // Match System, Light or Dark, as Settings › General › Appearance says (DL-224).
        AppearanceSetting.apply()
        NSWindow.allowsAutomaticWindowTabbing = false

        let fixture: Fixture
        do {
            fixture = try options.resolveFixture()
        } catch {
            FileHandle.standardError.write(Data("Duo: \(error.localizedDescription)\n".utf8))
            exit(66)
        }
        // What every window shares (multi-window slice 0, F-537), and the main window's model on it.
        let core = AppCore(fixture: fixture)
        let model = AppModel(core: core)
        DeckPreviewRegistration.install(model: model)   // Duo Decks: a `type: deck` note previews as slides in split view
        // Stalls of the main thread, logged on this Mac for `duo2 hangs` (DL-139). DUO_HANG_LOG=0 turns it off.
        if ProcessInfo.processInfo.environment["DUO_HANG_LOG"] != "0" { HangMonitor.shared.start { model.hangScreen() } }
        model.interactivePrompts = !options.capturing
        // Scripted runs restore only when asked (DUO_RESTORE=1), on their own workspace's file.
        model.restoreEnabled = (!options.capturing && options.thenActions.isEmpty) || ProcessInfo.processInfo.environment["DUO_RESTORE"] == "1"
        // duo2's endpoint (DL-15). Terminals start after the window appears, by which time the
        // listener is ready; the environment is read when each process starts.
        let helpers = Bundle.main.bundleURL.appending(path: "Contents/Helpers")
        if FileManager.default.isExecutableFile(atPath: helpers.appending(path: "duo2").path) {
            ChildEnvironment.cliDirectory = helpers.path
        }
        let server = ControlServer { core.handle($0, done: $1) }   // the core picks the window (the primary, Q-430)
        // Scripted and capture runs never take the socket from the user's open Duo (C-18).
        try? server.start(privateIfTaken: options.capturing) { ChildEnvironment.control = $0 }
        options.state?.apply(to: model)
        if let screen = options.searchState {
            if SurfaceTargets.screens.contains(screen) { SurfaceTargets.apply(screen, to: model) }
            else if ChatTargets.screens.contains(screen) { ChatTargets.apply(screen, to: model) }
            else if NarrowTargets.screens.contains(screen) { NarrowTargets.apply(screen, to: model) }
            else if HomeListTargets.screens.contains(screen) { HomeListTargets.apply(screen, to: model) }
            else if VideoTargets.screens.contains(screen) { VideoTargets.apply(screen, to: model) }
            else if GlyphTargets.screens.contains(screen) { GlyphTargets.apply(screen, to: model) }
            else if SidebarTargets.screens.contains(screen) { SidebarTargets.apply(screen, to: model) }
            else if ForkTargets.screens.contains(screen) { ForkTargets.apply(screen, to: model) }
            else if NewSessionTargets.screens.contains(screen) { NewSessionTargets.apply(screen, to: model) }
            else { SearchTargets.apply(screen, to: model) }
        }
        if options.collapseLeft { model.leftCollapsed = true }
        if let ws = options.workspace {
            // `--workspace none`: live with no Home, whatever Duo's state says (scripted runs, DL-84).
            model.startLive(root: ws == "none" ? nil : URL(fileURLWithPath: (ws as NSString).expandingTildeInPath))
        } else if let t = options.terminals, t.hasPrefix("demo") {
            let root = t.split(separator: ":", maxSplits: 1).dropFirst().first.map(String.init)
                ?? FileManager.default.currentDirectoryPath + "/.build/demo"
            model.terminalsMode = .demo(root: root)
        } else if options.usesFixture == false {
            // Every launch lists every Claude session (DL-82), with Home's projects once a Home is chosen.
            model.startLive(root: DuoState.load().root.map { URL(fileURLWithPath: $0) })
        }
        self.model = model
        // In-app updates (Sparkle) in release builds; the GitHub notice (F-69) where Sparkle isn't running.
        if !options.capturing, model.terminalsMode == .live { SparkleUpdater.start(model: model) }
        // The CLI's version decides chat mode's hooks when a session starts (F-111): asked now, off the
        // main thread, so the first session finds it cached (C-34).
        // Off the main thread (F-564): finding `claude` can start the user's login shell, and a shell that waits
        // kept Duo bouncing in the Dock. A draw that asks meanwhile waits on the same lookup, at most its timeout.
        if model.terminalsMode == .live {
            DispatchQueue.global(qos: .userInitiated).async {
                if let claude = ClaudeLocator.resolve() { ClaudeVersion.warm(claude); RemoteControl.warm(claude); DuoSignal.warm(claude) }
            }
        }
        if !options.capturing, model.terminalsMode == .live {
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) { MainActor.assumeIsolated { model.checkForUpdates(userInitiated: false) } }
        }
        // Launch trace for scripted runs: one launch in a few opens no window (F-26).
        if options.capturing {
            let trace: @Sendable (String) -> Void = { m in FileHandle.standardError.write(Data("trace \(String(format: "%.2f", ProcessInfo.processInfo.systemUptime)) \(m)\n".utf8)) }
            trace("init")
            NotificationCenter.default.addObserver(forName: NSApplication.didFinishLaunchingNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated {
                    trace("didFinishLaunching windows=\(NSApp.windows.count)")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        trace("+3s windows=\(NSApp.windows.map { "\($0.className) visible=\($0.isVisible) \($0.frame)" })")
                    }
                }
            }
        }
        // The main window is made in AppKit, once, at launch (F-29): SwiftUI's Window scene
        // sometimes finished launching with no window, and reopening didn't bring one back.
        let mainWindow = MainWindow(model: model, options: options)
        // More windows (multi-window slice 1, DL-311): the core asks for one per new model, and brings one forward.
        MainWindow.wire(core: core, options: options)
        AppDelegate.reopen = { (core.keyModel.flatMap { MainWindow.of($0) } ?? mainWindow).show() }
        AppDelegate.dockMenu = { (core.keyModel ?? model).dockMenu() }
        AppDelegate.openURL = { url in
            // Session links from notes or other apps (DL-87), in the key window (its project's, if one shows it).
            if url.scheme == "duo2", url.host == "session" {
                let m = core.keyModel ?? model
                MainWindow.of(m)?.show(); m.openLink(url.absoluteString); return
            }
            guard url.scheme == "duo2", url.host == "walk-setup",
                  let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "id" })?.value else { return }
            mainWindow.show()
            model.walkSetup(id) { r in FileHandle.standardError.write(Data("walk-setup \(id): \(r.text)\n".utf8)) }
        }
        AppDelegate.flush = { done in
            let all = core.models.flatMap { $0.loadedEditors }   // every window's editors (DL-311)
            guard !all.isEmpty else { return done() }
            let once = Once()
            var pending = all.count
            let finish: @MainActor () -> Void = { if !once.fired { once.fired = true; done() } }
            for e in all { e.flush { pending -= 1; if pending == 0 { finish() } } }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { MainActor.assumeIsolated { finish() } }  // never hang a quit
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didFinishLaunchingNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                HangMonitor.shared.launchFinished()   // a launch that never gets here is logged (F-573)
                mainWindow.show()
                model.installPaneKeys()   // ⌃Tab and ⌃⇧Tab, even in terminals (DL-165)
                // While the element picker is open, Escape closes it wherever the keyboard is
                // (it reached the Claude terminal instead, where Escape interrupts Claude; F-52).
                // Installed after launch: NSApp doesn't exist while the app initialises.
                NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
                    guard e.keyCode == 53 else { return e }
                    let picking = MainActor.assumeIsolated { () -> Bool in
                        // The event's window's picker (DL-311), not the first window's.
                        guard let v = (core.model(for: e.window) ?? model).htmlViewerIfLoaded, v.picking else { return false }
                        v.stopPicking()
                        return true
                    }
                    return picking ? nil : e
                }
                // DL-74, DL-75: what lets Claude sessions anywhere use duo2; asked once, kept current.
                if !options.capturing || Installer.testRoot != nil, let dir = ChildEnvironment.cliDirectory {
                    model.lookForProjectDirectorSkills()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) { InstallPrompt.run(cli: dir + "/duo2") }
                }
            }
        }
        FixtureHarness.beforeExit = { model.terminals.terminateAll(); server.stop() }

        // SIGTERM quits like ⌘Q (sessions end cleanly, the document saves): scripts quit the one
        // instance they started by pid, never "the" Duo by app id, which may be the user's (C-18).
        signal(SIGTERM, SIG_IGN)
        let term = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        term.setEventHandler { MainActor.assumeIsolated { NSApp.terminate(nil) } }
        term.resume()
        AppDelegate.termSource = term
        // End sessions cleanly on quit. Hiding or collapsing never does this (LR-13).
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { model.saveRestoreState(force: true); model.terminals.terminateAll(); server.stop() }
        }
    }

    var body: some Scene {
        // The window itself is AppKit (MainWindow); this scene carries the menus.
        Settings { SettingsView().environment(model) }
            .commands { DuoCommands(model: model) }
    }
}

@MainActor final class Once { var fired = false }

/// Dock click or `open` with no window visible: show the main window again.
final class AppDelegate: NSObject, NSApplicationDelegate {
    nonisolated(unsafe) static var reopen: (@MainActor () -> Void)?
    nonisolated(unsafe) static var termSource: DispatchSourceSignal?
    /// `duo2://walk-setup?id=<test>` from the acceptance walk page.
    nonisolated(unsafe) static var openURL: (@MainActor (URL) -> Void)?

    func application(_ application: NSApplication, open urls: [URL]) {
        MainActor.assumeIsolated { for u in urls { Self.openURL?(u) } }
    }
    /// Saves the open document before quitting (DL-77: the last second's typing isn't lost).
    nonisolated(unsafe) static var flush: (@MainActor (@escaping @MainActor () -> Void) -> Void)?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let flush = Self.flush else { return .terminateNow }
        MainActor.assumeIsolated {
            flush { NSApp.reply(toApplicationShouldTerminate: true) }
        }
        return .terminateLater
    }

    /// The Dock menu of sessions that need you (ENH-24).
    nonisolated(unsafe) static var dockMenu: (@MainActor () -> NSMenu?)?
    @MainActor func applicationDockMenu(_ sender: NSApplication) -> NSMenu? { Self.dockMenu?() }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { MainActor.assumeIsolated { Self.reopen?() } }
        return true
    }
}

/// A Duo window: SwiftUI content in an AppKit window, toolbar bridged from `.toolbar`. One per `AppModel`
/// (multi-window slice 1, DL-311): the first at launch, more from New Window and Open in New Window.
@MainActor
final class MainWindow {
    private let model: AppModel
    private let options: LaunchOptions
    private var window: NSWindow?
    /// Keeps the window at or above 1280 × 800 while the user resizes it (F-527), and tells the core when
    /// a second window closes.
    private let minimum = MinimumWindowSize()
    /// Every open window (the core holds models weakly; this keeps them and their windows).
    private static var open: [MainWindow] = []

    init(model: AppModel, options: LaunchOptions) {
        self.model = model
        self.options = options
        Self.open.append(self)
    }

    static func of(_ m: AppModel) -> MainWindow? { open.first { $0.model === m } }

    /// The core's hooks: make a window for a new model, bring one forward, close or hide one.
    static func wire(core: AppCore, options: LaunchOptions) {
        core.windowMaker = { m in MainWindow(model: m, options: options).show() }
        core.windowFocuser = { m in of(m)?.show() }
        core.windowCloser = { m in of(m)?.window?.close() }
        core.windowHider = { m in of(m)?.window?.orderOut(nil) }
    }

    func show() {
        if let window {
            DuoFocus.hide(window); window.makeKeyAndOrderFront(nil)
            if !SupportFolder.isIsolated { NSApp.activate() }
            return
        }
        let content = Group {
            if options.gallery { AnyView(GalleryView()) } else { AnyView(RootView()) }
        }
        .environment(model)
        .frame(minWidth: DuoMetric.minimumWindow.width,
               minHeight: DuoMetric.minimumWindow.height - DuoMetric.toolbarHeight)
        let host = NSHostingController(rootView: content)
        host.sceneBridgingOptions = [.toolbars]
        // Lay out at the design size from the first pass: the split view keeps proportions on
        // resize, so a first layout at SwiftUI's ideal size would skew the pane widths.
        host.sizingOptions = []
        host.view.frame = NSRect(origin: .zero, size: DuoMetric.designWindow)
        let w = NSWindow(contentViewController: host)
        w.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]  // as SwiftUI's windows
        w.toolbarStyle = .unifiedCompact
        w.titleVisibility = .hidden
        w.title = model.windowTitle   // the project's name, or Duo at All projects (DL-311); RootView keeps it current
        w.isReleasedWhenClosed = false
        w.setContentSize(DuoMetric.designWindow)  // full-size content: the whole window, as SwiftUI's defaultSize
        // The minimum window (1280 × 800): `sizingOptions = []` above means the hosting controller never
        // passes the content's minimum to the window, which then shrank below it and clipped the panes
        // on every side, the console over the toolbar (Geoff, 2026-11-01, F-527).
        w.contentMinSize = DuoMetric.minimumWindow
        w.delegate = minimum   // the hosting controller resets contentMinSize; the delegate holds the line
        // A second window closing: the core forgets it; its projects keep their tabs and sessions (DL-311).
        minimum.closed = { [model] in
            guard model.core.models.count > 1 else { return }   // the last window only hides
            model.core.detach(model)
            MainWindow.open.removeAll { $0.model === model }
        }
        w.center()
        if model.windowNumber == 1 {
            w.setFrameAutosaveName("main")
        } else {
            // Below and right of the key window by 22 pt, as macOS cascades, under its own frame name.
            if let key = model.core.models.first(where: { $0 !== model && $0.windowID == model.core.keyWindowID })?.window ?? model.core.primary?.window {
                w.setFrameTopLeftPoint(NSPoint(x: key.frame.minX + 22, y: key.frame.maxY - 22))
            }
            w.setFrameAutosaveName("window-\(model.windowNumber)")
        }
        window = w
        model.window = w   // the model's own window: lookups go by identity, never by title (multi-window slice 0)
        // Menus act on the key window's model (AppCore.keyModel).
        NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: w, queue: .main) { [model] _ in
            MainActor.assumeIsolated { if model.core.keyWindowID != model.windowID { model.core.keyWindowID = model.windowID } }
        }
        // View › Enter Full Screen (DL-108) says which way it goes.
        for (name, on) in [(NSWindow.didEnterFullScreenNotification, true), (NSWindow.didExitFullScreenNotification, false)] {
            NotificationCenter.default.addObserver(forName: name, object: w, queue: .main) { [model] _ in
                MainActor.assumeIsolated { model.fullScreen = on }
            }
        }
        if model.windowNumber == 1 { FixtureHarness.configure(w, model: model, options: options) }
        else { FixtureHarness.configureMore(w, options: options) }   // the actions and capture stay window 1's
        DuoFocus.hide(w)   // a background test launch draws its window without showing it (F-227)
        w.makeKeyAndOrderFront(nil)
        if !SupportFolder.isIsolated { NSApp.activate() }   // an isolated instance never takes focus (C-28)
    }
}

/// The window never resizes below Duo's minimum (1280 × 800, `minimumWindow`): under it the panes'
/// own minimums don't fit and the content overflowed, clipped at every edge (Geoff, 2026-11-01, F-527).
/// With full-size content the window's frame is its content.
@MainActor
final class MinimumWindowSize: NSObject, NSWindowDelegate {
    var closed: (@MainActor () -> Void)?
    func windowWillClose(_ notification: Notification) { closed?() }
    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        NSSize(width: max(frameSize.width, DuoMetric.minimumWindow.width), height: max(frameSize.height, DuoMetric.minimumWindow.height))
    }
}
