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
        self.model = model
    }

    var body: some Scene {
        Window("Duo", id: "main") {
            RootView()
                .environment(model)
                .frame(minWidth: DuoMetric.minimumWindow.width,
                       minHeight: DuoMetric.minimumWindow.height - DuoMetric.toolbarHeight)
                .background(WindowConfigurator { window in
                    FixtureHarness.configure(window, options: options)
                })
        }
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
        .defaultSize(width: DuoMetric.designWindow.width, height: DuoMetric.designWindow.height)
        .windowResizability(.contentMinSize)
    }
}
