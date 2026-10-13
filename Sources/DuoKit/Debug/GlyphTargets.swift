import Foundation

/// The session-glyphs handoff's boards as window states (`--state glyphs`, DL-174): the project's
/// left pane on board 02's sessions, every glyph (both kinds × idle, working, ready for review;
/// needs you; resolved), a task whose session waits, and a project with no tasks.
/// `glyphs-240` is the narrowest pane (`--then left-width:240`).
@MainActor
public enum GlyphTargets {
    nonisolated public static let screens = ["glyphs", "glyphs-240", "glyphs-notasks", "hierarchy", "hierarchy-240", "done-task", "done-task-open"]

    static let project = "checkout-redesign"

    public static func apply(_ screen: String, to model: AppModel) {
        TargetState.project.apply(to: model)
        if screen.hasPrefix("hierarchy") { return hierarchy(screen, to: model) }
        if screen.hasPrefix("done-task") { return doneTask(screen, to: model) }
        var f = model.fixture
        f.sessions.removeAll { $0.project == project }
        f.groups.removeAll { $0.project == project }
        f.tasks = (f.tasks ?? []).filter { $0.project != project }
        // (name, state, wait, kind). "Update README badges" idle and "Competitor teardown" idle are today's; the rest
        // are board 02's, plus one of each remaining state so every glyph is on screen.
        let rows: [(String, SessionState, String, ChatViewMode)] = [
            ("Pricing copy review", .needsYou, "4m", .chat),
            ("Migrate Stripe webhooks", .needsYou, "12m", .terminal),
            ("Fix flaky cart test", .working, "now", .terminal),
            ("Summarise user interviews", .readyForReview, "9m", .chat),
            ("Competitor teardown", .idle, "2h", .chat),
            ("Update README badges", .idle, "5h", .terminal),
            ("Rebuild search index", .working, "1h", .chat),
            ("Webhook retries", .readyForReview, "3h", .terminal),
        ]
        for (name, state, wait, _) in rows { f.sessions.append(.init(name: name, project: project, state: state, wait: wait == "now" ? "now" : wait)) }
        if screen != "glyphs-notasks" {
            let tasks: [(String, String, String, [(String, SessionState, String, ChatViewMode)])] = [
                ("Launch email", "tasks/launch-email.md", "open", [("Draft launch email", .working, "1m", .chat), ("Segment list query", .idle, "3h", .terminal)]),
                ("Refund policy", "tasks/refund-policy.md", "open", [("Refund policy research", .resolved, "2d", .terminal)]),
                ("Pricing page", "tasks/pricing-page.md", "in progress", [("Pricing page copy", .needsYou, "7m", .terminal), ("Pricing page layout", .idle, "1d", .chat)]),
            ]
            for (title, path, status, members) in tasks {
                for (n, s, w, _) in members { var x = Fixture.Session(name: n, project: project, state: s, wait: w); x.sessionId = n; f.sessions.append(x) }
                f.groups.append(.init(name: title, project: project, sessions: members.map(\.0), threads: members.map { [$0.0] }, task: path))
                f.tasks = (f.tasks ?? []) + [.init(project: project, path: path, title: title, status: status, sessionIds: members.map(\.0))]
            }
        }
        model.fixture = f
        // The kind each glyph draws: chat.json's modes, as the build reads them.
        var prefs = ChatPrefs()
        let all = rows + (screen == "glyphs-notasks" ? [] : [("Draft launch email", .working, "", .chat), ("Segment list query", .idle, "", .terminal),
                                                                ("Refund policy research", .resolved, "", .terminal), ("Pricing page copy", .needsYou, "", .terminal),
                                                                ("Pricing page layout", .idle, "", .chat)] as [(String, SessionState, String, ChatViewMode)])
        for (n, _, _, k) in all { prefs.modes[n] = k }
        model.chats.prefs = prefs
        model.videoTasks = true
        // Open in Duo (activeTint): the board's two OPEN rows; "Competitor teardown" is the selected one.
        model.fixtureActive = ["Fix flaky cart test", "Summarise user interviews", "Draft launch email"]
        model.selectedSidebarItem = "Competitor teardown"
        model.expandedGroups = ["Launch email", "Refund policy", "Pricing page"]
        model.consoleTab = nil
        if screen == "glyphs-240" { DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { FixtureHarness.perform("left-width:240", on: model) } }
    }
}

