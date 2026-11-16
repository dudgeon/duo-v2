import AppKit
import SwiftUI

// Actions on a chat turn (DL-338): a quiet row under the turn on hover. This file is the turn
// model (what a turn copies as, which turns can be acted on) and the row. Rewind and Fork come in
// their own files and plug into the same row.

/// What a turn puts on the clipboard (Q-509): the turn's words as Markdown.
public enum ChatTurnCopy {
    /// Yours as typed; each picture as `[Image #n]` (the transcript keeps the pictures apart from the text).
    public static func markdown(you: ChatYou) -> String {
        let pictures = you.images.indices.map { "[Image #\($0 + 1)]" }
        return (pictures + [you.text]).filter { !$0.isEmpty }.joined(separator: "\n")
    }

    /// Claude's text segments, trimmed and joined by a blank line; no thinking, tool calls or questions.
    public static func markdown(turn: ChatTurn) -> String {
        turn.segments.compactMap { seg -> String? in
            guard case .text(let t) = seg else { return nil }
            let s = t.markdown.trimmingCharacters(in: .whitespacesAndNewlines)
            return s.isEmpty ? nil : s
        }.joined(separator: "\n\n")
    }

    /// The item's copy text, nil for items that aren't a turn.
    public static func markdown(item: ChatItem) -> String? {
        switch item {
        case .you(let y): markdown(you: y)
        case .claude(let t): markdown(turn: t)
        default: nil
        }
    }
}

/// One of the buttons in a turn's row.
enum ChatTurnAction: String, CaseIterable {
    case copy = "Copy", rewind = "Rewind", fork = "Fork"
}

extension ChatSession {
    /// The actions a turn's row offers (board 1): Copy, Rewind, Fork under yours; Copy, Fork under Claude's.
    func turnActions(for id: String) -> [ChatTurnAction] {
        switch log.items.first(where: { $0.id == id }) {
        case .you?: (canRewind(id) ? [.copy, .rewind] : [.copy]) + (forkPlan(id) != nil ? [.fork] : [])
        case .claude?: [.copy] + (forkPlan(id) != nil ? [.fork] : [])
        default: []
        }
    }

    /// A turn still being written has no row.
    func turnIsFinished(_ id: String) -> Bool {
        guard let last = log.items.last else { return true }
        if last.id == id, case .claude(let t) = last {
            if screen.kind == .busy { return false }
            return !t.segments.contains { if case .text(let x) = $0 { return x.streaming } else { return false } }
        }
        return true
    }

    /// Copy the turn `id` (its row's Copy, the Chat menu, `duo2 session copy-turn`). False when there's nothing to copy.
    @discardableResult
    func copyTurn(_ id: String) -> Bool {
        guard let item = log.items.first(where: { $0.id == id }), let text = ChatTurnCopy.markdown(item: item), !text.isEmpty else { return false }
        FileActions.copy(text)
        ui.copiedTurn = id
        let stamp = Date()
        ui.copiedAt = stamp
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            if let self, self.ui.copiedAt == stamp { self.ui.copiedTurn = nil }
        }
        return true
    }
}

/// The row: 22 high buttons, radius 6, a 1 pt `controlEdge` edge on `pane`, a 12 icon in `text2` and the label (board 1).
struct ChatTurnRow: View {
    let turnId: String
    let actions: [ChatTurnAction]
    let chat: ChatSession

    var body: some View {
        HStack(spacing: 6) {
            ForEach(actions, id: \.self) { a in button(a) }
        }
        .frame(height: 22)
    }

