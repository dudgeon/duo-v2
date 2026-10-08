import Foundation

/// A project's task board (DL-148, DL-150, `task-board-handoff/`): computed from the task notes
/// every time, nothing stored for it. A lane is a `status` value; a project's lanes are the brief's
/// `lanes:` list, or the default five. Order inside a lane is computed: a session that needs you
/// first, then due (soonest), then oldest created.
public enum TaskBoard {
    /// The lanes a project has until someone changes them (DL-150: absent means these).
    public static let defaultLanes = ["open", "in-progress", "waiting", "review", "done"]
    /// Lanes that can't be removed: new tasks start in Open, Mark Complete needs Done (board 12).
    public static let fixedLanes: Set<String> = ["open", "done"]
    /// Done shows tasks completed in the last week; older ones sit in an Earlier fold (board 8).
    public static let recentDays = 7

    /// A status as the board matches it (research doc §4 rule 4): trimmed, lowercased; missing is open.
    /// The file is never normalised.
    public static func key(_ status: String?) -> String {
        let s = (status ?? "").trimmingCharacters(in: .whitespaces).lowercased()
        return s.isEmpty ? "open" : s
    }

    /// A lane's name in its header: `in-progress` → `In progress`.
    public static func title(_ lane: String) -> String {
        let words = lane.replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " ")
        return words.prefix(1).uppercased() + words.dropFirst()
    }

    /// The status a new column's name becomes: its slug (Blocked → `blocked`, DL-150).
    public static func status(forColumn name: String) -> String? {
        guard name.rangeOfCharacter(from: .alphanumerics) != nil else { return nil }
        return TaskNotes.slug(name)
    }

    /// The project's lanes from its brief's `lanes:` list, cleaned (trimmed, lowercased, no
    /// repeats, never `dropped`); the default five when the key is absent or empty. Open and Done
    /// are kept even if the list leaves them out.
    public static func lanes(brief text: String?) -> [String] {
        guard let text else { return defaultLanes }
        var out: [String] = []
        for item in Frontmatter.parse(text).list("lanes") {
            let k = key(item)
            if k != "dropped", !out.contains(k) { out.append(k) }
        }
        if out.isEmpty { return defaultLanes }
        if !out.contains("open") { out.insert("open", at: 0) }
        if !out.contains("done") { out.append("done") }
        return out
    }

    /// One card: a task and what the board reads off it and its sessions.
    public struct Card: Sendable, Equatable, Identifiable {
        public var task: Fixture.TaskSummary
        /// The most urgent state among its linked sessions, if any is live.
        public var urgent: SessionState?
        public var id: String { task.id }
        public init(task: Fixture.TaskSummary, urgent: SessionState?) { self.task = task; self.urgent = urgent }
    }

    public struct Lane: Sendable, Equatable, Identifiable {
        public var status: String
        public var title: String
        public var cards: [Card]
        /// A status not in the project's lanes: shown at the end, with Keep as Column (DL-150).
        public var extra = false
        /// Done only: older than a week, and dropped tasks, as folds under the lane.
        public var earlier: [Card] = []
        public var dropped: [Card] = []
        public var id: String { status }
        /// The header's count (board 4): the cards shown; Earlier and Dropped count in their folds.
        public var count: Int { cards.count }
    }

    /// The board: one lane per project lane, then one per status found that isn't listed. Archived
    /// tasks never show (DL-115).
    public static func lanes(tasks: [Fixture.TaskSummary], lanes order: [String], state: (String) -> SessionState?, today: Date = Date()) -> [Lane] {
        let cards = tasks.filter { $0.archived != true }.map { t in
            Card(task: t, urgent: t.sessionIds.compactMap(state).filter { $0 != .resolved }.min())
        }
        var byLane: [String: [Card]] = [:]
        for c in cards { byLane[key(c.task.status), default: []].append(c) }
        var out = order.map { Lane(status: $0, title: title($0), cards: sorted(byLane[$0] ?? [])) }
        let extras = byLane.keys.filter { !order.contains($0) && $0 != "dropped" }.sorted()
        out += extras.map { Lane(status: $0, title: title($0), cards: sorted(byLane[$0] ?? []), extra: true) }
        if let d = out.firstIndex(where: { $0.status == "done" }) {
            let cutoff = Calendar(identifier: .gregorian).date(byAdding: .day, value: -recentDays, to: today) ?? today
            let all = byLane["done"] ?? []
            let isRecent: (Card) -> Bool = { c in c.task.completed.flatMap(day).map { $0 >= startOfDay(cutoff) } ?? true }
            out[d].cards = all.filter(isRecent).sorted(by: recentFirst)
            out[d].earlier = all.filter { !isRecent($0) }.sorted(by: recentFirst)
            out[d].dropped = (byLane["dropped"] ?? []).sorted(by: recentFirst)
        }
        return out
    }

    /// Needs you first, then due (soonest; none last), then oldest created, then title.
    public static func sorted(_ cards: [Card]) -> [Card] {
        cards.sorted { a, b in
            let an = a.urgent == .needsYou, bn = b.urgent == .needsYou
            if an != bn { return an }
            let ad = a.task.due.flatMap(day), bd = b.task.due.flatMap(day)
            if ad != bd { return ad.map { d in bd.map { d < $0 } ?? true } ?? false }
            let ac = a.task.created.flatMap(day), bc = b.task.created.flatMap(day)
            if ac != bc { return ac.map { c in bc.map { c < $0 } ?? true } ?? false }
            return a.task.title.localizedStandardCompare(b.task.title) == .orderedAscending
        }
    }

    /// Done and Dropped: the most recently completed first.
    static func recentFirst(_ a: Card, _ b: Card) -> Bool {
        let ad = a.task.completed.flatMap(day), bd = b.task.completed.flatMap(day)
        if ad != bd { return ad.map { d in bd.map { d > $0 } ?? true } ?? false }
        return a.task.title.localizedStandardCompare(b.task.title) == .orderedAscending
    }

    /// Where a card lands in a lane it's dragged to: its computed place (board 7's dashed slot).
    public static func slot(of card: Card, in lane: Lane) -> Int {
        let others = lane.cards.filter { $0.id != card.id }
        return sorted(others + [card]).firstIndex { $0.id == card.id } ?? others.count
    }

    // MARK: Dates

    /// A frontmatter date (`2026-10-10`, or a datetime starting with one), as a day.
    public static func day(_ s: String) -> Date? {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard t.count >= 10 else { return nil }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = .current
        return f.date(from: String(t.prefix(10)))
    }

    static func startOfDay(_ d: Date) -> Date { Calendar(identifier: .gregorian).startOfDay(for: d) }

    /// `Oct 10`: a card's dates (board 6).
    public static func short(_ s: String) -> String? {
        guard let d = day(s) else { return nil }
        let f = DateFormatter(); f.dateFormat = "MMM d"; f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: d)
    }

    /// Past due and not closed (board 6: the date in `text` semibold with "overdue").
    public static func overdue(_ t: Fixture.TaskSummary, today: Date = Date()) -> Bool {
        guard let d = t.due.flatMap(day), !["done", "dropped"].contains(key(t.status)) else { return false }
        return d < startOfDay(today)
    }

    // MARK: People

    /// A person or thing as written: `[[Sam Ortiz]]`, `[Sam Ortiz](people/sam.md)` or `Sam Ortiz`.
    public static func plain(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("[["), t.hasSuffix("]]") { t = String(t.dropFirst(2).dropLast(2)); t = t.split(separator: "|").last.map(String.init) ?? t }
        if let r = t.range(of: #"^\[(.*)\]\((.*)\)$"#, options: .regularExpression), r.lowerBound == t.startIndex,
           let close = t.range(of: "](") { t = String(t[t.index(after: t.startIndex)..<close.lowerBound]) }
        return t
    }

    /// The owner is you when it names you: your full name, your first name, or `me` (board 6 shows
    /// an owner only when it isn't you).
    public static func isYou(_ owner: String, user: String) -> Bool {
        let o = plain(owner).lowercased()
        let u = user.lowercased()
        return o.isEmpty || o == "me" || o == u || o == u.split(separator: " ").first.map(String.init)
    }
}

