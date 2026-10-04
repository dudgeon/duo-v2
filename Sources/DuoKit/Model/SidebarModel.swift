import Foundation

/// A titled run of rows in a project's session list (DL-91). An empty title draws no label (the
/// Earlier fold labels itself).
public struct SidebarSection: Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var rows: [SidebarRow]
    public var needsYou = false
}

/// The session list inside a project (handoff §3.3, DL-24): groups of threads, threads folding
/// fork families, and plain sessions, sectioned by state.
public struct SidebarRow: Identifiable, Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case group(threads: [SidebarRow], sessionCount: Int)
        /// A fork family folded into one row; `count` is its sessions (shown when ≥ 2).
        case thread(count: Int)
        case older(rows: [SidebarRow])
        case session
    }

    public var id: String
    public var name: String
    public var state: SessionState
    public var wait: String?
    public var kind: Kind

    /// The session a row stands for (its id when live, else its name): rows are keyed by identity.
    public var sessionKey: String { id.components(separatedBy: "/thread/").last ?? name }

    /// Builds the rows for one project's sessions, most urgent first within each state.
    public static func rows(for project: String, in fixture: Fixture) -> [SidebarRow] {
        let sessions = fixture.sessions(inProject: project)
        func session(named name: String) -> Fixture.Session? { sessions.first { $0.name == name } }

        /// Rows are keyed by session identity (id when live, else name): live sessions can share a
        /// name ("New session"), and keying by name folded them into a false thread (F-43).
        func threadRow(_ members: [Fixture.Session]) -> SidebarRow? {
            guard let lead = mostUrgent(members) else { return nil }
            return SidebarRow(id: "\(project)/thread/\(lead.tabKey)", name: lead.name, state: lead.state,
                              wait: lead.wait, kind: members.count >= 2 ? .thread(count: members.count) : .session)
        }

        var grouped = Set<String>()   // tabKeys
        var rows: [SidebarRow] = []
        for g in fixture.groups where g.project == project {
            let threads = g.threads.map { $0.compactMap(session(named:)) }.compactMap(threadRow).sorted(by: urgency)
            guard let lead = threads.first else { continue }
            grouped.formUnion(g.sessions.compactMap { session(named: $0)?.tabKey })
            rows.append(SidebarRow(id: "\(project)/group/\(g.name)", name: g.name, state: lead.state, wait: lead.wait,
                                   kind: .group(threads: threads, sessionCount: g.sessions.count)))
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

    /// The list as Geoff chose it (DL-91, Q-27 option A): what needs you, then what's open in Duo
    /// (a tab, whatever Claude is doing), then the rest as history by last use: Today, This week,
    /// and an Earlier fold. Archived sessions keep their own fold below (drawn by the view).
    public static func sections(for project: String, in fixture: Fixture, isOpen: (String) -> Bool,
                                now: Date = Date(), calendar: Calendar = .current) -> [SidebarSection] {
        let all = rows(for: project, in: fixture).flatMap { r -> [SidebarRow] in
            if case .older(let rows) = r.kind { return rows } else { return [r] }
        }
        func open(_ r: SidebarRow) -> Bool {
            if case .group(let threads, _) = r.kind { return threads.contains { isOpen($0.sessionKey) } }
            return isOpen(r.sessionKey)
        }
        let needs = all.filter { $0.state == .needsYou }.sorted(by: urgency)
        let opened = all.filter { $0.state != .needsYou && open($0) }.sorted(by: urgency)
        let past = all.filter { $0.state != .needsYou && !open($0) }.sorted { WaitTime($0.wait) < WaitTime($1.wait) }
        let sinceMidnight = Int(now.timeIntervalSince(calendar.startOfDay(for: now)))
        let today = past.filter { WaitTime($0.wait).seconds <= sinceMidnight }
        let week = past.filter { WaitTime($0.wait).seconds > sinceMidnight && WaitTime($0.wait).seconds <= 7 * 86400 }
        let earlier = past.filter { WaitTime($0.wait).seconds > 7 * 86400 }
        var out: [SidebarSection] = []
        if !needs.isEmpty { out.append(.init(id: "needs", title: "Needs you", rows: needs, needsYou: true)) }
        if !opened.isEmpty { out.append(.init(id: "open", title: "Open", rows: opened)) }
        if !today.isEmpty { out.append(.init(id: "today", title: "Today", rows: today)) }
        if !week.isEmpty { out.append(.init(id: "week", title: "This week", rows: week)) }
        if !earlier.isEmpty {
            out.append(.init(id: "earlier", title: "", rows: [SidebarRow(id: "\(project)/earlier", name: "Earlier", state: .idle, wait: nil, kind: .older(rows: earlier))]))
        }
        return out
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
