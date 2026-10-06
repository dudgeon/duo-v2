import DuoControl
import DuoKit
import DuoSearch
import Foundation

// Plain assertions, run with `swift run DuoChecks`. Exit status is the number of failures.

nonisolated(unsafe) var failures = 0
nonisolated(unsafe) var passes = 0

func check(_ condition: @autoclosure () throws -> Bool, _ name: String, line: Int = #line) {
    do {
        if try condition() { passes += 1; print("  ✔ \(name)") }
        else { failures += 1; print("  ✘ \(name)  (line \(line))") }
    } catch {
        failures += 1; print("  ✘ \(name): \(error)  (line \(line))")
    }
}

func repoFixture() throws -> Fixture {
    var dir = URL(fileURLWithPath: #filePath)
    for _ in 0..<3 { dir.deleteLastPathComponent() }
    return try Fixture.load(from: dir.appending(path: "docs/design/build-handoff/fixture.json"))
}

@MainActor func run() throws {
    let f = try repoFixture()

    print("fixture")
    check(f.topics == ["Payments", "Growth", "Platform"], "topics decode")
    check(f.home?.name == "home", "home project")
    check(f.sessions.count == 11, "eleven sessions")
    check(f.needsYou.map(\.name) == ["Morning triage", "Copy review pass 2", "PRD v2 edits"], "needs-you longest wait first")

    print("session list: needs you, open, then history (DL-91)")
    do {
        let all = SidebarRow.rows(for: "checkout-redesign", in: f)
        let leafs = all.flatMap { r -> [SidebarRow] in if case .older(let rows) = r.kind { return rows } else { return [r] } }
        let quiet = leafs.first { $0.state != .needsYou }
        let secs = SidebarRow.sections(for: "checkout-redesign", in: f, isOpen: { $0 == quiet?.sessionKey })
        let flat = secs.flatMap { $0.rows.flatMap { r -> [SidebarRow] in if case .older(let rows) = r.kind { return rows } else { return [r] } } }
        check(Set(flat.map(\.id)) == Set(leafs.map(\.id)) && flat.count == leafs.count, "every row once")
        check(secs.first?.id == "needs" && secs.first?.rows.allSatisfy { $0.state == .needsYou } == true, "needs you first")
        check(secs.dropFirst().first?.id == "open" && secs.dropFirst().first?.rows.map(\.id) == [quiet?.id].compactMap { $0 }, "then what's open in Duo")
        check(secs.dropFirst(2).allSatisfy { ["today", "week", "earlier"].contains($0.id) }, "then history by date")
    }

    print("properties (DB-16)")
    do {
        check(PropertyCorpus.type(name: "due", value: "2026-10-14", hasItems: false) == "date"
              && PropertyCorpus.type(name: "at", value: "2026-10-14T09:30", hasItems: false) == "datetime"
              && PropertyCorpus.type(name: "ok", value: "false", hasItems: false) == "checkbox"
              && PropertyCorpus.type(name: "n", value: "15", hasItems: false) == "number"
              && PropertyCorpus.type(name: "prd", value: "\"[PRD v2](docs/prd-v2.md)\"", hasItems: false) == "link"
              && PropertyCorpus.type(name: "tags", value: "", hasItems: false) == "list"
              && PropertyCorpus.type(name: "x", value: "[a, b]", hasItems: false) == "list"
              && PropertyCorpus.type(name: "goal", value: "\"Cut churn\"", hasItems: false) == "text", "types read from how values are written, as the editor reads them")
        let dir = FileManager.default.temporaryDirectory.appending(path: "duo-corpus-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir.appending(path: "a"), withIntermediateDirectories: true)
        try? "---\nowner: Geoff\ntags:\n  - pm\n  - q4\n---\n# A\n".write(to: dir.appending(path: "a/one.md"), atomically: true, encoding: .utf8)
        try? "---\nowner: Geoff\ndue: 2026-10-14\n---\n".write(to: dir.appending(path: "two.md"), atomically: true, encoding: .utf8)
        try? "no frontmatter\n".write(to: dir.appending(path: "three.md"), atomically: true, encoding: .utf8)
        let c = PropertyCorpus.scan(here: dir, others: [])
        let names = (c["names"] as? [[String: Any]]) ?? []
        let owner = names.first { $0["name"] as? String == "owner" }
        check(names.first?["name"] as? String == "owner" && owner?["count"] as? Int == 2 && owner?["here"] as? Bool == true, "names counted by document, most used first")
        check(names.contains { $0["name"] as? String == "tags" && $0["type"] as? String == "list" } && (((c["values"] as? [String: Any])?["tags"] as? [[String: Any]])?.count == 2), "list items become suggested values")
        try? FileManager.default.removeItem(at: dir)
    }

    print("task notes (DL-93)")
    do {
        let id1 = "aaaaaaaa-1111-4222-8333-444444444444", id2 = "bbbbbbbb-1111-4222-8333-444444444444"
        let fresh = TaskNotes.newNote(title: "Exec review prep", links: [TaskNotes.link(title: "Interview [notes]", id: id1)])
        let parsed = TaskNotes.parse(fresh, path: "tasks/exec-review-prep.md")
        check(parsed.title == "Exec review prep" && parsed.status == "open" && parsed.sessionIds == [id1], "a new note reads back: title, status, linked session")
        let added = TaskNotes.adding(TaskNotes.link(title: "Draft", id: id2), to: fresh)
        check(added.map { TaskNotes.parse($0, path: "t.md").sessionIds } == [id1, id2], "Add to Task appends to the sessions list")
        check(added.map { $0.replacingOccurrences(of: "\n  - \"[Draft](duo2://session/\(id2))\"", with: "") } == fresh, "and changes nothing else in the note")
        check(TaskNotes.adding(TaskNotes.link(title: "x", id: id1), to: fresh) == nil, "a session already linked isn't added twice")
        let bare = "---\ntitle: Old\nsessions: [\(id1)]\nowner: me\n---\nBody\r"
        check(TaskNotes.parse(bare, path: "t.md").sessionIds == [id1], "bare ids still count (DL-13)")
        check(TaskNotes.adding(TaskNotes.link(title: "y", id: id2), to: bare).map { TaskNotes.parse($0, path: "t.md").sessionIds } == [id1, id2]
              && TaskNotes.adding(TaskNotes.link(title: "y", id: id2), to: bare)?.contains("owner: me\n---\nBody\r") == true, "an inline list becomes a block list; the rest stays")
        let none = "# Just a note\n\nText\n"
        check(TaskNotes.adding(TaskNotes.link(title: "z", id: id2), to: none).map { TaskNotes.parse($0, path: "tasks/just.md") }?.sessionIds == [id2]
              && TaskNotes.parse(none, path: "tasks/just.md").title == "Just a note", "a note with no frontmatter gets one; title from its heading")
        check(TaskNotes.slug("Exec review — prep (v2)!") == "exec-review-prep-v2", "slug filenames")
        let day = Date(timeIntervalSince1970: 1_791_000_000)
        let done = TaskNotes.settingStatus("done", in: fresh, today: day)
        check(TaskNotes.parse(done, path: "t.md").status == "done" && done.contains("\ncompleted: 2026-") && done.hasSuffix("# Exec review prep\n\n"),
              "status done adds completed:, nothing else changes")
        check(TaskNotes.settingStatus("in-progress", in: done) == fresh.replacingOccurrences(of: "status: open", with: "status: in-progress"),
              "reopening removes completed: and puts the note back as it was")
        let quoted = TaskNotes.newNote(title: #"Say "hi" \ bye"#, links: [])
        check(TaskNotes.parse(quoted, path: "t.md").title == #"Say "hi" \ bye"#, "a title with quotes and backslashes reads back as written")
        check(TaskNotes.parse("---\ntitle: 'It''s done'\n---\n", path: "t.md").title == "It's done", "single-quoted titles unescape ''")
        check(TaskNotes.parse("---\ntitle: \"\"\n---\n\n# Retyped\n", path: "tasks/x.md").title == "Retyped",
              "an emptied title: falls back to the heading")
    }

    print("New Session in Task: the task drafted in the prompt, not sent (DL-112)")
    do {
        check(TaskNotes.draft(path: "tasks/exec-review-prep.md") == "@tasks/exec-review-prep.md ", "the draft is the note's @-reference and a space, as drawn")
        check(TaskNotes.draft(path: "tasks/my task.md") == "@\"tasks/my task.md\" ", "a note with a space in its name is quoted")
        let hostile = TaskNotes.draft(path: "tasks/a\rb\nc.md")
        check(!hostile.contains("\r") && !hostile.contains("\n"), "no Return can reach the prompt from a note's name")
        check(TerminalSession.bracketed(TaskNotes.draft(path: "tasks/exec-review-prep.md")) == "\u{1b}[200~@tasks/exec-review-prep.md \u{1b}[201~",
              "typed as one bracketed paste: no Return after it")
        check(TerminalSession.bracketed("x\u{1b}[201~\r") == "\u{1b}[200~x[201~\u{1b}[201~", "a paste can't end itself early or press Return")
    }

    print("restore on relaunch (LR-58)")
    do {
        let tmp = FileManager.default.temporaryDirectory.appending(path: "duo-restore-\(UUID().uuidString).json")
        var r = RestoreState(); r.root = "/x/home"; r.project = "/x/home/a"
        r.projects = [.init(folder: "/x/home/a", sessions: ["s1"], consoleTab: "s1", documents: ["notes.md"], rightTab: "notes.md")]
        try JSONEncoder().encode(r).write(to: tmp)
        check(RestoreState.load(tmp) == r, "round-trips")
        var newer = r; newer.version = RestoreState.version + 1
        try JSONEncoder().encode(newer).write(to: tmp)
        check(RestoreState.load(tmp) == nil, "a file from a newer Duo is ignored")
        try Data("not json".utf8).write(to: tmp)
        check(RestoreState.load(tmp) == nil, "an unreadable file is ignored")
        check(RestoreState.file(root: "/x/home") != RestoreState.file(root: "/y/home") && RestoreState.file(root: nil).lastPathComponent == "restore-no-home.json",
              "one file per Home")
        try? FileManager.default.removeItem(at: tmp)
    }

    print("update notice")
    check(UpdateCheck.isNewer("0.1.10", than: "0.1.9") && UpdateCheck.isNewer("v0.2.0", than: "0.1.2") && !UpdateCheck.isNewer("0.1.2", than: "0.1.2"), "versions compare by number")
    check(UpdateCheck.isNewer("0.2.0", than: "0.2.0-rc.1") && !UpdateCheck.isNewer("0.2.0-rc.1", than: "0.2.0"), "a pre-release sorts below its release")

    print("update question: Open Releases Page, Install Now, Later (DL-114)")
    do {
        let page = URL(string: "https://github.com/dudgeon/duo-v2/releases/tag/v0.1.9")!
        let r = UpdateCheck.Release(version: "0.1.9", page: page)
        func plan(_ latest: UpdateCheck.Release?, _ current: String = "0.1.8", writable: Bool, sparkle: Bool = true, user: Bool = true) -> UpdateCheck.Plan {
            UpdateCheck.plan(latest: latest, current: current, installWritable: writable, sparkle: sparkle, folder: "/Applications", userInitiated: user)
        }
        func labels(_ q: DuoQuestion) -> [String] { q.choices.map(\.label) }
        func defaultLabel(_ q: DuoQuestion) -> String? { q.choices.first(where: \.isDefault)?.label }
        func ask(_ p: UpdateCheck.Plan) -> DuoQuestion? {
            guard case .offer(let o) = p else { return nil }
            return UpdateCheck.question(o, openPage: {}, installNow: {}, later: {})
        }

        // Writable: Install Now is the default, Open Releases Page beside it.
        let w = plan(r, writable: true)
        check(w == .offer(.init(version: "0.1.9", current: "0.1.8", page: page, needsAdmin: false, canInstallNow: true, folder: "/Applications")),
              "writable: a newer release is offered, no password needed")
        if let q = ask(w) {
            check(q.title == "Duo 0.1.9 is available." && q.paragraphs.first == "You have 0.1.8.", "writable: the title names the version, then what you have")
            check(labels(q) == ["Later", "Open Releases Page", "Install Now"] && defaultLabel(q) == "Install Now" && q.choices.first?.isCancel == true,
                  "writable: Install Now is the default, Later is Escape")
            check(!q.paragraphs.joined().contains("administrator"), "writable: no mention of a password")
        } else { check(false, "writable: asks") }

        // Not writable: say so, and Open Releases Page is the default.
        let n = plan(r, writable: false)
        if let q = ask(n) {
            check(q.paragraphs.contains { $0.hasPrefix("Installing it here needs an administrator password") && $0.contains("`/Applications`") },
                  "not writable: the question says installing here needs an administrator password")
            check(labels(q) == ["Later", "Install Now", "Open Releases Page"] && defaultLabel(q) == "Open Releases Page",
                  "not writable: Open Releases Page is the default, Install Now still offered")
        } else { check(false, "not writable: asks") }

        // Up to date and unreachable: no question (Sparkle answers as before).
        check(plan(r, "0.1.9", writable: false) == .upToDate(current: "0.1.9", page: page) && plan(r, "0.2.0", writable: true) == .upToDate(current: "0.2.0", page: page),
              "up to date: no offer")
        check(plan(nil, writable: true) == .unreachable && plan(nil, writable: false) == .unreachable, "GitHub unreachable: no offer")

        // Without Sparkle (development and scripted builds) only the releases page is offered.
        if let q = ask(plan(r, writable: true, sparkle: false)) {
            check(labels(q) == ["Later", "Open Releases Page"] && defaultLabel(q) == "Open Releases Page", "no Sparkle: Open Releases Page and Later only")
        } else { check(false, "no Sparkle: asks") }
        check(ask(plan(r, "0.0.1", writable: true, sparkle: true)).map(labels) == ["Later", "Open Releases Page"]
              && ask(plan(r, "0.0.1", writable: true)).map { $0.paragraphs.first } == "You have a development build.",
              "a development build is offered the latest, never Install Now")

        // duo2 update's answer names the releases page and the password.
        let sw = UpdateCheck.summary(w, installedAt: "/Applications/Duo.app", installWritable: true, sparkle: true)
        let sn = UpdateCheck.summary(n, installedAt: "/Applications/Duo.app", installWritable: false, sparkle: true)
        let su = UpdateCheck.summary(.unreachable, installedAt: "/Applications/Duo.app", installWritable: false, sparkle: true)
        check(sw.contains("Releases page: \(page.absoluteString)") && sw.contains("needs no administrator password"), "duo2 update, writable: the page and no password")
        check(sn.contains("Releases page: \(page.absoluteString)") && sn.contains("needs an administrator password"), "duo2 update, not writable: the page and the password")
        check(su.hasPrefix("Couldn't reach GitHub") && su.contains("Releases page: https://github.com/dudgeon/duo-v2/releases\n"), "duo2 update, unreachable: every release's page")
        check(UpdateCheck.page(plan(r, "0.1.9", writable: true)) == page && UpdateCheck.page(.unreachable) == UpdateCheck.releasesList, "--open opens the release's page, or every release's")
        check(Invocation(["--open", "--json"]).has("open") && Invocation(["--open", "--json"]).json, "--open takes no value")

        // The writability test the probe and the question share.
        let tmpApp = FileManager.default.temporaryDirectory.appending(path: "duo-checks-\(UUID().uuidString)/Duo.app")
        try FileManager.default.createDirectory(at: tmpApp.appending(path: "Contents/Helpers"), withIntermediateDirectories: true)
        check(InstallLocation.app(containing: tmpApp.appending(path: "Contents/Helpers/duo2"))?.lastPathComponent == "Duo.app"
              && InstallLocation.app(containing: URL(fileURLWithPath: "/usr/bin/true")) == nil, "the app around a helper, none outside one")
        check(InstallLocation.canReplace(tmpApp), "an app in a folder you own can be replaced")
        check(!InstallLocation.canReplace(URL(fileURLWithPath: "/System/Applications/Calculator.app")), "an app in a folder you can't write can't")
        try? FileManager.default.removeItem(at: tmpApp.deletingLastPathComponent())
    }

    print("browser tabs: allowed sites (DL-3)")
    do {
        let list = ["example.com", "docs.google.com"]
        check(AllowedSites.allows(URL(string: "https://example.com/a")!, list: list) && AllowedSites.allows(URL(string: "https://www.example.com")!, list: list),
              "a host allows itself and its subdomains")
        check(!AllowedSites.allows(URL(string: "https://notexample.com")!, list: list) && !AllowedSites.allows(URL(string: "https://google.com")!, list: list),
              "lookalikes and parents aren't allowed")
        check(AllowedSites.allows(URL(string: "http://localhost:3000")!, list: []) && AllowedSites.allows(URL(string: "http://app.localhost")!, list: []),
              "localhost is always allowed")
        check(AllowedSites.url(from: "example.com/x")?.absoluteString == "https://example.com/x" && AllowedSites.url(from: "localhost:8080")?.absoluteString == "http://localhost:8080"
              && AllowedSites.url(from: "two words") == nil, "the address field reads hosts, localhost and URLs")
        let f = FileManager.default.temporaryDirectory.appending(path: "duo-sites-\(UUID().uuidString).txt")
        check(AllowedSites.add("www.Example.com", to: f) && !AllowedSites.add("example.com", to: f) && AllowedSites.load(f) == ["example.com"], "allow list adds once, without www")
        try? FileManager.default.removeItem(at: f)
    }

    print("ordering")
    check(WaitTime("1h") > WaitTime("12m") && WaitTime("3d") > WaitTime("1h") && WaitTime("now") < WaitTime("4m"), "wait times")
    check(SessionState.allCases.sorted() == [.needsYou, .readyForReview, .working, .idle, .resolved], "states most urgent first")

    print("target states")
    let project = AppModel(fixture: f)
    TargetState.project.apply(to: project)
    check(project.needsYouElsewhere.count == 2, "chip counts only other projects (2 need you)")
    let zoom4 = AppModel(fixture: f)
    TargetState.flowZoom4.apply(to: zoom4)
    check(zoom4.fixture.counts.needsYou == 2 && zoom4.fixture.counts.working == 5, "flow-zoom-4 counts: 2 need you, 5 working")
    check(zoom4.fixture.needsYou.map(\.name) == ["Morning triage", "PRD v2 edits"], "flow-zoom-4 action column one card shorter")
    check(zoom4.selectedActionSession == "checkout-redesign/PRD v2 edits", "flow-zoom-4 selection")

    print("navigation")
    let nav = AppModel(fixture: f)
    TargetState.overview.apply(to: nav)
    nav.open(project: "checkout-redesign")
    check(nav.altitude == .project("checkout-redesign"), "tile opens the project")
    check(nav.consoleTab == "PRD v2 edits" && nav.rightTab == "docs/prd-v2.md", "opens on the session that needs you and its document [P]")
    check(nav.selectedSidebarItem == "PRD v2" && nav.expandedGroups.contains("PRD v2"), "its group is selected and expanded")
    check(nav.needsYouElsewhere.count == 2, "chip: 2 need you elsewhere")
    nav.togglePeek()
    check(nav.peekOpen && nav.peekSelection == "home/Morning triage", "peek opens on the longest wait")
    nav.movePeekSelection(by: 1)
    check(nav.peekSelection == "onboarding-v3/Copy review pass 2", "down arrow moves the peek selection")
    nav.movePeekSelection(by: 5)
    check(nav.peekSelection == "onboarding-v3/Copy review pass 2", "selection stops at the last card")
    nav.jumpToPeekSelection()
    check(nav.altitude == .project("onboarding-v3") && nav.consoleTab == "Copy review pass 2" && !nav.peekOpen, "cmd-return jumps into that project on that session")
    nav.zoomOut()
    check(nav.altitude == .allProjects && nav.selectedActionSession == "onboarding-v3/Copy review pass 2", "zooming out selects the session last in (flow-zoom-4)")
    nav.open(project: "checkout-redesign")
    nav.goHome()
    check(nav.altitude == .allProjects && nav.homeTab == "Morning triage" && nav.focusHomeRequest == 1, "shift-cmd-H: All projects, Home terminal focused")
    let tiles = AppModel(fixture: f)
    tiles.moveTileFocus(dx: 0, dy: 0)
    check(tiles.focusedTile == "home", "first arrow focuses the first tile: Home's, in a column of its own (DL-104)")
    tiles.moveTileFocus(dx: 1, dy: 0)
    tiles.moveTileFocus(dx: 0, dy: 1)
    check(tiles.focusedTile == "refunds-api-spec", "down moves within a topic column")
    tiles.moveTileFocus(dx: 1, dy: 0)
    check(tiles.focusedTile == "pricing-experiment-q4", "right moves to the next topic, nearest row")
    tiles.moveTileFocus(dx: 1, dy: 0)
    check(tiles.focusedTile == "api-deprecations", "right clamps to the last row of a shorter column")
    let chords = DuoCommand.allCases.compactMap(\.shortcut).map { "\($0.key.character)\($0.modifiers.rawValue)" }
    check(chords.count == Set(chords).count, "no two commands share a chord")

    print("claude storage")
    check(ClaudeStorage.encode("/Users/geoff/repos/duo-v2") == "-Users-geoff-repos-duo-v2", "encode: slashes")
    check(ClaudeStorage.encode("/w/a.b_c d") == "-w-a-b-c-d", "encode: dots, underscores, spaces")
    check(ClaudeStorage.encode("/w/ünï-côde") == "-w--n--c-de", "encode: non-ASCII one dash per code point")
    let long = "/Users/geoff/" + String(repeating: "deep-folder/", count: 40)
    check(ClaudeStorage.encode(long).count > 200 && ClaudeStorage.encode(long).hasPrefix(String(ClaudeStorage.encode(String(long.prefix(300))).prefix(200)) + "-"), "encode: over 200 chars truncates and hashes")
    let cal = ClaudeStorage.calibrate()
    print("    calibration against ~/.claude/projects: \(cal.matched)/\(cal.checked) folders match, \(cal.collisions) collisions, \(cal.mismatches.count) mismatches")
    for m in cal.mismatches.prefix(5) { print("      ✘ \(m.folder) ← \(m.cwd) encodes to \(m.encoded)") }
    check(cal.ok, "encoder self-calibration on this machine")

    print("frontmatter")
    let fm = Frontmatter.parse("---\r\ntype: project\r\ntitle: \"Checkout, redesign\"\r\ntags: [a, \"b, c\"]\r\nwaiting_on:\r\n  - Priya\r\n  - \"[Legal](../people/legal.md)\"\r\n# a comment\r\nhealth: on-track\r\n---\r\nBody text\r\n")
    check(fm.string("type") == "project" && fm.string("title") == "Checkout, redesign", "scalars, quoted with a comma, CRLF")
    check(fm.list("tags") == ["a", "b, c"], "inline list with a quoted comma")
    check(fm.list("waiting_on") == ["Priya", "[Legal](../people/legal.md)"], "block list, quoted markdown link")
    check(fm.body == "Body text\n", "body after the fence")
    check(Frontmatter.parse("No frontmatter\n").values.isEmpty, "no fence: no values, no failure")

    print("project discovery")
    let ws = FileManager.default.temporaryDirectory.appending(path: "duo-checks-\(UUID().uuidString)")
    func write(_ rel: String, _ text: String) throws {
        let u = ws.appending(path: rel)
        try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: u, atomically: true, encoding: .utf8)
    }
    try write("payments/checkout-redesign/PROJECT.md", "---\ntype: project\ngoal: Cut guest-checkout abandonment 15% by Q1\nhealth: on-track\nnext: Exec review Oct 14\n---\n")
    try write("payments/checkout-redesign/docs/inner/PROJECT.md", "---\ngoal: nested, ignored\n---\n")
    try write("growth/onboarding-v3/PROJECT.md", "---\ngoal: Lift day-7 activation to 40%\nhealth: at-risk\n---\n")
    try write("home/HOME.md", "---\ntype: home\ngoal: Triage\n---\n")
    try write("old-home/HOME.md", "---\ntype: home\n---\n")
    try write("node_modules/x/PROJECT.md", "---\n---\n")
    let found = ProjectDiscovery.scan(root: ws)
    check(Set(found.map(\.project.name)) == ["checkout-redesign", "inner", "onboarding-v3", "home", "old-home"], "finds projects, nested ones and homes; skips node_modules")
    check(found.first { $0.project.name == "inner" }?.project.topic == "payments", "a project inside a project sits beside it, in its topic (DL-89)")
    let checkout = found.first { $0.project.name == "checkout-redesign" }?.project
    check(checkout?.topic == "payments" && checkout?.health == "On track" && checkout?.next == "Exec review Oct 14", "topic from parent folder, health label, next")
    let homes = ProjectDiscovery.chooseHome(found, remembered: ws.appending(path: "home").path)
    check(homes.home?.project.name == "home" && homes.contested, "two HOME.md: the remembered one wins, flagged as contested (DL-42)")
    try? FileManager.default.removeItem(at: ws)

    print("home as container, topics by folder (DL-82..85)")
    do {
        let base = FileManager.default.temporaryDirectory.appending(path: "duo-home-\(UUID().uuidString)").resolvingSymlinksInPath()
        let hw = base.appending(path: "work")
        func put(_ rel: String, _ text: String = "---\n---\n") throws {
            let u = base.appending(path: rel)
            try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: u, atomically: true, encoding: .utf8)
        }
        try put("work/HOME.md")
        try put("work/checkout/PROJECT.md")
        try put("work/payments/refunds/PROJECT.md")
        try FileManager.default.createDirectory(at: hw.appending(path: "scratch"), withIntermediateDirectories: true)
        try put("outside/repo/PROJECT.md")
        try FileManager.default.createDirectory(at: base.appending(path: "outside/repo/src"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: base.appending(path: "outside/loose"), withIntermediateDirectories: true)
        let hist: [(id: String, transcript: URL, cwd: String)] = [
            ("h-home", base.appending(path: "t1.jsonl"), hw.path),
            ("h-scratch", base.appending(path: "t2.jsonl"), hw.appending(path: "scratch").path),
            ("h-checkout", base.appending(path: "t3.jsonl"), hw.appending(path: "checkout/src").path),
            ("h-repo", base.appending(path: "t4.jsonl"), base.appending(path: "outside/repo/src").path),
            ("h-loose", base.appending(path: "t5.jsonl"), base.appending(path: "outside/loose").path),
        ]
        var c = LiveSnapshot.Context(root: hw)
        c.includeHistory = false
        c.historyOverride = hist
        let (hs, _, _) = LiveSnapshot.build(c, beacons: [])
        let byId = { (id: String) in hs.sessions.first { $0.sessionId == id }?.project }
        let outsideLabel = ProjectDiscovery.topic(for: base.appending(path: "outside/loose"), root: hw)
        check(hs.home?.name == "work", "HOME.md at the root makes the root Home (DL-85)")
        check(byId("h-home") == "work" && byId("h-scratch") == "scratch" && byId("h-checkout") == "checkout",
              "Home holds only its own folder's sessions; a folder inside it is listed as a folder; deepest project wins")
        check(byId("h-repo") == "repo" && byId("h-loose") == "loose", "outside Home: a PROJECT.md above the cwd makes a project; other folders listed (DL-82)")
        check(hs.projects.first { $0.name == "checkout" }?.topic == "" && hs.projects.first { $0.name == "refunds" }?.topic == "payments"
              && hs.projects.first { $0.name == "scratch" }?.topic == "", "in Home: unlabelled when directly in it, else the folder it sits in (DL-83)")
        check(hs.projects.first { $0.name == "repo" }?.topic == outsideLabel && outsideLabel.hasSuffix("/outside"), "outside Home: grouped by parent folder path")
        check(hs.topics == ["", "payments", outsideLabel], "columns: Home's root projects, Home's topics, then outside folders")
        var none = c
        none.root = nil
        let (ns, _, _) = LiveSnapshot.build(none, beacons: [])
        check(ns.home == nil && Set(ns.sessions.compactMap(\.sessionId)) == Set(hist.map(\.id)), "no Home: every session still listed (DL-82)")
        check(ns.projects.first { $0.name == "checkout" }?.topic == ProjectDiscovery.topic(for: hw.appending(path: "checkout"), root: nil)
              && ns.projects.first { $0.name == "checkout" }?.isFolderOnly == false, "no Home: projects found from the sessions' folders, grouped by parent")
        check(ProjectDiscovery.topic(for: FileManager.default.homeDirectoryForCurrentUser.appending(path: "repos/duo"), root: nil) == "~/repos",
              "a folder in ~/repos is labelled ~/repos")
        try? FileManager.default.removeItem(at: base)
    }

    print("attention")
    func beacon(_ status: String, _ waiting: String? = nil) -> Beacon {
        Beacon(pid: 1, sessionId: "s", cwd: "/", name: nil, status: status, waitingFor: waiting, statusUpdatedAt: nil, entrypoint: nil, kind: nil)
    }
    check(Attention.state(for: beacon("waiting", "input needed")) == (.needsYou, .question), "waiting for input: needs you, question")
    check(Attention.state(for: beacon("waiting", "permission prompt")) == (.needsYou, .permission), "waiting for permission: needs you, permission")
    check(Attention.state(for: beacon("busy")).0 == .working, "busy: working")
    check(Attention.state(for: beacon("idle"), lastStopMessage: "Move saved cards into scope?").0 == .needsYou, "idle after a question: needs you")
    check(Attention.state(for: beacon("idle"), lastStopMessage: "Done.").0 == .idle, "idle after a statement: idle")
    let now = Date(timeIntervalSince1970: 10_000)
    check(Attention.waitText(since: 9_990_000, now: now) == "now" && Attention.waitText(since: 9_760_000, now: now) == "4m", "wait text")
    check(!Beacon.readAll().isEmpty, "reads live beacons on this machine")

    print("session index and live snapshot")
    let lw = FileManager.default.temporaryDirectory.appending(path: "duo-live-\(UUID().uuidString)")
    let proj = lw.appending(path: "payments/checkout-redesign")
    try FileManager.default.createDirectory(at: proj, withIntermediateDirectories: true)
    try "---\ngoal: \"Cut abandonment\"\nhealth: at-risk\n---\n".write(to: proj.appending(path: "PROJECT.md"), atomically: true, encoding: .utf8)
    try FileManager.default.createDirectory(at: lw.appending(path: "home"), withIntermediateDirectories: true)
    try "# Home\n".write(to: lw.appending(path: "home/HOME.md"), atomically: true, encoding: .utf8)
    var idx = SessionIndex()
    idx.sessions = [.init(sessionId: "aaaa-filed"), .init(sessionId: "bbbb-archived")]
    idx.sessions[1].archived = true
    idx.groups = [.init(name: "PRD v2", sessions: ["aaaa-filed", "cccc-live"])]
    try idx.save(project: proj)
    let saved = try Data(contentsOf: SessionIndex.url(for: proj))
    let mtime = try FileManager.default.attributesOfItem(atPath: SessionIndex.url(for: proj).path)[.modificationDate] as? Date
    Thread.sleep(forTimeInterval: 0.02)
    try idx.save(project: proj)
    let mtime2 = try FileManager.default.attributesOfItem(atPath: SessionIndex.url(for: proj).path)[.modificationDate] as? Date
    check(SessionIndex.load(project: proj) == idx, "index round-trips")
    check(mtime == mtime2 && String(decoding: saved, as: UTF8.self).hasSuffix("}\n"), "byte-equal index isn't rewritten (LDI-39)")
    check(SessionIndex.load(project: lw) == SessionIndex(), "missing index reads as empty")
    let live = Beacon(pid: 1, sessionId: "cccc-live", cwd: proj.appending(path: "docs").path, name: "PRD v2 edits",
                      status: "waiting", waitingFor: "input needed", statusUpdatedAt: Date().timeIntervalSince1970 * 1000 - 240_000,
                      entrypoint: "cli", kind: nil, nameSource: "user")
    let (snap, folders, _) = LiveSnapshot.build(noHistory(lw), beacons: [live])
    let ss = snap.sessions(inProject: "checkout-redesign")
    check(ss.map(\.sessionId) == ["aaaa-filed", "cccc-live"], "filed sessions plus live ones attributed by cwd; archived hidden")
    check(ss.last?.name == "PRD v2 edits" && ss.last?.state == .needsYou && ss.last?.wait == "4m", "beacon gives name, state, wait")
    check(snap.projects.first { $0.name == "checkout-redesign" }?.health == "At risk"
          && snap.projects.first { $0.name == "checkout-redesign" }?.topic == "payments", "project from PROJECT.md: health, topic")
    check(snap.projects.first { $0.isHome == true }?.name == "home" && folders["home"] != nil, "Home from HOME.md")
    check(snap.groups.first?.sessions.last == "PRD v2 edits" && snap.groups.first?.sessions.first?.hasPrefix("Session ") == true,
          "groups resolve ids to names; a never-used session shows its start time (DL-90)")
    check(snap.counts.needsYou == 1 && snap.counts.idle == 1, "counts")
    let quiet = Beacon(pid: 1, sessionId: "aaaa-filed", cwd: proj.path, name: nil, status: "idle", waitingFor: nil,
                       statusUpdatedAt: nil, entrypoint: "cli", kind: nil)
    check(LiveSnapshot.build(noHistory(lw), beacons: [live, quiet]).0.counts.idle == 0, "a running, quiet session isn't counted as resumable")
    // `/cd`: a filed session running in another project's folder is listed there and moves (F-32).
    let other = lw.appending(path: "growth/onboarding")
    try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
    try "---\ngoal: x\n---\n".write(to: other.appending(path: "PROJECT.md"), atomically: true, encoding: .utf8)
    let moved = Beacon(pid: 1, sessionId: "aaaa-filed", cwd: other.path, name: nil, status: "idle", waitingFor: nil,
                       statusUpdatedAt: nil, entrypoint: "cli", kind: nil)
    let (snap2, _, moves) = LiveSnapshot.build(noHistory(lw), beacons: [moved])
    check(snap2.sessions.first { $0.sessionId == "aaaa-filed" }?.project == "onboarding"
          && moves.map(\.sessionId) == ["aaaa-filed"] && moves.first?.to.lastPathComponent == "onboarding",
          "a session moved with /cd is listed in its new project, and its entry moves")
    // DL-59, DL-63, DL-64: history in place, folder projects, sticky user moves.
    let scratchFolder = lw.appending(path: "scratch")
    try FileManager.default.createDirectory(at: scratchFolder, withIntermediateDirectories: true)
    try "# notes".write(to: scratchFolder.appending(path: "CLAUDE.md"), atomically: true, encoding: .utf8)
    let fakeT = lw.appending(path: "fake.jsonl")
    try "{}".write(to: fakeT, atomically: true, encoding: .utf8)
    var hctx = noHistory(lw)
    hctx.historyOverride = [(id: "hist-in-project", transcript: fakeT, cwd: proj.path),
                            (id: "hist-orphan", transcript: fakeT, cwd: scratchFolder.path)]
    let (hs, hfolders, _) = LiveSnapshot.build(hctx, beacons: [])
    check(hs.sessions.first { $0.sessionId == "hist-in-project" }?.project == "checkout-redesign", "a past session in a project's folder is listed there (DL-59)")
    let orphanProject = hs.projects.first { $0.name == "scratch" }
    check(orphanProject?.isFolderOnly == true && orphanProject?.hasClaudeMD == true && hfolders["scratch"] != nil
          && hs.sessions.first { $0.sessionId == "hist-orphan" }?.project == "scratch", "a session from a non-project folder makes a folder entry, CLAUDE.md noted (DL-63)")
    check(hs.projectFiles["scratch"] == ["CLAUDE.md"], "a folder entry's tree lists its files, as a project's does (DL-63, F-88)")
    var moveIdx = SessionIndex.load(project: proj)
    moveIdx.sessions.append(.init(sessionId: "hist-orphan", provenance: "moved-by-user:scratch"))
    try moveIdx.save(project: proj)
    let (ms, _, mmoves) = LiveSnapshot.build(hctx, beacons: [])
    check(ms.sessions.first { $0.sessionId == "hist-orphan" }?.project == "checkout-redesign" && !mmoves.contains { $0.sessionId == "hist-orphan" }
          && ms.sessions(inProject: "scratch").isEmpty, "a session the user moved stays where it was filed (DL-64)")
    check(ms.projects.first { $0.name == "scratch" }?.hasClaudeMD == true, "its folder stays listed: it has a CLAUDE.md (DL-103)")
    try? FileManager.default.removeItem(at: lw)

    print("hooks")
    let ev = FileManager.default.temporaryDirectory.appending(path: "duo-ev-\(UUID().uuidString)")
    let settings = try HookEvents.settingsFile(for: "s1", in: ev)
    let sj = try JSONSerialization.jsonObject(with: Data(contentsOf: settings)) as? [String: Any]
    let stopCmd = (((sj?["hooks"] as? [String: Any])?["Stop"] as? [[String: Any]])?.first?["hooks"] as? [[String: Any]])?.first?["command"] as? String
    check(stopCmd != nil, "settings file has a Stop hook command")
    let allowed = ((sj?["sandbox"] as? [String: Any])?["network"] as? [String: Any])?["allowUnixSockets"] as? [String]
    check(allowed == [ControlEndpoint.defaultSocket], "settings allow exactly Duo's socket in the sandbox (DL-43)")
    // Run the real hook command the way Claude does: payload on stdin, pretty-printed.
    func fire(_ payload: String) {
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/bin/sh"); p.arguments = ["-c", stopCmd!]
        let pin = Pipe(); p.standardInput = pin; let out = Pipe(); p.standardOutput = out
        try? p.run(); pin.fileHandleForWriting.write(Data(payload.utf8)); try? pin.fileHandleForWriting.close(); p.waitUntilExit()
        check(out.fileHandleForReading.readDataToEndOfFile().isEmpty, "hook prints nothing (never answers a prompt)")
    }
    fire("{\n  \"hook_event_name\": \"UserPromptSubmit\", \"prompt\": \"hi\"\n}")
    fire(#"{"hook_event_name":"PermissionRequest","tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"Move saved cards into scope?","options":[{"label":"Yes"},{"label":"No"}]}]}}"#)
    var events = HookEvents.read("s1", in: ev)
    check(events.count == 2 && events[0].name == "UserPromptSubmit", "events append one per line, pretty payloads folded")
    var sum = HookEvents.summarize(events)
    check(sum?.kind == .pending && sum?.question == "Move saved cards into scope?" && sum?.options == ["Yes", "No"], "pending AskUserQuestion carries the verbatim question")
    fire(#"{"hook_event_name":"PostToolUse","tool_name":"AskUserQuestion"}"#)
    fire(###"{"hook_event_name":"Stop","last_assistant_message":"## Drafted the PRD section\nDetails…"}"###)
    events = HookEvents.read("s1", in: ev)
    sum = HookEvents.summarize(events)
    check(sum?.kind == .stopped && sum?.reason == .blocked, "answered, then the turn ended")
    func b(_ status: String, _ w: String? = nil) -> Beacon {
        Beacon(pid: 1, sessionId: "s1", cwd: "/", name: nil, status: status, waitingFor: w, statusUpdatedAt: 1000, entrypoint: nil, kind: nil)
    }
    fire(#"{"hook_event_name":"SessionStart","source":"resume"}"#)
    check(HookEvents.summarize(HookEvents.read("s1", in: ev))?.kind == .stopped, "resuming keeps the finished turn")
    let r = Attention.live(beacon: b("idle"), hooks: sum, seenAt: nil)
    check(r.state == .readyForReview && r.summary == "Drafted the PRD section", "finished turn: ready for review, headline as summary")
    check(Attention.live(beacon: b("idle"), hooks: sum, seenAt: sum!.at + 1).state == .idle, "seen after the turn: idle")
    check(HookEvents.headline("You prefer **red**.") == "You prefer red.", "summary drops bold markers")
    check(Attention.live(beacon: b("busy"), hooks: sum, seenAt: nil).state == .working, "busy beats hooks")
    check(Attention.live(beacon: b("waiting", "permission prompt"), hooks: nil, seenAt: nil).question == "Waiting for permission", "waiting without hooks: generic line")
    fire(#"{"hook_event_name":"UserPromptSubmit","prompt":"next"}"#)
    fire(#"{"hook_event_name":"Stop","last_assistant_message":"Done.\n\nShould I also update the FAQ?"}"#)
    let asked = Attention.live(beacon: b("idle"), hooks: HookEvents.summarize(HookEvents.read("s1", in: ev)), seenAt: nil)
    check(asked.state == .needsYou && asked.question == "Should I also update the FAQ?", "turn ending in a question: needs you, last paragraph")
    fire(#"{"hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{"command":"git push"}}"#)
    check(HookEvents.summarize(HookEvents.read("s1", in: ev))?.question == "Allow `git push`?", "permission prompt names the command")
    fire(#"{"hook_event_name":"PermissionRequest","tool_name":"Write","tool_input":{"file_path":"/x/refunds-note.md","content":"…"}}"#)
    check(HookEvents.summarize(HookEvents.read("s1", in: ev))?.question == "Allow Write to refunds-note.md?", "file permission names the file")
    fire(#"{"session_id":"s2-cleared","hook_event_name":"UserPromptSubmit","tool_input":{"note":"{\"session_id\": \"decoy\"}"}}"#)
    check(HookEvents.read("s2-cleared", in: ev).count == 1 && HookEvents.read("decoy", in: ev).isEmpty,
          "events follow the payload's session_id (/clear), first key only")
    // C-27: hooks fire together. 40 concurrent events of ~1 KB each must land as 40 whole lines.
    let stressPad = String(repeating: "x", count: 1100)
    DispatchQueue.concurrentPerform(iterations: 40) { n in
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/bin/sh"); p.arguments = ["-c", stopCmd!]
        let pin = Pipe(); p.standardInput = pin
        try? p.run()
        pin.fileHandleForWriting.write(Data(#"{"session_id":"stress","hook_event_name":"Stop","last_assistant_message":"\#(n) \#(stressPad)"}"#.utf8))
        try? pin.fileHandleForWriting.close(); p.waitUntilExit()
    }
    let stressLines = (try? String(contentsOf: HookEvents.file(for: "stress", in: ev), encoding: .utf8))?.split(separator: "\n") ?? []
    check(stressLines.count == 40 && HookEvents.read("stress", in: ev).count == 40
          && Set(HookEvents.read("stress", in: ev).compactMap { $0.lastMessage?.split(separator: " ").first }).count == 40,
          "40 concurrent ~1 KB hook events: 40 lines, every one parses (one write each, C-27)")
    let store = TerminalStore()
    _ = store.session("old-id", command: .shell, cwd: NSTemporaryDirectory())
    store.rekey("old-id", to: "new-id")
    check(store.existing("old-id") == nil && store.existing("new-id")?.key == "new-id", "terminal re-keys to the new session id")
    store.terminateAll()
    try? FileManager.default.removeItem(at: ev)

    print("titles")
    func rec(_ json: String) -> [String: Any] { try! JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any] }
    let prompt = rec(#"{"type":"user","message":{"role":"user","content":"<system-reminder>ignore me</system-reminder>  Draft the   refunds FAQ for support"}}"#)
    let meta = rec(#"{"type":"user","isMeta":true,"message":{"content":"Caveat: local commands"}}"#)
    let slash = rec(#"{"type":"user","message":{"content":"<command-name>/review</command-name><command-args></command-args>"}}"#)
    let ai = rec(#"{"type":"ai-title","aiTitle":"Refunds FAQ draft"}"#)
    let custom = rec(#"{"type":"custom-title","customTitle":"FAQ v2"}"#)
    check(SessionTitles.title(head: [meta, prompt], tail: []) == "“Draft the refunds FAQ for support”", "first prompt in quotes, wrapper tags stripped, meta skipped (DL-90)")
    check(SessionTitles.title(head: [slash, prompt], tail: []) == "/review", "slash command beats the prompt")
    check(SessionTitles.title(head: [prompt, ai], tail: []) == "Refunds FAQ draft", "AI title beats the prompt")
    check(SessionTitles.title(head: [prompt, ai], tail: [custom]) == "FAQ v2", "custom title beats all")
    check(SessionTitles.clean(String(repeating: "word ", count: 30))?.hasSuffix("word…") == true, "long prompts shorten on a word")
    let tdir = FileManager.default.temporaryDirectory.appending(path: "duo-t-\(UUID().uuidString).jsonl")
    let big = String(repeating: #"{"type":"assistant","message":{"content":"x"}}"# + "\n", count: 9000)
    try (#"{"type":"user","message":{"content":"Plan the launch"}}"# + "\n" + big + #"{"type":"ai-title","aiTitle":"Launch plan"}"# + "\n").write(to: tdir, atomically: true, encoding: .utf8)
    check(SessionTitles.title(transcript: tdir) == "Launch plan", "bounded head + tail read finds a late AI title")
    try? FileManager.default.removeItem(at: tdir)

    if let bench = ProcessInfo.processInfo.environment["DUO_BENCH"] {
        let root = URL(fileURLWithPath: bench)
        let beacons = Beacon.readAll()
        var times: [Double] = []
        for _ in 0..<5 {
            let t0 = Date()
            let (snap, _, _) = LiveSnapshot.build(.init(root: root, events: DuoPaths.events), beacons: beacons)
            times.append(Date().timeIntervalSince(t0) * 1000)
            if times.count == 1 { print("bench: \(snap.projects.count) projects, \(snap.sessions.count) sessions, \(beacons.count) beacons") }
        }
        let t0 = Date(); _ = Beacon.readAll(); let tb = Date().timeIntervalSince(t0) * 1000
        print("bench: build ms \(times.map { String(format: "%.1f", $0) }), beacons ms \(String(format: "%.1f", tb))")
    }

    print("fork lineage")
    func msg(_ uuid: String, _ parent: String?, _ ts: String, _ type: String = "user") -> [String: Any] {
        var d: [String: Any] = ["uuid": uuid, "timestamp": ts, "type": type]
        if let parent { d["parentUuid"] = parent }
        return d
    }
    // A: u1 → a1 → u2 → a2. B forks A after a1. C forks A after a2. D forks B.
    // Each file starts with a queue record stamped at the session's own start (as Claude writes).
    func start(_ ts: String) -> [String: Any] { ["type": "queue-operation", "timestamp": ts] }
    let msgsA = [msg("u1", nil, "t01"), msg("a1", "u1", "t02", "assistant"), msg("u2", "a1", "t03"), msg("a2", "u2", "t04", "assistant")]
    let A = [start("t00")] + msgsA
    let B = [start("t05")] + Array(msgsA.prefix(2)) + [msg("b1", "a1", "t05"), msg("b2", "b1", "t06", "assistant")]
    let C = [start("t07")] + msgsA + [msg("c1", "a2", "t07")]
    let D = [start("t08")] + Array(B.dropFirst()) + [msg("d1", "b2", "t08")]
    let recs = ["A": A, "B": B, "C": C, "D": D]
    let infos = recs.map { ForkLineage.info(sessionId: $0.key, records: $0.value) }
    check(Set(infos.map(\.root)) == ["u1"], "a thread shares its first user uuid")
    let parents = ForkLineage.parents(infos, records: recs)
    check(parents == ["B": "A", "C": "A", "D": "B"], "parents from fork points, including a fork of a fork")

    if let dir = ProcessInfo.processInfo.environment["DUO_LINEAGE"] {
        let files = (try? FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: dir), includingPropertiesForKeys: nil)) ?? []
        var recs: [String: [[String: Any]]] = [:]
        for f in files where f.pathExtension == "jsonl" {
            recs[String(f.deletingPathExtension().lastPathComponent.prefix(8))] = (try? String(contentsOf: f, encoding: .utf8))?
                .split(separator: "\n").compactMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] } ?? []
        }
        let infos = recs.map { ForkLineage.info(sessionId: $0.key, records: $0.value) }
        print("lineage: roots \(Set(infos.compactMap(\.root)).count), parents \(ForkLineage.parents(infos, records: recs))")
    }

    print("search: pieces")
    check(GitIgnore_ignored("build/out.txt", rules: "build/\n*.log\n!keep.log\n/root-only.md\ndocs/**/draft*.md"), "gitignore: directory pattern")
    check(GitIgnore_ignored("a/b/x.txt", rules: "*.txt") && !GitIgnore_ignored("keep.txt", rules: "*.txt\n!keep.txt"), "gitignore: glob and negation")
    check(GitIgnore_ignored("docs/a/b/draft-1.md", rules: "docs/**/draft*.md") && !GitIgnore_ignored("other/draft.md", rules: "/draft.md"), "gitignore: ** and anchored")
    check(Secrets.isDenied("/p/.env.local") && Secrets.isDenied("/p/id_ed25519") && Secrets.isDenied("/p/cert.pem") && !Secrets.isDenied("/p/notes.md"), "secret files denied")
    let redacted = Secrets.redact("key AKIAABCDEFGHIJKLMNOP and sk-ant-api03-abcdefghijklmnopqrstuvwxyz0123 and ghp_abcdefghijklmnopqrstuvwxyz0123456789 password: hunter2hunter2")
    check(!redacted.contains("AKIA") && !redacted.contains("sk-ant") && !redacted.contains("ghp_") && !redacted.contains("hunter2"), "secrets redacted before storing")
    check(SearchIndex.literal(in: "\"exponential backoff\"") == "exponential backoff" && SearchIndex.literal(in: "retry_request") == "retry_request"
          && SearchIndex.literal(in: "camelCaseName") == "camelCaseName" && SearchIndex.literal(in: "why are tides") == nil, "exact-match detection")
    let fts = SearchIndex.ftsQuery("retry OR backoff* NEAR(x) -y", exact: false) ?? ""
    check(fts.components(separatedBy: " OR ").allSatisfy { $0.hasPrefix("\"") && $0.hasSuffix("\"") }, "every FTS term is quoted, so query syntax can't break it")

    // Golden set (SRCH § 12, the POC's), through Duo's own chunker and index, when the model is here.
    let pkg = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "Spikes/S13CoreML/out/bge-small-fp16.mlpackage")
    let vocabURL = pkg.deletingLastPathComponent().deletingLastPathComponent().appending(path: "hf/bge-small/vocab.txt")
    let poc = FileManager.default.homeDirectoryForCurrentUser.appending(path: "repos/smol-sim-search/tests/fixtures")
    if FileManager.default.fileExists(atPath: pkg.path), FileManager.default.fileExists(atPath: poc.path) {
        print("search: golden set (POC fixtures)")
        let scratch = FileManager.default.temporaryDirectory.appending(path: "duo-search-\(UUID().uuidString)")
        setenv("DUO_SEARCH_ROOT", scratch.path, 1)
        SearchSetup.registerExtractors()
        let proj = scratch.appending(path: "work/fx")
        try FileManager.default.createDirectory(at: proj.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: poc, to: proj)
        let t0 = Date()
        let compiled: URL = try blocking { try await Embedder.install(package: pkg, vocab: vocabURL) }
        let indexer = try Embedder(modelAt: compiled, vocab: SearchPaths.vocab, use: .indexing)
        let index = try SearchIndex(readOnly: false)
        let stats: IndexStats = try blocking { try await index.indexProject("fx", root: proj, embedder: indexer) }
        print("  indexed \(stats.files) files, \(stats.chunks) chunks in \(Int(Date().timeIntervalSince(t0) * 1000)) ms")
        let reader = try SearchIndex(readOnly: true)
        let queryEmbedder = try Embedder(use: .query)
        let golden = [("why are there two high tides every day", "docs/tides.md"),
                      ("feeding a sourdough starter with flour and water", "docs/sourdough.md"),
                      ("horizontal pod autoscaler adds replicas", "docs/kubernetes.md"),
                      ("retry a request with exponential backoff", "code/http_retry.py"),
                      ("customer credit card charged twice", "data/tickets.jsonl"),
                      ("magma erupts from a volcano", "papers/volcanoes.pdf"),
                      ("growing tomato seedlings in sunlight", "notes/garden.txt")]
        var top1 = 0
        for (q, want) in golden {
            let hits = try reader.search(SearchQuery(text: q), embedder: queryEmbedder)
            if hits.first?.path.hasSuffix(want) == true { top1 += 1 } else { print("    \(q) → \(hits.first?.title ?? "-")") }
        }
        check(top1 == golden.count, "golden top-1 \(top1)/\(golden.count) through Duo's index")
        // A small, unrelated file in the current project mustn't outrank the strong match (FR-7.4.3).
        try "---\ngoal: \"Lift day-7 activation to 40%\"\n---\n# onboarding\n".write(to: scratch.appending(path: "work/onb/PROJECT.md").creatingParent(), atomically: true, encoding: .utf8)
        _ = try blocking { try await index.indexProject("onb", root: scratch.appending(path: "work/onb"), embedder: indexer) }
        var boosted = SearchQuery(text: "why are there two high tides every day"); boosted.currentProject = "onb"
        check(try reader.search(boosted, embedder: queryEmbedder).first?.path.hasSuffix("docs/tides.md") == true,
              "the current-project boost doesn't crowd out a strong match elsewhere")
        let again: IndexStats = try blocking { try await index.indexProject("fx", root: proj, embedder: indexer) }
        check(again.changed == 0 && again.embedded == 0, "re-index with nothing changed embeds nothing")
        try FileManager.default.moveItem(at: proj.appending(path: "docs/tides.md"), to: proj.appending(path: "notes/tides-moved.md"))
        let moved: IndexStats = try blocking { try await index.indexProject("fx", root: proj, embedder: indexer) }
        check(moved.changed == 1 && moved.removed == 1 && moved.embedded == 0, "a moved file reuses its vectors (FR-7.3.5)")
        var q = SearchQuery(text: "exponential backoff"); q.exactOnly = true
        let ex = try reader.search(q, embedder: nil)
        check(!ex.isEmpty && ex.allSatisfy { $0.matched.contains("exact") }, "exact-only mode returns literal matches only")
        var sim = SearchQuery(text: ""); sim.similarTo = proj.appending(path: "notes/moon-notes.md").resolvingSymlinksInPath().path
        let similar = try reader.search(sim, embedder: nil)
        check(similar.first?.path.hasSuffix("tides-moved.md") == true && !similar.contains { $0.path.hasSuffix("moon-notes.md") },
              "find similar: the copied article's source comes first, the item itself is left out")
        // Same passage in two files: shown once, with the other place listed (FR-7.4.5).
        try FileManager.default.copyItem(at: proj.appending(path: "docs/sourdough.md"), to: proj.appending(path: "notes/sourdough-copy.md"))
        _ = try blocking { try await index.indexProject("fx", root: proj, embedder: indexer) }
        let dup = try reader.search(SearchQuery(text: "feeding a sourdough starter with flour and water"), embedder: queryEmbedder)
        check(dup.filter { $0.path.contains("sourdough") }.count == 1 && dup.first?.alsoIn.count == 1, "identical content shown once, other place listed")
        let cov = try reader.coverage()
        check(cov.first?.complete == true && (cov.first?.known ?? 0) >= stats.files, "coverage reported")
        // Sessions (SRCH L7, FR-7.1.3-5, L17): conversation text only, by turn, attributed by cwd.
        let claudeProjects = scratch.appending(path: "claude-projects")
        let bucket = claudeProjects.appending(path: "-work-fx")
        try FileManager.default.createDirectory(at: bucket, withIntermediateDirectories: true)
        let lines = [
            #"{"type":"user","cwd":"\#(proj.path)","message":{"role":"user","content":"Why do spring tides happen at new moon?"}}"#,
            #"{"type":"assistant","message":{"content":[{"type":"thinking","thinking":"SECRET THOUGHT"},{"type":"text","text":"Because the Sun and Moon line up and their pulls add."}]}}"#,
            #"{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"grep TOOLCALL"}}]}}"#,
            #"{"type":"user","message":{"content":[{"type":"tool_result","content":"TOOLOUTPUT"}]}}"#,
            #"{"type":"user","message":{"content":"Now draft the quarterly pricing readout outline."}}"#,
            #"{"type":"assistant","message":{"content":[{"type":"text","text":"Outline: goals, results, decision."}]}}"#,
            #"{"type":"ai-title","aiTitle":"Tides and pricing"}"#, "{not json",
        ]
        try lines.joined(separator: "\n").write(to: bucket.appending(path: "11111111-aaaa.jsonl"), atomically: true, encoding: .utf8)
        try #"{"type":"user","cwd":"/elsewhere","message":{"content":"Unrelated chat about lunch"}}"#.write(to: bucket.appending(path: "22222222-bbbb.jsonl"), atomically: true, encoding: .utf8)
        let ss: IndexStats = try blocking { try await index.indexSessions(projects: ["fx": proj], claudeProjects: claudeProjects, embedder: indexer) }
        check(ss.changed == 2, "two transcripts indexed")
        var sq = SearchQuery(text: "why spring tides at new moon"); sq.kinds = ["session"]
        let sh = try reader.search(sq, embedder: queryEmbedder)
        check(sh.first?.title == "Tides and pricing" && sh.first?.project == "fx" && sh.first?.locator == "turn 1", "session found by meaning, titled, attributed, at its turn")
        var pq = SearchQuery(text: "quarterly pricing readout outline"); pq.kinds = ["session"]
        check(try reader.search(pq, embedder: queryEmbedder).first?.locator == "turn 2", "second turn located")
        for leak in ["SECRET THOUGHT", "TOOLCALL", "TOOLOUTPUT"] {
            var lq = SearchQuery(text: leak); lq.exactOnly = true
            check(try reader.search(lq, embedder: nil).isEmpty, "\(leak.lowercased()) not indexed (conversation text only)")
        }
        var uq = SearchQuery(text: "lunch"); uq.kinds = ["session"]
        check(try reader.search(uq, embedder: queryEmbedder).first?.project == SearchIndex.unfiled, "a session outside every project is Unfiled")
        try FileManager.default.removeItem(at: bucket.appending(path: "22222222-bbbb.jsonl"))
        let swept: IndexStats = try blocking { try await index.indexSessions(projects: ["fx": proj], claudeProjects: claudeProjects, embedder: indexer) }
        // DL-49: a purged session kept by Duo's archive stays findable, marked archived.
        let archivedCopy = scratch.appending(path: "archive/33333333-cccc.jsonl")
        try FileManager.default.createDirectory(at: archivedCopy.deletingLastPathComponent(), withIntermediateDirectories: true)
        try #"{"type":"user","cwd":"\#(proj.path)","message":{"content":"Draft the lighthouse keeper rota for winter"}}"#.write(to: archivedCopy, atomically: true, encoding: .utf8)
        _ = try blocking { try await index.indexSessions(projects: ["fx": proj], claudeProjects: claudeProjects, embedder: indexer,
                                                         archived: [(id: "33333333-cccc", copy: archivedCopy, cwd: proj.path)]) }
        var aq = SearchQuery(text: "lighthouse keeper rota"); aq.kinds = ["session"]
        let ah = try reader.search(aq, embedder: queryEmbedder).first
        check(ah?.archived == true && ah?.project == "fx", "a purged session is found from Duo's archive, marked archived (DL-49)")
        let afterSweep = try reader.search(uq, embedder: nil)
        check(swept.removed == 1 && afterSweep.allSatisfy { $0.project != SearchIndex.unfiled }, "a deleted transcript leaves the index (L17)")
        unsetenv("DUO_SEARCH_ROOT")
        try? FileManager.default.removeItem(at: scratch)
    }

    print("legacy duo (DL-39)")
    let lg = FileManager.default.temporaryDirectory.appending(path: "legacy-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: lg.appending(path: "skills/duo"), withIntermediateDirectories: true)
    let lgSettings = #"{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"a","_duo":"managed-v3"}]},{"hooks":[{"type":"command","command":"mine"}]}]},"model":"opus"}"#
    let lgMD = "# Mine\n\nKeep this.\n\n<!-- duo:managed-v3 -->\nDuo\n<!-- duo:end -->\n\nAnd this.\n"
    try lgSettings.write(to: lg.appending(path: "settings.json"), atomically: true, encoding: .utf8)
    try lgMD.write(to: lg.appending(path: "CLAUDE.md"), atomically: true, encoding: .utf8)
    check(LegacyDuo.detect(in: lg).count == 3, "detects legacy hooks, block and skill")
    let lgBackup = try LegacyDuo.disable(in: lg, backupRoot: lg.appending(path: "backups"))
    let mdAfter = try String(contentsOf: lg.appending(path: "CLAUDE.md"), encoding: .utf8)
    let setAfter = try String(contentsOf: lg.appending(path: "settings.json"), encoding: .utf8)
    check(LegacyDuo.detect(in: lg).isEmpty && mdAfter == "# Mine\n\nKeep this.\n\nAnd this.\n" && setAfter.contains("mine") && setAfter.contains("opus"),
          "disable removes only legacy's parts")
    try LegacyDuo.restore(from: lgBackup)
    check(try String(contentsOf: lg.appending(path: "CLAUDE.md"), encoding: .utf8) == lgMD
          && (try String(contentsOf: lg.appending(path: "settings.json"), encoding: .utf8)) == lgSettings
          && FileManager.default.fileExists(atPath: lg.appending(path: "skills/duo").path), "restore puts everything back exactly")
    try? FileManager.default.removeItem(at: lg)

    print("retention (DL-44, DL-47)")
    let ar = FileManager.default.temporaryDirectory.appending(path: "archive-\(UUID().uuidString)")
    setenv("DUO_ARCHIVE_ROOT", ar.appending(path: "archive").path, 1)
    let bucketDir = ar.appending(path: "claude/projects/-work-p")
    try FileManager.default.createDirectory(at: bucketDir.appending(path: "s-old/tool-results"), withIntermediateDirectories: true)
    let oldT = bucketDir.appending(path: "s-old.jsonl"), freshT = bucketDir.appending(path: "s-new.jsonl")
    try #"{"type":"user","cwd":"/work/p","message":{"content":"Plan the readout"}}"#.write(to: oldT, atomically: true, encoding: .utf8)
    try #"{"type":"user","cwd":"/work/p","message":{"content":"Fresh one"}}"#.write(to: freshT, atomically: true, encoding: .utf8)
    try "big output".write(to: bucketDir.appending(path: "s-old/tool-results/r1.txt"), atomically: true, encoding: .utf8)
    let keepNow = Date()
    for u in [oldT, bucketDir.appending(path: "s-old/tool-results/r1.txt"), bucketDir.appending(path: "s-old/tool-results"), bucketDir.appending(path: "s-old")] {
        try FileManager.default.setAttributes([.modificationDate: keepNow.addingTimeInterval(-25 * 86_400)], ofItemAtPath: u.path)
    }
    check(try SessionArchive.sync([("s-old", oldT), ("s-new", freshT)]) == 2 && FileManager.default.fileExists(atPath: SessionArchive.copyURL("s-old").path), "listed transcripts are copied to Duo's archive")
    check(try SessionArchive.sync([("s-old", oldT), ("s-new", freshT)]) == 0, "unchanged transcripts aren't copied again")
    let refreshed = SessionArchive.keepAlive([oldT, freshT], periodDays: 30, now: keepNow)
    let oldMod = try FileManager.default.attributesOfItem(atPath: oldT.path)[.modificationDate] as! Date
    let freshMod = try FileManager.default.attributesOfItem(atPath: freshT.path)[.modificationDate] as! Date
    check(refreshed == 4 && abs(oldMod.timeIntervalSince(keepNow.addingTimeInterval(-15 * 86_400))) < 2 && keepNow.timeIntervalSince(freshMod) < 60,
          "keep-alive moves a quiet session to half the period ago (with its sidecars), leaves fresh ones alone")
    check(SessionArchive.carryOnPrompt("s-old")?.contains(SessionArchive.copyURL("s-old").path) == true, "carry-on prompt points at the archived transcript")
    check(FileManager.default.fileExists(atPath: SessionArchive.sidecarURL("s-old").appending(path: "tool-results/r1.txt").path),
          "the sidecar folder is archived too (DL-48)")
    unsetenv("DUO_ARCHIVE_ROOT")
    try? FileManager.default.removeItem(at: ar)

    print("threads and groups (DL-24, Phase G)")
    do {
        check(LiveSnapshot.threads(["PRD v2 edits", "quick q about tax rules", "Interview synth"], in: f.sessions)
              == [["Interview synth", "PRD v2 edits"], ["quick q about tax rules"]], "a group's threads: fork families, parent first")
        let dir = FileManager.default.temporaryDirectory.appending(path: "duo-threads-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        func write(_ name: String, _ lines: [String]) -> URL {
            let u = dir.appending(path: name + ".jsonl"); try? (lines.joined(separator: "\n") + "\n").write(to: u, atomically: true, encoding: .utf8); return u
        }
        func rec(_ type: String, _ uuid: String, _ parent: String?, _ t: String) -> String {
            #"{"type":"\#(type)","uuid":"\#(uuid)","parentUuid":\#(parent.map { "\"\($0)\"" } ?? "null"),"timestamp":"\#(t)"}"#
        }
        let parent = write("p", [#"{"type":"mode","timestamp":"2026-10-04T10:00:00Z"}"#, rec("user", "u1", nil, "2026-10-04T10:00:01Z"),
                                 rec("assistant", "u2", "u1", "2026-10-04T10:00:02Z"), rec("user", "u3", "u2", "2026-10-04T10:00:03Z")])
        let fork = write("f", [#"{"type":"mode","timestamp":"2026-10-04T11:00:00Z"}"#, rec("user", "u1", nil, "2026-10-04T10:00:01Z"),
                               rec("assistant", "u2", "u1", "2026-10-04T10:00:02Z"), rec("user", "u9", "u2", "2026-10-04T11:00:05Z")])
        let other = write("o", [rec("user", "x1", nil, "2026-10-04T09:00:00Z")])
        let cache = ThreadCache()
        let pairs: [(id: String, transcript: URL)] = [("p", parent), ("f", fork), ("o", other)]
        check(cache.parents(pairs) == ["f": "p"], "a fork's parent from shared uuids and its fork point (S11)")
        let h = try FileHandle(forWritingTo: fork); try h.seekToEnd(); try h.write(contentsOf: Data((rec("assistant", "u10", "u9", "2026-10-04T11:00:06Z") + "\n").utf8)); try h.close()
        check(cache.parents(pairs) == ["f": "p"], "a growing transcript is read on from where it stopped")
        try? FileManager.default.removeItem(at: dir)
    }

    print("inventory and evidence (CONS FR-7.1, 7.8, 7.10; DL-41)")
    do {
        let h = FileManager.default.homeDirectoryForCurrentUser.path
        check(Inventory.candidateHome(["\(h)/w/a/x.md", "\(h)/w/a/b/y.md"], cwd: h) == "\(h)/w/a", "candidate home: the deepest folder holding every edit")
        check(Inventory.candidateHome(["\(h)/w/a/x.md", "\(h)/v/y.md"], cwd: h) == nil, "disjoint edits under the cwd: no home")
        check(Inventory.candidateHome(["/tmp/x", "\(h)/.claude/projects/p", "\(h)/w/a/x.md"], cwd: h) == "\(h)/w/a", "system, temp and ~/.claude paths don't count")
        check(Inventory.candidateHome([], cwd: h) == nil, "nothing edited: no home")
        let dir = FileManager.default.temporaryDirectory.appending(path: "duo-inv-\(UUID().uuidString)")
        let claude = dir.appending(path: "claude")
        func bucket(_ name: String, _ id: String, _ lines: [String]) throws -> URL {
            let d = claude.appending(path: "projects/\(name)"); try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
            let u = d.appending(path: "\(id).jsonl"); try (lines.joined(separator: "\n") + "\n").write(to: u, atomically: true, encoding: .utf8); return u
        }
        let t = try bucket("-x-junk", "s1", [
            #"{"type":"user","cwd":"/x/junk","uuid":"a","timestamp":"2026-09-01T10:00:00.000Z","message":{"content":"go"}}"#,
            #"{"type":"assistant","timestamp":"2026-09-01T10:01:00.000Z","message":{"content":[{"type":"tool_use","name":"Edit","input":{"file_path":"/x/w/a/one.md"}},{"type":"tool_use","name":"Read","input":{"file_path":"/x/w/read-only.md"}}]}}"#,
            #"{"type":"file-history-snapshot","snapshot":{"trackedFileBackups":{"/x/w/a/b/two.md":{}}}}"#,
            #"{"type":"user","timestamp":"2026-09-01T10:02:00.000Z","toolUseResult":{"type":"create","filePath":"/x/w/a/three.md"}}"#])
        let e = Inventory.evidence(t, cwd: "/x/junk")
        check(Set(e.edited) == ["/x/w/a/one.md", "/x/w/a/b/two.md", "/x/w/a/three.md"], "edits from the editing tools, file-history and results; reads don't count")
        check(e.candidateHome == "/x/w/a", "that session's candidate home")
        _ = try bucket("-x-junk", "s2", [#"{"type":"user","cwd":"/x/other","uuid":"b","timestamp":"2026-09-05T10:00:00.000Z","message":{"content":"go"}}"#])
        _ = try bucket("-x-copy", "s1", [#"{"type":"user","cwd":"/x/junk","uuid":"a","timestamp":"2026-09-01T10:00:00.000Z","message":{"content":"go"}}"#])
        let r = Inventory.build(claudeDir: claude, now: ISO8601DateFormatter().date(from: "2026-10-04T00:00:00Z")!, periodDays: 30)
        check(r.buckets.first { $0.folder == "-x-junk" }?.collision == true, "a folder holding sessions from two cwds is a collision (FR-7.8.2)")
        check(r.duplicates["s1"]?.count == 2, "the same id in two folders is a duplicate (FR-7.8.1)")
        check(r.buckets.first { $0.folder == "-x-junk" }?.cwdMissing == true, "folders whose cwds are all gone are flagged")
        func ev(_ id: String, _ from: String, _ to: String) -> Inventory.Evidence {
            let f = ISO8601DateFormatter()
            return .init(sessionId: id, title: nil, first: f.date(from: from), last: f.date(from: to), edited: [], candidateHome: nil, partial: false)
        }
        let c = Inventory.clusters([ev("a", "2026-09-01T00:00:00Z", "2026-09-01T02:00:00Z"), ev("b", "2026-09-03T02:00:00Z", "2026-09-03T03:00:00Z"),
                                    ev("c", "2026-09-05T03:00:01Z", "2026-09-05T04:00:00Z")])
        check(c.map { $0.map(\.sessionId) } == [["a", "b"], ["c"]], "date clusters split at a 48-hour gap (FR-7.10.4)")
        try? FileManager.default.removeItem(at: dir)
    }

    print("migrator (CONS §6.3, §7.4, §7.5; DL-41) on a throwaway Claude config")
    do {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appending(path: "duo-mig-\(UUID().uuidString)").resolvingSymlinksInPath()
        let claude = root.appending(path: "claude"), work = root.appending(path: "work")
        let a = work.appending(path: "a").path, b = work.appending(path: "b").path
        try fm.createDirectory(atPath: a + "/sub", withIntermediateDirectories: true)
        try fm.createDirectory(atPath: b, withIntermediateDirectories: true)
        func session(_ id: String, cwd: String) throws -> URL {
            let d = claude.appending(path: "projects/" + ClaudeStorage.encode(cwd)); try fm.createDirectory(at: d, withIntermediateDirectories: true)
            let u = d.appending(path: "\(id).jsonl")
            try (#"{"type":"user","cwd":"\#(cwd)","uuid":"u-\#(id)","sessionId":"\#(id)","message":{"content":"hi"}}"# + "\n").write(to: u, atomically: true, encoding: .utf8)
            try fm.createDirectory(at: d.appending(path: id), withIntermediateDirectories: true)
            try "tool output".write(to: d.appending(path: "\(id)/tool.txt"), atomically: true, encoding: .utf8)
            try fm.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_790_000_000)], ofItemAtPath: u.path)
            return u
        }
        let s1 = try session("s1", cwd: a), original = try Data(contentsOf: s1)
        _ = try session("s2", cwd: a + "/sub")
        let m = Migrator(claudeDir: claude, journalDir: root.appending(path: "migrations"))
        let plan = try m.planRelocate("s1", to: b)
        let done = try m.apply(plan)
        let moved = claude.appending(path: "projects/\(ClaudeStorage.encode(b))/s1.jsonl")
        let text = (try? String(contentsOf: moved, encoding: .utf8)) ?? ""
        check(done.state == .committed && !fm.fileExists(atPath: s1.path) && fm.fileExists(atPath: moved.deletingLastPathComponent().appending(path: "s1/tool.txt").path),
              "relocate moves the transcript and its sidecar folder, as /cd does")
        check(text.hasPrefix(String(decoding: original, as: UTF8.self)) && text.contains(#""relocatedCwd":"\#(b)""#) && text.hasSuffix("}\n"),
              "history untouched; one relocated record appended, last (R1, FR-7.4.3)")
        check((try? fm.attributesOfItem(atPath: moved.path)[.modificationDate] as? Date)?.timeIntervalSince1970 == 1_790_000_000, "the mtime is kept, so Claude's cleanup clock is unchanged")
        try m.undo(done)
        check((try? Data(contentsOf: s1)) == original && !fm.fileExists(atPath: moved.path), "undo puts it back byte for byte")
        check((try? m.planRelocate("s1", to: b, live: ["s1"])) == nil, "a running session is refused")
        _ = try session("s1", cwd: b)   // the same id already in the target
        check((try? m.planRelocate("s1", to: b)) == nil, "a same-id transcript in the target stops the plan (FR-7.4.4)")
        try fm.removeItem(at: claude.appending(path: "projects/\(ClaudeStorage.encode(b))"))
        let dest = work.appending(path: "moved").path
        let move = try m.apply(try m.planFolderMove(a, to: dest))
        let sub2 = claude.appending(path: "projects/\(ClaudeStorage.encode(dest + "/sub"))/s2.jsonl")
        check(move.state == .committed && fm.fileExists(atPath: dest + "/sub") && fm.fileExists(atPath: sub2.path)
              && ((try? String(contentsOf: sub2, encoding: .utf8)) ?? "").contains(#""relocatedCwd":"\#(dest)/sub""#),
              "a folder move renames the folder and relocates every session under it to the mapped path (FR-7.5.4)")
        let bucket = { (p: String) in claude.appending(path: "projects/" + ClaudeStorage.encode(p)).path }
        check(!fm.fileExists(atPath: bucket(a)) && !fm.fileExists(atPath: bucket(a + "/sub")), "the emptied buckets are swept after the move")
        try m.undo(move)
        check(fm.fileExists(atPath: a + "/sub") && !fm.fileExists(atPath: dest) && (try? Data(contentsOf: s1)) == original, "and undo puts the folder and every transcript back")
        check(!fm.fileExists(atPath: bucket(dest)) && !fm.fileExists(atPath: bucket(dest + "/sub")), "and sweeps the buckets the undo emptied")
        // A folder moved outside Duo (DB-8): its sessions follow without moving the folder again.
        let elsewhere = work.appending(path: "elsewhere").path
        try fm.moveItem(atPath: a, toPath: elsewhere)
        let reconnect = try m.apply(try m.planReconnect(a, to: elsewhere))
        let s2there = claude.appending(path: "projects/\(ClaudeStorage.encode(elsewhere + "/sub"))/s2.jsonl")
        check(reconnect.state == .committed && fm.fileExists(atPath: s2there.path) && !fm.fileExists(atPath: s1.path)
              && ((try? String(contentsOf: s2there, encoding: .utf8)) ?? "").contains(#""relocatedCwd":"\#(elsewhere)/sub""#),
              "reconnect moves a moved folder's sessions to where it is now, mapped path by path (DB-8)")
        try m.undo(reconnect)
        try fm.moveItem(atPath: elsewhere, toPath: a)
        check((try? Data(contentsOf: s1)) == original, "and undo puts them back")
        check((try? m.planReconnect(a, to: work.appending(path: "nowhere").path)) == nil, "reconnect needs a folder that's there")
        var stuck = try m.planRelocate("s1", to: b); stuck.state = .applying; try m.save(stuck)
        check((try? m.apply(try m.planRelocate("s2", to: b))) == nil, "an interrupted migration blocks new ones until it's completed or undone (FR-7.8.4)")
        try m.undo(stuck)
        try fm.createDirectory(at: claude.appending(path: "projects/-wrong-name"), withIntermediateDirectories: true)
        try fm.copyItem(at: s1, to: claude.appending(path: "projects/-wrong-name/x.jsonl"))
        check(m.calibrationProblem() != nil && (try? m.apply(try m.planRelocate("s2", to: b))) == nil, "a folder name Duo can't reproduce stops every physical operation (§6.3 5)")
        // Delete (FR-7.6.2): the transcript, sidecar, and Claude's per-session folders; never memory or history.
        try fm.removeItem(at: claude.appending(path: "projects/-wrong-name"))
        // A bucket can rightly hold a session whose first cwd is elsewhere: a fork opens with its parent's
        // records (F-31), a `/cd` keeps the old head cwd. Neither is an encoder change.
        let host = work.appending(path: "host").path, parentDir = claude.appending(path: "projects/" + ClaudeStorage.encode(host))
        try fm.createDirectory(at: parentDir, withIntermediateDirectories: true)
        try ([#"{"type":"user","cwd":"\#(host)/kb","uuid":"u-p","sessionId":"f1"}"#, #"{"type":"user","cwd":"\#(host)","uuid":"u-f","sessionId":"f1"}"#]
            .joined(separator: "\n") + "\n").write(to: parentDir.appending(path: "f1.jsonl"), atomically: true, encoding: .utf8)
        try ([#"{"type":"user","cwd":"\#(host)/kb","sessionId":"c1"}"#, #"{"type":"relocated","relocatedCwd":"\#(host)"}"#]
            .joined(separator: "\n") + "\n").write(to: parentDir.appending(path: "c1.jsonl"), atomically: true, encoding: .utf8)
        check(m.calibrationProblem() == nil, "a bucket holding a fork or a /cd'd session that started in another folder still calibrates")
        try fm.removeItem(at: parentDir)
        let gone = try session("s9", cwd: b)
        let fh = claude.appending(path: "file-history/s9"); try fm.createDirectory(at: fh, withIntermediateDirectories: true)
        let env = claude.appending(path: "session-env/s9"); try fm.createDirectory(at: env, withIntermediateDirectories: true)
        try "keep".write(to: claude.appending(path: "history.jsonl"), atomically: true, encoding: .utf8)
        check((try? m.planDelete("s9", live: ["s9"])) == nil, "a running session can't be deleted")
        let del = try m.apply(try m.planDelete("s9"))
        check(del.state == .committed && !fm.fileExists(atPath: gone.path) && !fm.fileExists(atPath: fh.path) && !fm.fileExists(atPath: env.path)
              && !fm.fileExists(atPath: gone.deletingLastPathComponent().appending(path: "s9").path) && fm.fileExists(atPath: claude.appending(path: "history.jsonl").path),
              "delete removes the transcript, sidecar, file history and environment; history.jsonl stays")
        check((try? m.undo(del)) == nil && del.steps.count == 4, "a delete can't be undone, and its journal lists what went")
        try? fm.removeItem(at: root)
    }

    print("surfaces slice 1 (DB-1 to DB-4)")
    do {
        // Saturday 3 Oct 2026, 12:00: this week began Sunday 27 Sep (or Monday 28, by locale).
        let now = ISO8601DateFormatter().date(from: "2026-10-03T12:00:00Z")!
        func r(_ n: String, _ days: Int) -> IdleRow { IdleRow(id: n, name: n, project: "p", age: "\(days)d", seconds: days * 86_400) }
        let b = AppModel.idleBuckets([r("a", 1), r("b", 9), r("c", 40)], now: now)
        check(b.map(\.label) == ["This week", "Last week", "Earlier"] && b.map { $0.rows.count } == [1, 1, 1], "idle list: this week, last week, then a short tail as Earlier")
        let many = (0..<40).map { r("s\($0)", 15 + $0 * 3) }
        check(AppModel.idleBuckets(many, now: now).dropFirst(0).contains { $0.label == "August" }, "a long tail is grouped by month")
        check(ForegroundCommand.arguments(getpid()).first?.hasSuffix("DuoChecks") == true, "a process's argv, for a shell tab's title (DB-4)")
        check(DuoTerminalPalette.ansi.count == 16 && DuoTerminalPalette.ansiIncreaseContrast.count == 16, "the terminal palette has 16 colours and an Increase Contrast set (DB-2)")
    }

    print("search modal (DL-76, DL-79, DL-80)")
    do {
        func hit(_ path: String, _ kind: String, _ start: Int, archived: Bool = false) -> SearchHit {
            let j = #"{"project":"checkout","kind":"\#(kind)","path":"\#(path)","title":"t","locator":"L\#(start)-\#(start + 2)","startLine":\#(start),"endLine":\#(start + 2),"score":1,"matched":["words"],"snippet":"saved cards","alsoIn":[],"archived":\#(archived)}"#
            return try! JSONDecoder().decode(SearchHit.self, from: Data(j.utf8))
        }
        let rows = AppModel.rows([hit("/x/a.md", "file", 40), hit("/x/b.md", "file", 1), hit("/x/a.md", "file", 71), hit("/x/c.jsonl", "session", 3, archived: true)],
                                 words: "saved cards", includeArchived: false, time: .any)
        check(rows.map(\.path) == ["/x/a.md", "/x/b.md"], "one row per item; archived hidden unless asked")
        check(rows.first?.passages.map(\.location) == ["L40–42", "L71–73"], "later hits become the item's passages, with en dashes")
        check(AppModel.rows([hit("/x/c.jsonl", "session", 3, archived: true)], words: "", includeArchived: true, time: .any).first?.archived == true, "Include archived shows them, labelled")
        check(AppModel.queryWords("where did we land on saved cards") == ["where", "did", "land", "saved", "cards"], "matched words skip short ones")
        check(AppModel.queryWords("\"saved cards\"") == ["saved cards"], "a quoted phrase is one matched word")

        let m = AppModel(fixture: f)
        let names = m.nameMatches("prd")
        check(names.first?.kind == .group && names.first?.title == "PRD v2", "Go to: groups before sessions, by name (DL-80)")
        check(names.allSatisfy(\.goTo) && names.contains { $0.title == "PRD v2 edits" }, "Go to: sessions by name")
        check(m.nameMatches("checkout").first?.kind == .project, "Go to: projects first")

        let s = m.search
        s.items = rows + [SearchItem(id: "s", kind: .session, project: "checkout", title: "PRD v2 edits")]
        s.phase = .results; s.sendTargetName = "Morning triage"
        s.move(1, extend: true)
        check(s.multi == [0, 1] && s.returnLabel == "Send 2 to Claude in Morning triage", "⇧↓ selects several; Return sends them (DL-79 c)")
        var archived = SearchItem(id: "a", kind: .session, project: "refunds", title: "Old"); archived.archived = true
        check(s.actions(for: archived).contains { $0.id == .carryOn }, "archived sessions offer Carry on in a new session (DL-47)")
        check(s.actions(for: rows[0]).first { $0.id == .sendToClaude }?.chord == "⌘D", "Send to Claude is ⌘D (DL-79 e)")
        s.isOpen = true; s.menuOpen = true
        m.searchKey(.escape)
        check(s.isOpen && !s.menuOpen, "Esc closes the menu first (DL-79 h)")
        s.similarTo = rows[0]; s.similarReturnsTo = "saved cards"
        m.searchKey(.escape)
        check(s.isOpen && s.similarTo == nil && s.query == "saved cards", "then leaves find similar for the previous search")
        m.searchKey(.escape)
        check(!s.isOpen, "then closes")
    }

    print("launch options")
    let o = LaunchOptions(arguments: ["Duo", "--state", "flow-zoom-3", "--capture", "/tmp/x.png", "--left", "collapsed"])
    check(o.state == .flowZoom3 && o.capturePath == "/tmp/x.png" && o.collapseLeft && o.capturing, "flags parse")

    print("support folder: scripted runs never use the real one (C-21, F-89)")
    do {
        let none: [String: String] = ["HOME": NSHomeDirectory()]
        let given = ["DUO_SUPPORT_DIR": "/tmp/duo-given"]
        for flag in ["--workspace", "--state", "--capture", "--capture-window", "--then"] {
            check(SupportFolder.choose(arguments: ["Duo", flag, "x"], environment: none) == .temporary, "\(flag) without DUO_SUPPORT_DIR → a temporary folder")
        }
        check(SupportFolder.choose(arguments: ["Duo", "--workspace", "/tmp/ws", "--capture-window", "/tmp/x.png", "--then", "wait"], environment: given) == .given("/tmp/duo-given"), "DUO_SUPPORT_DIR always wins")
        check(SupportFolder.choose(arguments: ["Duo"], environment: given) == .given("/tmp/duo-given"), "DUO_SUPPORT_DIR wins on a plain launch too")
        check(SupportFolder.choose(arguments: ["Duo"], environment: none) == .real, "a plain launch uses the real folder")
        check(SupportFolder.choose(arguments: ["Duo", "-NSDocumentRevisionsDebugMode", "YES"], environment: none) == .real, "AppKit's own flags aren't a scripted run")
        check(SupportFolder.choose(arguments: ["Duo", "--state", "overview"], environment: ["DUO_SUPPORT_DIR": ""]) == .temporary, "an empty DUO_SUPPORT_DIR counts as unset")
        // Every flag LaunchOptions reads marks a scripted run.
        let src = (try? String(contentsOf: repoRoot().appending(path: "Sources/DuoKit/Debug/LaunchOptions.swift"), encoding: .utf8)) ?? ""
        let flags = Set(src.matches(of: /case "(--[a-z-]+)"/).map { String($0.1) })
        check(!flags.isEmpty && flags.isSubset(of: SupportFolder.scriptedFlags), "every LaunchOptions flag is a scripted flag (missing: \(flags.subtracting(SupportFolder.scriptedFlags).sorted()))")
        // No other place resolves the folder itself.
        let strays = (FileManager.default.enumerator(at: repoRoot().appending(path: "Sources"), includingPropertiesForKeys: nil)?.compactMap { $0 as? URL } ?? [])
            .filter { $0.pathExtension == "swift" && $0.lastPathComponent != "SupportFolder.swift" && !$0.path.contains("/DuoChecks/") }
            .filter { ((try? String(contentsOf: $0, encoding: .utf8)) ?? "").contains(".applicationSupportDirectory") }
        check(strays.isEmpty, "only SupportFolder resolves Application Support (\(strays.map(\.lastPathComponent)))")
        // The launch step, in this process: a temporary folder, short, exported; then put back.
        let saved = getenv("DUO_SUPPORT_DIR").map { String(cString: $0) }
        unsetenv("DUO_SUPPORT_DIR")
        let real = SupportFolder.duo.path
        check(real.hasSuffix("/Library/Application Support/Duo"), "unset → the real folder (\(real))")
        let choice = SupportFolder.prepareForLaunch(arguments: ["Duo", "--workspace", "/tmp/ws"], environment: [:])
        let temp = ProcessInfo.processInfo.environment["DUO_SUPPORT_DIR"] ?? ""
        check(choice == .temporary && temp.hasPrefix("/tmp/duo-") && FileManager.default.fileExists(atPath: temp), "a scripted launch makes and exports \(temp)")
        check(SupportFolder.duo.path == temp + "/Duo" && ControlEndpoint.file.path.hasPrefix(temp) && DuoPaths.state.path.hasPrefix(temp) && SessionArchive.root.path.hasPrefix(temp) && Migrator.defaultJournalDir.path.hasPrefix(temp), "state, archive, journals and endpoint follow it")
        check(ControlEndpoint.privateSocket.utf8.count < 104, "its socket path is short (\(ControlEndpoint.privateSocket.utf8.count) bytes)")
        check(ChildEnvironment.make(sessionID: nil).contains("DUO_SUPPORT_DIR=\(temp)"), "terminals inherit it, so duo2 in them finds the instance")
        check(SupportFolder.prepareForLaunch(arguments: ["Duo"], environment: ProcessInfo.processInfo.environment) == .given(temp), "an explicit folder is kept, not replaced")
        try? FileManager.default.removeItem(atPath: temp)
        if let saved { setenv("DUO_SUPPORT_DIR", saved, 1) } else { unsetenv("DUO_SUPPORT_DIR") }
    }

    print("tokens")
    check(DuoTextStyle.body.spec.size == 13 && DuoTextStyle.body.spec.lineHeight == 20, "body 13/20")
    check(DuoTextStyle.sectionLabel.spec.uppercase && DuoTextStyle.sectionLabel.spec.tracking == 0.66, "section label caps +0.66")
    check(DuoMetric.paneOverviewHome == 340 && DuoMetric.paneProjectRight == 460, "pane widths")
    // C-22: the editor's H2 and smaller sit 4 lower, from the token the app hands the page.
    let editorSource = (try? String(contentsOf: repoRoot().appending(path: "Vendor/codemirror/src/duo-editor.js"), encoding: .utf8)) ?? ""
    check(EditorController.tokenCSS().contains("--duo-heading-above: \(Int(DuoSpace.gapAboveDocumentHeading))px")
          && editorSource.contains("paddingTop: \"var(--duo-heading-above)\""), "the editor's space above H2 and smaller comes from space.gap.aboveDocumentHeading")

    print("cli parity (DL-71, DL-72)")
    check(Set(DuoAction.all.map(\.id)) == Set(ActionID.allCases) && DuoAction.all.count == ActionID.allCases.count, "every action is in the registry once")
    let gaps = parityGaps()
    if !gaps.isEmpty { print("    UI with no verb: " + gaps.joined(separator: "; ")) }
    check(gaps.isEmpty, "every button, menu item, click and drag in the app names a duo2 action (or is listed in Parity.uiOnly)")
    let primerVerbs = DuoAction.primer().matches(of: /`duo2 ([a-z-]+(?: [a-z-]+)?)/).map { String($0.1) }
    check(!primerVerbs.isEmpty && primerVerbs.allSatisfy { DuoAction.resolve($0.split(separator: " ").map(String.init)) != nil }, "the primer names only verbs that exist")
    check(DuoAction.resolve(["file", "rename", "a.md", "b.md"]).map { $0.0.id == .fileRename && $0.rest == ["a.md", "b.md"] } == true, "two-word verbs resolve")
    check(DuoAction.resolve(["doc-status", "x.md"])?.0.id == .docStatus && DuoAction.resolve(["needs-you"])?.0.id == .needsYou, "old spellings resolve")
    let inv = Invocation(["a.md", "--to", "abc", "--new", "--json", "b"])
    check(inv.positional == ["a.md", "b"] && inv.flags["to"] == "abc" && inv.has("new") && inv.json, "flags and positionals parse")
    let reference = try? String(contentsOf: repoRoot().appending(path: "docs/cli/duo2.md"), encoding: .utf8)
    check(reference == DuoAction.markdown(), "docs/cli/duo2.md is current (regenerate: build/Duo.app/Contents/Helpers/duo2 help --markdown > docs/cli/duo2.md)")
    // The design system Claude Design reads (docs/design/system) is generated from tokens.json.
    let gen = Process()
    gen.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
    gen.arguments = [repoRoot().appending(path: "scripts/gen-design-system.py").path, "--check"]
    gen.standardOutput = FileHandle.nullDevice
    try? gen.run(); gen.waitUntilExit()
    check(gen.terminationStatus == 0, "docs/design/system tokens and icons are current (regenerate: python3 scripts/gen-design-system.py)")

    print("install loop (DL-74, DL-75)")
    let iroot = FileManager.default.temporaryDirectory.appending(path: "duo-install-\(UUID().uuidString)")
    Installer.testRoot = iroot
    defer { Installer.testRoot = nil; try? FileManager.default.removeItem(at: iroot) }
    let cli = iroot.appending(path: "Duo.app/Contents/Helpers/duo2").creatingParent()
    FileManager.default.createFile(atPath: cli.path, contents: Data())
    try? FileManager.default.createDirectory(at: Installer.claudeDir, withIntermediateDirectories: true)
    let mine = "# My rules\n\nBe brief.\n\n<!-- duo:managed-v0.13.0 -->\nlegacy\n<!-- duo:end -->\n"
    try? mine.write(to: Installer.claudeMD, atomically: true, encoding: .utf8)
    check(Installer.needsConsent(cli: cli.path), "asks before installing anything")
    Installer.recordConsent(false, cli: cli.path)
    Installer.install(cli: cli.path)
    check((try? String(contentsOf: Installer.claudeMD, encoding: .utf8)) == mine && !Installer.needsConsent(cli: cli.path), "declined: nothing written, not asked again")
    Installer.recordConsent(true, cli: cli.path)
    Installer.install(cli: cli.path)
    let md1 = (try? String(contentsOf: Installer.claudeMD, encoding: .utf8)) ?? ""
    check(md1.hasPrefix(mine) && md1.contains(Installer.block()) && LegacyDuo.detect(in: Installer.claudeDir).count == 1, "block added after the user's text; legacy's block untouched and still detected as legacy's alone")
    check((try? String(contentsOf: Installer.skillFile, encoding: .utf8)) == Installer.skill(), "skill written")
    check((try? FileManager.default.destinationOfSymbolicLink(atPath: Installer.link.path)) == cli.path, "duo2 linked onto PATH")
    check(Installer.install(cli: cli.path).lines.isEmpty, "a second launch changes nothing")
    let edited = md1.replacingOccurrences(of: "## Duo", with: "## Duo (mine)")
    try? edited.write(to: Installer.claudeMD, atomically: true, encoding: .utf8)
    Installer.install(cli: cli.path)
    check((try? String(contentsOf: Installer.claudeMD, encoding: .utf8)) == edited, "an edited block is left alone")
    try? md1.replacingOccurrences(of: Installer.block() + "\n", with: "").write(to: Installer.claudeMD, atomically: true, encoding: .utf8)
    Installer.install(cli: cli.path)
    Installer.install(cli: cli.path)
    check(!((try? String(contentsOf: Installer.claudeMD, encoding: .utf8)) ?? "").contains("duo2:begin"), "a removed block is never added back")
    Installer.uninstall()
    check(!FileManager.default.fileExists(atPath: Installer.skillFile.path) && (try? FileManager.default.destinationOfSymbolicLink(atPath: Installer.link.path)) == nil
          && ((try? String(contentsOf: Installer.claudeMD, encoding: .utf8)) ?? "").hasPrefix("# My rules"), "uninstall removes exactly what Duo wrote")
    let before = "# Mine\n\n" + Installer.block() + "\n"
    let restored = iroot.appending(path: "restore/CLAUDE.md").creatingParent()
    try? "# Mine\n".write(to: restored, atomically: true, encoding: .utf8)
    Installer.reapplyBlock(ifPresentIn: before, to: restored)
    check(((try? String(contentsOf: restored, encoding: .utf8)) ?? "").contains(Installer.block()), "legacy restore keeps Duo v2's block")
    check(Installer.block().split(separator: " ").count < 110, "the always-on block stays short")

    print("collisions (DL-77, DL-78)")
    let hroot = FileManager.default.temporaryDirectory.appending(path: "duo-history-\(UUID().uuidString)")
    FileHistory.root = hroot
    let doc = URL(fileURLWithPath: "/tmp/some/doc.md")
    FileHistory.snapshot(doc, Data("one".utf8), source: "open")
    FileHistory.snapshot(doc, Data("one".utf8), source: "open")
    FileHistory.snapshot(doc, Data("two".utf8), source: "conflict-theirs")
    let kept = FileHistory.index(doc)
    check(kept.map(\.source) == ["open", "conflict-theirs"] && (try? String(contentsOf: FileHistory.blob(doc, hash: kept[1].hash), encoding: .utf8)) == "two",
          "history keeps each version once, readable")
    try? FileManager.default.removeItem(at: hroot)
    let hookDir = FileManager.default.temporaryDirectory.appending(path: "duo-hooks-\(UUID().uuidString)")
    let withHook = (try? HookEvents.settingsFile(for: "s9", in: hookDir, cli: "/Apps/Duo.app/Contents/Helpers/duo2")).flatMap { try? Data(contentsOf: $0) }
        .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    let pre = ((withHook?["hooks"] as? [String: Any])?["PreToolUse"] as? [[String: Any]])?.first
    check(pre?["matcher"] as? String == "Edit|MultiEdit|Write" && ((pre?["hooks"] as? [[String: Any]])?.first?["command"] as? String)?.hasSuffix("duo2' hook pre-edit") == true,
          "Duo's sessions route Edit, MultiEdit and Write through the edit hook")
    let noHook = (try? HookEvents.settingsFile(for: "s10", in: hookDir)).flatMap { try? Data(contentsOf: $0) }.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    check((noHook?["hooks"] as? [String: Any])?["PreToolUse"] == nil, "no CLI, no edit hook (the primer and the merge still hold)")
    let ctxHooks = withHook?["hooks"] as? [String: Any]
    for e in ["SessionStart", "UserPromptSubmit"] {
        let cmds = ((ctxHooks?[e] as? [[String: Any]])?.first?["hooks"] as? [[String: Any]])?.compactMap { $0["command"] as? String } ?? []
        check(cmds.count == 2 && cmds[0].hasPrefix("/usr/bin/perl") && cmds[1].hasSuffix("duo2' hook context"), "\(e): the event hook, then the task context hook (DL-116)")
    }
    check((((noHook?["hooks"] as? [String: Any])?["SessionStart"] as? [[String: Any]])?.first?["hooks"] as? [[String: Any]])?.count == 1, "no CLI, no task context hook")
    try? FileManager.default.removeItem(at: hookDir)

    print("task context (DL-116)")
    let tc = FileManager.default.temporaryDirectory.appending(path: "duo-tc-\(UUID().uuidString)")
    let tcProj = tc.appending(path: "proj"), tcOther = tc.appending(path: "other"), told = tc.appending(path: "events")
    for f in [tcProj, tcOther] { try FileManager.default.createDirectory(at: f.appending(path: "tasks"), withIntermediateDirectories: true) }
    let sA = "11111111-2222-3333-4444-555555555555", sB = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
    func note(_ folder: URL, _ name: String, _ text: String) { try? Data(text.utf8).write(to: folder.appending(path: "tasks/\(name)")) }
    func gone(_ folder: URL, _ name: String) { try? FileManager.default.removeItem(at: folder.appending(path: "tasks/\(name)")) }
    let tcFolders = ["proj": tcProj, "other": tcOther]
    func ctx(_ event: String, _ sid: String = sA, cwd: String? = tcProj.path) -> String {
        TaskContext.hook(event, sessionId: sid, now: TaskContext.entries(for: [sid], folders: tcFolders), cwd: cwd, in: told)
    }
    note(tcProj, "exec-review-prep.md", TaskNotes.newNote(title: "Exec review prep", links: [TaskNotes.link(title: "Draft", id: sA)]))
    note(tcProj, "unrelated.md", TaskNotes.newNote(title: "Unrelated", links: [TaskNotes.link(title: "Other", id: sB)]))
    let start = ctx("start")
    print("    start: " + start.replacingOccurrences(of: "\n", with: "\n           "))
    check(start.hasPrefix("Duo: This session is attributed to the task “Exec review prep” (status: open).")
          && start.contains("Its note, tasks/exec-review-prep.md, is the task's brief") && start.contains("`duo2 session task`")
          && !start.contains("Unrelated") && start.split(separator: "\n").count == 3, "start: the one task, its status and note, in three lines")
    check(ctx("prompt") == "", "a prompt with nothing changed adds nothing")
    check(ctx("start", cwd: "/elsewhere").contains(tcProj.appending(path: "tasks/exec-review-prep.md").path), "outside the project the note's path is absolute")
    check(ctx("start") == start && ctx("prompt") == "", "resume and compact (SessionStart again) say it all again; the next prompt nothing")
    // Status changes, then the session joins a second task in another project.
    note(tcProj, "exec-review-prep.md", TaskNotes.settingStatus("review", in: TaskNotes.newNote(title: "Exec review prep", links: [TaskNotes.link(title: "Draft", id: sA)])))
    note(tcOther, "q4-plan.md", TaskNotes.newNote(title: "Q4 plan", links: [TaskNotes.link(title: "Draft", id: sA)]))
    let two = ctx("prompt")
    print("    two:   " + two.replacingOccurrences(of: "\n", with: "\n           "))
    check(two.contains("The task “Exec review prep” is now review (was open).") && two.contains("This session was added to the task “Q4 plan”.")
          && two.contains("This session is attributed to 2 tasks:") && two.contains("- “Q4 plan” (status: open): " + tcOther.appending(path: "tasks/q4-plan.md").path),
          "linked to a second task mid-session: told once, on the next prompt, with both listed")
    check(ctx("prompt") == "", "…and only once")
    // Renamed (the note follows its title, C-24), given an id and archived.
    gone(tcOther, "q4-plan.md")
    note(tcOther, "q4-plan-final.md", "---\nid: 0b9e7c1e-1111-2222-3333-444455556666\narchived: true\n" + TaskNotes.newNote(title: "Q4 plan final", links: [TaskNotes.link(title: "Draft", id: sA)]).dropFirst(4))
    let renamed = ctx("prompt")
    print("    renamed: " + renamed.replacingOccurrences(of: "\n", with: "\n           "))
    check(renamed.contains("The task “Q4 plan” was renamed “Q4 plan final”.") && renamed.contains("q4-plan.md to ") && renamed.contains("q4-plan-final.md")
          && renamed.contains("was archived") && renamed.contains("(status: open, archived, id: 0b9e7c1e-1111-2222-3333-444455556666)"),
          "renamed, moved, archived: told the new title and path, archived tasks still told (marked)")
    // Unlinked from both.
    note(tcProj, "exec-review-prep.md", TaskNotes.newNote(title: "Exec review prep", links: []))
    gone(tcOther, "q4-plan-final.md")
    let unlinked = ctx("prompt")
    print("    unlinked: " + unlinked.replacingOccurrences(of: "\n", with: "\n           "))
    check(unlinked.contains("This session was removed from the task “Exec review prep” (tasks/exec-review-prep.md).")
          && unlinked.contains("removed from the task “Q4 plan final”") && unlinked.hasSuffix("This session has no task now."), "unlinked: told once which tasks it left")
    check(ctx("prompt") == "" && ctx("start") == "", "no task: no output at prompt or start")
    // A session with no task that's never been told: nothing; linked later: told on the next prompt.
    check(ctx("start", sB + "x") == "" && ctx("prompt", "99999999-2222-3333-4444-555555555555") == "", "never attributed: nothing, ever")
    note(tcProj, "exec-review-prep.md", TaskNotes.newNote(title: "Exec review prep", links: [TaskNotes.link(title: "Draft", id: sA)]))
    let added = ctx("prompt")
    check(added.hasPrefix("Duo: This session was added to the task “Exec review prep”.\nThis session is attributed to the task"), "linked mid-session (Make a Task, Add to Task): told on the next prompt")
    check(TaskContext.onPrompt(TaskContext.entries(for: [sA], folders: tcFolders), told: nil, cwd: nil) == TaskContext.atStart(TaskContext.entries(for: [sA], folders: tcFolders), cwd: nil),
          "a session never told (older settings) hears it all on its next prompt")
    let launch = TaskContext.Entry(project: "proj", folder: "/w/proj", path: "tasks/launch.md", title: "Launch", status: "open")
    var after = launch; after.project = "other"; after.folder = "/w/other"
    let movedCtx = TaskContext.onPrompt([after], told: [launch], cwd: "/w/proj") ?? ""
    check(movedCtx.hasPrefix("Duo: The task “Launch” moved to the project other; its note is now /w/other/tasks/launch.md.") && !movedCtx.contains("removed"),
          "Move to Project: told the note's new place, not removed and added")
    try? FileManager.default.removeItem(at: tc)

    check(DuoAction.primer().contains("duo2 doc edit --stdin") && DuoAction.primer().contains("not with Edit, Write or shell redirection"),
          "the primer tells Claude how to edit open documents without the hook")

    print("privacy prompts (F-53)")
    let home = FileManager.default.homeDirectoryForCurrentUser
    check(FileSource.files(in: home).isEmpty, "the home folder is never walked for files")
    check(ProtectedFolders.skip(home.appending(path: "Music"), root: home) == true
          && ProtectedFolders.skip(home.appending(path: "Pictures"), root: home) == true
          && ProtectedFolders.skip(home.appending(path: "Documents"), root: home.appending(path: "Documents")) == false
          && ProtectedFolders.skip(home.appending(path: "repos"), root: home) == false,
          "walks never enter Music, Photos, Documents… unless the project lives inside them")
    check(FileSource.files(in: URL(fileURLWithPath: "/")).isEmpty && FileSource.files(in: home.deletingLastPathComponent()).isEmpty,
          "folders above home are never walked for files (a session started in / or /Users)")

    print("Claude folders (DL-103)")
    let cw = FileManager.default.temporaryDirectory.appending(path: "duo-claude-\(UUID().uuidString)")
    for (dir, file) in [("", "HOME.md"), ("tool", "CLAUDE.md"), ("tool/pkg", "CLAUDE.md"), ("tool/inner", "PROJECT.md"),
                        ("proj", "PROJECT.md"), ("proj/sub", "CLAUDE.md"), ("plain", "notes.md")] {
        try FileManager.default.createDirectory(at: cw.appending(path: dir), withIntermediateDirectories: true)
        try "---\ngoal: x\n---\n".write(to: cw.appending(path: dir).appending(path: file), atomically: true, encoding: .utf8)
    }
    let cscan = ProjectDiscovery.scanAll(root: cw)
    check(cscan.claudeFolders.map(\.lastPathComponent) == ["tool"],
          "a CLAUDE.md folder is found; one inside it or inside a project is part of that one")
    check(Set(cscan.projects.map(\.folder.lastPathComponent)) == [cw.lastPathComponent, "inner", "proj"],
          "projects are still found, inside a Claude folder too")
    let (csnap, cfolders, _) = LiveSnapshot.build(noHistory(cw), beacons: [])
    let toolEntry = csnap.projects.first { $0.name == "tool" }
    check(toolEntry?.isFolderOnly == true && toolEntry?.hasClaudeMD == true && cfolders["tool"] != nil
          && csnap.sessions(inProject: "tool").isEmpty && csnap.projects.contains { $0.name == "plain" } == false,
          "a Claude folder without sessions is on the map as a folder; a plain folder isn't")
    let toolFiles = FileSource.files(in: cw.appending(path: "tool"), excluding: [cw.appending(path: "tool/inner").path]).map(\.relative)
    check(toolFiles.contains("CLAUDE.md") && toolFiles.contains("pkg/CLAUDE.md") && !toolFiles.contains("inner/PROJECT.md"),
          "a folder's files leave out a searched folder inside it, so no file is indexed twice")
    try? FileManager.default.removeItem(at: cw)

    print("send to claude (DL-67, DL-68)")
    let hostile = SendFormat.documentSelection("ok\u{1b}[201~rm -rf ~\r\nnext", path: "a\nb.md", fromLine: 1, toLine: 2)
    check(!hostile.contains("\u{1b}") && !hostile.contains("\r") && hostile.hasPrefix("From a b.md, lines 1–2:\n> ok[201~rm -rf ~\n> next"), "control characters can't escape the paste; fields stay on one line")
    check(SendFormat.file("docs/my notes.md") == "@\"docs/my notes.md\" " && SendFormat.file("docs/prd.md") == "@docs/prd.md ", "file references, quoted when they have spaces")
    let el = SendFormat.Element(tag: "button", label: "button#pay", selector: "#pay", trail: ["Checkout", "Payment"], text: "Pay", attributes: ["type": "submit"],
                                styles: ["color": "red"], rect: [1, 2, 30, 40], html: "<button>```</button>", url: "file:///x.html", title: "T")
    let ep = SendFormat.element(el, path: "x.html", screenshot: "/tmp/e.png")
    check(ep.contains("````html\n<button>```</button>\n````") && ep.contains("under: Checkout › Payment") && ep.contains("screenshot: /tmp/e.png"), "element payload: fence outgrows backticks, trail, screenshot")
    check(SendFormat.documentSelection(String(repeating: "x", count: 9000), path: "a", fromLine: 1, toLine: 1).count < SendFormat.cap + 100, "payloads are capped")

    print("the map with many projects (DL-104)")
    var many = f
    many.topics += ["~/repos", "~/Desktop"]
    func decoded<T: Decodable>(_ value: [String: Any]) -> T {
        try! JSONDecoder().decode(T.self, from: JSONSerialization.data(withJSONObject: value))
    }
    func folder(_ name: String, _ parent: String) -> Fixture.Project {
        decoded(["name": name, "topic": parent, "path": "\(parent)/\(name)", "goal": "", "kind": "folder"])
    }
    func idle(_ name: String, _ project: String, _ wait: String, _ state: SessionState = .idle) -> Fixture.Session {
        decoded(["name": name, "project": project, "state": state.rawValue, "wait": wait])
    }
    for (i, n) in ["alpha", "bravo", "charlie", "delta", "echo", "foxtrot", "golf"].enumerated() {
        many.projects.append(folder(n, "~/repos"))
        many.sessions.append(idle("s-\(n)", n, "\(i + 1)d"))
    }
    many.projects.append(folder("zulu", "~/Desktop"))
    many.sessions.append(idle("s-zulu", "zulu", "2h"))
    many.projects.append(folder("board-deck", "~/Desktop"))
    many.sessions.append(idle("Slide 7", "board-deck", "9m", .needsYou))
    let m1 = MapLayout.build(many, sort: .recent, filter: "")
    check(m1.home?.name == "home" && m1.homeColumns.map(\.topic) == ["", "Payments", "Growth", "Platform"], "Home's tile, then Home's columns as tiles")
    check(m1.active.map(\.name) == ["board-deck"], "a folder outside Home that needs you is a tile, not a row")
    check(m1.outside.map(\.topic) == ["~/Desktop", "~/repos"], "Recent: the group with the newest activity first")
    check(m1.outside.last?.projects.map(\.name) == ["alpha", "bravo", "charlie", "delta", "echo"] && m1.outside.last?.hidden == 2,
          "rows newest first, five, then + n more")
    let m2 = MapLayout.build(many, sort: .name, filter: "", openGroups: ["~/repos"])
    check(m2.outside.map(\.topic) == ["~/Desktop", "~/repos"] && m2.outside.last?.projects.count == 7 && m2.outside.last?.hidden == 0,
          "Name: groups and rows by name; an opened group shows every row")
    check(m2.homeColumns.first { $0.topic == "Payments" }?.projects.map(\.name) == ["checkout-redesign", "fraud-rules-review", "refunds-api-spec"], "Name orders Home's tiles too")
    let m3 = MapLayout.build(many, sort: .name, filter: "ECH")
    check(m3.home == nil && m3.homeColumns.isEmpty && m3.outside.flatMap(\.projects).map(\.name) == ["echo"] && m3.shown == 1,
          "the filter matches names and paths, ignoring case")
    check(m3.total == many.projects.count && m1.outsideTotal == 9, "counts before the filter")
    let settled = MapLayout.build(many, sort: .recent, filter: "", settled: ["golf": .greatestFiniteMagnitude])
    check(settled.outside.first?.topic == "~/repos" && settled.outside.first?.projects.first?.name == "golf", "the order holds what was settled on arrival")
    check(MapLayout.minutesAgo("3d") == 4320 && MapLayout.minutesAgo("at prompt") == 0 && MapLayout.minutesAgo(nil) == nil, "wait words to minutes")
    check(MapLayout.homeSessions(many).first?.state == .needsYou, "Home's tile lists its sessions in attention order")

    print("files in and out of the project (C-20, DL-105, DL-106, DL-107)")
    let treeDir = FileManager.default.temporaryDirectory.appending(path: "duo-tree-\(UUID().uuidString)")
    let tfm = FileManager.default
    for d in ["docs/deep", ".git", ".claude/worktrees/x", ".claude/skills", "node_modules/pkg", ".duo"] { try tfm.createDirectory(at: treeDir.appending(path: d), withIntermediateDirectories: true) }
    for f in ["PROJECT.md", "docs/a.md", "docs/deep/b.md", ".env", ".gitignore", ".DS_Store", ".claude/settings.json"] { try Data("x".utf8).write(to: treeDir.appending(path: f)) }
    check(AppModel.contained("docs/a.md", in: treeDir) != nil && AppModel.contained("../outside.md", in: treeDir) == nil
          && AppModel.contained("docs/../../x", in: treeDir) == nil && AppModel.contained("/etc/hosts", in: treeDir) == nil,
          "a tree path can't leave the project (C-20)")
    let closed = LiveSnapshot.treeFiles(treeDir)
    check(closed == ["PROJECT.md", "docs/"], "the tree lists the top level only, folders closed, no dotfiles")
    check(LiveSnapshot.treeFiles(treeDir, expanded: ["docs"]) == ["PROJECT.md", "docs/", "docs/a.md", "docs/deep/"], "an open folder lists what's inside it, one level")
    let hidden = LiveSnapshot.treeFiles(treeDir, showHidden: true, expanded: [".claude"])
    check(hidden.contains(".env") && hidden.contains(".gitignore") && hidden.contains(".claude/") && hidden.contains(".claude/skills/")
          && !hidden.contains(".git/") && !hidden.contains(".DS_Store") && !hidden.contains(".duo/") && !hidden.contains(".claude/worktrees/") && !hidden.contains("node_modules/"),
          "Show Hidden Files adds dotfiles; .git, .DS_Store, .duo, worktrees and node_modules never show (DL-105)")
    check(LiveSnapshot.topLevelFiles(treeDir).contains("docs/deep/b.md"), "duo2 files still lists three levels, whatever the tree has open")
    let outsideFile = FileManager.default.temporaryDirectory.appending(path: "duo-outside-\(UUID().uuidString).md")
    try Data("# outside".utf8).write(to: outsideFile)
    var tabsFixture = f
    tabsFixture.projects.append(decoded(["name": "treeproj", "topic": "Platform", "path": treeDir.path, "goal": "g"]))
    let tabsModel = AppModel(fixture: tabsFixture)
    tabsModel.terminalsMode = .live
    tabsModel.liveFolders["treeproj"] = treeDir
    tabsModel.open(project: "treeproj")
    let outTab = tabsModel.openFile(at: outsideFile)
    check(outTab == AppModel.outsideFilePrefix + outsideFile.standardizedFileURL.path && tabsModel.liveFile(outTab ?? "") != nil
          && tabsModel.openFile(at: treeDir.appending(path: "docs/a.md")) == "docs/a.md" && tabsModel.openFile(at: treeDir.appending(path: "docs")) == nil,
          "Open File…: outside files as file: tabs, the project's own as themselves, folders refused (DL-106)")
    check(tabsModel.expandedFolders["treeproj"]?.contains("docs") == true, "opening a document opens its folders in the tree")
    tabsModel.rightTab = outTab
    tabsModel.open(project: "checkout-redesign")
    tabsModel.zoomOut()
    tabsModel.open(project: "treeproj")
    check(tabsModel.rightTab == outTab && tabsModel.openDocuments.contains(outTab ?? ""), "coming back to a project shows the tab it was on, an outside file too (DL-107)")
    tabsModel.open(project: "checkout-redesign", session: "Teardown research")
    let wasConsole = tabsModel.consoleTab
    tabsModel.open(project: "treeproj")
    tabsModel.open(project: "checkout-redesign")
    check(wasConsole != nil && tabsModel.consoleTab == wasConsole, "coming back shows the console tab it was on, not the most urgent (DL-107)")
    let tabsSaved = tabsModel.currentRestoreState()
    check(tabsSaved.projects.first { $0.folder == treeDir.path }?.rightTab == outTab, "the restore file keeps each project's tabs, not only the one on screen")
    try? tfm.removeItem(at: treeDir)
    try? tfm.removeItem(at: outsideFile)

    print("drag and drop of files (DL-117)")
    do {
        // Paths into a terminal: Terminal.app's form.
        check(FileDrop.terminalText([URL(fileURLWithPath: "/tmp/a b.md")]) == "/tmp/a\\ b.md ", "a space is backslashed, with a trailing space")
        check(FileDrop.shellEscaped("/x/it's \"q\" (1) & $HOME;`x`*?[]!#{}|<>=~^") == "/x/it\\'s\\ \\\"q\\\"\\ \\(1\\)\\ \\&\\ \\$HOME\\;\\`x\\`\\*\\?\\[\\]\\!\\#\\{\\}\\|\\<\\>\\=\\~\\^",
              "quotes, brackets and every shell character are backslashed")
        check(FileDrop.shellEscaped("/Users/me/Café 日本 🙂/notes-v1.2_final+x@y:z%,.md") == "/Users/me/Café\\ 日本\\ 🙂/notes-v1.2_final+x@y:z%,.md", "letters beyond ASCII stay as they are; plain punctuation isn't escaped")
        check(FileDrop.terminalText([URL(fileURLWithPath: "/a/one.md"), URL(fileURLWithPath: "/a/two words"), URL(fileURLWithPath: "/a/dir/")]) == "/a/one.md /a/two\\ words /a/dir ",
              "several items: separated by spaces, one trailing space")
        let nl = FileDrop.terminalText([URL(fileURLWithPath: "/a/line\nbreak\r.md"), URL(fileURLWithPath: "/a/tab\there")])
        check(nl == "$'/a/line\\nbreak\\r.md' $'/a/tab\\there' " && !nl.contains("\n") && !nl.contains("\r"), "a control character in a name is written $'…', so nothing typed is a Return")
        check(!FileDrop.terminalText([URL(fileURLWithPath: "/a/x\ny")]).unicodeScalars.contains { $0.value < 0x20 }, "no control character is ever typed")

        // Moves into a folder: scratch folders, a scratch Trash.
        let root = FileManager.default.temporaryDirectory.appending(path: "duo-drop-\(UUID().uuidString)")
        let proj = root.appending(path: "proj"), finder = root.appending(path: "finder"), bin = root.appending(path: "trash")
        let fm = FileManager.default
        for d in ["proj/docs/sub", "proj/notes", "finder/folder/inner", "trash"] { try fm.createDirectory(at: root.appending(path: d), withIntermediateDirectories: true) }
        for (f, t) in [("finder/a.md", "dropped a"), ("finder/folder/inner/x.md", "x"), ("proj/docs/a.md", "the one there"), ("proj/notes/n.md", "n"), ("finder/b c.md", "b")] {
            try Data(t.utf8).write(to: root.appending(path: f))
        }
        let saved = FileDrop.trash
        FileDrop.trash = { u in let to = bin.appending(path: UUID().uuidString + "-" + u.lastPathComponent); try fm.moveItem(at: u, to: to); return to }
        defer { FileDrop.trash = saved }
        func text(_ u: URL) -> String? { try? String(contentsOf: u, encoding: .utf8) }

        let docs = proj.appending(path: "docs")
        let p1 = FileDrop.plan([finder.appending(path: "b c.md"), finder.appending(path: "folder")], into: docs)
        check(p1.refused.isEmpty && p1.plans.count == 2 && p1.plans.allSatisfy { $0.mode == .move && !$0.clashes }, "Finder items on the same volume plan as moves")
        let d1 = try p1.plans.map { try FileDrop.perform($0, clash: nil) }
        check(fm.fileExists(atPath: docs.appending(path: "b c.md").path) && fm.fileExists(atPath: docs.appending(path: "folder/inner/x.md").path)
              && !fm.fileExists(atPath: finder.appending(path: "b c.md").path) && !fm.fileExists(atPath: finder.appending(path: "folder").path), "a drop moves files and folders on disk")
        check(FileDrop.undo(d1).isEmpty && fm.fileExists(atPath: finder.appending(path: "b c.md").path) && fm.fileExists(atPath: finder.appending(path: "folder/inner/x.md").path)
              && !fm.fileExists(atPath: docs.appending(path: "b c.md").path), "undo puts them back where they were")

        // A taken name.
        let clash = FileDrop.plan([finder.appending(path: "a.md")], into: docs).plans
        check(clash.count == 1 && clash[0].clashes, "a taken name is a clash")
        check((try? FileDrop.perform(clash[0], clash: nil)) == nil && text(docs.appending(path: "a.md")) == "the one there" && fm.fileExists(atPath: finder.appending(path: "a.md").path),
              "a clash without an answer moves nothing and never overwrites")
        let kept = try FileDrop.perform(clash[0], clash: .keepBoth)
        check(kept.dest.lastPathComponent == "a 2.md" && text(docs.appending(path: "a.md")) == "the one there" && text(kept.dest) == "dropped a", "Keep Both names the dropped one “a 2.md”, like Finder")
        FileDrop.undo([kept])
        let rep = try FileDrop.perform(clash[0], clash: .replace)
        check(text(docs.appending(path: "a.md")) == "dropped a" && rep.replaced.map { text($0) == "the one there" } == true, "Replace puts the one there in the Trash, not away for good")
        check(FileDrop.undo([rep]).isEmpty && text(docs.appending(path: "a.md")) == "the one there" && text(finder.appending(path: "a.md")) == "dropped a",
              "undoing a Replace brings both back")

        // Into itself.
        check(FileDrop.refusal(docs, into: docs) != nil && FileDrop.refusal(docs, into: docs.appending(path: "sub")) != nil && FileDrop.refusal(docs, into: proj.appending(path: "notes")) == nil,
              "a folder can't go into itself or its own children")
        let selfPlan = FileDrop.plan([docs, proj.appending(path: "notes")], into: docs.appending(path: "sub"))
        check(selfPlan.refused.count == 1 && selfPlan.plans.map(\.source.lastPathComponent) == ["notes"], "the rest of a drop still goes when one item would go into itself")
        check(FileDrop.plan([docs.appending(path: "a.md")], into: docs).plans.isEmpty, "an item dropped on its own folder stays put")
        try fm.createDirectory(at: docs.appending(path: "sub/docs"), withIntermediateDirectories: true)
        check(FileDrop.plan([docs.appending(path: "sub/docs")], into: proj).refused.count == 1, "nothing replaces the folder that holds it")

        // Across volumes: a scratch disk image (the boot disk's volumes all report as one, as Finder sees them).
        func hdiutil(_ args: [String]) -> Bool {
            let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil"); p.arguments = args
            p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
            guard (try? p.run()) != nil else { return false }
            p.waitUntilExit(); return p.terminationStatus == 0
        }
        let mnt = root.appending(path: "mnt"), img = root.appending(path: "vol.dmg")
        if hdiutil(["create", "-size", "2m", "-fs", "HFS+", "-volname", "DuoDrop", "-layout", "NONE", img.path]),
           hdiutil(["attach", img.path, "-nobrowse", "-noverify", "-mountpoint", mnt.path]) {
            let far = mnt.appending(path: "far.md")
            try Data("far".utf8).write(to: far)
            check(FileDrop.sameVolume(finder, docs) && !FileDrop.sameVolume(far, docs), "volumes are told apart")
            let cross = FileDrop.plan([far], into: docs).plans
            check(cross.first?.mode == .copy && FileDrop.plan([docs.appending(path: "a.md")], into: mnt).plans.first?.mode == .copy, "from another volume a drop copies, either way (Q-51)")
            if let c = cross.first {
                let done = try FileDrop.perform(c, clash: nil)
                check(text(done.dest) == "far" && text(far) == "far", "the copy lands and the original stays")
                check(FileDrop.undo([done]).isEmpty && !fm.fileExists(atPath: done.dest.path) && fm.fileExists(atPath: far.path), "undoing a copy puts the copy in the Trash")
            }
            _ = hdiutil(["detach", mnt.path, "-force"])
        } else {
            check(false, "a scratch disk image for the cross-volume checks")
        }

        // The model: a drop on a folder of the tree; open tabs follow an item moved inside the project.
        var dropFixture = f
        dropFixture.projects.append(decoded(["name": "dropproj", "topic": "Platform", "path": proj.path, "goal": "g"]))
        let m = AppModel(fixture: dropFixture)
        m.terminalsMode = .live
        m.liveFolders["dropproj"] = proj
        m.open(project: "dropproj")
        m.openDocument("notes/n.md")
        check(m.dropFolder("notes/n.md")?.lastPathComponent == "notes" && m.dropFolder(nil)?.path == proj.path, "a file row drops into its folder; the empty area into the root")
        check(m.dropFiles([proj.appending(path: "notes/n.md")], onto: "docs") && fm.fileExists(atPath: docs.appending(path: "n.md").path), "dragging within the tree moves to the folder")
        check(m.openDocuments.contains("docs/n.md") && !m.openDocuments.contains("notes/n.md"), "an open tab follows the moved file")
        check(!m.dropFiles([docs], onto: "docs/sub") && fm.fileExists(atPath: docs.path), "the model refuses a folder into itself")
        try? fm.removeItem(at: root)
    }

    print("New Session in Task, end to end with a stand-in claude (DL-112; no model, no turn)")
    do {
        // Everything in a scratch folder: Duo's support folder (whose state names the stand-in as
        // Settings' chosen claude), Claude's config folder (its beacon) and the project.
        let root = URL(fileURLWithPath: "/tmp/duo-draft-\(UUID().uuidString.prefix(8))")
        let support = root.appending(path: "s"), config = root.appending(path: "c"), proj = root.appending(path: "p")
        let log = root.appending(path: "claude.log"), fake = root.appending(path: "claude")
        for d in [support, config, proj.appending(path: "tasks")] { try tfm.createDirectory(at: d, withIntermediateDirectories: true) }
        try Data("# p\n".utf8).write(to: proj.appending(path: "PROJECT.md"))
        try Data(TaskNotes.newNote(title: "Exec review prep", links: []).utf8).write(to: proj.appending(path: "tasks/exec-review-prep.md"))
        // The stand-in: logs its arguments and every byte it is sent, writes an idle beacon, and
        // shows what it's typed. It never answers anything.
        let script = """
        #!/usr/bin/python3
        import os, sys, json, tty
        log = open("\(log.path)", "a")
        a = sys.argv[1:]
        log.write("ARGS " + json.dumps(a) + "\\n"); log.flush()
        d = os.path.join(os.environ["CLAUDE_CONFIG_DIR"], "sessions"); os.makedirs(d, exist_ok=True)
        json.dump({"pid": os.getpid(), "sessionId": a[a.index("--session-id") + 1], "cwd": os.getcwd(), "status": "idle"}, open(os.path.join(d, "%d.json" % os.getpid()), "w"))
        tty.setraw(0)
        os.write(1, b"> ")
        while True:
            b = os.read(0, 4096)
            if not b: break
            log.write("IN " + b.hex() + "\\n"); log.flush()
            os.write(1, b.replace(b"\\x1b[200~", b"").replace(b"\\x1b[201~", b""))
        """
        try Data(script.utf8).write(to: fake)
        try tfm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fake.path)
        let saved = ["DUO_SUPPORT_DIR", "CLAUDE_CONFIG_DIR"].map { k in (k, ProcessInfo.processInfo.environment[k]) }
        setenv("DUO_SUPPORT_DIR", support.path, 1)
        setenv("CLAUDE_CONFIG_DIR", config.path, 1)
        defer {
            for (k, v) in saved { if let v { setenv(k, v, 1) } else { unsetenv(k) } }
            ClaudeLocator.forget()
            try? tfm.removeItem(at: root)
        }
        DuoState.update { $0.claudePath = fake.path }
        ClaudeLocator.forget()
        check(ClaudeLocator.resolve() == fake.path && DuoPaths.state.path.hasPrefix(root.path), "the stand-in claude, from the scratch support folder")

        var fx = f
        fx.projects.append(decoded(["name": "drafty", "topic": "Platform", "path": proj.path, "goal": "g"]))
        let m = AppModel(fixture: fx)
        m.terminalsMode = .live
        m.liveFolders["drafty"] = proj
        m.open(project: "drafty")
        guard case .success(let id) = m.newSession(inTask: "tasks/exec-review-prep.md", project: "drafty") else {
            check(false, "New Session in Task started a session"); return
        }
        let deadline = Date().addingTimeInterval(15)
        while m.lastDrafted == nil && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.1)) }
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))   // the stand-in logs what it got
        let lines = ((try? String(contentsOf: log, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init)
        let args = lines.first { $0.hasPrefix("ARGS ") }.flatMap { try? JSONSerialization.jsonObject(with: Data($0.dropFirst(5).utf8)) as? [String] } ?? []
        var got = [UInt8]()
        for l in lines where l.hasPrefix("IN ") {
            let hex = Array(l.dropFirst(3))
            got += stride(from: 0, to: hex.count - 1, by: 2).compactMap { UInt8(String(hex[$0...$0 + 1]), radix: 16) }
        }
        let typed = String(decoding: got, as: UTF8.self)
        check(args.contains(id) && !args.contains { $0.contains("exec-review-prep") }, "the session starts with no first message (nothing is sent as its prompt)")
        check(m.lastDrafted?.key == id && m.lastDrafted?.text == "@tasks/exec-review-prep.md ", "once Claude's prompt is up, Duo drafts @tasks/exec-review-prep.md into it")
        check(typed == "\u{1b}[200~@tasks/exec-review-prep.md \u{1b}[201~", "the terminal received exactly the bracketed draft (\(typed.debugDescription))")
        check(!got.contains(13) && !got.contains(10), "no Return was sent: the draft waits for the user")
        check(TaskNotes.load(project: proj).first?.sessionIds == [id], "the note's sessions: links the new session")
        check(m.consoleTab == id, "the console shows it")
        m.terminals.existing(id)?.terminate()
    }

    print("The task menu: rename, archive, delete, move, link, with sessions kept or included, and undo (DL-115, C-24)")
    do {
        // Pure parts first.
        let note = TaskNotes.newNote(title: "Exec review prep", links: [])
        let renamed = TaskNotes.renaming(to: #"Board "deck" prep"#, in: note)
        check(TaskNotes.parse(renamed, path: "t.md").title == #"Board "deck" prep"# && renamed.contains(#"title: "Board \"deck\" prep""#)
              && renamed.contains("\n# Board \"deck\" prep\n") && !renamed.contains("Exec"), "Rename writes title: and the heading")
        let apart = "---\ntitle: \"A\"\n---\n\n# Something else\n"
        check(TaskNotes.renaming(to: "B", in: apart).contains("# Something else"), "a heading that says something else is left alone (F-87)")
        let taken: Set<String> = ["tasks/board-prep.md", "tasks/board-prep-2.md"]
        check(TaskNotes.pathForTitle("Board prep", current: "tasks/exec.md", exists: taken.contains) == "tasks/board-prep-3.md", "a taken slug gets -2, -3…")
        check(TaskNotes.pathForTitle("Board prep", current: "tasks/board-prep-2.md", exists: taken.contains) == "tasks/board-prep-2.md", "a note already at its name stays")
        check(TaskNotes.parse("---\narchived: true\nid: abc\n---\n", path: "t.md").archived && TaskNotes.parse("---\nid: abc\n---\n", path: "t.md").id == "abc",
              "archived: and id: read back")

        let root = URL(fileURLWithPath: "/tmp/duo-tm-\(UUID().uuidString.prefix(8))")
        let support = root.appending(path: "s"), config = root.appending(path: "c"), proj = root.appending(path: "p"), other = root.appending(path: "q")
        for d in [support, config.appending(path: "projects"), proj.appending(path: "tasks"), other] { try tfm.createDirectory(at: d, withIntermediateDirectories: true) }
        try Data("# p\n".utf8).write(to: proj.appending(path: "PROJECT.md"))
        try Data("# q\n".utf8).write(to: other.appending(path: "PROJECT.md"))
        let saved = ["DUO_SUPPORT_DIR", "CLAUDE_CONFIG_DIR"].map { k in (k, ProcessInfo.processInfo.environment[k]) }
        setenv("DUO_SUPPORT_DIR", support.path, 1)
        setenv("CLAUDE_CONFIG_DIR", config.path, 1)
        defer {
            for (k, v) in saved { if let v { setenv(k, v, 1) } else { unsetenv(k) } }
            try? tfm.removeItem(at: root)
        }
        let quiet = "aaaaaaaa-0000-4000-8000-000000000001", busy = "aaaaaaaa-0000-4000-8000-000000000002"
        // The quiet session has a transcript on disk, filed the way Claude files it, so it can be deleted.
        let bucket = config.appending(path: "projects/" + ClaudeStorage.encode(proj.path))
        try tfm.createDirectory(at: bucket, withIntermediateDirectories: true)
        try Data("{\"type\":\"user\",\"cwd\":\"\(proj.path)\",\"sessionId\":\"\(quiet)\"}\n".utf8).write(to: bucket.appending(path: "\(quiet).jsonl"))
        let links = [TaskNotes.link(title: "Quiet one", id: quiet), TaskNotes.link(title: "Busy one", id: busy)]
        func write(_ name: String) throws -> String {
            try Data(TaskNotes.newNote(title: name, links: links).utf8).write(to: proj.appending(path: "tasks/\(TaskNotes.slug(name)).md"))
            return "tasks/\(TaskNotes.slug(name)).md"
        }
        var fx = f
        fx.projects.append(decoded(["name": "tasky", "topic": "Platform", "path": proj.path, "goal": "g"]))
        fx.projects.append(decoded(["name": "elsewhere", "topic": "Platform", "path": other.path, "goal": "g"]))
        fx.sessions += [decoded(["name": "Quiet one", "project": "tasky", "state": "idle", "sessionId": quiet]),
                        decoded(["name": "Busy one", "project": "tasky", "state": "working", "sessionId": busy])]
        let m = AppModel(fixture: fx)
        m.terminalsMode = .live
        m.liveFolders["tasky"] = proj
        m.liveFolders["elsewhere"] = other
        m.liveElsewhere = [busy]   // running in another app
        var undos: [(String, @MainActor (AppModel) -> Void)] = []
        m.undoRecorder = { name, u in undos.append((name, u)) }
        func undoLast() { if let u = undos.popLast() { u.1(m) } }
        func archivedIds() -> Set<String> { Set(DuoState.load().archivedSessions) }

        // Rename: title, heading, file; one undo puts both back.
        var path = try write("Exec review prep")
        guard case .success(let newPath) = m.renameTask(project: "tasky", path: path, to: "Board prep") else { check(false, "Rename worked"); return }
        let afterRename = m.loadTask("tasky", newPath)
        check(newPath == "tasks/board-prep.md" && afterRename?.title == "Board prep" && !tfm.fileExists(atPath: proj.appending(path: path).path),
              "Rename retitles the note and moves it to tasks/board-prep.md")
        undoLast()
        check(m.loadTask("tasky", path)?.title == "Exec review prep" && !tfm.fileExists(atPath: proj.appending(path: newPath).path), "undo puts the name and the file back")

        // A name changed in the note (as the editor or an agent would) moves the file on the next refresh.
        m.fixture.tasks = [.init(project: "tasky", path: path, title: "Exec review prep", status: "open", sessionIds: [quiet, busy])]
        m.followTaskTitles()   // first look: remembers
        let text = try String(contentsOf: proj.appending(path: path), encoding: .utf8)
        try Data(TaskNotes.renaming(to: "Exec review final", in: text).utf8).write(to: proj.appending(path: path))
        m.fixture.tasks = [.init(project: "tasky", path: path, title: "Exec review final", status: "open", sessionIds: [quiet, busy])]
        m.followTaskTitles()
        check(tfm.fileExists(atPath: proj.appending(path: "tasks/exec-review-final.md").path) && !tfm.fileExists(atPath: proj.appending(path: path).path),
              "retitling the note moves it to its new slug once settled (C-24)")
        path = "tasks/exec-review-final.md"
        m.fixture.tasks = nil

        // Archive, sessions kept.
        guard case .success = m.archiveTask(project: "tasky", path: path, sessions: false) else { check(false, "Archive worked"); return }
        check(m.loadTask("tasky", path)?.archived == true && archivedIds().isEmpty, "Archive Task Only marks the note archived and leaves its sessions")
        undoLast()
        check(m.loadTask("tasky", path)?.archived == false, "undo unarchives it")

        // Archive with sessions: the quiet one goes, the running one stays; one undo for all.
        let undoCount = undos.count
        guard case .success(let skipped) = m.archiveTask(project: "tasky", path: path, sessions: true) else { check(false, "Archive with sessions worked"); return }
        check(m.loadTask("tasky", path)?.archived == true && archivedIds() == [quiet] && skipped == ["Busy one"],
              "Archive Task and Its Sessions archives the quiet session and never the running one")
        check(undos.count == undoCount + 1, "it's one undo step")
        undoLast()
        check(m.loadTask("tasky", path)?.archived == false && archivedIds().isEmpty, "one undo brings the task and its session back")

        // Unarchive brings back the sessions archived with it.
        _ = m.archiveTask(project: "tasky", path: path, sessions: true)
        m.fixture.archivedSessions = m.fixture.sessions.filter { $0.sessionId == quiet }
        check(m.unarchiveTask(project: "tasky", path: path) == nil && m.loadTask("tasky", path)?.archived == false && archivedIds().isEmpty,
              "Unarchive Task brings back the task and the sessions archived with it")
        m.fixture.archivedSessions = nil

        // Copy Link: an id is written once; the link opens the task wherever it is.
        let link = m.taskLink(project: "tasky", path: path)
        let id = m.loadTask("tasky", path)?.id
        check(id != nil && link == "[Exec review final](duo2://task/\(id!))" && m.taskLink(project: "tasky", path: path) == link, "Copy Link writes id: once and links duo2://task/<id>")

        // Move, sessions kept, then with sessions; undo puts the note back.
        guard case .success(let moved) = m.moveTask(project: "tasky", path: path, to: "elsewhere", sessions: false) else { check(false, "Move worked"); return }
        check(moved == "elsewhere/tasks/exec-review-final.md" && tfm.fileExists(atPath: other.appending(path: path).path)
              && SessionIndex.load(project: other).sessions.isEmpty, "Move Task Only moves the note, not its sessions")
        check(m.findTask(id!, project: nil) == nil && TaskNotes.load(project: other).first?.id == id, "its id (and so its link) moves with it")
        undoLast()
        check(tfm.fileExists(atPath: proj.appending(path: path).path) && !tfm.fileExists(atPath: other.appending(path: path).path), "undo moves it back")
        _ = m.moveTask(project: "tasky", path: path, to: "elsewhere", sessions: true)
        check(Set(SessionIndex.load(project: other).sessions.map(\.sessionId)) == [quiet, busy], "Move Task and Its Sessions files its sessions in the other project")
        undoLast()
        check(tfm.fileExists(atPath: proj.appending(path: path).path) && SessionIndex.load(project: other).sessions.isEmpty, "one undo moves the note and its sessions back")

        // Delete, sessions kept: the note goes to the Trash; undo brings it back.
        guard case .success = m.deleteTask(project: "tasky", path: path, sessions: false) else { check(false, "Delete worked"); return }
        check(!tfm.fileExists(atPath: proj.appending(path: path).path) && tfm.fileExists(atPath: bucket.appending(path: "\(quiet).jsonl").path),
              "Delete Task Only trashes the note and keeps its sessions")
        undoLast()
        check(tfm.fileExists(atPath: proj.appending(path: path).path), "undo brings the note back from the Trash")

        // Delete with sessions: the quiet one's transcript goes; the running one is never deleted.
        guard case .success(let said) = m.deleteTask(project: "tasky", path: path, sessions: true) else { check(false, "Delete with sessions worked"); return }
        check(!tfm.fileExists(atPath: proj.appending(path: path).path) && !tfm.fileExists(atPath: bucket.appending(path: "\(quiet).jsonl").path)
              && said.contains("Deleted 1 session: Quiet one") && said.contains("Kept Busy one"),
              "Delete Task and Its Sessions deletes the quiet session and keeps the running one (\(said))")
        undoLast()
        check(tfm.fileExists(atPath: proj.appending(path: path).path), "undo still brings the note back (deleted sessions stay deleted)")

        // The questions, answered by default in a scripted run: Archive's default takes the sessions,
        // Delete's keeps them (board C).
        setenv("DUO_AUTOCONFIRM", "1", 1)
        defer { unsetenv("DUO_AUTOCONFIRM") }
        var answer = ""
        m.askArchiveTask(project: "tasky", path: path) { answer = $0 }
        check(answer.hasPrefix("Archived Exec review final") && m.loadTask("tasky", path)?.archived == true, "Archive's default answer archives the task (\(answer))")
        undoLast()
        m.askDeleteTask(project: "tasky", path: path) { answer = $0 }
        check(answer == "Moved Exec review final to the Trash." , "Delete's default is Delete Task Only (\(answer))")
    }
}

do { try MainActor.assumeIsolated { try run() } } catch { print("✘ setup: \(error)"); failures += 1 }
print("\(passes) passed, \(failures) failed")
exit(Int32(failures))


/// Runs async work from the synchronous checks.
func blocking<T: Sendable>(_ work: @escaping @Sendable () async throws -> T) throws -> T {
    let sem = DispatchSemaphore(value: 0)
    nonisolated(unsafe) var result: Result<T, Error>!
    Task.detached { do { result = .success(try await work()) } catch { result = .failure(error) }; sem.signal() }
    sem.wait()
    return try result.get()
}

/// .gitignore rules from text, applied to one path (checks only).
func GitIgnore_ignored(_ rel: String, rules text: String) -> Bool {
    let dir = FileManager.default.temporaryDirectory.appending(path: "gi-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try? text.write(to: dir.appending(path: ".gitignore"), atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: dir) }
    // Lay the path out on disk and ask FileSource whether it would be indexed.
    let file = dir.appending(path: rel)
    try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? "x".write(to: file, atomically: true, encoding: .utf8)
    return !FileSource.files(in: dir).contains { $0.relative == rel }
}

extension URL {
    /// Creates the parent folder and returns self (checks only).
    func creatingParent() -> URL {
        try? FileManager.default.createDirectory(at: deletingLastPathComponent(), withIntermediateDirectories: true)
        return self
    }
}

/// A snapshot context that ignores this Mac's real Claude history.
func noHistory(_ root: URL) -> LiveSnapshot.Context {
    var c = LiveSnapshot.Context(root: root)
    c.includeHistory = false
    return c
}


func repoRoot() -> URL {
    URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
}

/// Labels and clicks in the app's views that aren't tied to an action (DL-71). Buttons, menus and
/// menu items are matched by label against the registry's `ui` and `Parity.uiOnly`; clicks and
/// drags (`.onActivate {`, `.onDrag`, `.onDrop`) must say `// action: <verb>` on the same line.
func parityGaps() -> [String] {
    let known = Set(DuoAction.all.flatMap(\.ui)).union(Parity.uiOnly.keys)
    var gaps: [String] = []
    for c in DuoCommand.allCases where !known.contains(c.title) { gaps.append("menu \(c.title)") }
    let dir = repoRoot().appending(path: "Sources/DuoKit")
    let files = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil)?.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []
    for file in files where !file.path.contains("/Debug/") {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
        for (n, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let l = String(line)
            if l.trimmingCharacters(in: .whitespaces).hasPrefix("//") { continue }
            for m in l.matches(of: /(?:Button|Menu|ActionMenuItem)\("((?:[^"\\]|\\.)+)"/) {
                let label = String(m.1).replacing(/\\\([^)]*\)/, with: "").replacing(/\s+/, with: " ")
                    .trimmingCharacters(in: CharacterSet(charactersIn: " :"))
                if !known.contains(label) { gaps.append("\(file.lastPathComponent):\(n + 1) \"\(label)\"") }
            }
            if l.contains(".onActivate {") || l.contains(".onDrag {") || l.contains(".onDrag(") || l.contains(".onDrop(") {
                // A click that only changes the view (a fold, a clamp) says why it has no verb.
                if l.contains("// not an action:") { continue }
                if let m = l.firstMatch(of: /\/\/ action: ([a-z -]+)/), DuoAction.resolve(String(m.1).trimmingCharacters(in: .whitespaces).split(separator: " ").map(String.init)) != nil { continue }
                gaps.append("\(file.lastPathComponent):\(n + 1) click or drag without `// action: <verb>`")
            }
        }
    }
    return gaps
}
