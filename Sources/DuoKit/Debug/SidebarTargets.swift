import Foundation

/// The sidebar-hierarchy handoff's boards as window states (DL-217, DL-218): the project's left pane on
/// board B's data (`sidebar-pane`, `-240`), the director's slot in its states (`sidebar-director-needs`,
/// `-notopen`, `-replaced`), Later opened with a done task (`sidebar-later-open`).
@MainActor
public enum SidebarTargets {
    nonisolated public static let screens = ["sidebar-pane", "sidebar-pane-240", "sidebar-director-needs", "sidebar-director-notopen",
                                             "sidebar-director-replaced", "sidebar-later-open"]

    static let project = "checkout-redesign"

    public static func apply(_ screen: String, to model: AppModel) {
        TargetState.project.apply(to: model)
        var f = model.fixture
        f.sessions.removeAll { $0.project == project }
        f.groups.removeAll { $0.project == project }
        f.tasks = (f.tasks ?? []).filter { $0.project != project }
        var prefs = ChatPrefs()
        func add(_ name: String, _ st: SessionState, _ wait: String, _ kind: ChatViewMode, archived: Bool = false, id: String? = nil) {
            var s = Fixture.Session(name: name, project: project, state: st, wait: wait)
            s.sessionId = id ?? name
            if archived { f.archivedSessions = (f.archivedSessions ?? []) + [s] } else { f.sessions.append(s) }
            prefs.modes[id ?? name] = kind
        }
        let lateOpen = screen == "sidebar-later-open"
        let directorState: SessionState = screen == "sidebar-director-needs" ? .needsYou : .working
        let notOpen = screen == "sidebar-director-notopen"
        add("director-checkout", notOpen ? .idle : directorState, screen == "sidebar-director-needs" ? "6m" : notOpen ? "3h" : "now", .terminal)
        if screen == "sidebar-director-replaced" { add("director-checkout", .idle, "2h", .terminal, id: "director-checkout-old") }
        if !lateOpen { add("Nightly order export", .idle, "5m", .terminal) }
        if !lateOpen { add("Pricing copy review", .needsYou, "4m", .chat) }
        add("Draft launch email", .working, "now", .chat)
        add("Segment list query", .idle, "3h", .terminal)
        add("Migrate Stripe webhooks", .readyForReview, "1h", .terminal)
        add("A/B test harness", .idle, "2m", .terminal)
        add("Autocomplete spike", .idle, "1h", .terminal)
        if !lateOpen { add("Fix flaky cart test", .working, "now", .terminal); add("Summarise user interviews", .idle, "9m", .chat) }
        add("Competitor teardown", .idle, "2h", .chat)
        add("Update README badges", .idle, "5h", .terminal)
        for (i, n) in ["Tax rules", "Checkout latency", "Cart abandonment"].enumerated() { add(n, .idle, "\(2 + i)d", i == 1 ? .chat : .terminal) }
        for i in 1...12 { add("Older session \(i)", .idle, "\(10 + i)d", .terminal) }
        for n in ["Old spike", "Vendor call notes", "Kickoff"] { add(n, .idle, "40d", .terminal, archived: true) }

        let day = 86400.0, now = Date().timeIntervalSince1970 * 1000
        func summary(_ title: String, _ path: String, _ members: [String], quietDays: Double, status: String = "open") -> Fixture.TaskSummary {
            var t = Fixture.TaskSummary(project: project, path: path, title: title, status: status, sessionIds: members)
            t.modified = now - quietDays * day * 1000
            return t
        }
        func slug(_ s: String) -> String { "tasks/" + s.lowercased().replacingOccurrences(of: " ", with: "-").replacingOccurrences(of: "/", with: "-") + ".md" }
        var tasks: [(String, [String], Double, String)] = [
            ("Launch email", lateOpen ? ["Draft launch email", "Segment list query"] : ["Pricing copy review", "Draft launch email", "Segment list query"], 0, "open"),
            ("Stripe migration", ["Migrate Stripe webhooks"], lateOpen ? 4 : 0, lateOpen ? "done" : "open"),
            ("Guest checkout A/B test", ["A/B test harness"], 0, "open"),
            ("Address autocomplete", ["Autocomplete spike"], 0, "open"),
            ("Fraud rule audit", [], 2, "open"),
        ]
        if lateOpen { tasks.removeAll { $0.0 == "Launch email" } }
        let quiet: [(String, Double)] = [("Tax engine upgrade", 5), ("Saved cards", 6), ("Apple Pay", 9), ("Receipt redesign", 12), ("Abandoned-cart emails", 14),
                                         ("Localise currency", 21), ("Accessibility audit", 22), ("Order history page", 30), ("Gift cards", 35),
                                         ("Refund flow copy", 65), ("Shipping estimates", 70)]
        for (title, members, days, status) in tasks {
            let path = slug(title)
            f.tasks = (f.tasks ?? []) + [summary(title, path, members, quietDays: days, status: status)]
            if !members.isEmpty { f.groups.append(Fixture.Group(name: title, project: project, sessions: members, threads: members.map { [$0] }, task: path)) }
        }
        for (title, days) in quiet { f.tasks = (f.tasks ?? []) + [summary(title, slug(title), [], quietDays: days)] }
        model.fixture = f
        model.chats.prefs = prefs
        model.videoTasks = true
        model.completingTasks = lateOpen ? ["\(project)/\(slug("Stripe migration"))"] : []
        model.fixtureActive = lateOpen ? ["director-checkout", "Draft launch email"]
            : notOpen ? ["Fix flaky cart test", "Summarise user interviews", "Draft launch email", "Nightly order export"]
            : ["director-checkout", "Nightly order export", "Fix flaky cart test", "Summarise user interviews", "Draft launch email"]
        if screen == "sidebar-director-replaced" { model.fixtureActive?.insert("director-checkout-old") }
        model.keepRunningIDs = notOpen ? ["Nightly order export"] : lateOpen ? ["director-checkout"] : ["director-checkout", "Nightly order export"]
        model.fixtureDirector = DirectorSlotInfo(sessionId: "director-checkout", workers: 2, workersNeedYou: 0,
                                                 replaced: screen == "sidebar-director-replaced" ? [.init(sessionId: "director-checkout-old", ago: "2h")] : [])
        model.selectedSidebarItem = "Competitor teardown"
        model.expandedGroups = lateOpen ? ["\(project)/later"] : ["Launch email", "Stripe migration", "Guest checkout A/B test", "Address autocomplete"]
        model.consoleTab = nil
        if screen == "sidebar-pane-240" { DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { FixtureHarness.perform("left-width:240", on: model) } }
    }
}