    @ViewBuilder func button(_ a: ChatTurnAction) -> some View {
        let copied = a == .copy && chat.ui.copiedTurn == turnId
        let label = copied ? "Copied" : a.rawValue
        // Rewind and Fork wait while Claude works (board 1): dimmed, and "When Claude finishes" on hover.
        let dim = a != .copy && chat.screen.kind == .busy
        let icon = dim ? DuoColor.text2.opacity(0.55) : DuoColor.text2
        HStack(spacing: 5) {
            Group {
                if copied { CheckMark().stroke(icon, style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round)) }
                else if a == .fork { ChatForkMark().stroke(icon, style: StrokeStyle(lineWidth: 1.2, lineCap: .round)) }
                else if a == .rewind { RewindMark().stroke(icon, style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round)) }
                else { CopyMark().stroke(icon, style: StrokeStyle(lineWidth: 1.2, lineCap: .round)) }
            }.frame(width: 12, height: 12)
            Text(label).duoText(.chatMeta).foregroundStyle(dim ? DuoColor.text2 : DuoColor.text)
        }
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(RoundedRectangle(cornerRadius: DuoMetric.radiusControl).fill(DuoColor.pane))
        .overlay(RoundedRectangle(cornerRadius: DuoMetric.radiusControl).strokeBorder(dim ? DuoColor.rule : DuoColor.controlEdge, lineWidth: DuoMetric.borderHairline))
        .contentShape(Rectangle())
        .onActivate { if !dim { perform(a) } }  // action: session copy-turn
        .help(dim ? "When Claude finishes" : a.rawValue)
        .accessibilityLabel(a.rawValue)
    }

    func perform(_ a: ChatTurnAction) {
        switch a {
        case .copy: chat.copyTurn(turnId)  // action: session copy-turn
        case .rewind: chat.askRewind(turnId)  // action: session rewind
        case .fork: chat.askFork(turnId)  // action: session fork --at
        }
    }
}

/// The check that replaces Copy's icon for 1.5 s (board 2).
struct CheckMark: Shape {
    func path(in r: CGRect) -> Path {
        let s = r.width / 12
        var p = Path()
        p.move(to: .init(x: 2 * s, y: 6.5 * s)); p.addLine(to: .init(x: 4.8 * s, y: 9 * s)); p.addLine(to: .init(x: 10 * s, y: 3 * s))
        return p
    }
}

extension View {
    /// Shows the turn's row under it while the pointer is on the turn or the row (the row hangs below the turn, into the gap
    /// to the next one, so it moves nothing). The pointer is followed by the feed's `ChatTurnHover`, not by `onHover`: the row
    /// hangs outside the turn's frame, so `onHover` ended the hover in the 4 pt between turn and row and the row went before
    /// the pointer reached it (F-738). Each turn tells the feed its frame; a turn with a row owns the band under it too.
    func turnRow(id: String, chat: ChatSession, trailing: Bool, showRow: Bool = true, key: String? = nil) -> some View {
        let on = chat.ui.hoverTurn == id || chat.ui.selectedTurn == id
        let actions = showRow && on ? chat.turnActions(for: id) : []
        let show = !actions.isEmpty && chat.turnIsFinished(id)
        let key = key ?? id
        return self
            .overlay(alignment: trailing ? .bottomTrailing : .bottomLeading) {
                if show { ChatTurnRow(turnId: id, actions: actions, chat: chat).offset(y: ChatTurnHover.band) }
            }
            .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .named(ChatTurnHover.space)) }) { frame in
                chat.turnFrames.set(key, turn: id, frame: frame, row: showRow)
            }
            .onDisappear { chat.turnFrames.remove(key) }
            .zIndex(show ? 1 : 0)
    }
}

/// Where each turn of the feed is, in the feed's own space (it doesn't change as you scroll), and whether it carries the row.
@MainActor
final class ChatTurnFrames {
    struct Entry { var turn: String; var frame: CGRect; var row: Bool }
    private(set) var entries: [String: Entry] = [:]
    func set(_ key: String, turn: String, frame: CGRect, row: Bool) { entries[key] = Entry(turn: turn, frame: frame, row: row) }
    func remove(_ key: String) { entries[key] = nil }

