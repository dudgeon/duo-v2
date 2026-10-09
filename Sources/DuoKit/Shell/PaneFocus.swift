import AppKit
import SwiftUI

/// The mark of the active pane (DL-165, option A): a 2 pt rule across the top edge of the pane,
/// drawn over the top of its tab strip or header so nothing moves. `consoleText` on a dark console,
/// `text` on a light pane. Always shown, whether or not the window is key.
struct PaneFocusRule: View {
    @Environment(AppModel.self) private var model
    let pane: DuoPane
    /// This pane is a console (the project's middle, Home) and so is dark unless it shows chat.
    let onConsole: Bool

    var body: some View {
        if model.activePane == pane {
            let light = pane == .left ? model.homeShowsChat : model.consoleShowsChat
            let dark = onConsole && !light
            (dark ? DuoColor.consoleText : DuoColor.text)
                .frame(height: DuoMetric.borderPaneFocusRule)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

extension View {
    /// The active-pane rule over this pane's top edge.
    func paneFocusRule(_ pane: DuoPane, onConsole: Bool = false) -> some View {
        overlay(alignment: .top) { PaneFocusRule(pane: pane, onConsole: onConsole) }
    }
}

@MainActor enum PaneKeyMonitor { static var installed = false }

extension AppModel {
    /// ⌃Tab and ⌃⇧Tab step the active pane's tabs wherever the keyboard is. A terminal sends them to
    /// the shell and a web view may take them, so one key monitor handles them before either sees
    /// them. They are used even with one tab, so ⌃⇧Tab never reaches Claude as ⇧Tab. Not while a
    /// sheet, the search, the peek or the idle list is up. Idempotent.
    public func installPaneKeys() {
        guard !PaneKeyMonitor.installed else { return }
        PaneKeyMonitor.installed = true
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let forward = PaneCycle.tabCycleDirection(keyCode: e.keyCode, flags: e.modifierFlags) else { return e }
            let used = MainActor.assumeIsolated { () -> Bool in
                guard let self, let w = e.window, w.title == "Duo", w.attachedSheet == nil,
                      !self.sheetIsUp, !self.search.isOpen, !self.peekOpen, !self.idleOpen else { return false }
                self.cycleTab(forward: forward)
                return true
            }
            return used ? nil : e
        }
    }
}
