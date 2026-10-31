import AppKit
import Foundation

/// Split view, slice 1 (DL-275 to DL-278): a file's source and its preview in one tab of the right pane.
/// Make, swap, close and fold are each one synchronous model change (legacy rule 4).
extension AppModel {
    // MARK: - Reading

    /// The split tabs of the project on screen, by source path.
    public var splitTabs: [String: SplitTab] {
        get { currentProject.flatMap { splits.tabs[$0.name] } ?? [:] }
        set { if let p = currentProject?.name { splits.tabs[p] = newValue; splits.revision += 1 } }
    }

    /// The split tab for `key` (a tab key), if it is one.
    public func splitTab(_ key: String?) -> SplitTab? { key.flatMap { splitTabs[$0] } }

    /// The split on screen: the right pane's selected tab, when it is a split.
    public var showingSplit: SplitTab? { splitTab(rightTab) }

    /// Whether the right pane is the active pane and shows a split: where ⌘W, ⌘D and the like route by side.
    public var splitHasKeys: Bool { showingSplit != nil && keyboardInRightPane }

    /// The preview a file would get, if any.
    public func previewKind(forTab path: String) -> PreviewKind? {
        guard path.contains("."), !path.hasPrefix("web:") else { return nil }
        return PreviewProviders.kind(forFile: path)
    }

    // MARK: - Making and closing

    /// ⌥⌘P: Show Preview in Split View / Close Split View for the showing file (DL-277).
    public func togglePreviewInSplitView() {
        guard let path = rightTab, path != "Project" else { return }
        if splitTabs[path] != nil { closeSplitView(path) } else { openSplitView(path) }
    }

    public var canTogglePreviewInSplitView: Bool {
        guard terminalsMode == .live, let path = rightTab, path != "Project" else { return false }
        return splitTabs[path] != nil || previewKind(forTab: path) != nil
    }

    /// Opens `path` split with its own preview. A file already split is selected (DL-278).
    @discardableResult
    public func openSplitView(_ path: String, side: SplitSide? = nil) -> Bool {
        guard currentProject != nil, let kind = previewKind(forTab: path), liveFile(path) != nil else { return false }
        if splitTabs[path] == nil {
            if !openDocuments.contains(path) { openDocument(path) }
            rightCollapsed = false
            takeRoomIfNeeded()
            splitTabs[path] = SplitTab(source: path, kind: kind)
        }
        rightTab = path
        selectedFile = path
        activate(.right, focus: false)
        if let side { focusSplitSide(side) }
        return true
    }

    /// Close Split View: ends the split and keeps the source as an ordinary tab (the preview has no file).
    public func closeSplitView(_ path: String) {
        guard let t = splitTabs[path] else { return }
        if t.isDocPair { return separateDocPair(path) }   // both stay as tabs (slice 2)
        endSplit(path)
        if rightTab == path { selectedFile = path }
    }

    /// The preview side's ×.
    public func closePreviewSide(_ path: String) { closeSplitView(path) }

    /// The source side's ×: the whole split closes, with the source tab.
    public func closeSourceSide(_ path: String) { closeDocument(path) }

    /// Closes one side of the showing split: the preview side closes the preview; the source side
    /// closes the split with its tab. `duo2 split close --side`.
    public func closeSplitSide(_ side: SplitSide) {
        guard let tab = showingSplit else { return }
        if tab.isDocPair { return closeDocPairSide(tab.role(at: side)) }
        if tab.role(at: side) == .preview { closePreviewSide(tab.source) } else { closeSourceSide(tab.source) }
    }

    /// Takes the split out of the model (called by `closeDocument` too); gives back the room with the last one.
    func endSplit(_ path: String) {
        guard let project = currentProject?.name, var all = splits.tabs[project], all[path] != nil else { return }
        all[path] = nil
        splits.tabs[project] = all.isEmpty ? nil : all
        splits.revision += 1
        splits.dropPolicy(project, path)
        if htmlViewerIfLoaded?.bufferText != nil { htmlViewerIfLoaded?.endBuffer() }
        if !splits.any { giveBackRoom() }
    }

    // MARK: - Previewing (the provider interface)