    /// The turn under a point of the feed (F-738). A turn whose row can show owns the band under it down to the row's foot,
    /// so the pointer can go from the message to its buttons; where that band lies over the next turn, the turn already
    /// hovered keeps it (the row stays put while you're on it, and the next turn keeps its own top when you come up to it).
    func turn(at p: CGPoint, current: String?, hasRow: (String) -> Bool) -> String? {
        var hits: [String] = []
        for e in entries.values {
            var r = e.frame
            if e.row, hasRow(e.turn) { r.size.height += ChatTurnHover.band }
            if r.contains(p) { hits.append(e.turn) }
        }
        if let c = current, hits.contains(c) { return c }
        // Off the band, the turn's own frame wins over a band that reaches into it.
        return entries.values.first { $0.frame.contains(p) }?.turn ?? hits.first
    }
}

/// Follows the pointer over the feed and sets the turn under it (`hoverTurn`), from the frames the turns report: a mouse-moved
/// monitor, as `ChatLinkHover` does, so it works on the feed whatever is drawn over a turn (its row) and a scripted pointer can
/// drive it (`pointer:` in the harness).
struct ChatTurnHover: NSViewRepresentable {
    /// The row's foot under the turn: 4 pt of gap and the 22 pt row (board 1).
    static let band: CGFloat = 26
    static let space = "chat.feed"
    let chat: ChatSession

    func makeNSView(context: Context) -> Probe { let v = Probe(); v.chat = chat; return v }
    func updateNSView(_ v: Probe, context: Context) { v.chat = chat }
    static func dismantleNSView(_ v: Probe, coordinator: ()) { v.stop() }

    final class Probe: NSView {
        weak var chat: ChatSession?
        private var monitor: Any?

        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stop()
            guard let window else { return }
            window.acceptsMouseMovedEvents = true
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .mouseExited, .scrollWheel, .leftMouseUp]) { [weak self] e in
                MainActor.assumeIsolated {
                    guard let self, let w = self.window, e.window === w else { return }
                    if e.type == .scrollWheel {
                        // The feed moves under a still pointer: look again once it has.
                        DispatchQueue.main.async { MainActor.assumeIsolated { self.look(w.mouseLocationOutsideOfEventStream) } }
                    } else if e.type == .mouseExited, e.trackingArea == nil {
                        self.set(nil)
                    } else {
                        self.look(e.locationInWindow)
                    }
                }
                return e
            }
        }

        func stop() { if let m = monitor { NSEvent.removeMonitor(m) }; monitor = nil }

        private func look(_ p: NSPoint) {
            guard let chat, !isHiddenOrHasHiddenAncestor else { return }
            let q = convert(p, from: nil)
            guard visibleRect.contains(q) else { return set(nil) }
            set(chat.turnFrames.turn(at: q, current: chat.ui.hoverTurn) { !chat.turnActions(for: $0).isEmpty && chat.turnIsFinished($0) })
        }

        private func set(_ id: String?) {
            guard let chat, chat.ui.hoverTurn != id else { return }
            chat.ui.hoverTurn = id
            if let id, chat.ui.selectedTurn != id { chat.ui.selectedTurn = nil }
        }
    }
}

extension View {
    /// The row's actions for VoiceOver, without hover (board 4): Copy, Rewind…, Fork….
    func turnAccessibility(id: String, chat: ChatSession, showRow: Bool = true) -> some View {
        let actions = showRow ? chat.turnActions(for: id) : []
        return self
            .accessibilityAction(named: "Copy") { if actions.contains(.copy) { chat.copyTurn(id) } }
            .accessibilityAction(named: "Rewind…") { if actions.contains(.rewind) { chat.askRewind(id) } }
            .accessibilityAction(named: "Fork…") { if actions.contains(.fork) { chat.askFork(id) } }
    }
}

