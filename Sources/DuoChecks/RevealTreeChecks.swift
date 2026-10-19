import DuoControl
import DuoKit
import Foundation

/// BUG-053 (F-340): revealing a folder in the file tree opens its ancestors, selects it, and asks the
/// tree to scroll to it, every time (even when it was already the selection).
@MainActor func revealTreeChecks() throws {
    print("files tree: reveal selects and asks to scroll (BUG-053)")
    let fx = try repoFixture()
    let m = AppModel(fixture: fx)
    let name = fx.projects.first { $0.kind == nil }!.name
    m.open(project: name)
    let before = m.treeRevealTick
    m.revealInTree("docs/notes")
    check(m.selectedFile == "docs/notes/", "the folder is selected")
    check((m.expandedFolders[name] ?? []).isSuperset(of: ["docs", "docs/notes"]), "and its ancestors are open")
    check(m.treeRevealTick == before + 1, "the tree is asked to scroll to it")
    m.revealInTree("docs/notes")
    check(m.treeRevealTick == before + 2, "again when it was already selected (it may have scrolled away)")
}