    /// Starts rendering `path`'s preview from the editor's buffer: now, and 250 ms after each pause in typing.
    /// Split view owns this policy; the provider only draws what it is given.
    func startPreview(_ path: String) {
        guard let project = currentProject?.name, let t = splitTabs[path] else { return }
        let policy = splits.policy(project, path)
        if t.kind == .markdown { splits.markdown.emit = { [weak policy] e in policy?.accept(e) } }
        let render: @MainActor (Int) -> Void = { [weak self] rev in self?.renderPreview(path, rev: rev) }
        editor(.main).onBufferChange = { [weak policy] in policy?.bufferChanged(render: render) }
        // The editor opens the file after this view appears: render once it has, and again a moment later.
        for delay in [0.3, 1.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { MainActor.assumeIsolated { policy.bufferChanged(render: render) } }
        }
    }

    func renderPreview(_ path: String, rev: Int) {
        guard let t = splitTabs[path], let file = liveFile(path), editor(.main).url?.standardizedFileURL == file.standardizedFileURL else { return }
        editor(.main).currentText { [weak self] text in
            guard let self, let text, self.splitTabs[path] != nil else { return }
            switch t.kind {
            case .markdown: self.splits.markdown.render(text: text, rev: rev)
            case .html:
                let root = Self.isOutsideFile(path) ? file.deletingLastPathComponent() : (self.projectFolder ?? file.deletingLastPathComponent())
                self.htmlViewer.renderBuffer(text, file: file, root: root)
            case .deck, .document: break   // Duo Decks' provider (preview-provider)
            }
        }
    }

    // MARK: - Sides

    public func swapSplitSides() {
        guard var t = showingSplit else { return }
        t.swapped.toggle()
        splitTabs[t.source] = t
    }

    public func setSplitRatio(_ r: Double) {
        guard var t = showingSplit else { return }
        t.ratio = SplitGeometry.clampedRatio(r)
        splitTabs[t.source] = t
    }

    /// Double-click on the divider.
    public func evenSplit() { setSplitRatio(0.5) }

    /// The active side is model state: set by a click or typing in a side, `duo2 split focus`.
    public func setActiveRole(_ role: SplitRole, in key: String? = nil) {
        guard let k = key ?? rightTab, var t = splitTabs[k] else { return }
        defer { syncActiveEditor(t) }   // a pair's active side is the active editor (C-135)
        guard t.active != role else { return }
        t.active = role
        splitTabs[k] = t
    }

    /// Unfolds a folded split: the console narrows just enough for two sides (never under its 480),
    /// and the hidden side becomes active. Clicking the rail or the dimmed name; `duo2 split unfold`.
    public func unfoldSplit(_ role: SplitRole? = nil) {
        guard let t = showingSplit else { return }
        if let host = splits.paneHost, host.bounds.width > 0 {
            let sidebar = leftCollapsedProject ? (splits.sidebarFolded ? SplitRoom.railWidth : 0) : SplitRoom.sidebarWidth
            let wanted = SplitGeometry.foldBelow + 1   // two sides, their divider and the pane's edge
            let right = min(wanted, Double(host.bounds.width) - sidebar - SplitRoom.consoleMin)
            if right > Double(host.lastPaneWidth) { host.setLastPaneWidth(CGFloat(right)) }
        }
        setActiveRole(role ?? (t.active == .source ? .preview : .source), in: t.source)
    }

    /// ⇧⌘[ and ⇧⌘]: the other side of the split becomes active, folded or not (Q-368).
    public func stepSplitSide() {
        guard let t = showingSplit else { return }
        focusSplitSide(t.activeSide.other)
    }

