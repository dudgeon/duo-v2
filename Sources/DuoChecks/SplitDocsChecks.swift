import AppKit
import DuoControl
import DuoKit
import Foundation

// DL-278 (split-docs): two documents side by side, both editable; an editor per side (C-135).
@MainActor func splitDocsChecks() throws {
    print("split view, slice 2: two documents, both editable (DL-278)")
    let fm = FileManager.default
    let root = URL(fileURLWithPath: "/tmp/duo-pair-\(UUID().uuidString.prefix(6))")
    let proj = root.appending(path: "buyer-interviews")
    try fm.createDirectory(at: proj, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: root) }
    try Data("# Interview 4: Dana, ops lead\n\nWe stopped trusting the dashboard.\n".utf8).write(to: proj.appending(path: "interview-notes.md"))
    try Data("# What we heard\n\nTrust broke at the March outage.\n".utf8).write(to: proj.appending(path: "synthesis.md"))
    try Data("# Plan\n".utf8).write(to: proj.appending(path: "plan.md"))
    try Data([0x89, 0x50, 0x4e, 0x47, 0, 0, 0, 0]).write(to: proj.appending(path: "chart.png"))
    setenv("DUO_EDITOR_DIR", repoRoot().appending(path: "Vendor/codemirror/dist").path, 1)

    var fx = try repoFixture()
    fx.projects.append(try JSONDecoder().decode(Fixture.Project.self, from: JSONSerialization.data(withJSONObject: ["name": "buyer-interviews", "topic": "Research", "path": proj.path, "goal": "g"])))
    let m = AppModel(fixture: fx)
    m.terminalsMode = .live
    m.liveFolders["buyer-interviews"] = proj
    m.open(project: "buyer-interviews")
    func wait(_ s: Double = 10, _ ok: () -> Bool) -> Bool {
        let until = Date().addingTimeInterval(s)
        while !ok(), Date() < until { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
        return ok()
    }
    func duo2(_ args: String...) -> ControlResponse {
        var out: ControlResponse?
        m.handle(ControlRequest(token: "", command: args[0], args: Array(args.dropFirst()), session: nil, cwd: proj.path)) { out = $0 }
        _ = wait { out != nil }
        return out ?? ControlResponse(ok: false, output: "no answer")
    }
    let notes = "interview-notes.md", synth = "synthesis.md"

    // Making a pair: the other file's tab moves into the split; one tab, two documents.
    m.openDocument(notes); m.openDocument(synth)
    check(m.openSplitView(notes, with: synth), "Open in Split View: synthesis.md beside interview-notes.md")
    let t = m.showingSplit
    check(t?.isDocPair == true && t?.source == notes && t?.with == synth && t?.kind == .document, "a pair: the source and `with`, kind document")
    check(m.openDocuments.contains(notes) && !m.openDocuments.contains(synth), "the other file's tab moved into the split (one tab for the pair)")
    check(t?.active == .preview && t?.activeSide == .right, "the file opened in split view is on the right, active")
    check(m.activeEditorRef == .second, "the active side's editor is the second (C-135)")
    check(m.splitSideName(t!, .source) == notes && m.splitSideName(t!, .preview) == synth, "each side is named for its file")

    // Both editable: each side's editor opens its own document.
    let e1 = m.editor(.main), e2 = m.editor(.second)
    e1.open(proj.appending(path: notes)); e2.open(proj.appending(path: synth))
    check(wait { e1.phase == .open && e2.phase == .open }, "both sides open, each in its own editor")
    check(m.editor === e2 && m.editorShowing(proj.appending(path: notes)) === e1, "`editor` (⌘S, Format, review, duo2 doc) is the active side's")

    // One document per file: opening a file that's in a split selects the split and its side.
    m.rightTab = "Project"
    check(m.openSplitView(notes, with: synth), "Open in Split View on a file already in a split selects it")
    check(m.rightTab == notes && m.showingSplit?.active == .preview, "…that split, on that file's side")
    check(m.splitCandidates(beside: notes).isEmpty && !m.splitCandidates(beside: "plan.md").contains(synth), "a split's files aren't offered for another split")
    check(!m.openSplitView("plan.md", with: notes) || m.rightTab == notes, "a file in a split never opens in a second split (it selects the first)")
    check(m.splitTabs.count == 1, "still one split")
    check(!m.openSplitView(notes, with: notes), "a file can't be beside itself")
    m.openDocument("chart.png")
    check(!m.openSplitView("chart.png", with: "plan.md") && !m.canOpenInSplitView("chart.png"), "a file that isn't text isn't offered (C-26)")
    m.closeDocument("chart.png")
    m.rightTab = notes

    // Routing by the active side (one table): ⌘W, ⌘S, find, ⌘D, voice, the formatting bar.
    for role in [SplitRole.source, .preview] {
        check(SplitRouting.route(.closeTab, active: role, docPair: true) == .closeSideDocument(role), "pair, \(role): ⌘W closes that side's document")
        check(SplitRouting.route(.save, active: role, docPair: true) == .saveDocument, "pair, \(role): ⌘S saves (the active side's editor)")
        check(SplitRouting.route(.find, active: role, docPair: true) == .findInSide(role), "pair, \(role): ⌘F finds in that side")
        check(SplitRouting.route(.sendSelection, active: role, docPair: true) == .sendSelection(role), "pair, \(role): ⌘D sends that side's selection")
        check(SplitRouting.route(.formattingBar, active: role, docPair: true) == .formattingBarOverActive, "pair, \(role): the formatting bar over the active side")
        check(SplitRouting.route(.dictation, active: role, docPair: true) == .formattingBarOverActive, "pair, \(role): dictation into the active side")
        m.setActiveRole(role)
        check(m.activeEditorRef == (role == .source ? .main : .second) && m.editor === (role == .source ? e1 : e2), "pair, \(role): the menus' editor is that side's")
    }
    // A preview split keeps the main editor whatever was active (slice 1's routing is untouched).
    m.editors.active = .second
    m.openDocument("plan.md"); m.splitTabs["plan.md"] = SplitTab(source: "plan.md", kind: .markdown)
    check(m.activeEditorRef == .main && m.editor === e1, "a source and its preview: the editor is the main one")
    m.closeSplitView("plan.md"); m.rightTab = notes

    // Save and reconcile per side.
    m.setActiveRole(.preview)
    e2.run("duo.typeOne(0); return 1") { _ in }
    check(wait { e2.dirty }, "typing in the right side makes it dirty, the left untouched (\(e1.dirty ? "dirty" : "clean"))")
    DuoCommand.save.perform(in: m)
    check(wait { !e2.dirty } && ((try? String(contentsOf: proj.appending(path: synth), encoding: .utf8)) ?? "").hasPrefix("x# What"), "⌘S with the right side active saves synthesis.md")
    try Data("# Interview 4: Dana, ops lead\n\nWe stopped trusting the dashboard.\n\nAdded by Claude.\n".utf8).write(to: proj.appending(path: notes))
    var leftText: String?
    _ = wait { e1.run("return duo.text()") { leftText = $0 as? String }; return leftText?.contains("Added by Claude.") == true }
    check(leftText?.contains("Added by Claude.") == true, "an outside write to the left side's file merges into the left side")

    // ⌘W on each side; the console's session never closes (F-479).
    let console = m.consoleTab
    m.setActiveRole(.preview); m.activate(.right, focus: false)
    DuoCommand.closeSession.perform(in: m)
    check(m.showingSplit == nil && m.rightTab == notes && m.openDocuments.contains(notes) && !m.openDocuments.contains(synth), "⌘W on the right side closes synthesis.md; interview-notes.md stays a tab")
    check(e2.url == nil && m.consoleTab == console, "…the second editor lets go of it, and the console's session stays")
    _ = m.openSplitView(notes, with: synth)
    m.setActiveRole(.source); m.activate(.right, focus: false)
    DuoCommand.closeSession.perform(in: m)
    check(m.showingSplit == nil && !m.openDocuments.contains(notes) && m.openDocuments.contains(synth) && m.rightTab == synth, "⌘W on the left side closes interview-notes.md; synthesis.md stays a tab, selected")
    check(m.consoleTab == console, "…and the console's session stays")

    // Close Split View: both stay as tabs. The name's × on the right closes that document.
    m.openDocument(notes)
    _ = m.openSplitView(notes, with: synth)
    m.closeSplitView(notes)
    check(m.showingSplit == nil && m.openDocuments.contains(notes) && m.openDocuments.contains(synth), "Close Split View on a pair keeps both as tabs")
    check(m.openDocuments.firstIndex(of: synth) == m.openDocuments.firstIndex(of: notes).map { $0 + 1 }, "…side by side in the strip")
    _ = m.openSplitView(notes, with: synth)
    m.closeSplitSide(m.showingSplit!.place(of: .preview))
    check(m.showingSplit == nil && !m.openDocuments.contains(synth), "the right side's × closes its document")
    m.closeDocument(notes)
    m.openDocument(notes)
    _ = m.openSplitView(notes, with: synth)
    m.closeDocument(synth)
    check(m.showingSplit == nil && m.openDocuments.contains(notes), "closing the right document by name (a trash, a move) closes its side")

    // Swap: 200 swaps with sides active in turn don't crash, and the editors keep their documents.
    _ = m.openSplitView(notes, with: synth)
    e1.open(proj.appending(path: notes)); e2.open(proj.appending(path: synth))
    _ = wait { e1.phase == .open && e2.phase == .open }
    let before = (e1.url, e2.url)
    for i in 0..<200 {
        m.swapSplitSides()
        if i % 3 == 0 { m.setActiveRole(i % 2 == 0 ? .source : .preview) }
        if i % 5 == 0 { m.stepSplitSide() }
    }
    check(m.showingSplit?.isDocPair == true && m.showingSplit?.swapped == false, "200 swaps leave a sound pair")
    check(e1.url == before.0 && e2.url == before.1, "swaps never move a document between editors (no reload)")
    m.swapSplitSides()
    check(m.showingSplit!.place(of: .preview) == .left && m.splitReport().contains("left: \(synth)"), "swapped, synthesis.md is on the left (`duo2 split` says so)")
    m.swapSplitSides()

    // Rename and restore follow `with`.
    m.splitMoved(synth, to: "synthesis-v2.md")
    check(m.showingSplit?.with == "synthesis-v2.md", "a rename of the right document follows it into the pair")
    m.splitMoved("synthesis-v2.md", to: synth)
    let saved = m.splitsForRestore("buyer-interviews") ?? []
    check(saved.first?.with == synth, "the pair is saved with its second document")
    let m2 = AppModel(fixture: fx)
    m2.restoreSplits(saved, project: "buyer-interviews", documents: [notes])
    check(m2.splits.tabs["buyer-interviews"]?[notes]?.with == synth, "…and restored")
    m.separateDocPair(notes)

    // duo2: split --with, split separate.
    m.closeDocument(synth)
    m.rightTab = notes
    let r = duo2("split", "--with", synth)
    check(r.ok && m.showingSplit?.with == synth, "`duo2 split --with <file>` opens it beside the showing tab (\(r.output.prefix(60)))")
    check(duo2("split").output.contains("right: \(synth)"), "`duo2 split` reports both documents")
    check(duo2("split", "separate").ok && m.showingSplit == nil && m.openDocuments.contains(synth), "`duo2 split separate` keeps both as tabs")
    check(duo2("split", notes, "--with", synth).ok && m.showingSplit?.source == notes, "`duo2 split <file> --with <file>` names both")
    check(!duo2("split", notes, "--with", notes).ok, "…and refuses a file beside itself")
    m.separateDocPair(notes)
}
