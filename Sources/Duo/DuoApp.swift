import AppKit
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
        // End sessions cleanly on quit. Hiding or collapsing never does this (LR-13).
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { model.terminals.terminateAll() }
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
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
        .defaultSize(width: DuoMetric.designWindow.width, height: DuoMetric.designWindow.height)
        .windowResizability(.contentMinSize)
        .commands { DuoCommands(model: model) }
    }
}
