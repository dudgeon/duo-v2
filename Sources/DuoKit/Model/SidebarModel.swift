import Foundation

/// A titled run of rows in a project's session list (DL-91). An empty title draws no label (the
/// Earlier fold labels itself).
public struct SidebarSection: Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var rows: [SidebarRow]
    public var needsYou = false

    /// The sessions the rows stand for: a thread counts its members (DL-228's boards read "OPEN · 3" for a thread and one more).
    public var sessionCount: Int {
        rows.reduce(0) { n, r in if case .thread(let c, _) = r.kind { return n + c } else { return n + 1 } }
    }

    public init(id: String, title: String, rows: [SidebarRow], needsYou: Bool = false) {
        self.id = id; self.title = title; self.rows = rows; self.needsYou = needsYou
    }
}

/// The session list inside a project (handoff §3.3, DL-24): groups of threads, threads folding
/// fork families, and plain sessions, sectioned by state.
public struct SidebarRow: Identifiable, Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case group(threads: [SidebarRow], sessionCount: Int)
        /// A fork family in one row; `count` is its sessions (shown when ≥ 2). `members` are the original first,
        /// then its forks oldest first (DL-228): the pane lists them when the thread is open.
        case thread(count: Int, members: [SidebarRow])
        case older(rows: [SidebarRow])
        case session
        /// A task with no session yet (DL-93): a line, in the TASKS order by its note's last change (DL-217).
        case taskLine
    }

    /// The director's slot (DL-218): a two-line row in PINNED.
    public enum Slot: Equatable, Sendable {
        /// The project's current director. `needsYou` and `open` are the session's; counts are its workers
        /// (and, in Home, the projects it directs in).
        case director(open: Bool, needsYou: Bool, workers: Int, workersNeedYou: Int, projects: Int?)
        /// A replaced director still open: `ago` is "2h" (since its replacement).
        case replaced(ago: String)
    }

    public var id: String
    public var name: String
    public var state: SessionState
    public var wait: String?
    public var kind: Kind
    /// For a task row (DL-93): the note's path in the project.
    public var task: String? = nil
    /// Set on the director's row and a replaced director's (DL-218).
    public var slot: Slot? = nil
    /// Keep Running is on (DL-217): the pin after the name.
    public var pinned = false
    /// For a task under Later: how long it's been quiet, "5d", "2w", "1mo" (DL-217).
    public var age: String? = nil
    /// A fork that left its thread for NEEDS YOU says whose fork it is on a second line (DL-228).
    public var forkOf: String? = nil
    /// A session that is a fork wears the mark where a row shows one (Q-229); nil for an original.
    public var isFork = false
    /// Show "Fork of ‹original›" under the name: a fork that left its thread for NEEDS YOU (DL-228).
    public var showsOrigin = false

    public init(id: String, name: String, state: SessionState, wait: String?, kind: Kind, task: String? = nil) {
        self.id = id; self.name = name; self.state = state; self.wait = wait; self.kind = kind; self.task = task
    }

    /// The session a row stands for (its id when live, else its name): rows are keyed by identity.
    public var sessionKey: String { id.components(separatedBy: "/thread/").last ?? name }

    /// Builds the rows for one project's sessions, most urgent first within each state.
    public static func rows(for project: String, in fixture: Fixture) -> [SidebarRow] {
        let sessions = fixture.sessions(inProject: project)
        func session(named name: String) -> Fixture.Session? { sessions.first { $0.name == name } }

        /// Rows are keyed by session identity (id when live, else name): live sessions can share a
        /// name ("New session"), and keying by name folded them into a false thread (F-43).
        func threadRow(_ members: [Fixture.Session]) -> SidebarRow? {
            guard let lead = leader(members) else { return nil }
            guard members.count >= 2 else { return SidebarRow(id: "\(project)/thread/\(lead.tabKey)", name: lead.name, state: lead.state, wait: lead.wait, kind: .session) }
            // The original first, then the forks, oldest first (DL-228); the row keeps the original's name.
            let order = ForkThread.ordered(members.map { (key: $0.tabKey, parent: parentKey(of: $0, in: members)) })
            let ordered = order.compactMap { k in members.first { $0.tabKey == k } }
            let rows = ordered.enumerated().map { i, m -> SidebarRow in
                var r = SidebarRow(id: "\(project)/thread/\(m.tabKey)", name: m.name, state: m.state, wait: m.wait, kind: .session)
                r.isFork = i > 0
                r.forkOf = i > 0 ? ordered[0].name : nil
                return r
            }
            return SidebarRow(id: "\(project)/thread/\(ordered[0].tabKey)", name: ordered[0].name, state: lead.state, wait: lead.wait,
                              kind: .thread(count: members.count, members: rows))
        }

        var grouped = Set<String>()   // tabKeys
        var rows: [SidebarRow] = []
        for g in fixture.groups where g.project == project {
            let threads = g.threads.map { $0.compactMap(session(named:)) }.compactMap(threadRow).sorted(by: urgency)
            guard let lead = threads.first else { continue }
            grouped.formUnion(g.sessions.compactMap { session(named: $0)?.tabKey })
            rows.append(SidebarRow(id: "\(project)/\(g.task == nil ? "group" : "task")/\(g.name)", name: g.name, state: lead.state, wait: lead.wait,
                                   kind: .group(threads: threads, sessionCount: g.sessions.count), task: g.task))
        }
        // Fork families outside groups fold too: a session and the sessions forked from it.
        let loose = sessions.filter { !grouped.contains($0.tabKey) }
        var seen = Set<String>()
        for s in loose where !seen.contains(s.tabKey) {
            let family = loose.filter { $0.tabKey == s.tabKey || ($0.forkOf != nil && $0.forkOf == s.name) || (s.forkOf != nil && s.forkOf == $0.name) }
            seen.formUnion(family.map(\.tabKey))
            if let row = threadRow(family) { rows.append(row) }
        }
        var sorted = rows.sorted(by: urgency)
        // DL-59: every past session is listed; beyond the five most recent idle ones they fold
        // under "Older · N" so the list stays short.
        let idle = sorted.filter { $0.state == .idle }
        if idle.count > 7 {
            let older = Array(idle.dropFirst(5))
            let olderIDs = Set(older.map(\.id))
            sorted.removeAll { olderIDs.contains($0.id) }
            sorted.append(SidebarRow(id: "\(project)/older", name: "Older", state: .idle, wait: nil, kind: .older(rows: older)))
        }
        return sorted
    }

    /// The pane's hierarchy (DL-217, DL-218; it amends DL-174's): PINNED (the director's slot, then the Keep
    /// Running sessions), NEEDS YOU, OPEN (open sessions in no task), TASKS (in play, then Later), OTHER
    /// SESSIONS (Today, This week, Earlier). A session in a task that is pinned or waiting leaves it for
    /// its section; the task row still counts it and keeps its state. Section ids: pinned, needs, open,
    /// tasks, later, today, week, earlier; an empty section isn't listed.
    public static func sections(for project: String, in fixture: Fixture, isOpen: (String) -> Bool,
                                isPinned: (String) -> Bool = { _ in false }, director: DirectorSlotInfo? = nil,
                                listedTask: (Fixture.TaskSummary) -> Bool = { $0.isOpen },
                                now: Date = Date(), calendar: Calendar = .current) -> [SidebarSection] {
        let all = rows(for: project, in: fixture).flatMap { r -> [SidebarRow] in
            if case .older(let rows) = r.kind { return rows } else { return [r] }
        }
        func open(_ r: SidebarRow) -> Bool {
            if case .group(let threads, _) = r.kind { return threads.contains { open($0) } }
            if case .thread(_, let members) = r.kind { return members.contains { isOpen($0.sessionKey) } }   // placed by its liveliest member
            return isOpen(r.sessionKey)
        }
        /// The row for a session that goes to PINNED: the director's slot, a replaced director's, or a kept session.
        func slotted(_ r: SidebarRow) -> (row: SidebarRow, rank: Int)? {
            var r = r
            if let d = director, r.sessionKey == d.sessionId {
                r.slot = .director(open: isOpen(r.sessionKey), needsYou: r.state == .needsYou, workers: d.workers,
                                   workersNeedYou: d.workersNeedYou, projects: d.projects)
                r.pinned = isPinned(r.sessionKey)
                return (r, 0)
            }
            if let old = director?.replaced.first(where: { $0.sessionId == r.sessionKey }), isOpen(r.sessionKey) {
                r.slot = .replaced(ago: old.ago)
                r.pinned = isPinned(r.sessionKey)
                return (r, 1)
            }
            if isPinned(r.sessionKey) { r.pinned = true; return (r, 2) }
            return nil
        }
        var pinned: [(row: SidebarRow, rank: Int)] = [], needs: [SidebarRow] = [], groups: [SidebarRow] = [], rest: [SidebarRow] = []
        for r in all {
            if r.task != nil, case .group(let threads, let n) = r.kind {
                // A pinned session goes up to PINNED, a waiting one to NEEDS YOU; the task row keeps its (most urgent) state.
                var staying: [SidebarRow] = []
                for t in threads {
                    if let p = slotted(t) { pinned.append(p); continue }
                    let (stay, leave) = splitNeeds(t)
                    needs += leave
                    if let stay { staying.append(stay) }
                }
                var t = r
                t.kind = .group(threads: staying, sessionCount: n)
                groups.append(t)
            } else if let p = slotted(r) {
                pinned.append(p)
            } else if r.state == .needsYou || { if case .thread = r.kind { return true } else { return false } }() {
                let (stay, leave) = splitNeeds(r)
                needs += leave
                if let stay { rest.append(stay) }
            } else {
                rest.append(r)
            }
        }
        pinned.sort { $0.rank != $1.rank ? $0.rank < $1.rank : WaitTime($0.row.wait) < WaitTime($1.row.wait) }
        needs.sort(by: urgency)
        let opened = rest.filter(open).sorted(by: urgency)
        let past = rest.filter { !open($0) }.sorted { WaitTime($0.wait) < WaitTime($1.wait) }
        let sinceMidnight = Int(now.timeIntervalSince(calendar.startOfDay(for: now)))
        let today = past.filter { WaitTime($0.wait).seconds <= sinceMidnight }
        let week = past.filter { WaitTime($0.wait).seconds > sinceMidnight && WaitTime($0.wait).seconds <= 7 * 86400 }
        let earlier = past.filter { WaitTime($0.wait).seconds > 7 * 86400 }

        // TASKS: in play first, then Later (DL-217).
        let summaries = (fixture.tasks ?? []).filter { $0.project == project }
        let members = Dictionary(fixture.groups.filter { $0.project == project }.map { ("\(project)/task/\($0.name)", $0.sessions) }, uniquingKeysWith: { a, _ in a })
        let listedSessions = Set(fixture.sessions(inProject: project).compactMap(\.sessionId))
        for t in summaries where listedTask(t) && !t.sessionIds.contains(where: listedSessions.contains) && !groups.contains(where: { $0.task == t.path }) {
            groups.append(SidebarRow(id: "\(project)/taskline/\(t.path)", name: t.title, state: .idle, wait: nil, kind: .taskLine, task: t.path))
        }
        struct Placed { var row: SidebarRow; var quiet: Int; var live: Bool; var done: Bool }
        var inPlay: [Placed] = [], later: [Placed] = []
        for var r in groups {
            let summary = summaries.first { $0.path == r.task }
            var quiet = Int.max, live = r.state == .needsYou || r.state == .working
            for name in members[r.id] ?? [] {
                guard let s = fixture.sessions(inProject: project).first(where: { $0.name == name }) else { continue }
                quiet = min(quiet, s.state == .working ? 0 : WaitTime(s.wait).seconds)
                if isOpen(s.tabKey) || s.state == .working || s.state == .needsYou { live = true }
            }
            if let m = summary?.modified { quiet = min(quiet, max(0, Int(now.timeIntervalSince1970 - m / 1000))) }
            if quiet == Int.max { quiet = 0 }   // no dates at all (the design fixture): just now
            let done = summary.map { $0.status == "done" } ?? false
            if case .taskLine = r.kind { r.wait = waitText(quiet) }
            let play = live || quiet <= inPlayDays * 86400
            r.age = play ? nil : age(quiet)
            let placed = Placed(row: r, quiet: quiet, live: live, done: done)
            if play { inPlay.append(placed) } else { later.append(placed) }
        }
        inPlay.sort { a, b in
            if a.done != b.done { return !a.done }
            return urgency(a.row, b.row)
        }
        later.sort { $0.quiet < $1.quiet }

        var out: [SidebarSection] = []
        if !pinned.isEmpty { out.append(.init(id: "pinned", title: "Pinned", rows: pinned.map(\.row))) }
        if !needs.isEmpty { out.append(.init(id: "needs", title: "Needs you", rows: needs, needsYou: true)) }
        if !opened.isEmpty { out.append(.init(id: "open", title: "Open", rows: opened)) }
        if !inPlay.isEmpty { out.append(.init(id: "tasks", title: "Tasks", rows: inPlay.map(\.row))) }
        if !later.isEmpty { out.append(.init(id: "later", title: "Later", rows: later.map(\.row))) }
        if !today.isEmpty { out.append(.init(id: "today", title: "Today", rows: today)) }
        if !week.isEmpty { out.append(.init(id: "week", title: "This week", rows: week)) }
        if !earlier.isEmpty { out.append(.init(id: "earlier", title: "Earlier", rows: earlier)) }
        return out
    }

    /// A task is in play while one of its sessions is live, or it ran or changed within this many days
    /// (DL-217; Q-203: one constant).
    public static let inPlayDays = 3

    /// "12m", "3h", "2d": the wait text of `seconds`.
    static func waitText(_ seconds: Int) -> String {
        seconds < 3600 ? "\(max(1, seconds / 60))m" : seconds < 86400 ? "\(seconds / 3600)h" : "\(seconds / 86400)d"
    }

    /// Later's age column: "5d", "2w", "1mo" (DL-217).
    static func age(_ seconds: Int) -> String {
        let d = seconds / 86400
        return d < 14 ? "\(d)d" : d < 28 ? "\(d / 7)w" : "\(max(1, d / 30))mo"
    }

    /// The section ids, in the order they are drawn.
    static let sectionOrder = ["pinned", "needs", "open", "tasks", "later", "today", "week", "earlier"]

    /// The sections as they stood when the pointer came into the list (Q-80, DL-130): while it's
    /// there, a row that was already listed keeps its section and place, so nothing moves under a
    /// click. Rows carry their fresh state (glyph, wait); a new row joins its own section; a row
    /// that's gone, goes. `order` is each section's row ids when the hold began.
    public static func held(_ fresh: [SidebarSection], order: [String: [String]]) -> [SidebarSection] {
        let byID = Dictionary(fresh.flatMap(\.rows).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let heldIDs = Set(order.values.joined())
        let template = Dictionary(fresh.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let titles = ["pinned": ("Pinned", false), "later": ("Later", false), "needs": ("Needs you", true), "tasks": ("Tasks", false), "open": ("Open", false), "today": ("Today", false),
                      "week": ("This week", false), "earlier": ("Earlier", false)]
        var out: [SidebarSection] = []
        for id in sectionOrder {
            var rows = (order[id] ?? []).compactMap { byID[$0] }
            // New rows join where the fresh list puts them, after the held rows before them.
            for (i, r) in (template[id]?.rows ?? []).enumerated() where !heldIDs.contains(r.id) {
                rows.insert(r, at: min(i, rows.count))
            }
            guard !rows.isEmpty else { continue }
            let t = titles[id] ?? (template[id]?.title ?? "", false)
            out.append(SidebarSection(id: id, title: template[id]?.title ?? t.0, rows: rows, needsYou: template[id]?.needsYou ?? t.1))
        }
        return out
    }

    /// The member whose state and wait a thread shows (DL-24, DL-228): the most urgent one; with every member quiet,
    /// the most recent, where it would be listed on its own.
    static func leader(_ sessions: [Fixture.Session]) -> Fixture.Session? {
        guard let best = mostUrgent(sessions) else { return nil }
        guard best.state == .idle || best.state == .resolved else { return best }
        return sessions.min { a, b in a.state != b.state ? a.state < b.state : WaitTime(a.wait) < WaitTime(b.wait) }
    }

    /// The parent's tab key, from its session id or its name (a fork family is linked by `forkOf`).
    static func parentKey(of s: Fixture.Session, in family: [Fixture.Session]) -> String? {
        if let p = s.forkParent, family.contains(where: { $0.tabKey == p }) { return p }
        return s.forkOf.flatMap { n in family.first { $0.name == n }?.tabKey }
    }

    /// A thread with members that need you: they leave it for NEEDS YOU, the rest stay as the thread (DL-228).
    /// A fork leaving says whose it is; the original says nothing. Nil `staying` when nothing is left.
    static func splitNeeds(_ r: SidebarRow) -> (staying: SidebarRow?, leaving: [SidebarRow]) {
        guard case .thread(_, let members) = r.kind else { return r.state == .needsYou ? (nil, [r]) : (r, []) }
        guard members.contains(where: { $0.state == .needsYou }) else { return (r, []) }
        let leaving = members.filter { $0.state == .needsYou }.map { m -> SidebarRow in var m = m; m.showsOrigin = m.forkOf != nil; return m }
        let rest = members.filter { $0.state != .needsYou }
        guard let lead = rest.min(by: urgency) else { return (nil, leaving) }
        var out = r
        out.state = lead.state; out.wait = lead.wait
        if rest.count == 1 { out.id = lead.id; out.name = lead.name; out.kind = .session; out.isFork = lead.isFork; out.forkOf = lead.forkOf }
        else {
            // The original may have left: the first row left leads, under its own name.
            out.kind = .thread(count: rest.count, members: rest)
            out.id = rest[0].id; out.name = rest[0].name
        }
        return (out, leaving)
    }

    static func mostUrgent(_ sessions: [Fixture.Session]) -> Fixture.Session? {
        sessions.min { a, b in a.state != b.state ? a.state < b.state : WaitTime(a.wait) > WaitTime(b.wait) }
    }

    /// Most urgent state first. Within needs you, review and working, the longest wait first (it's
    /// been waiting on you); within idle and resolved, the most recent first, so a session you just
    /// left is at the top and the Older fold holds the old ones (Geoff: a new session landed in Older).
    static func urgency(_ a: SidebarRow, _ b: SidebarRow) -> Bool {
        if a.state != b.state { return a.state < b.state }
        let quiet = a.state == .idle || a.state == .resolved
        return quiet ? WaitTime(a.wait) < WaitTime(b.wait) : WaitTime(a.wait) > WaitTime(b.wait)
    }
}

/// What the sidebar needs to know of the project's director (DL-218), worked out from
/// `.duo/director.json` by session id, never by name.
public struct DirectorSlotInfo: Equatable, Sendable {
    public struct Replaced: Equatable, Sendable {
        public var sessionId: String
        public var ago: String
        public init(sessionId: String, ago: String) { self.sessionId = sessionId; self.ago = ago }
    }
    public var sessionId: String
    public var workers = 0
    public var workersNeedYou = 0
    /// Home's director: how many projects it directs in (DL-197).
    public var projects: Int? = nil
    public var replaced: [Replaced] = []
    public init(sessionId: String, workers: Int = 0, workersNeedYou: Int = 0, projects: Int? = nil, replaced: [Replaced] = []) {
        self.sessionId = sessionId; self.workers = workers; self.workersNeedYou = workersNeedYou; self.projects = projects; self.replaced = replaced
    }
}
