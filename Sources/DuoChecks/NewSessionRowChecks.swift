import AppKit
import DuoControl
import DuoKit
import Foundation

// DL-262: the New session row at All projects: its default (Home, else ~/Documents, else none), ⌘T there (F-446),
// the popup, and `duo2 session new --folder`.
@MainActor func newSessionRowChecks() throws {
    print("New session row at All projects (DL-262)")
    let docs = StartDefault.documentsURL
    let home = (name: "work", folder: URL(fileURLWithPath: "/work/home"))
    let withHome = StartDefault.resolve(home: home, documents: docs, documentsExists: true)
    check(withHome?.kind == .home && withHome?.label == "★ home" && withHome?.project == "work", "with a Home, the default is Home (even when ~/Documents exists)")
    let noHome = StartDefault.resolve(home: nil, documents: docs, documentsExists: true)
    check(noHome?.kind == .folder && noHome?.label == "~/Documents" && noHome?.folder == docs, "with no Home, the default is ~/Documents")
    check(StartDefault.resolve(home: nil, documents: docs, documentsExists: false) == nil, "with neither, there is no default, and Duo never falls back to ~ or creates ~/Documents")
    check(StartDefault.resolve(home: home, documents: docs, documentsExists: false)?.kind == .home, "a missing ~/Documents doesn't matter while there is a Home")

    // ⌘T at All projects presses the row: it started nothing before (F-446).
    let m = AppModel(fixture: try repoFixture())
    TargetState.overview.apply(to: m)
    check(m.altitude.isAllProjects, "the overview is All projects")
    m.documentsExists = false
    check(m.startDefault?.kind == .home, "the fixture's Home is the default")
    let src = (try? String(contentsOf: repoRoot().appending(path: "Sources/DuoKit/Model/AppModel.swift"), encoding: .utf8)) ?? ""
    check(src.contains("if altitude.isAllProjects { return pressNewSessionRow() }"), "New Claude Session (⌘T) at All projects presses the New session row")
    let row = (try? String(contentsOf: repoRoot().appending(path: "Sources/DuoKit/AllProjects/NewSessionRow.swift"), encoding: .utf8)) ?? ""
    check(row.contains("model.pressNewSessionRow()") && row.contains("// action: session new"), "the row runs `duo2 session new`")

    // The popup: default ticked first, a rule, the others, a rule, Choose Another Folder…, New Project…; Choose Home Folder… with no Home.
    let menu = NewSessionPopup.menu(m)
    let titles = menu.items.map { $0.isSeparatorItem ? "—" : $0.title }
    check(titles.first == "★ home" && menu.items.first?.state == .on, "the popup's first entry is the default, ticked")
    check(titles.suffix(2) == ["Choose Another Folder…", "New Project…"] && !titles.contains("Choose Home Folder…"), "it ends with Choose Another Folder… and New Project…")
    check(titles.dropFirst().first == "—", "a rule follows the default")
    let ids = Set(titles)
    check(!ids.contains("Choose…"), "no stand-in label")
    for i in m.fixture.projects.indices { m.fixture.projects[i].isHome = nil }
    let none = NewSessionPopup.menu(m).items.map { $0.isSeparatorItem ? "—" : $0.title }
    check(m.startDefault == nil && none.last == "Choose Home Folder…" && none.first != "—", "with no default and no Home: no ticked entry, and Choose Home Folder… last")
    m.documentsExists = true
    check(m.startDefault?.label == "~/Documents" && NewSessionPopup.menu(m).items.first?.state == .on, "with no Home the popup ticks ~/Documents")
    check(!m.startOthers.contains { $0.label == "~/Documents" }, "~/Documents isn't listed twice")

    // duo2.
    check(ActionID.sessionNew.action.usage.contains("--folder <path>") && ActionID.sessionNew.action.summary.contains("asks for --project or --folder"), "`duo2 session new` takes --folder and says what it does with neither")
    let ctl = (try? String(contentsOf: repoRoot().appending(path: "Sources/DuoKit/Control/AppModel+Control.swift"), encoding: .utf8)) ?? ""
    check(ctl.contains("Choose where it starts: --project <name> or --folder <path>"), "with no default it refuses and asks for --project or --folder")
    check(!ctl.contains("writeTrust") && !row.contains("ClaudeTrust.trust"), "the row never writes Claude's trust")
}
