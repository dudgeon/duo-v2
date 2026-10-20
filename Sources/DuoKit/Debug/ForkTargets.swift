import Foundation

/// The fork-thread handoff's boards as window states (DL-227, DL-228): the thread after `/branch` (`fork-branch`, board 02),
/// after `/fork` (`fork-fork`, board 03), the same folded (`fork-folded`, board 01), in a task (`fork-task`), with a fork that
/// needs you (`fork-needs`), at 240 wide (`fork-branch-240`) and with many tabs, the fork mid-strip (`fork-tabs`, board 04).
@MainActor
public enum ForkTargets {
    nonisolated public static let screens = ["fork-branch", "fork-fork", "fork-folded", "fork-task", "fork-needs", "fork-branch-240", "fork-tabs"]

    static let project = "checkout-redesign"

    public static func apply(_ screen: String, to model: AppModel) {
        TargetState.project.apply(to: model)
        var f = model.fixture
        f.sessions.removeAll { $0.project == project }
        f.groups.removeAll { $0.project == project }
        f.tasks = (f.tasks ?? []).filter { $0.project != project }
        var prefs = ChatPrefs()
        func add(_ name: String, _ st: SessionState, _ wait: String, _ kind: ChatViewMode, id: String? = nil, fork: (of: String, kind: String)? = nil) {
            var s = Fixture.Session(name: name, project: project, state: st, wait: wait)
            s.sessionId = id ?? name
            if let fork { s.forkOf = fork.of; s.forkParent = fork.of; s.fork = fork.kind }
            f.sessions.append(s)
            prefs.modes[id ?? name] = kind
        }
        let task = screen == "fork-task", needs = screen == "fork-needs", fork = screen == "fork-fork", folded = screen == "fork-folded"
        let original = task ? "Pricing research" : needs ? "Rates study" : "Pricing research"
        let branch = original + " (Branch)"
        if needs { add("Rates study", .idle, "20m", .terminal); add(branch, .needsYou, "2m", .terminal, fork: (of: original, kind: "branch")) }
        else if fork { add(original, .working, "now", .terminal); add(original, .idle, "now", .terminal, id: "fork:\(original)", fork: (of: original, kind: "fork")) }
        else if task {
            add(original, .idle, "now", .terminal); add(branch, .working, "now", .terminal, fork: (of: original, kind: "branch"))
            add("Pricing research ", .idle, "now", .terminal, id: "fork2:Pricing research", fork: (of: original, kind: "fork"))
        } else { add(original, .idle, "now", .terminal); add(branch, .working, "now", .terminal, fork: (of: original, kind: "branch")) }
        if screen != "fork-tabs" || true { add("Fix flaky cart test", .working, "now", .chat) }
        if !task && !needs { add("Refund copy review", .needsYou, "4m", .chat) }
        add("Draft launch email", .idle, "2h", .chat)
        add("alpha", .idle, "3h", .terminal)
        if screen == "fork-tabs" { for n in ["Tax rules", "Checkout latency", "Cart abandonment", "Segment list query", "Nightly order export"] { add(n, .idle, "1h", .terminal) } }

        func summary(_ title: String, _ path: String, _ members: [String]) -> Fixture.TaskSummary {
            var t = Fixture.TaskSummary(project: project, path: path, title: title, status: "open", sessionIds: members)
            t.modified = Date().timeIntervalSince1970 * 1000
            return t
        }
        var tasks: [(String, String, [String])] = [("Launch email", "tasks/launch-email.md", ["Draft launch email"])]
        if task { tasks.insert(("Pricing page", "tasks/pricing-page.md", [original, branch, "Pricing research "]), at: 0) }
        for (title, path, members) in tasks {
            f.tasks = (f.tasks ?? []) + [summary(title, path, members)]
            f.groups.append(Fixture.Group(name: title, project: project, sessions: members, threads: LiveSnapshot.threads(members, in: f.sessions), task: path))
        }
        model.fixture = f
        model.chats.prefs = prefs
        model.videoTasks = true
        let open: [String] = task ? [original, branch, "fork2:Pricing research"] : fork ? [original, "fork:\(original)"] : needs ? ["Rates study", branch] : folded ? [original, branch] : [original, branch]
        model.fixtureActive = Set(open + ["Fix flaky cart test"])
        // The tabs Duo has open: an idle original has one too (a parked tab, as a restored session does).
        model.parkedTabs = Set(open)
        let selected = fork ? original : branch
        model.selectedSidebarItem = nil   // set below with the tab
        model.expandedGroups = Set((folded ? [] : ["\(project)/thread/\(original)"]) + ["Launch email"] + (task ? ["Pricing page"] : []))
        model.consoleTab = selected
        model.selectedSidebarItem = "\(project)/\(selected)"
        var order = [original, branch, "Fix flaky cart test", "alpha"]
        if fork { order = [original, "fork:\(original)", "Fix flaky cart test", "alpha"] }
        if screen == "fork-tabs" { order = ["Tax rules", "Checkout latency", original, branch, "Cart abandonment", "Segment list query", "Nightly order export", "Fix flaky cart test"] }
        model.consoleTabOrder[project] = order
        if screen == "fork-branch-240" { DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { FixtureHarness.perform("left-width:240", on: model) } }
    }
}
