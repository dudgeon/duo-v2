import Foundation
import Observation

// The conversation chat mode draws (chat-mode-handoff `window`, `text`, `tools`, `status`), built
// from two read-only sources (F-103):
//   hooks       live: UserPromptSubmit, MessageDisplay (streamed Markdown), PreToolUse/PostToolUse/
//               PostToolUseFailure, PermissionRequest, Subagent*, Pre/PostCompact, Stop, StopFailure
//   transcript  the record: history, thinking, refusals and feedback (which fire no hook), and the
//               reply text when MessageDisplay isn't available (hooks off, or an older CLI)
// Either can arrive first; items are matched across them (prompts by text, tools by id, text by
// content), so nothing shows twice.

/// One entry in the transcript.
public enum ChatItem: Identifiable, Equatable, Sendable {
    /// Your message: a blue bubble on the right.
    case you(ChatYou)
    /// One white card per Claude turn.
    case claude(ChatTurn)
    /// Your answer to a review card, as a small reply of yours (`You chose 1 · Yes for the edit to prd-v2.md`).
    case answer(ChatNote)
    /// A quiet centred line: a background agent finished, a task reported back.
    case note(ChatNote)
    /// A divider across the column: the conversation was compacted.
    case divider(ChatNote)
    /// `Interrupted · What should Claude do instead?`
    case interrupted(ChatNote)

    public var id: String {
        switch self {
        case .you(let y): y.id
        case .claude(let t): t.id
        case .answer(let n), .note(let n), .divider(let n), .interrupted(let n): n.id
        }
    }
}

public struct ChatYou: Equatable, Sendable {
    public var id: String
    public var text: String
    public var time: Date?
    /// Sent while Claude works: the TUI holds it until it's ready (composer board).
    public var queued = false
    /// Sent in plan mode (`You · 10:30 · plan mode`).
    public var planMode = false
    var fromHook = false
    var fromTranscript = false
}

public struct ChatNote: Equatable, Sendable {
    public var id: String
    public var text: String
    public var time: Date?
}

/// Claude's turn: what it did and said, in order.
public struct ChatTurn: Equatable, Sendable {
    public var id: String
    public var time: Date?
    public var segments: [ChatSegment] = []
}

public enum ChatSegment: Identifiable, Equatable, Sendable {
    /// `› Thought for 6s`, once the block is complete.
    case thinking(id: String, seconds: Int?, text: String)
    /// Tool steps on one dotted thread.
    case tools(id: String, steps: [ChatToolStep])
    /// Markdown; `streaming` while MessageDisplay is still adding lines.
    case text(ChatText)
    /// The questions Claude asked (AskUserQuestion): `Platforms · Which platforms …?`.
    case asked(id: String, questions: [ChatAsked])

    public var id: String {
        switch self {
        case .thinking(let id, _, _), .tools(let id, _), .asked(let id, _): id
        case .text(let t): t.id
        }
    }
}

public struct ChatAsked: Equatable, Sendable {
    public var header: String
    public var question: String
}

public struct ChatText: Equatable, Sendable {
    public var id: String
    public var markdown: String
    public var streaming: Bool
    /// The MessageDisplay message this came from; the transcript block that matches it.
    var streamKey: String?
    var committed = false
    /// Cut off by an interrupt: drawn faded (handoff `status`).
    public var cut = false
}

/// A tool call (handoff `tools`).
public struct ChatToolStep: Identifiable, Equatable, Sendable {
    public enum Status: Equatable, Sendable {
        case running, done, needsYou, declined, interrupted
        case failed(exit: Int?)
    }
    public enum ObjectKind: Sendable { case path, url, code, quoted, plain }

    public var id: String
    public var name: String
    /// The bold word: Read, Search, Fetch, Edit, Write, Bash, Agent …
    public var verb: String
    /// What it acted on, and how to show it.
    public var object: String
    public var objectKind: ObjectKind = .plain
    /// Where a path link opens.
    public var path: String?
    /// `214 lines`, `6 matches in 2 files`, `12 KB`, `in the background`.
    public var detail: String?
    public var status: Status = .running
    public var adds: Int?
    public var dels: Int?
    public var diff: [ChatDiffLine]?
    /// Bash: `$ command`, then the output's lines.
    public var output: [String]?
    public var error: String?
    public var agent: ChatAgentResult?
    /// Reads grouped into this step's line (`Read a.md, b.md`): each one's shown path and real path.
    public var others: [(String, String?)] = []
    /// A folded step's first lines of output (Read, Search), shown when opened.
    public var preview: [String]?
    /// What the command does, in Claude's words (Bash's `description`), shown before it in a run (DL-135).
    public var summary: String?
    /// The to-do list as this update left it (TodoWrite).
    public var todos: [ChatTodo]?
    /// The input, canonical, to match a PermissionRequest (which has no tool_use_id, F-103).
    var inputKey: String

