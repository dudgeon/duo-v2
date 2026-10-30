import Foundation

/// Several sessions selected in one list (DL-247, session-multiselect-handoff): ⇧-click selects a range
/// from the anchor, ⌘-click adds or removes one row, a plain click opens and clears. Modified clicks never
/// open, resume or change the console. The selection holds session keys (`tabKey`) only.
public struct SessionSelection: Equatable, Sendable {
    /// What the click carried.
    public enum Click: Sendable { case plain, shift, command }

    /// Which list the selection is in ("project:<name>", "list", "action", "idle"); another list's click starts over.
    public private(set) var list: String = ""
    /// The selected sessions, in the order they were added.
    public private(set) var keys: [String] = []
    /// The row the next ⇧-click ranges from: the last plain- or ⌘-clicked one.
    public private(set) var anchor: String?
    /// The selection before the current ⇧ range, so a new ⇧-click replaces that range (as in Finder).
    private var base: [String] = []

    public init() {}

    public var isEmpty: Bool { keys.isEmpty }
    public var count: Int { keys.count }
    public func contains(_ key: String) -> Bool { keys.contains(key) }
    /// Several selected: the selection's menu replaces the row's own.
    public func isMulti(_ key: String) -> Bool { keys.count > 1 && keys.contains(key) }

    /// A click on `key` in `list`, whose rows read `order` on screen (session keys; `SessionSelection.breaker`
    /// marks a row that isn't a session). Returns true when the row should open (a plain click).
    @discardableResult
    public mutating func click(_ key: String, _ click: Click, list: String, order: [String]) -> Bool {
        if list != self.list { self = SessionSelection(); self.list = list }
        switch click {
        case .plain:
            keys = []; base = []; anchor = key
            return true
        case .command:
            if let i = keys.firstIndex(of: key) { keys.remove(at: i) } else { keys.append(key) }
            base = keys; anchor = key
        case .shift:
            let sessions = order.filter { $0 != Self.breaker }
            guard let a = anchor, let from = sessions.firstIndex(of: a), let to = sessions.firstIndex(of: key) else {
                // No anchor showing (folded away, or none yet): the row alone, and it anchors.
                keys = base.contains(key) ? base : base + [key]; anchor = key
                return false
            }
            let range = Array(sessions[min(from, to)...max(from, to)])
            keys = base + range.filter { !base.contains($0) }
        }
        return false
    }

    /// Folded fork threads a modified click took in (DL-250): `threads` maps a folded thread's row key to its
    /// sessions, the original first. Each one taken in brings all its sessions into the selection (⌘-click or
    /// ⌘A: for keeps; ⇧: as part of the range). Returns the row keys whose threads should unfold.
    @discardableResult
    public mutating func takeInThreads(_ threads: [String: [String]]) -> [String] {
        var opened: [String] = []
        for (row, members) in threads.sorted(by: { $0.key < $1.key }) where keys.contains(row) {
            opened.append(row)
            let keep = base.contains(row)
            for m in members where !keys.contains(m) {
                keys.append(m)
                if keep { base.append(m) }
            }
        }
        return opened
    }

    /// ⌘A: every session row showing in `list`.
    public mutating func selectAll(list: String, order: [String]) {
        if list != self.list { self = SessionSelection(); self.list = list }
        keys = order.filter { $0 != Self.breaker }
        base = keys
        if anchor == nil || !keys.contains(anchor!) { anchor = keys.first }
    }

    /// Esc, a click on empty pane, after an action, another project.
    public mutating func clear() { keys = []; base = [] }

    /// Sessions that left the list (archived elsewhere, deleted, moved) leave the selection.
    public mutating func keepOnly(_ present: Set<String>) {
        keys.removeAll { !present.contains($0) }
        base.removeAll { !present.contains($0) }
    }

    /// `duo2 view select`: set, add to, or take from the selection directly.
    public mutating func set(_ new: [String], list: String, adding: Bool = false) {
        if list != self.list { self = SessionSelection(); self.list = list }
        keys = adding ? keys + new.filter { !keys.contains($0) } : new
        base = keys
        anchor = new.last ?? anchor
    }

    /// In `order`, a row that isn't a session (a fold row, a task line, a section label): ranges skip it, and it
    /// breaks a run of selected rows.
    public static let breaker = "\u{1}"

    /// How a selected row's fill joins its neighbours' (board 01, A): rounded at a run's ends only.
    public enum Run: Equatable, Sendable { case none, single, top, middle, bottom }

    public func run(_ key: String, order: [String]) -> Run {
        guard keys.contains(key), let i = order.firstIndex(of: key) else { return .none }
        let above = i > 0 && keys.contains(order[i - 1])
        let below = i + 1 < order.count && keys.contains(order[i + 1])
        switch (above, below) {
        case (false, false): return .single
        case (false, true): return .top
        case (true, true): return .middle
        case (true, false): return .bottom
        }
    }
}
