import Foundation

/// The session-glyphs handoff's boards as window states (`--state glyphs`, DL-174): the project's
/// left pane on board 02's sessions, every glyph (both kinds × idle, working, ready for review;
/// needs you; resolved), a task whose session waits, and a project with no tasks.
/// `glyphs-240` is the narrowest pane (`--then left-width:240`).
@MainActor
public enum GlyphTargets {
    nonisolated public static let screens = ["glyphs", "glyphs-240", "glyphs-notasks"]

    static let project = "checkout-redesign"

    public static func apply(_ screen: String, to model: AppModel) {
        TargetState.project.apply(to: model)
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
