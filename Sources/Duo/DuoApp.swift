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
        let options = LaunchOptions()
        self.options = options
        // Light only until a dark appearance is approved (handoff §12 Q4).
        NSApplication.shared.appearance = NSAppearance(named: .aqua)
        NSWindow.allowsAutomaticWindowTabbing = false

        let fixture: Fixture
        do {
            fixture = try options.resolveFixture()
        } catch {
            FileHandle.standardError.write(Data("Duo: \(error.localizedDescription)\n".utf8))
            exit(66)
        }
        let model = AppModel(fixture: fixture)
        model.interactivePrompts = !options.capturing
        // duo2's endpoint (DL-15). Terminals start after the window appears, by which time the
        // listener is ready; the environment is read when each process starts.
        let helpers = Bundle.main.bundleURL.appending(path: "Contents/Helpers")
        if FileManager.default.isExecutableFile(atPath: helpers.appending(path: "duo2").path) {
            ChildEnvironment.cliDirectory = helpers.path
        }
        let server = ControlServer { model.handle($0, done: $1) }
        try? server.start { ChildEnvironment.control = $0 }
        options.state?.apply(to: model)
        if options.collapseLeft { model.leftCollapsed = true }
        if let ws = options.workspace {
            model.startLive(root: URL(fileURLWithPath: (ws as NSString).expandingTildeInPath))
        } else if let t = options.terminals, t.hasPrefix("demo") {
            let root = t.split(separator: ":", maxSplits: 1).dropFirst().first.map(String.init)
                ?? FileManager.default.currentDirectoryPath + "/.build/demo"
            model.terminalsMode = .demo(root: root)
        }
        self.model = model
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
        AppDelegate.reopen = { mainWindow.show() }
        AppDelegate.flush = { done in
            guard let e = model.editorIfLoaded else { return done() }
            let once = Once()
            let finish: @MainActor () -> Void = { if !once.fired { once.fired = true; done() } }
            e.flush(finish)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { MainActor.assumeIsolated { finish() } }  // never hang a quit
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didFinishLaunchingNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                mainWindow.show()
                // DL-74, DL-75: what lets Claude sessions anywhere use duo2; asked once, kept current.
                if !options.capturing, let dir = ChildEnvironment.cliDirectory {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) { InstallPrompt.run(cli: dir + "/duo2") }
                }
            }
        }
        FixtureHarness.beforeExit = { model.terminals.terminateAll(); server.stop() }
        // End sessions cleanly on quit. Hiding or collapsing never does this (LR-13).
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { model.terminals.terminateAll(); server.stop() }
        }
    }

    var body: some Scene {
        // The window itself is AppKit (MainWindow); this scene carries the menus.
        Settings { EmptyView() }
            .commands { DuoCommands(model: model) }
    }
}

@MainActor final class Once { var fired = false }

/// Dock click or `open` with no window visible: show the main window again.
final class AppDelegate: NSObject, NSApplicationDelegate {
    nonisolated(unsafe) static var reopen: (@MainActor () -> Void)?
    /// Saves the open document before quitting (DL-77: the last second's typing isn't lost).
    nonisolated(unsafe) static var flush: (@MainActor (@escaping @MainActor () -> Void) -> Void)?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let flush = Self.flush else { return .terminateNow }
        MainActor.assumeIsolated {
            flush { NSApp.reply(toApplicationShouldTerminate: true) }
        }
        return .terminateLater
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { MainActor.assumeIsolated { Self.reopen?() } }
        return true
    }
}

/// The one Duo window: SwiftUI content in an AppKit window, toolbar bridged from `.toolbar`.
@MainActor
final class MainWindow {
    private let model: AppModel
    private let options: LaunchOptions
    private var window: NSWindow?

    init(model: AppModel, options: LaunchOptions) {
        self.model = model
        self.options = options
    }

    func show() {
        if let window { window.makeKeyAndOrderFront(nil); return }
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
        w.title = "Duo"
        w.isReleasedWhenClosed = false
        w.setContentSize(DuoMetric.designWindow)  // full-size content: the whole window, as SwiftUI's defaultSize
        w.center()
        w.setFrameAutosaveName("main")
        window = w
        FixtureHarness.configure(w, model: model, options: options)
        w.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}