    public static func == (a: ChatToolStep, b: ChatToolStep) -> Bool {
        a.id == b.id && a.verb == b.verb && a.object == b.object && a.detail == b.detail && a.status == b.status && a.adds == b.adds && a.dels == b.dels
            && a.diff == b.diff && a.output == b.output && a.error == b.error && a.agent == b.agent && a.preview == b.preview
            && a.others.map(\.0) == b.others.map(\.0) && a.summary == b.summary && a.todos == b.todos
    }

    /// Folded to one line until opened (Read, Search, Fetch); the others open.
    public var foldsByDefault: Bool { diff == nil && output == nil && error == nil && agent == nil }
}

public struct ChatTodo: Equatable, Sendable {
    public enum Status: String, Sendable { case pending, inProgress = "in_progress", completed }
    public var text: String
    public var status: Status
}

public struct ChatDiffLine: Equatable, Sendable {
    public enum Kind: Sendable { case context, add, del }
    public var kind: Kind
    public var number: Int?
    public var text: String
}

public struct ChatAgentResult: Equatable, Sendable {
    public var message: String
    public var seconds: Int?
    public var toolUses: Int?
    public var background: Bool
    public var finished: Bool
}

/// A JSON object from a hook or the transcript.
public typealias ChatJSON = [String: Any]

/// Not tied to the main thread: a history replay builds a scratch log in the background, used by
/// that one task only, and `adopt` hands it over on the main thread (F-160). The log the chat
/// draws is only ever changed on the main thread.
@Observable
public final class ChatLog: @unchecked Sendable {
    public internal(set) var items: [ChatItem] = [] {
        didSet { assert(!drawn || Thread.isMainThread, "the log a chat draws changes only on the main thread (F-160)") }
    }
    /// The log a chat draws (ChatSession's): changed only on the main thread. A scratch log for a
    /// replay isn't, and is built anywhere (F-160).
    @ObservationIgnored public internal(set) var drawn = false
    /// The session's folder, for showing paths relative to it.
    public var cwd: String?
    /// When the turn being written started (the Writing line's clock).
    public internal(set) var turnStarted: Date?
    /// Hooks are flowing for this session (SessionStart or any event seen).
    public internal(set) var hooksSeen = false
    /// MessageDisplay is streaming replies, so the transcript's text is only matched, never added.
    public internal(set) var streams = false
    /// The model Claude answers with, by family name (Opus, Sonnet, Haiku, Fable), from the transcript.
    public internal(set) var model: String?
    /// Turns before the last 50 aren't shown yet (Earlier turns, Q-56c).
    public internal(set) var earlierHidden = false
    @ObservationIgnored private var nextID = 0
    @ObservationIgnored private var agentsStarted: [String: String] = [:]
    @ObservationIgnored private var askedIDs: Set<String> = []
    /// Tool calls the transcript has reached: a hook can show one before the text that preceded it.
    @ObservationIgnored var transcriptTools: Set<String> = []
    /// Which item holds each tool step: items are only appended or replaced, so this stays true (F-157).
    @ObservationIgnored private var stepItem: [String: Int] = [:]
    private static let hole = ChatItem.note(ChatNote(id: "", text: ""))

    public init() {}

    /// Empties the log (before a history replay).
    func reset() {
        items = []
        stepItem = [:]
        turnStarted = nil
    }

    /// Takes over a log built elsewhere (a replay): everything it holds, in one change.
    func adopt(_ o: ChatLog) {
        nextID = o.nextID; agentsStarted = o.agentsStarted; askedIDs = o.askedIDs
        transcriptTools = o.transcriptTools; stepItem = o.stepItem
        if o.model != nil { model = o.model }
        if o.streams { streams = true }
        if o.hooksSeen { hooksSeen = true }
        earlierHidden = o.earlierHidden
        turnStarted = o.turnStarted
        items = o.items
    }

    func newID(_ p: String) -> String { nextID += 1; return "\(p)-\(nextID)" }

    // MARK: Items

    /// The last item, if it's Claude's turn: where text and tools go.
    private var openTurnIndex: Int? {
        guard let i = items.indices.last, case .claude = items[i] else { return nil }
        return i
    }

