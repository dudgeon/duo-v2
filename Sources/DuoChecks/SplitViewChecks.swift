import AppKit
import DuoKit
import Foundation

// Split view, slice 1 (DL-275 to DL-278). One check per failure legacy's Split View had (the handoff's
// pre-mortem): the active side, one document per file, narrow widths, and a swap that can't crash.
@MainActor func splitViewChecks() throws {
    print("split view: the active side, one document per file, narrow widths, swaps (DL-275 to DL-278)")

    // Tokens agree with the geometry.
    check(SplitGeometry.sideMin == Double(DuoMetric.splitSideMin), "splitSideMin is the token's 300")
    check(SplitRoom.railWidth == Double(DuoMetric.sidebarRail), "the sidebar rail is the token's 16")

    // --- Narrow widths (legacy: sides squeezed to nothing)
    for width in stride(from: 100.0, through: 2000.0, by: 7.0) {
        for ratio in [0.0, 0.2, 0.5, 0.8, 1.0, -3.0, .infinity, .nan] {
            let w = SplitGeometry.widths(width: width, ratio: ratio)
            if SplitGeometry.folded(width: width) {
                check(w.left == width && w.right == width, "folded \(Int(width)): each side gets the whole pane")
            } else {
                check(w.left >= 300 && w.right >= 300 && abs(w.left + w.right + 1 - width) < 0.01, "width \(Int(width)) ratio \(ratio): sides \(w.left) + \(w.right), neither under 300, nothing lost")
            }
        }
    }
    check(!SplitGeometry.folded(width: 601) && SplitGeometry.folded(width: 600), "a pane folds under 2 × 300 + 1")
    check(SplitGeometry.clampedRatio(0.05) == 0.2 && SplitGeometry.clampedRatio(0.95) == 0.8 && SplitGeometry.clampedRatio(.nan) == 0.5, "the ratio clamps to 0.2–0.8")
    let dragged = SplitGeometry.ratio(left: 100, width: 1000)
    check(SplitGeometry.widths(width: 1000, ratio: dragged).left == 300, "a drag past the minimum stops at 300")
    // Restore reproduces what was saved (rule 5).
    for r in [0.25, 0.4, 0.5, 0.63, 0.75] {
        let saved = SplitGeometry.widths(width: 960, ratio: r).left
        let again = SplitGeometry.widths(width: 960, ratio: SplitGeometry.ratio(left: saved, width: 960)).left
        check(abs(saved - again) <= 1, "ratio \(r): the divider comes back where it was saved")
    }

    // --- Making room (DL-276, with DL-306's "Squeeze others first"): the console to 400 and the sides to 300
    // before the sidebar is touched, so it folds only under 1,303 (about 1,300).
    check(SplitRoom.consoleMin == Double(DuoMetric.splitConsoleMin), "the console's split minimum is the token's 400")
    let r1440 = SplitRoom.plan(window: 1440, sidebarShown: true)
    check(!r1440.foldsSidebar && r1440.rightWidth == 1440 - 300 - 400 - 2, "1440: all three panes stay, the console is at 400 and the right pane takes the rest")
    check(abs(SplitGeometry.widths(width: r1440.rightWidth - 1, ratio: 0.5).left - 368) <= 1 && !SplitGeometry.folded(width: r1440.rightWidth - 1), "1440: two sides of about 368")
    let r1280 = SplitRoom.plan(window: 1280, sidebarShown: true)
    check(r1280.foldsSidebar && r1280.rightWidth == 1280 - 16 - 400 - 2, "1280: under 1,303 the sidebar folds to its rail, the right pane takes the rest")
    check(abs(SplitGeometry.widths(width: r1280.rightWidth - 1, ratio: 0.5).left - 430) <= 1, "1280: sides of about 430 beside the rail")
    // F-531, DL-306: the sidebar folds only when sidebar 300 + console 400 + two 300 sides don't fit.
    let r1810 = SplitRoom.plan(window: 1810, sidebarShown: true)
    check(!r1810.foldsSidebar && r1810.rightWidth == 1810 - 300 - 400 - 2, "1810: the sidebar stays; the console narrows to 400 and the right pane takes the rest")
    check(!SplitGeometry.folded(width: r1810.rightWidth - 1), "1810: two sides fit")
    check(!SplitRoom.plan(window: 1303, sidebarShown: true).foldsSidebar && SplitRoom.plan(window: 1302, sidebarShown: true).foldsSidebar,
          "the sidebar folds under 1,303 and not at it (300 + 400 + two 300 sides and their dividers)")
    check(SplitRoom.plan(window: 1303, sidebarShown: true).rightWidth == 601 && !SplitGeometry.folded(width: 601) && SplitGeometry.folded(width: 600),
          "at the edge the right pane is exactly two 300 sides and their divider, and one less folds the split")
    check(!SplitRoom.plan(window: 1300, sidebarShown: true).foldsSidebar == false && SplitRoom.plan(window: 1300, sidebarShown: true).foldsSidebar,
          "about 1,300 and under, it folds")
    // The split folds to one side only when even the sidebar's rail leaves too little (never at the 1280 minimum window).
    check(!SplitGeometry.folded(width: SplitRoom.plan(window: 1280, sidebarShown: true).rightWidth - 1), "at the 1280 window minimum two sides still fit with the sidebar folded")
    let wide = SplitRoom.plan(window: 1700, sidebarShown: true)
    check(!wide.foldsSidebar && wide.rightWidth == 1700 - 300 - 400 - 2, "a wide window keeps the sidebar")
    check(SplitRoom.plan(window: 1700, sidebarShown: false).rightWidth == 1700 - 400 - 2 && !SplitRoom.plan(window: 1000, sidebarShown: false).foldsSidebar, "a hidden sidebar is left alone")
    check(abs(SplitRoom.foldSidebarBelow - 1303) <= 1, "the sidebar folds under about 1,300 (1,303 with the dividers)")

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
    func makeSplit(_ path: String = "pages/report.html", kind: PreviewKind = .html) {
        if !m.openDocuments.contains(path) { m.openDocuments.append(path) }
        m.rightTab = path; m.selectedFile = path
        m.splitTabs[path] = SplitTab(source: path, kind: kind)
    }
    let console = m.consoleTab

    makeSplit()
    check(m.showingSplit?.source == "pages/report.html" && m.showingSplit?.activeSide == .left, "a split is made: the source on the left, active")
    check(m.openDocuments.filter { $0 == "pages/report.html" }.count == 1, "one tab for the file: the split adds no second document")
    check(m.rightTabKeys().filter { $0 == "pages/report.html" }.count == 1, "the strip lists the split once")

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
    check(m.showingSplit == nil && m.openDocuments.contains("pages/report.html") && m.rightTab == "pages/report.html", "⌘W on the preview side closes the preview and leaves the source tab")
    check(m.consoleTab == console, "and leaves the console's session alone")

    // ⌘W on the source closes the whole split with its tab
    makeSplit(); m.setActiveRole(.source); m.activate(.right, focus: false)
    DuoCommand.closeSession.perform(in: m)
    check(m.showingSplit == nil && !m.openDocuments.contains("pages/report.html"), "⌘W on the source side closes the split with its tab")
    check(m.consoleTab == console, "and the console's session is still alone")

    // The × of each side; Close Split View
    makeSplit(); m.closeSplitSide(.right)
    check(m.splitTab("pages/report.html") == nil && m.openDocuments.contains("pages/report.html"), "close the preview side: the source stays an ordinary tab")
    makeSplit(); m.closeSplitSide(.left)
    check(m.splitTab("pages/report.html") == nil && !m.openDocuments.contains("pages/report.html"), "close the source side: the split goes with its tab")
    makeSplit(); m.closeSplitView("pages/report.html")
    check(m.splitTab("pages/report.html") == nil && m.openDocuments.contains("pages/report.html"), "Close Split View keeps the source as a tab")
    m.closeDocument("pages/report.html")

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
    m.closeSplitView("pages/report.html"); m.closeDocument("pages/report.html")

    // Folding is a model change too
    makeSplit()
    m.splitFolded(true, for: "pages/report.html")
    check(m.showingSplit?.folded == true, "fold is recorded")
    m.splitFolded(false, for: "pages/report.html")
    check(m.showingSplit?.folded == false, "unfold is recorded")
    m.splitFolded(true, for: "docs/nothing.md")   // a split that isn't there: nothing happens
    m.closeSplitView("pages/report.html"); m.closeDocument("pages/report.html")

    // One document per file across kinds and two tabs
    makeSplit("pages/report.html"); makeSplit("pages/other.html", kind: .html)
    check(m.splitTabs.count == 2 && m.openDocuments.filter { $0 == "pages/other.html" }.count == 1, "two files, two splits, one tab each")
    m.splits.tabs[project]?["pages/report.html"]?.ratio = 0.35
    let saved = m.splitsForRestore(project) ?? []
    check(saved.count == 2, "both splits are saved with the restore state")

    // Persistence round trip, and the fields are optional (older files decode)
    var state = RestoreState()
    state.projects = [.init(folder: "/x", sessions: [], consoleTab: nil, documents: ["pages/report.html"], rightTab: nil)]
    state.projects[0].splits = saved
    state.splitRoom = SplitRoom.Taken(rightWidth: 460, sidebarWasShown: true, foldedSidebar: true)
    let data = try JSONEncoder().encode(state)
    let back = try JSONDecoder().decode(RestoreState.self, from: data)
    check(back == state && back.projects[0].splits?.contains { $0.ratio == 0.35 } == true, "splits and the room taken survive a save and reload")
    let old = try JSONDecoder().decode(RestoreState.self, from: Data(#"{"version":1,"leftCollapsedAllProjects":false,"leftCollapsedProject":false,"projects":[]}"#.utf8))
    check(old.splitRoom == nil, "a restore file from before split view still reads")

    // DL-315: All projects' sidebar starts closed until the person toggles it; a project's starts open
    let fresh = AppModel(fixture: f)
    check(fresh.leftCollapsedAllProjects && !fresh.leftTouchedAllProjects && !fresh.leftCollapsedProject, "untouched: All projects' sidebar starts closed, a project's open")
    check(fresh.currentRestoreState().leftAllProjectsOnRestore == (collapsed: true, touched: false), "an untouched save restores closed, still untouched")
    fresh.altitude = .allProjects; fresh.leftCollapsed = false
    let openSave = fresh.currentRestoreState()
    check(fresh.leftTouchedAllProjects && openSave.leftAllProjectsOnRestore == (collapsed: false, touched: true), "touched open: stays open across launches")
    let reopened = try JSONDecoder().decode(RestoreState.self, from: try JSONEncoder().encode(openSave))
    check(reopened.leftAllProjectsOnRestore == (collapsed: false, touched: true), "touched open survives a save and reload")
    fresh.leftCollapsed = true
    check(fresh.currentRestoreState().leftAllProjectsOnRestore == (collapsed: true, touched: true), "touched closed: stays closed across launches")
    let oldTrue = try JSONDecoder().decode(RestoreState.self, from: Data(#"{"version":1,"leftCollapsedAllProjects":true,"leftCollapsedProject":false,"projects":[]}"#.utf8))
    check(oldTrue.leftAllProjectsOnRestore == (collapsed: true, touched: true), "an old file with true counts as touched, and stays closed")
    check(old.leftAllProjectsOnRestore == (collapsed: true, touched: false) && !old.leftCollapsedProject, "an old file with false counts as untouched, and starts closed; a project's sidebar is read as saved")

    // Restore validates: a split whose source is no longer a document is dropped; a wild ratio is clamped
    let m2 = AppModel(fixture: f)
    TargetState.project.apply(to: m2)
    let p2 = m2.currentProject!.name
    m2.restoreSplits([SplitTab(source: "pages/report.html", kind: .html, ratio: 9), SplitTab(source: "gone.md", kind: .html)], project: p2, documents: ["pages/report.html"])
    check(m2.splits.tabs[p2]?.count == 1 && m2.splits.tabs[p2]?["pages/report.html"]?.ratio == 0.8, "restore drops a missing source and clamps the ratio")

    // A rename follows
    makeSplit("pages/report.html")
    m.splitMoved("pages/report.html", to: "pages/report3.html")
    check(m.splitTab("pages/report3.html")?.source == "pages/report3.html" && m.splitTab("pages/report.html") == nil, "a renamed file keeps its split")

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

    // Which files preview
    check(PreviewProviders.kind(forFile: "a.md") == nil && PreviewProviders.kind(forFile: "a.html") == .html && PreviewProviders.kind(forFile: "a.png") == nil, "HTML previews; Markdown (live in the editor) and a picture don't")
    check(PreviewProviders.kind(forFile: "a.pptx") == nil, "a deck has no preview until Duo Decks registers its provider")
}