/// The project's brief (DL-147): `_PROJECT.md` for new projects, `PROJECT.md`, or a top-level note
/// marked `project_brief: true`. `lanes:` lives in whichever it is (DL-150).
public enum ProjectBrief {
    public static func url(in folder: URL) -> URL? {
        let fm = FileManager.default
        for name in ["_PROJECT.md", "PROJECT.md"] where fm.fileExists(atPath: folder.appending(path: name).path) {
            return folder.appending(path: name)
        }
        let notes = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        return notes.filter { $0.pathExtension.lowercased() == "md" }.sorted { $0.path < $1.path }.first { url in
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return false }
            return Frontmatter.parse(text).string("project_brief")?.lowercased() == "true"
        }
    }

    /// The brief's text with its `lanes:` list set to `lanes`, as a block list, touching nothing
    /// else: the key's lines are replaced where they are, or added before the closing fence.
    public static func settingLanes(_ lanes: [String], in text: String) -> String {
        TaskNotes.settingList("lanes", lanes, in: text)
    }
}

extension TaskNotes {
    /// The note with a block-list key set to `items` (plain, unquoted values), touching only its
    /// lines; added before the closing fence when absent.
    public static func settingList(_ key: String, _ items: [String], in text: String) -> String {
        let nl = text.contains("\r\n") ? "\r\n" : "\n"
        var lines = text.components(separatedBy: nl)
        let block = ["\(key):"] + items.map { "  - \($0)" }
        guard lines.first == "---", let close = lines.dropFirst().firstIndex(of: "---") else {
            return (["---"] + block + ["---"] + lines).joined(separator: nl)
        }
        if let k = (1..<close).first(where: { lines[$0].hasPrefix("\(key):") }) {
            var end = k + 1
            if lines[k].dropFirst(key.count + 1).trimmingCharacters(in: .whitespaces).isEmpty {
                while end < close, lines[end].hasPrefix("  - ") || lines[end].hasPrefix("- ") { end += 1 }
            }
            lines.replaceSubrange(k..<end, with: block)
        } else {
            lines.insert(contentsOf: block, at: close)
        }
        return lines.joined(separator: nl)
    }
}