    private func withTurn(time: Date?, _ change: (inout ChatTurn) -> Void) {
        if let i = openTurnIndex, case .claude(var t) = items[i] {
            items[i] = Self.hole   // t's arrays are now uniquely held: changed in place, not copied
            change(&t)
            items[i] = .claude(t)
        } else {
            var t = ChatTurn(id: newID("turn"), time: time)
            change(&t)
            items.append(.claude(t))
            if turnStarted == nil { turnStarted = time ?? Date() }
        }
    }

    /// Updates every turn's step with this id; true when one was found.
    @discardableResult
    private func updateStep(_ id: String, _ change: (inout ChatToolStep) -> Void) -> Bool {
        guard let i = stepItem[id], i < items.count, case .claude(var t) = items[i] else { return false }
        for s in t.segments.indices {
            guard case .tools(let sid, var steps) = t.segments[s], let k = steps.firstIndex(where: { $0.id == id }) else { continue }
            items[i] = Self.hole
            t.segments[s] = .tools(id: sid, steps: [])
            change(&steps[k])
            t.segments[s] = .tools(id: sid, steps: steps)
            items[i] = .claude(t)
            return true
        }
        return false
    }

    public func step(_ id: String) -> ChatToolStep? {
        guard let i = stepItem[id], i < items.count else { return nil }
        for case .claude(let t) in [items[i]] {
            for case .tools(_, let steps) in t.segments { if let s = steps.first(where: { $0.id == id }) { return s } }
        }
        return nil
    }

    /// All steps, newest last.
    public var steps: [ChatToolStep] {
        items.flatMap { item -> [ChatToolStep] in
            guard case .claude(let t) = item else { return [] }
            return t.segments.flatMap { seg -> [ChatToolStep] in if case .tools(_, let s) = seg { return s } else { return [] } }
        }
    }

    // MARK: What happened

