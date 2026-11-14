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
            let color = dark ? DuoColor.paneFocusOnConsole : DuoColor.paneFocus
            if pane == .right, let split = model.showingSplit {
                // A split (DL-275): the rule spans only the active side's width, at the top of the strip.
                GeometryReader { geo in
                    let w = SplitGeometry.widths(width: geo.size.width, ratio: split.ratio)
                    let side = split.activeSide
                    let folded = SplitGeometry.folded(width: geo.size.width)
                    color.frame(width: folded ? geo.size.width : side == .left ? w.left : w.right, height: DuoMetric.borderPaneFocusRule)
                        .offset(x: folded || side == .left ? 0 : w.left + SplitGeometry.divider)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            } else {
                color
                    .frame(height: DuoMetric.borderPaneFocusRule)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
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
        // One monitor for the app: each key goes to the model of the window it was typed in (multi-window slice 0).
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak core = self.core] e in
            // Return on the file tree's selected file opens it; only while no text field, terminal or page holds the keys (F-348).
            if [36, 76].contains(e.keyCode), e.modifierFlags.intersection([.command, .shift, .option, .control]).isEmpty {
                let used = MainActor.assumeIsolated { () -> Bool in
                    guard let w = e.window, let m = core?.model(for: w), w.attachedSheet == nil, w.firstResponder === w,
                          !m.sheetIsUp, !m.search.isOpen, !m.peekOpen, !m.idleOpen, m.renamingPath == nil else { return false }
                    return m.openSelectedFile()
                }
                return used ? nil : e
            }
            // Esc clears a selection of sessions, ⌘A selects a list's sessions (DL-247): only while the list's pane
            // has the keyboard, so a terminal's Esc and an editor's ⌘A stay theirs.
            let mods = e.modifierFlags.intersection([.command, .shift, .option, .control])
            if (e.keyCode == 53 && mods.isEmpty) || (e.keyCode == 0 && mods == .command) {
                let used = MainActor.assumeIsolated { () -> Bool in
                    guard let w = e.window, let m = core?.model(for: w), w.attachedSheet == nil, !(w.firstResponder is NSTextView),
                          !m.sheetIsUp, !m.search.isOpen, !m.peekOpen, !m.idleOpen,
                          let list = m.selectionListWithKeyboard else { return false }
                    if e.keyCode == 53 {
                        guard m.sessionSelection.list == list, !m.sessionSelection.isEmpty else { return false }
                        m.clearSessionSelection()
                    } else {
                        m.selectAllSessions(list: list)
                    }
                    return true
                }
                if used { return nil }
            }
            guard let forward = PaneCycle.tabCycleDirection(keyCode: e.keyCode, flags: e.modifierFlags) else { return e }
            let used = MainActor.assumeIsolated { () -> Bool in
                guard let w = e.window, let m = core?.model(for: w), w.attachedSheet == nil,
                      !m.sheetIsUp, !m.search.isOpen, !m.peekOpen, !m.idleOpen else { return false }
                m.cycleTab(forward: forward)
                return true
            }
            return used ? nil : e
        }
    }
}