    /// Gives the keyboard to the side at `side` and makes it active.
    public func focusSplitSide(_ side: SplitSide) {
        guard let t = showingSplit else { return }
        let role = t.role(at: side)
        setActiveRole(role)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let view: NSView? = role == .source ? self.editorIfLoaded(.main)?.webView : self.previewWebView(for: t)
            if let v = view, v.window != nil { v.window?.makeFirstResponder(v) }
        }
    }

    func previewWebView(for t: SplitTab) -> NSView? {
        switch t.kind {
        case .markdown: splits.markdown.webView
        case .html: htmlViewerIfLoaded?.webView
        case .document: editorIfLoaded(.second)?.webView
        case .deck: nil
        }
    }

    /// The fold of the split on screen, from its width (watched inside AppKit by the side split).
    public func splitFolded(_ folded: Bool, for path: String) {
        guard var t = splitTabs[path], t.folded != folded else { return }
        t.folded = folded
        splitTabs[path] = t
    }

    /// `duo2 split` with nothing else: the sides, active side, ratio, folded, and the sidebar.
    public func splitReport() -> String {
        guard let t = showingSplit else { return "no split view showing" }
        let name = { (r: SplitRole) in r == .source ? t.source : (t.with ?? t.kind.sideName) }
        let left = name(t.role(at: .left)), right = name(t.role(at: .right))
        return "left: \(left)\nright: \(right)\nactive: \(t.activeSide.rawValue)\nratio: \(String(format: "%.3f", t.ratio))\nfolded: \(t.folded)\nsidebar folded by the split: \(splits.sidebarFolded)"
    }

    // MARK: - Making room (DL-276)

    func takeRoomIfNeeded() {
        guard splits.taken == nil, let host = splits.paneHost, host.bounds.width > 0 else { return }
        let width = Double(host.bounds.width)
        let plan = SplitRoom.plan(window: width, sidebarShown: !leftCollapsedProject)
        splits.taken = SplitRoom.Taken(rightWidth: Double(host.lastPaneWidth), sidebarWasShown: !leftCollapsedProject, foldedSidebar: plan.foldsSidebar)
        if plan.foldsSidebar { leftCollapsedProject = true }
        host.setLastPaneWidth(CGFloat(plan.rightWidth))
    }

    /// Closing the last split gives back exactly what it took.
    func giveBackRoom() {
        guard let taken = splits.taken else { return }
        splits.taken = nil
        splits.peek = false
        splits.paneHost?.setLastPaneWidth(CGFloat(taken.rightWidth))
        if taken.foldedSidebar, taken.sidebarWasShown { leftCollapsedProject = false }
    }

    /// ⌃⌘S: the sidebar, or while the split folded it, a peek over the console.
    public func toggleSidebarOrPeek() {
        if splits.sidebarFolded { splits.peek.toggle() } else { leftCollapsed.toggle() }
    }

    public func setSidebarPeek(_ on: Bool) { if splits.sidebarFolded { splits.peek = on } }

    // MARK: - Routing (⌘W, ⌘S, ⌘D) by the active side

    /// ⌘W while a split has the keys: the active side closes; never the console's session (F-479).
    func closeActiveSplitSide() {
        guard let t = showingSplit else { return }
        switch SplitRouting.route(.closeTab, active: t.active, docPair: t.isDocPair) {
        case .closeSideDocument(let role): closeDocPairSide(role)
        case .closePreview: closePreviewSide(t.source)
        default: closeSourceSide(t.source)
        }
    }

    // MARK: - Moves

    /// A file in a split was renamed or moved: the split follows.
    public func splitMoved(_ old: String, to new: String) {
        for (project, var all) in splits.tabs {
            if let k = all.first(where: { $0.value.with == old })?.key { all[k]?.with = new; splits.tabs[project] = all }   // a pair's other document
            guard var t = all.removeValue(forKey: old) else { continue }
            t.source = new
            all[new] = t
            splits.tabs[project] = all
            splits.dropPolicy(project, old)
        }
    }

    // MARK: - Persistence (Duo Decks R10)

    /// The saved splits of `project`, valid ones only.
    public func splitsForRestore(_ project: String) -> [SplitTab]? {
        let docs = Set(openDocumentsByProject[project] ?? [])
        let all = (splits.tabs[project] ?? [:]).values.filter { docs.contains($0.source) }.sorted { $0.source < $1.source }
        return all.isEmpty ? nil : Array(all)
    }

    /// Reopens saved splits for `project`: only those whose source is still a document and still previews as saved.
    public func restoreSplits(_ saved: [SplitTab]?, project: String, documents: [String]) {
        guard let saved else { return }
        var out: [String: SplitTab] = [:]
        for var t in saved where documents.contains(t.source) {
            guard PreviewProviders.kind(forFile: t.source) == t.kind || t.kind == .deck || (t.kind == .document && t.with != nil) else { continue }
            t.ratio = SplitGeometry.clampedRatio(t.ratio)
            out[t.source] = t
        }
        if !out.isEmpty { splits.tabs[project] = out }
    }

    func restoreRoom(_ taken: SplitRoom.Taken?) {
        guard splits.any, let taken else { return }
        splits.taken = taken
        if taken.foldedSidebar { leftCollapsedProject = true }
        let width = splits.paneHost.map { Double($0.bounds.width) } ?? 0
        let right = SplitRoom.plan(window: width, sidebarShown: taken.sidebarWasShown).rightWidth
        if width > 0 { splits.applyRightWidthSoon(right) } else { splits.pendingRightWidth = right }
    }
}