extension GlyphTargets {
    /// DL-187: board 04's hierarchy with "Stripe migration" done (its group folded under it; `done-task-open`
    /// has the user expand it) and a done task with no session, "Sign-off notes", still listed under TASKS.
    static func doneTask(_ screen: String, to model: AppModel) {
        hierarchy("hierarchy", to: model)
        var f = model.fixture
        if let i = f.tasks?.firstIndex(where: { $0.path == "tasks/stripe-migration.md" }) { f.tasks![i].status = "done" }
        f.tasks = (f.tasks ?? []) + [.init(project: project, path: "tasks/sign-off-notes.md", title: "Sign-off notes", status: "done", sessionIds: [])]
        model.fixture = f
        model.completingTasks.insert("\(project)/tasks/sign-off-notes.md")   // listed, as it is while Mark Complete holds
        model.expandedGroups = screen == "done-task-open" ? ["Launch email", "Stripe migration"] : ["Launch email"]
    }
}

extension GlyphTargets {
    /// Board 04: NEEDS YOU, TASKS (Launch email with the waiting session's hand, Stripe migration), OTHER SESSIONS
    /// (Open 2, Today 2, This week 3, Earlier 12 folded) and Archived 3, on the board's data.
    static func hierarchy(_ screen: String, to model: AppModel) {
        var f = model.fixture
        f.sessions.removeAll { $0.project == project }
        f.groups.removeAll { $0.project == project }
        f.tasks = (f.tasks ?? []).filter { $0.project != project }
        var prefs = ChatPrefs()
        func add(_ name: String, _ st: SessionState, _ wait: String, _ kind: ChatViewMode, archived: Bool = false) {
            var s = Fixture.Session(name: name, project: project, state: st, wait: wait)
            s.sessionId = name
            if archived { f.archivedSessions = (f.archivedSessions ?? []) + [s] } else { f.sessions.append(s) }
            prefs.modes[name] = kind
        }
        add("Pricing copy review", .needsYou, "4m", .chat)
        add("Draft launch email", .idle, "1m", .chat)
        add("Segment list query", .idle, "3h", .terminal)
        add("Migrate Stripe webhooks", .readyForReview, "1h", .terminal)
        add("Fix flaky cart test", .working, "now", .terminal)
        add("Summarise user interviews", .readyForReview, "9m", .chat)
        add("Competitor teardown", .idle, "2h", .chat)
        add("Update README badges", .idle, "5h", .terminal)
        for (i, n) in ["Tax rules", "Checkout latency", "Cart abandonment"].enumerated() { add(n, .idle, "\(2 + i)d", i == 1 ? .chat : .terminal) }
        for i in 1...12 { add("Older session \(i)", .idle, "\(10 + i)d", .terminal) }
        for n in ["Old spike", "Vendor call notes", "Kickoff"] { add(n, .idle, "40d", .terminal, archived: true) }
        let tasks: [(String, String, [String])] = [
            ("Launch email", "tasks/launch-email.md", ["Pricing copy review", "Draft launch email", "Segment list query"]),
            ("Stripe migration", "tasks/stripe-migration.md", ["Migrate Stripe webhooks"]),
        ]
        for (title, path, members) in tasks {
            f.groups.append(Fixture.Group(name: title, project: project, sessions: members, threads: members.map { [$0] }, task: path))
            f.tasks = (f.tasks ?? []) + [.init(project: project, path: path, title: title, status: "open", sessionIds: members)]
        }
        model.fixture = f
        model.chats.prefs = prefs
        model.videoTasks = true
        model.fixtureActive = ["Fix flaky cart test", "Summarise user interviews"]
        model.selectedSidebarItem = "Competitor teardown"
        model.expandedGroups = ["Launch email", "Stripe migration"]
        model.consoleTab = nil
        if screen == "hierarchy-240" { DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { FixtureHarness.perform("left-width:240", on: model) } }
    }
}