/// Rewind's icon: an arrow turning back (board 1).
struct RewindMark: Shape {
    func path(in r: CGRect) -> Path {
        let s = r.width / 12
        var p = Path()
        // The board's `M2.2 5.5 A4 4 0 1 1 3.4 8.6`: the circle's centre is (6.19, 5.74); drawn as points, from 183.4° round to 494.3°.
        let c = CGPoint(x: 6.19 * s, y: 5.74 * s)
        for i in 0...24 {
            let a = (183.4 + (494.3 - 183.4) * Double(i) / 24) * .pi / 180
            let pt = CGPoint(x: c.x + 4 * s * cos(a), y: c.y + 4 * s * sin(a))
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.move(to: .init(x: 1.2 * s, y: 2.6 * s)); p.addLine(to: .init(x: 2.2 * s, y: 5.6 * s)); p.addLine(to: .init(x: 5 * s, y: 4.5 * s))
        return p
    }
}

/// Fork's icon in the row: two nodes in a line and one branching off (board 1).
struct ChatForkMark: Shape {
    func path(in r: CGRect) -> Path {
        let s = r.width / 12
        var p = Path()
        for (x, y) in [(3.0, 2.2), (3.0, 9.8), (9.0, 4.0)] {
            p.addEllipse(in: CGRect(x: (x - 1.3) * s, y: (y - 1.3) * s, width: 2.6 * s, height: 2.6 * s))
        }
        p.move(to: .init(x: 3 * s, y: 3.5 * s)); p.addLine(to: .init(x: 3 * s, y: 8.5 * s))
        p.move(to: .init(x: 9 * s, y: 5.3 * s))
        p.addCurve(to: .init(x: 5 * s, y: 7.9 * s), control1: .init(x: 9 * s, y: 7.3 * s), control2: .init(x: 7 * s, y: 7.5 * s))
        p.addLine(to: .init(x: 3.6 * s, y: 8.5 * s))
        return p
    }
}

/// One chat turn as `duo2 session turns` lists it.
public struct ChatTurnRef: Equatable, Sendable {
    public var n: Int
    public var id: String
    public var role: String
    public var uuid: String?
    public var preview: String
}

extension ChatSession {
    /// Your messages and Claude's replies, numbered from 1, oldest first (what the log shows; rewound turns are gone from it).
    public var turnList: [ChatTurnRef] {
        var out: [ChatTurnRef] = []
        for item in log.items {
            switch item {
            case .you(let y) where !y.queued:
                out.append(.init(n: out.count + 1, id: y.id, role: "you", uuid: y.uuid, preview: Self.words(y.text)))
            case .claude(let t):
                out.append(.init(n: out.count + 1, id: t.id, role: "claude", uuid: t.uuid, preview: Self.words(ChatTurnCopy.markdown(turn: t))))
            default: break
            }
        }
        return out
    }

    static func words(_ s: String) -> String {
        let one = s.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return one.count > 60 ? String(one.prefix(60)) + "…" : one
    }

    /// The turn a verb names: its number in `turnList`, or its uuid (a prefix of 8 or more will do).
    public func turnID(for ref: String) -> String? {
        let list = turnList
        if let n = Int(ref) { return list.first { $0.n == n }?.id }
        guard ref.count >= 8 else { return nil }
        let hits = list.filter { $0.uuid?.hasPrefix(ref) == true }
        return hits.count == 1 ? hits[0].id : nil
    }

    /// The message the Chat menu acts on: the selected one (⌥⌘↑/↓), else the latest.
    public var menuTurnID: String? {
        if let s = ui.selectedTurn, log.items.contains(where: { $0.id == s }) { return s }
        return turnList.last { $0.role == "you" }?.id
    }

    /// The reply that follows the message the menu acts on, if there is one.
    public var menuReplyID: String? {
        guard let you = menuTurnID, let at = log.items.firstIndex(where: { $0.id == you }) else { return nil }
        for item in log.items[(at + 1)...] { if case .claude(let t) = item { return t.id } }
        return nil
    }
}
