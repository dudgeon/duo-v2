import Foundation

/// The home-evolution-handoff targets as window states (`--state list-1440`, DL-142): All projects
/// with the List or the Board in the middle, on the boards' sessions. `list-1280` is captured with
/// `WINDOW=1280x800`.
@MainActor
public enum HomeListTargets {
    nonisolated public static let screens = ["list-1440", "list-1280", "board-1440"]

    public static func apply(_ screen: String, to model: AppModel) {
        TargetState.overview.apply(to: model)
        NarrowTargets.moreTopics(model)
        model.fixture = boardSessions(model.fixture, outsideFolder: screen != "board-1440")
        model.fixtureActive = Set(model.fixture.sessions.filter { open.contains($0.name) }.map(\.tabKey))
        model.homeView = screen == "board-1440" ? .board : .list
        // The boards' clock: late enough in the day that 5h ago is still Today.
        let cal = Calendar.current
        model.listClock = cal.date(bySettingHour: 18, minute: 0, second: 0, of: Date())
    }

    /// Open in Duo on the boards: three working, two at their prompt.
    static let open: Set<String> = ["Teardown research", "Edge-case matrix", "Rule audit", "Weekly status draft", "Fix footer links"]

    /// The boards' sessions (`list-1440`): the design fixture's, renamed and timed as drawn, with the
    /// tasks, the history and the archive the boards show.
    public static func boardSessions(_ base: Fixture, outsideFolder: Bool) -> Fixture {
        var f = base
        func set(_ name: String, state: SessionState? = nil, wait: String?, rename: String? = nil) {
            guard let i = f.sessions.firstIndex(where: { $0.name == name }) else { return }
            if let state { f.sessions[i].state = state }
            f.sessions[i].wait = wait
            if let rename {
                f.sessions[i].name = rename
                for g in f.groups.indices {
                    f.groups[g].sessions = f.groups[g].sessions.map { $0 == name ? rename : $0 }
                    f.groups[g].threads = f.groups[g].threads.map { $0.map { $0 == name ? rename : $0 } }
                }
            }
        }
        func add(_ name: String, _ project: String, _ wait: String, _ state: SessionState = .idle) {
            f.sessions.append(Fixture.Session(name: name, project: project, state: state, wait: wait))
        }
        set("Teardown research", wait: "40m")
        set("Edge-case matrix", wait: "20m")
        set("Rule audit", wait: "10m")
        set("Weekly status draft", state: .idle, wait: "2m")
        set("Results readout", wait: "25m")
        set("Funnel SQL", wait: "40m")
        set("Interview synth", wait: "2d", rename: "Checkout copy audit")
        set("quick q about tax rules", wait: "9d")
        if outsideFolder {
            f.topics.append("~/repos")
            f.projects.append(.init(name: "site", topic: "~/repos", path: "~/repos/site", goal: "", kind: "folder"))
            add("Fix footer links", "site", "1h")
        }
        add("Buyer synthesis", "buyer-interviews", "2h")
        add("Q4 plan outline", "q4-planning", "3h")
        add("Vendor shortlist", "vendor-review", "5h")
        add("Deprecation email", "api-deprecations", "3d")
        add("“Summarise the six buyer interviews”", "buyer-interviews", "4d")
        for (i, (name, project)) in [("Pricing page copy", "pricing-experiment-q4"), ("Refund states", "refunds-api-spec"),
                                      ("Fraud vendor calls", "vendor-review"), ("Q3 retro notes", "q4-planning"),
                                      ("Onboarding email tests", "onboarding-v3"), ("Old rules export", "fraud-rules-review"),
                                      ("Weekly status, Sept", "home"), ("API usage query", "api-deprecations")].enumerated() {
            add(name, project, "\(10 + i)d")
        }
        f.archivedSessions = [("Spike: guest wallet", "checkout-redesign"), ("Vendor RFP draft", "vendor-review"),
                              ("Legacy rules dump", "fraud-rules-review"), ("Q2 readout", "pricing-experiment-q4")]
            .enumerated().map { i, s in Fixture.Session(name: s.0, project: s.1, state: .idle, wait: "\(3 + i)w") }
        for (task, project, session) in [("Exec review prep", "checkout-redesign", "Teardown research"), ("Simplify rules", "fraud-rules-review", "Rule audit"),
                                         ("Q4 readout", "pricing-experiment-q4", "Results readout"), ("Synthesis memo", "buyer-interviews", "Buyer synthesis"),
                                         ("Draft plan", "q4-planning", "Q4 plan outline"), ("Sunset comms", "api-deprecations", "Deprecation email")] {
            f.groups.append(Fixture.Group(name: task, project: project, sessions: [session], threads: [[session]], task: "tasks/\(task.lowercased().replacingOccurrences(of: " ", with: "-")).md"))
        }
        f.tasks = [Fixture.TaskSummary(project: "checkout-redesign", path: "tasks/exec-review-prep.md", title: "Exec review prep", status: "in-progress", sessionIds: []),
                   Fixture.TaskSummary(project: "q4-planning", path: "tasks/draft-plan.md", title: "Draft plan", status: "open", sessionIds: []),
                   Fixture.TaskSummary(project: "checkout-redesign", path: "tasks/legal-review.md", title: "Legal review of saved cards", status: "waiting", sessionIds: [])]
        return f
    }
}