    /// A prompt, from the hook or the transcript. Injected prompts (task notifications, loop and
    /// schedule wakeups) are quiet notes, not your bubbles (F-103).
    public func prompt(_ text: String, time: Date?, fromHook: Bool, injected: Bool = false, planMode: Bool = false) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        if injected || t.hasPrefix("<task-notification>") {
            let line = "Background task reported back"
            if case .note(let n)? = items.last, n.text == line { return }
            items.append(.note(ChatNote(id: newID("note"), text: line, time: time)))
            return
        }
        // The other source already showed it: match the latest unmatched bubble with this text.
        for i in items.indices.reversed().prefix(12) {
            guard case .you(var y) = items[i], y.text.chatNorm == t.chatNorm else { continue }
            // A message sent from the composer: the first echo claims it.
            if !y.fromHook, !y.fromTranscript {
                if fromHook { y.fromHook = true } else { y.fromTranscript = true }
                y.queued = false
                items[i] = .you(y)
                return
            }
            if fromHook ? !y.fromHook : !y.fromTranscript {
                if fromHook { y.fromHook = true } else { y.fromTranscript = true }
                y.queued = false
                items[i] = .you(y)
                return
            }
        }
        var y = ChatYou(id: newID("you"), text: t, time: time, planMode: planMode)
        if fromHook { y.fromHook = true } else { y.fromTranscript = true }
        items.append(.you(y))
        turnStarted = time ?? Date()
    }

    /// Your message, sent from the composer: shown now, matched when the hook and transcript echo it.
    public func sent(_ text: String, time: Date?, queued: Bool, planMode: Bool = false) {
        var y = ChatYou(id: newID("you"), text: text, time: time, queued: queued, planMode: planMode)
        y.fromHook = false
        items.append(.you(y))
        if !queued { turnStarted = time ?? Date() }
    }

    /// A MessageDisplay flush: newly completed Markdown lines of one reply (2.1.152).
    public func display(message: String, delta: String, final: Bool, time: Date?) {
        streams = true
        var done = false
        if let i = openTurnIndex, case .claude(var t) = items[i],
           let s = t.segments.lastIndex(where: { if case .text(let x) = $0 { return x.streamKey == message } else { return false } }),
           case .text(var x) = t.segments[s] {
            x.markdown += delta
            x.streaming = !final
            t.segments[s] = .text(x)
            items[i] = .claude(t)
            done = true
        }
        if !done {
            withTurn(time: time) { t in
                t.segments.append(.text(ChatText(id: newID("text"), markdown: delta, streaming: !final, streamKey: message)))
            }
        }
        if final { dropDuplicateText() }
    }

    /// The transcript's text block. Matched to the streamed text it repeats; otherwise added.
    public func textBlock(_ text: String, time: Date?) {
        let norm = text.chatNorm
        guard !norm.isEmpty else { return }
        if let i = openTurnIndex, case .claude(var t) = items[i] {
            for s in t.segments.indices {
                guard case .text(var x) = t.segments[s], !x.committed else { continue }
                let have = x.markdown.chatNorm
                if have == norm || (x.streaming && norm.hasPrefix(have)) {
                    x.committed = true
                    t.segments[s] = .text(x)
                    items[i] = .claude(t)
                    return
                }
            }
        }
        // Text the transcript has before tool calls that hooks already drew goes in front of them,
        // in the order Claude wrote it.
        let seg = ChatSegment.text(ChatText(id: newID("text"), markdown: text, streaming: false, committed: true))
        if let i = openTurnIndex, case .claude(var t) = items[i],
           let first = t.segments.firstIndex(where: { if case .tools(_, let st) = $0 { return st.contains { !transcriptTools.contains($0.id) } } else { return false } }),
           case .tools(let sid, let steps) = t.segments[first] {
            let k = steps.firstIndex { !transcriptTools.contains($0.id) } ?? 0
            if k == 0 { t.segments.insert(seg, at: first) }
            else {
                t.segments[first] = .tools(id: sid, steps: Array(steps[..<k]))
                t.segments.insert(seg, at: first + 1)
                t.segments.insert(.tools(id: newID("tools"), steps: Array(steps[k...])), at: first + 2)
            }
            items[i] = .claude(t)
            return
        }
        withTurn(time: time) { t in t.segments.append(seg) }
    }

    /// A final stream that repeats text the transcript already added (a replay, or a late hook).
    private func dropDuplicateText() {
        guard let i = openTurnIndex, case .claude(var t) = items[i] else { return }
        var seen: [String: Int] = [:]
        var drop: [Int] = []
        for (n, seg) in t.segments.enumerated() {
            guard case .text(let x) = seg, !x.streaming else { continue }
            let k = x.markdown.chatNorm
            if let first = seen[k] {
                // Keep the streamed one's place; mark it committed.
                drop.append(x.streamKey == nil ? n : first)
            } else { seen[k] = n }
        }
        for n in drop.sorted().reversed() { t.segments.remove(at: n) }
        if !drop.isEmpty { items[i] = .claude(t) }
    }

    /// A thinking block, once complete.
    public func thinking(_ text: String, durationMs: Double?, time: Date?) {
        withTurn(time: time) { t in
            t.segments.append(.thinking(id: newID("think"), seconds: durationMs.map { max(1, Int(($0 / 1000).rounded())) }, text: text))
        }
    }

    /// A tool call: from PreToolUse, the transcript's tool_use, or PostToolUse when it's the first word of it.
    public func toolUse(id: String, name: String, input: ChatJSON, time: Date?) {
        // AskUserQuestion and ExitPlanMode are review cards, answered as replies. A question's list
        // stays in the card (handoff `question-chat-decline`).
        if name == "AskUserQuestion" {
            let qs = (input["questions"] as? [ChatJSON] ?? []).map { ChatAsked(header: $0["header"] as? String ?? "", question: $0["question"] as? String ?? "") }
            let shown = items.contains { item in
                guard case .claude(let t) = item else { return false }
                return t.segments.contains { if case .asked(_, let q) = $0 { return q == qs } else { return false } }
            }
            if !qs.isEmpty, !askedIDs.contains(id), !shown {
                askedIDs.insert(id)
                withTurn(time: time) { $0.segments.append(.asked(id: id, questions: qs)) }
            }
            return
        }
        if name == "ExitPlanMode" { return }
        if stepItem[id] != nil { return }
        let step = ChatToolDescriber.step(id: id, name: name, input: input, cwd: cwd)
        withTurn(time: time) { t in
            if case .tools(let sid, var steps)? = t.segments.last {
                t.segments[t.segments.count - 1] = .tools(id: sid, steps: [])
                steps.append(step)
                t.segments[t.segments.count - 1] = .tools(id: sid, steps: steps)
            } else {
                t.segments.append(.tools(id: newID("tools"), steps: [step]))
            }
        }
        stepItem[id] = items.count - 1
    }

    /// A tool finished. `result` is the hook's tool_response or the transcript's toolUseResult;
    /// `content` the tool_result's text.
    public func toolResult(id: String, name: String?, input: ChatJSON?, result: Any?, content: String?, isError: Bool,
                           denial: String? = nil, interrupt: Bool = false, time: Date?) {
        if let name, ["AskUserQuestion", "ExitPlanMode"].contains(name) { return }
        if step(id) == nil, let name, let input { toolUse(id: id, name: name, input: input, time: time) }
        updateStep(id) { s in
            ChatToolDescriber.finish(&s, result: result, content: content, isError: isError, denial: denial, interrupt: interrupt, cwd: cwd)
        }
    }

    /// A permission request for a tool call: its step needs you (matched by tool and input).
    public func permissionPending(name: String, input: ChatJSON) {
        let key = ChatToolDescriber.key(name, input)
        if let s = steps.last(where: { $0.inputKey == key && ($0.status == .running || $0.status == .needsYou) }) {
            updateStep(s.id) { $0.status = .needsYou }
        }
    }

    /// The permission was answered (or the dialog closed): steps waiting on you go back to running.
    public func permissionResolved() {
        for s in steps where s.status == .needsYou { updateStep(s.id) { $0.status = .running } }
    }

    /// A background agent: its final message, from SubagentStop.
    public func agentStarted(id: String, agentType: String?) { agentsStarted[id] = agentType ?? "agent" }

    public func agentFinished(agentType: String?, message: String?, time: Date?, agentId: String? = nil) {
        // Claude's own side agents stop without a start: not shown (F-103).
        if let agentId, agentsStarted[agentId] == nil, !steps.contains(where: { $0.agent?.finished == false }) { return }
        if steps.last(where: { $0.agent != nil && $0.agent?.finished == false }) == nil, let agentId, let name = agentsStarted[agentId] {
            items.append(.note(ChatNote(id: newID("note"), text: "Background agent finished: \(name)", time: time)))
            return
        }
        if let s = steps.last(where: { $0.agent != nil && $0.agent?.finished == false }) {
            updateStep(s.id) { st in st.agent?.finished = true; st.status = .done; if let m = message, !m.isEmpty { st.agent?.message = m } }
            // After its card is done, a quiet line says so (handoff `status`); inside the turn, the step says it.
            let inOpenTurn: Bool = {
                guard let i = openTurnIndex, case .claude(let t) = items[i] else { return false }
                return t.segments.contains { if case .tools(_, let st) = $0 { return st.contains { $0.id == s.id } } else { return false } }
            }()
            if !inOpenTurn || turnStarted == nil {
                items.append(.note(ChatNote(id: newID("note"), text: "Background agent finished: \(s.object)", time: time)))
            }
        }
    }

    public func compacted(time: Date?) {
        if case .divider? = items.last { return }
        items.append(.divider(ChatNote(id: newID("div"), text: "Conversation compacted · earlier turns are summarised for Claude", time: time)))
    }

    /// Your answer to a review card, or a declined question (transcript only, F-106).
    public func answer(_ text: String, time: Date?) {
        if case .answer(let n)? = items.last, n.text == text { return }
        items.append(.answer(ChatNote(id: newID("ans"), text: text, time: time)))
    }

    /// The turn ended (Stop): streams close; a reply that never streamed gets Stop's message.
    public func turnEnded(lastMessage: String?, time: Date?) {
        endStreaming(interrupted: false)
        turnStarted = nil
        permissionResolved()
        for s in steps where s.status == .running { updateStep(s.id) { $0.status = .done } }
    }

    /// The screen says a reply ended without its hook (an interrupt, F-105).
    public func endStreaming(interrupted: Bool) {
        for i in items.indices {
            guard case .claude(var t) = items[i] else { continue }
            var changed = false
            for s in t.segments.indices {
                if case .text(var x) = t.segments[s], x.streaming { x.streaming = false; x.cut = interrupted; t.segments[s] = .text(x); changed = true }
            }
            if changed { items[i] = .claude(t) }
        }
        if interrupted {
            for s in steps where s.status == .running || s.status == .needsYou { updateStep(s.id) { $0.status = .interrupted } }
            if case .interrupted? = items.last {} else {
                items.append(.interrupted(ChatNote(id: newID("int"), text: "What should Claude do instead?", time: Date())))
            }
            turnStarted = nil
        }
    }

    /// The turn being written: streaming text, or tools running.
    public var writing: Bool {
        guard let i = openTurnIndex, case .claude(let t) = items[i] else { return false }
        return t.segments.contains { if case .text(let x) = $0 { return x.streaming } else { return false } }
    }

    /// Your messages, for ⌘[ / ⌘] (DL-119 §4).
    public var yourMessageIDs: [String] { items.compactMap { if case .you(let y) = $0 { return y.id } else { return nil } } }
}
