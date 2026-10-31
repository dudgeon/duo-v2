import AppKit
import DuoKit
import Foundation

// Split view, slice 1 (DL-275 to DL-278). One check per failure legacy's Split View had (the handoff's
// pre-mortem): the active side, one document per file, narrow widths, and a swap that can't crash.
@MainActor func splitViewChecks() throws {
    print("split view: the active side, one document per file, narrow widths, swaps (DL-275 to DL-278)")

    // Tokens agree with the geometry.
    check(SplitGeometry.sideMin == Double(DuoMetric.splitSideMin), "splitSideMin is the token's 340")
    check(SplitRoom.railWidth == Double(DuoMetric.sidebarRail), "the sidebar rail is the token's 16")

    // --- Narrow widths (legacy: sides squeezed to nothing)
    for width in stride(from: 100.0, through: 2000.0, by: 7.0) {
        for ratio in [0.0, 0.2, 0.5, 0.8, 1.0, -3.0, .infinity, .nan] {
            let w = SplitGeometry.widths(width: width, ratio: ratio)
            if SplitGeometry.folded(width: width) {
                check(w.left == width && w.right == width, "folded \(Int(width)): each side gets the whole pane")
            } else {
                check(w.left >= 340 && w.right >= 340 && abs(w.left + w.right + 1 - width) < 0.01, "width \(Int(width)) ratio \(ratio): sides \(w.left) + \(w.right), neither under 340, nothing lost")
            }
        }
    }
    check(!SplitGeometry.folded(width: 681) && SplitGeometry.folded(width: 680), "a pane folds under 2 × 340 + 1")
    check(SplitGeometry.clampedRatio(0.05) == 0.2 && SplitGeometry.clampedRatio(0.95) == 0.8 && SplitGeometry.clampedRatio(.nan) == 0.5, "the ratio clamps to 0.2–0.8")
    let dragged = SplitGeometry.ratio(left: 100, width: 1000)
    check(SplitGeometry.widths(width: 1000, ratio: dragged).left == 340, "a drag past the minimum stops at 340")
    // Restore reproduces what was saved (rule 5).
    for r in [0.25, 0.4, 0.5, 0.63, 0.75] {
        let saved = SplitGeometry.widths(width: 960, ratio: r).left
        let again = SplitGeometry.widths(width: 960, ratio: SplitGeometry.ratio(left: saved, width: 960)).left
        check(abs(saved - again) <= 1, "ratio \(r): the divider comes back where it was saved")
    }

    // --- Making room (DL-276): the numbers in the handoff
    let r1440 = SplitRoom.plan(window: 1440, sidebarShown: true)
    check(r1440.foldsSidebar && r1440.rightWidth == 944, "1440: the sidebar folds to its rail, the console is at 480")
    check(SplitGeometry.widths(width: r1440.rightWidth - 1, ratio: 0.5).left == 471 || SplitGeometry.widths(width: r1440.rightWidth - 1, ratio: 0.5).left == 472, "1440: sides of about 470")
    let r1280 = SplitRoom.plan(window: 1280, sidebarShown: true)
    check(r1280.foldsSidebar && r1280.rightWidth == 784, "1280: the sidebar folds, the right pane takes the rest")
    check(abs(SplitGeometry.widths(width: r1280.rightWidth - 1, ratio: 0.5).left - 391) <= 1, "1280: sides of about 391")
    let wide = SplitRoom.plan(window: 1700, sidebarShown: true)
    check(!wide.foldsSidebar && wide.rightWidth == 1700 - 300 - 480, "a wide window keeps the sidebar")
    check(SplitRoom.plan(window: 1700, sidebarShown: false).rightWidth == 1700 - 480 && !SplitRoom.plan(window: 1000, sidebarShown: false).foldsSidebar, "a hidden sidebar is left alone")
    check(abs(SplitRoom.foldSidebarBelow - 1464) <= 1, "the sidebar folds under about 1,464")

    // --- The routing table: every command × side (legacy: the active side was inferred)
    for command in SplitCommand.allCases {
        for active in [SplitRole.source, .preview] {
            let route = SplitRouting.route(command, active: active)
            switch command {
            case .closeTab: check(route == (active == .preview ? .closePreview : .closeSplit), "⌘W on the \(active): \(route)")
            case .save: check(route == .saveDocument, "⌘S saves the one buffer from either side")
            case .find: check(route == .findInSide(active), "⌘F finds in the active side")
            case .sendSelection: check(route == .sendSelection(active), "⌘D sends the active side's selection")
            case .dictation: check(route == .dictateIntoSource, "dictation goes to the source from either side")
            case .formattingBar: check(route == (active == .source ? .formattingBarOverSource : .none), "the formatting bar is over the source only")
            }
            let pair = SplitRouting.route(command, active: active, docPair: true)
            if command == .closeTab { check(pair == .closeSideDocument(active), "a document pair: ⌘W closes that side's document") }
        }
    }

    // --- The model: make, close each side, swap, fold, ⌘W, one document per file
    let f = try repoFixture()
    let m = AppModel(fixture: f)
    TargetState.project.apply(to: m)
    let project = m.currentProject!.name
    func makeSplit(_ path: String = "docs/prd-v2.md", kind: PreviewKind = .markdown) {
        if !m.openDocuments.contains(path) { m.openDocuments.append(path) }
        m.rightTab = path; m.selectedFile = path
        m.splitTabs[path] = SplitTab(source: path, kind: kind)
    }
    let console = m.consoleTab

    makeSplit()
    check(m.showingSplit?.source == "docs/prd-v2.md" && m.showingSplit?.activeSide == .left, "a split is made: the source on the left, active")
    check(m.openDocuments.filter { $0 == "docs/prd-v2.md" }.count == 1, "one tab for the file: the split adds no second document")
    check(m.rightTabKeys().filter { $0 == "docs/prd-v2.md" }.count == 1, "the strip lists the split once")

    // The active side is model state, not DOM focus.
    m.webFocus = .editor
    m.setActiveRole(.preview)
    check(m.showingSplit?.active == .preview && m.showingSplit?.activeSide == .right, "setting the active side is a model change")
    m.webFocus = .none
    check(m.showingSplit?.active == .preview, "and it doesn't move when no web view has focus")
    m.stepSplitSide()
    check(m.showingSplit?.active == .source, "⇧⌘[ / ⇧⌘] step to the other side")
    m.stepSplitSide()
    check(m.showingSplit?.active == .preview, "and back")

    // ⌘W on the preview closes the preview; the source stays (and the console's session never closes: F-479)
    m.activate(.right, focus: false)
    check(m.splitHasKeys && DuoCommand.closeSession.isEnabled(in: m), "⌘W is enabled with the right pane active on a split")
    DuoCommand.closeSession.perform(in: m)
    check(m.showingSplit == nil && m.openDocuments.contains("docs/prd-v2.md") && m.rightTab == "docs/prd-v2.md", "⌘W on the preview side closes the preview and leaves the source tab")
    check(m.consoleTab == console, "and leaves the console's session alone")

    // ⌘W on the source closes the whole split with its tab
    makeSplit(); m.setActiveRole(.source); m.activate(.right, focus: false)
    DuoCommand.closeSession.perform(in: m)
    check(m.showingSplit == nil && !m.openDocuments.contains("docs/prd-v2.md"), "⌘W on the source side closes the split with its tab")
    check(m.consoleTab == console, "and the console's session is still alone")

    // The × of each side; Close Split View
    makeSplit(); m.closeSplitSide(.right)
    check(m.splitTab("docs/prd-v2.md") == nil && m.openDocuments.contains("docs/prd-v2.md"), "close the preview side: the source stays an ordinary tab")
    makeSplit(); m.closeSplitSide(.left)
    check(m.splitTab("docs/prd-v2.md") == nil && !m.openDocuments.contains("docs/prd-v2.md"), "close the source side: the split goes with its tab")
    makeSplit(); m.closeSplitView("docs/prd-v2.md")
    check(m.splitTab("docs/prd-v2.md") == nil && m.openDocuments.contains("docs/prd-v2.md"), "Close Split View keeps the source as a tab")
    m.closeDocument("docs/prd-v2.md")

    // A swap can't crash, however it's used (legacy: a swap crashed)
    m.swapSplitSides(); m.evenSplit(); m.stepSplitSide(); m.setSplitRatio(0.3); m.closeSplitSide(.left)
    check(m.showingSplit == nil, "swap, ratio, step and close with no split are harmless")
    makeSplit()
    for i in 0..<200 {
        m.swapSplitSides()
        if i % 3 == 0 { m.setActiveRole(i % 2 == 0 ? .source : .preview) }
        if i % 7 == 0 { m.setSplitRatio(Double(i % 11) / 10) }
    }
    let t = m.showingSplit!
    check(!t.swapped && t.place(of: .source) == .left && t.ratio >= 0.2 && t.ratio <= 0.8, "200 swaps leave a sound split (even swaps are the identity)")
    m.swapSplitSides()
    check(m.showingSplit!.place(of: .source) == .right && m.showingSplit!.role(at: .left) == .preview, "swapped, the source is on the right")
    check(m.showingSplit!.activeSide == m.showingSplit!.place(of: m.showingSplit!.active), "the active side follows its role through a swap")
    m.closeSplitView("docs/prd-v2.md"); m.closeDocument("docs/prd-v2.md")

    // Folding is a model change too
    makeSplit()
    m.splitFolded(true, for: "docs/prd-v2.md")
    check(m.showingSplit?.folded == true, "fold is recorded")
    m.splitFolded(false, for: "docs/prd-v2.md")
    check(m.showingSplit?.folded == false, "unfold is recorded")
    m.splitFolded(true, for: "docs/nothing.md")   // a split that isn't there: nothing happens
    m.closeSplitView("docs/prd-v2.md"); m.closeDocument("docs/prd-v2.md")

    // One document per file across kinds and two tabs
    makeSplit("docs/prd-v2.md"); makeSplit("pages/report.html", kind: .html)
    check(m.splitTabs.count == 2 && m.openDocuments.filter { $0 == "pages/report.html" }.count == 1, "two files, two splits, one tab each")
    m.splits.tabs[project]?["docs/prd-v2.md"]?.ratio = 0.35
    let saved = m.splitsForRestore(project) ?? []
    check(saved.count == 2, "both splits are saved with the restore state")

    // Persistence round trip, and the fields are optional (older files decode)
    var state = RestoreState()
    state.projects = [.init(folder: "/x", sessions: [], consoleTab: nil, documents: ["docs/prd-v2.md"], rightTab: nil)]
    state.projects[0].splits = saved
    state.splitRoom = SplitRoom.Taken(rightWidth: 460, sidebarWasShown: true, foldedSidebar: true)
    let data = try JSONEncoder().encode(state)
    let back = try JSONDecoder().decode(RestoreState.self, from: data)
    check(back == state && back.projects[0].splits?.contains { $0.ratio == 0.35 } == true, "splits and the room taken survive a save and reload")
    let old = try JSONDecoder().decode(RestoreState.self, from: Data(#"{"version":1,"leftCollapsedAllProjects":false,"leftCollapsedProject":false,"projects":[]}"#.utf8))
    check(old.splitRoom == nil, "a restore file from before split view still reads")

    // Restore validates: a split whose source is no longer a document is dropped; a wild ratio is clamped
    let m2 = AppModel(fixture: f)
    TargetState.project.apply(to: m2)
    let p2 = m2.currentProject!.name
    m2.restoreSplits([SplitTab(source: "docs/prd-v2.md", kind: .markdown, ratio: 9), SplitTab(source: "gone.md", kind: .markdown)], project: p2, documents: ["docs/prd-v2.md"])
    check(m2.splits.tabs[p2]?.count == 1 && m2.splits.tabs[p2]?["docs/prd-v2.md"]?.ratio == 0.8, "restore drops a missing source and clamps the ratio")

    // A rename follows
    makeSplit("docs/prd-v2.md")
    m.splitMoved("docs/prd-v2.md", to: "docs/prd-v3.md")
    check(m.splitTab("docs/prd-v3.md")?.source == "docs/prd-v3.md" && m.splitTab("docs/prd-v2.md") == nil, "a renamed file keeps its split")

    // --- The provider interface: revisions, stale events, echo suppression, nested anchors
    var gate = RevisionGate()
    check(gate.admit(3) && gate.admit(5) && !gate.admit(4) && gate.admit(5), "a provider drops a render older than its newest")
    let policy = PreviewPolicy()
    let rev = policy.bufferChanged { _ in }
    check(!policy.accept(.anchorMap(rev: rev - 1, [AnchorRange(anchor: "stale", firstLine: 1, lastLine: 2)])) && policy.map.isEmpty, "a map for an older revision is ignored")
    check(policy.accept(.anchorMap(rev: rev, [AnchorRange(anchor: "slide 3", firstLine: 24, lastLine: 40), AnchorRange(anchor: "slide 3/value", firstLine: 27, lastLine: 28)])), "a map for the current revision is taken")
    check(policy.narrowest(containing: 27)?.anchor == "slide 3/value" && policy.narrowest(containing: 30)?.anchor == "slide 3", "the narrowest range holding the line wins")
    let first = policy.anchorToReveal(forLine: 27)
    check(first == "slide 3/value" && policy.anchorToReveal(forLine: 27) == nil, "a reveal fires once for one anchor")
    check(!policy.accept(.current(anchor: "slide 3/value", origin: .reveal)) && policy.current == nil, "a reveal never echoes back as a current")
    check(policy.accept(.current(anchor: "slide 3", origin: .user)) && policy.current == "slide 3", "the preview's own current is taken")
    policy.caretFollow = false
    check(policy.anchorToReveal(forLine: 40) == nil, "with caret-follow off nothing is revealed")
    policy.cancel()

    // The Markdown preview: anchors by heading, outside code
    let md = "---\ntitle: x\n---\n# One\ntext\n```\n# not a heading\n```\n## Two\nmore\n"
    let map = MarkdownPreviewHTML.anchorMap(md)
    check(map.map(\.anchor) == ["h:1", "h:2"] && map[0].firstLine == 4 && map[0].lastLine == 8 && map[1].firstLine == 9, "headings are anchors, and a hash in a code block isn't one")
    let page = MarkdownPreviewHTML.page(md, colors: ("#fff", "#000", "#555", "#ccc"))
    check(page.contains("<h1>One</h1>") && page.contains("<h2>Two</h2>") && !page.contains("title: x"), "the preview renders the body, not the frontmatter")
    check(MarkdownPreviewHTML.page("<script>x</script>", colors: ("#fff", "#000", "#555", "#ccc")).contains("&lt;script&gt;"), "text in a preview is escaped")

    // Which files preview
    check(PreviewProviders.kind(forFile: "a.md") == .markdown && PreviewProviders.kind(forFile: "a.html") == .html && PreviewProviders.kind(forFile: "a.png") == nil, "Markdown and HTML preview; a picture doesn't")
    check(PreviewProviders.kind(forFile: "a.pptx") == nil, "a deck has no preview until Duo Decks registers its provider")
}
