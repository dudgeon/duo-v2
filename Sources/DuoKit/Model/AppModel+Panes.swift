import AppKit
import Foundation

/// The window's three panes (DL-165): left, middle, right. Inside a project that is the session list
/// and files, the console, and the right pane; at All projects it is Home, the map or list, and the
/// action column. While the task board is up it covers the left and middle: the cover counts as
/// the middle and the left is out of the order.
public enum DuoPane: String, CaseIterable, Sendable {
    case left, middle, right
}

/// The pure parts of moving between panes and tabs, apart from the model so DuoChecks can check them.
public enum PaneCycle {
    /// The panes that show, left to right; the middle always does.
    public static func order(leftShown: Bool, rightShown: Bool) -> [DuoPane] {
        (leftShown ? [DuoPane.left] : []) + [.middle] + (rightShown ? [.right] : [])
    }

    /// The next or previous item, wrapping. A `current` that is nil or not in the list gives the
    /// first (forward) or last (backward); an empty list gives nil.
    public static func step<T: Equatable>(_ items: [T], from current: T?, forward: Bool) -> T? {
        guard !items.isEmpty else { return nil }
        guard let current, let i = items.firstIndex(of: current) else { return forward ? items.first : items.last }
        return items[(i + (forward ? 1 : items.count - 1)) % items.count]
    }

    /// ⌃Tab is forward, ⌃⇧Tab backward; any other chord (with ⌘ or ⌥ too) is nil.
    public static func tabCycleDirection(keyCode: UInt16, flags: NSEvent.ModifierFlags) -> Bool? {
        guard keyCode == 48 else { return nil }
        let f = flags.intersection([.command, .option, .control, .shift])
        if f == .control { return true }
        if f == [.control, .shift] { return false }
        return nil
    }
}

extension AppModel {
    // MARK: - Which pane is active

    /// The active pane at the altitude on screen. A hidden pane can't be active: it falls back to
    /// a visible one (the middle in a project; Home, else the middle, at All projects).
    public var activePane: DuoPane {
        get {
            let stored = altitude.isAllProjects ? activePaneAllProjects : activePaneProject
            if visiblePanes().contains(stored) { return stored }
            return altitude.isAllProjects && visiblePanes().contains(.left) ? .left : .middle
        }
        set {
            if altitude.isAllProjects { activePaneAllProjects = newValue } else { activePaneProject = newValue }
        }
    }

    /// The panes on screen, left to right.
    public func visiblePanes() -> [DuoPane] {
        let leftHidden = leftCollapsed || (!altitude.isAllProjects && boardShown)
        return PaneCycle.order(leftShown: !leftHidden, rightShown: !rightCollapsed)
    }

    /// ⌥⌘→
    public func nextPane() { stepPane(forward: true) }
    /// ⌥⌘←
    public func previousPane() { stepPane(forward: false) }

    private func stepPane(forward: Bool) {
        let panes = visiblePanes()
        guard panes.count > 1, let to = PaneCycle.step(panes, from: activePane, forward: forward) else { return }
        activate(to)
    }

    /// Makes `pane` the active one and, with `focus`, gives it the keyboard.
    public func activate(_ pane: DuoPane, focus: Bool = true) {
        activePane = pane
        if focus { focusPane(pane) }
    }

    /// A click or the keyboard landing in a pane (PaneSplit): only the altitude on screen takes it,
    /// since both layouts are alive.
    func panePicked(_ pane: DuoPane, allProjects: Bool) {
        guard altitude.isAllProjects == allProjects, activePane != pane else { return }
        activePane = pane
    }

    /// The main window; none in DuoChecks, which has no application.
    var paneWindow: NSWindow? { NSApp == nil ? nil : NSApp.windows.first { $0.title == "Duo" } }

