import AppKit
import SwiftUI

/// The mark of the active pane (DL-165, option A): a 2 pt rule across the top edge of the pane,
/// drawn over the top of its tab strip or header so nothing moves. `paneFocusOnConsole` on a dark console,
/// `paneFocus` on a light pane (the text colours, until a scheme gives it its own: Classic's orange). Always shown, whether or not the window is key.
struct PaneFocusRule: View {
    @Environment(AppModel.self) private var model
    let pane: DuoPane
    /// This pane is a console (the project's middle, Home) and so is dark unless it shows chat.
    let onConsole: Bool

    var body: some View {
        if model.activePane == pane {
            let light = pane == .left ? model.homeShowsChat : model.consoleShowsChat
            let dark = onConsole && !light
            (dark ? DuoColor.paneFocusOnConsole : DuoColor.paneFocus)
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
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("video.pane.\(pane.rawValue)")   // anchors: the video camera's fixed target (H2)
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
        UserTyping.install(terminals: terminals)   // what the user typed where, for a director's guards (DL-199)
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            // Return on the file tree's selected file opens it; only while no text field, terminal or page holds the keys (F-348).
            if [36, 76].contains(e.keyCode), e.modifierFlags.intersection([.command, .shift, .option, .control]).isEmpty {
                let used = MainActor.assumeIsolated { () -> Bool in
                    guard let self, let w = e.window, w.title == "Duo", w.attachedSheet == nil, w.firstResponder === w,
                          !self.sheetIsUp, !self.search.isOpen, !self.peekOpen, !self.idleOpen, self.renamingPath == nil else { return false }
                    return self.openSelectedFile()
                }
                return used ? nil : e
            }
            // Esc clears a selection of sessions, ⌘A selects a list's sessions (DL-247): only while the list's pane
            // has the keyboard, so a terminal's Esc and an editor's ⌘A stay theirs.
            let mods = e.modifierFlags.intersection([.command, .shift, .option, .control])
            if (e.keyCode == 53 && mods.isEmpty) || (e.keyCode == 0 && mods == .command) {
                let used = MainActor.assumeIsolated { () -> Bool in
                    guard let self, let w = e.window, w.title == "Duo", w.attachedSheet == nil, !(w.firstResponder is NSTextView),
                          !self.sheetIsUp, !self.search.isOpen, !self.peekOpen, !self.idleOpen,
                          let list = self.selectionListWithKeyboard else { return false }
                    if e.keyCode == 53 {
                        guard self.sessionSelection.list == list, !self.sessionSelection.isEmpty else { return false }
                        self.clearSessionSelection()
                    } else {
                        self.selectAllSessions(list: list)
                    }
                    return true
                }
                if used { return nil }
            }
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
