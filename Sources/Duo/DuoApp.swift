import AppKit
import DuoControl
import DuoKit
import SwiftUI

@main
struct DuoApp: App {
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
        // duo2's endpoint (DL-15). Terminals start after the window appears, by which time the
        // listener is ready; the environment is read when each process starts.
        let helpers = Bundle.main.bundleURL.appending(path: "Contents/Helpers")
        if FileManager.default.isExecutableFile(atPath: helpers.appending(path: "duo2").path) {
            ChildEnvironment.cliDirectory = helpers.path
        }
        let server = ControlServer { model.handle($0) }
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
        // Window watchdog (F-29): the first launch of a freshly signed build sometimes finishes
        // with no window. Activate, then reopen the way a Dock click does.
        NotificationCenter.default.addObserver(forName: NSApplication.didFinishLaunchingNotification, object: nil, queue: .main) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                MainActor.assumeIsolated {
                    guard !NSApp.windows.contains(where: { $0.isVisible }) else { return }
                    FileHandle.standardError.write(Data("trace watchdog: no window, reopening\n".utf8))
                    NSApp.activate()
                    _ = NSApp.delegate?.applicationShouldHandleReopen?(NSApp, hasVisibleWindows: false)
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
        Window("Duo", id: "main") {
            Group {
                if options.gallery { GalleryView() } else { RootView() }
            }
                .environment(model)
                .frame(minWidth: DuoMetric.minimumWindow.width,
                       minHeight: DuoMetric.minimumWindow.height - DuoMetric.toolbarHeight)
                .background(WindowConfigurator { window in
                    FixtureHarness.configure(window, model: model, options: options)
                })
        }
        // Always open the main window at launch, never restore a closed one: one launch in a few
        // came up with no window at all (F-26, F-29).
        .defaultLaunchBehavior(.presented)
        .restorationBehavior(.disabled)
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
        .defaultSize(width: DuoMetric.designWindow.width, height: DuoMetric.designWindow.height)
        .windowResizability(.contentMinSize)
        .commands { DuoCommands(model: model) }
    }
}