    /// Moves the keyboard into `pane`: a terminal, the chat's composer, the editor or a page; the
    /// panes with no keyboard navigation yet just let go of the old responder.
    func focusPane(_ pane: DuoPane) {
        if altitude.isAllProjects {
            guard pane == .left else { paneWindow?.makeFirstResponder(nil); return }
            if let key = homeTab, let c = chat(for: key), c.showsChat { c.focusComposer += 1 } else { focusHomeRequest += 1 }
            return
        }
        switch pane {
        case .left: paneWindow?.makeFirstResponder(nil)
        case .middle:
            if let key = consoleTab {
                if !isShell(key), let c = chat(for: key), c.showsChat { c.focusComposer += 1 } else { focusTerminal(key) }
            } else { paneWindow?.makeFirstResponder(nil) }
        case .right:
            // After the tab switch has drawn, so a page that just came on screen is there to take it.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let pages: [NSView?] = [self.visibleWebTab?.webView, self.editorIfLoaded?.webView, self.htmlViewerIfLoaded?.webView]
                if let v = pages.compactMap({ $0 }).first(where: { $0.window != nil && !$0.isHiddenOrHasHiddenAncestor }) {
                    v.window?.makeFirstResponder(v)
                } else { self.paneWindow?.makeFirstResponder(nil) }
            }
        }
    }

    // MARK: - Tabs

    /// The console strip's tab keys, in its order: sessions, then shells.
    public func consoleTabKeys(inProject project: String) -> [String] {
        tabSessions(inProject: project).map(\.tabKey) + shells(inProject: project)
    }

    /// The right pane's tabs, in its order: Project, the selected group, documents, a read-only session.
    func rightTabItems() -> [(id: String, title: String, isDocument: Bool)] {
        var tabs: [(id: String, title: String, isDocument: Bool)] = [(id: "Project", title: "Project", isDocument: false)]
        if let group = selectedSidebarItem, fixture.groups.contains(where: { $0.name == group }) {
            tabs.append((id: group, title: group, isDocument: false))
        }
        for doc in openDocuments where doc != projectFile {
            let title = webTabs[doc].map { $0.title }
                ?? templateInfo(forTab: doc).map { $0.kind == .task ? "Task template" : "Project template" }   // DL-146, board A1
                ?? (doc as NSString).lastPathComponent
            tabs.append((id: doc, title: title, isDocument: true))
        }
        if let ro = readOnlySession { tabs.append((id: ReadOnlySession.tabKey, title: ro.title, isDocument: false)) }
        // Fixture mode keeps its single document tab (the targets).
        if let doc = rightTab, doc.contains("."), !tabs.contains(where: { $0.id == doc }), doc != projectFile {
            tabs.append((id: doc, title: (doc as NSString).lastPathComponent, isDocument: true))
        }
        return tabs
    }

    public func rightTabKeys() -> [String] { rightTabItems().map(\.id) }

    /// Home's tab keys, in HomePane's order: sessions, then shells.
    public func homeTabKeys() -> [String] {
        guard let h = fixture.home?.name else { return [] }
        return tabSessions(inProject: h).map(\.tabKey) + shells(inProject: h)
    }

    /// The tab keys of `pane` at the altitude on screen; panes with no tabs have none.
    public func tabKeys(in pane: DuoPane) -> [String] {
        if altitude.isAllProjects { return pane == .left ? homeTabKeys() : [] }
        switch pane {
        case .middle: return currentProject.map { consoleTabKeys(inProject: $0.name) } ?? []
        case .right: return rightTabKeys()
        case .left: return []
        }
    }

    public func tabCount(in pane: DuoPane) -> Int { tabKeys(in: pane).count }

    /// The selected tab of `pane`: its key.
    public func currentTabKey(in pane: DuoPane) -> String? {
        if altitude.isAllProjects { return pane == .left ? homeTab : nil }
        switch pane {
        case .middle: return consoleTab
        case .right: return rightTab
        case .left: return nil
        }
    }

    /// What `pane`'s selected tab says on its strip.
    public func currentTabTitle(in pane: DuoPane) -> String? {
        guard let key = currentTabKey(in: pane) else { return nil }
        if pane == .right, !altitude.isAllProjects { return rightTabItems().first { $0.id == key }?.title ?? key }
        if let s = fixture.sessions.first(where: { $0.tabKey == key }) { return s.name }
        return consoleTitle(key)
    }

    /// ⌃Tab / ⌃⇧Tab: the next or previous tab of the active pane, wrapping; the pane gets the keyboard.
    /// Does nothing when the pane has fewer than two tabs.
    public func cycleTab(forward: Bool) {
        let pane = activePane
        let keys = tabKeys(in: pane)
        guard keys.count > 1, let to = PaneCycle.step(keys, from: currentTabKey(in: pane), forward: forward) else { return }
        if altitude.isAllProjects {
            homeTab = to
        } else if pane == .middle {
            openConsoleTab(to)
        } else if pane == .right {
            // As a click on the tab does.
            rightTab = to
            if rightTabItems().first(where: { $0.id == to })?.isDocument == true { selectedFile = to }
        }
        focusPane(pane)
    }
}
