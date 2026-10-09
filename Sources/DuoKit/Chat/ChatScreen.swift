import Foundation

// Chat mode's screen reader (DL-118, F-104, F-106): reads Claude Code's TUI screen into a state
// chat mode can show. It has one job: which dialog is up, its verbatim option labels, the input
// box and the footer. Content (Markdown, tool calls) comes from hooks and the transcript, never
// from here. Anything it can't name is `unknown`, and unknown means the terminal (fallback).
// A port of the spike's `Spikes/chat-mode/screen.mjs`; the patterns live in a per-CLI-version
// signature table, so a TUI change is a new table, not new code.

/// The patterns that name each screen, for the Claude Code versions they were verified on.
public struct ChatSignatures: Sendable, Equatable {
    /// The CLI version the table was written against.
    public var version: String
    /// Every version a dialog-by-dialog run of the mock tour (`Spikes/chat-mode/tour.sh`) and the
    /// AskUserQuestion test (`asktest.sh`) passed on. Only these answer dialogs (fallback rule 3).
    public var verified: [String]
    /// A full-width rule; a named session writes its name into the input box's top rule (F-105).
    public var rule = #"^─{20,}(?: \S.*\S ─+)?$"#
    public var option = #"^\s*(❯)?\s*(\d+)\.\s(\[[ ✔]\]\s)?(.*)$"#
    public var optionsEnd = #"^\s*(ctrl\+g|Enter to|Esc to)"#
    public var planTitle = #"^\s*Ready to code\?"#
    public var planQuestion = #"Would you like to proceed\?"#
    /// The permission dialog's question. "Do you want to …?" (2.1.219 to 2.1.293); 2.1.295 adds "Allow this read
    /// outside the working directories?" (F-244), and its binary has "Allow external CLAUDE.md file imports?",
    /// "Trust this directory?", "Would you like to install …?". The dialog also needs numbered options and "Esc to cancel".
    public var permissionQuestion = #"^\s*(Do you want to|Allow|Trust|Would you like to) .*\?\s*$"#
    public var permissionCancel = #"Esc to cancel"#
    public var amend = #"Tab to amend"#
    public var reviewTitle = #"^Review your answers"#
    public var reviewQuestion = #"Ready to submit your answers\?"#
    public var questionNav = #"^Enter to select · "#
    public var busy = #"esc to interrupt"#
    public var modePlan = #"plan mode on"#
    public var modeAcceptEdits = #"accept edits on"#
    public var modeManual = #"manual mode on"#
    public var modeAuto = #"auto mode on"#
    public var modeBypass = #"bypass permissions on"#
    /// The spinner line above the input box: `✻ Sautéed for 2s`, `✻ 529 Overloaded · Retrying …`.
    public var status = #"^[✻✽✶✳✢·*] \S"#
    public var interrupted = #"Interrupted · What should Claude do instead\?"#
    /// The input box's placeholder (dim in the TUI; SwiftTerm doesn't expose cell attributes to a
    /// host, so it is named here, F-108). `Try "fix lint errors"`.
    public var inputPlaceholder = #"^Try ".*"$"#
    /// The free-text row's placeholder in AskUserQuestion.
    public var otherPlaceholder = #"^Type something\.?$"#
    /// The slash-command menu under the input.
    public var commandMenu = #"^\s{2}❯ /\S+\s{2,}"#
    /// `/model`'s and `/effort`'s screens (DL-143): a card in chat when both ends are on screen.
    public var modelTitle = #"^\s*Select model\s*$"#
    public var modelFooter = #"Enter to set as default · s to use this session only · Esc to cancel"#
    public var effortTitle = #"^\s*Effort\s*$"#
    public var effortFooter = #"←/→ to adjust · Enter to confirm · s for this session only · Esc to cancel"#
    /// Chat about this, Next and Submit in a question.
    public var chatAbout = "Chat about this"
    /// A row of the `/` command menu: `  ❯ /add-dir      Add a new working directory`.
    public var commandRow = #"^\s{2}(❯ )?\s*(/[\w:.-]+)\s{2,}(\S.*)$"#
    /// Commands with a screen of their own: they open in the terminal (handoff `composer`). Each was
    /// run from chat on 2.1.292 (F-173); `/doctor` and `/statusline` are turns now, and `/agents`,
    /// `/mcp` and `/output-style` print a line.
    /// `/model` and `/effort` open as cards in chat instead (DL-143).
    public var terminalCommands: Set<String> = ["/help", "/config", "/permissions", "/resume", "/tasks", "/login", "/logout",
                                                "/hooks", "/memory", "/theme", "/status", "/terminal-setup", "/install-github-app",
                                                "/ide", "/export", "/rewind", "/plugin", "/usage", "/cost", "/release-notes", "/skills",
                                                "/btw", "/fast", "/sandbox", "/scroll-speed", "/add-dir", "/powerup", "/workflows",
                                                "/autocompact", "/keybindings", "/mobile"]

    /// 2.1.291: every dialog verified with the mock tour and asktest (F-104, F-106) and with real
    /// turns under the CLI login (F-105).
    /// 2.1.292 and 2.1.293: the same screens; chat-live (AskUserQuestion at three sizes) and the dialog tour passed (F-175, F-176).
    public static let v2_1_291 = ChatSignatures(version: "2.1.291", verified: ["2.1.291", "2.1.292", "2.1.293"])

    public static let all: [ChatSignatures] = [.v2_1_291]

    /// How far a CLI version's dialogs are trusted (DL-145, DL-155): a verified version always;
    /// any other 2.1.x, newer (Claude Code updates about daily, C-49) or older (work Macs pin it
    /// months behind), while its dialogs read like the verified versions'; another major or minor,
    /// or an unknown one, never (its dialogs go to the terminal).
    public static func trust(for version: String?) -> ChatVersionTrust {
        guard let version, let v = ChatVersion(version) else { return .unverified }
        if all.contains(where: { $0.verified.contains(version) }) { return .verified }
        let family = all.flatMap(\.verified).compactMap(ChatVersion.init).map { Array($0.parts.prefix(2)) }
        return family.contains(Array(v.parts.prefix(2))) ? .newer : .unverified
    }

    /// The table for a CLI version: the newest at or below it (or the oldest), and whether this
    /// exact version was verified. An unverified version still renders; its dialogs go to the
    /// terminal (spike, fallback rule 3).
    public static func table(for version: String?) -> (table: ChatSignatures, verified: Bool) {
        guard let version, let v = ChatVersion(version) else { return (all.last!, false) }
        let fit = all.filter { (ChatVersion($0.version) ?? v) <= v }.last ?? all.first!
        return (fit, fit.verified.contains(version))
    }
}

/// DL-145: how a CLI version's dialogs are answered from chat.
public enum ChatVersionTrust: String, Sendable {
    /// Checked dialog by dialog (the tour, chat-live).
    case verified
    /// Another 2.1.x, newer or older (DL-155): trusted while its dialogs read like theirs.
    case newer
    /// Another major or minor version, or unknown: dialogs go to the terminal.
    case unverified
}

/// A dotted CLI version, comparable.
public struct ChatVersion: Comparable, Sendable, CustomStringConvertible {
    public let parts: [Int]
    public init?(_ s: String) {
        let p = s.split(separator: ".").map { Int($0.prefix { $0.isNumber }) }
        guard p.count >= 2, !p.contains(where: { $0 == nil }) else { return nil }
        parts = p.map { $0! }
    }
    public static func < (a: ChatVersion, b: ChatVersion) -> Bool {
        for i in 0..<max(a.parts.count, b.parts.count) {
            let x = i < a.parts.count ? a.parts[i] : 0, y = i < b.parts.count ? b.parts[i] : 0
            if x != y { return x < y }
        }
        return false
    }
    public var description: String { parts.map(String.init).joined(separator: ".") }

    /// Ctrl+G returns cleanly from the external editor from here (2.1.269 fixed a double draw):
    /// below it the composer pastes instead (spike, work Mac 2.1.219).
    public static let externalEditor = ChatVersion("2.1.269")!
    /// Hooks see the current plan on ExitPlanMode from here (2.1.285); below it the plan is read
    /// from `planFilePath`.
    public static let freshPlanInHook = ChatVersion("2.1.285")!
    /// MessageDisplay streams the reply (2.1.152).
    public static let messageDisplay = ChatVersion("2.1.152")!
}

/// The Claude Code mode the footer names.
public enum ChatPermissionMode: String, Sendable, Equatable {
    case manual, acceptEdits = "accept-edits", plan, auto, bypass

    /// The chip's words, as the TUI's footer says them (composer board).
    public var chip: String {
        switch self {
        case .manual: "manual mode"
        case .acceptEdits: "accept edits on"
        case .plan: "plan mode on"
        case .auto: "auto mode on"
        case .bypass: "bypass permissions on"
        }
    }
}

/// `/model` or `/effort` as its screen draws it (DL-143). Every word is Claude Code's own.
public struct ChatPicker: Sendable, Equatable {
    public enum Kind: String, Sendable { case model, effort }
    public struct Row: Sendable, Equatable {
        public var n: Int
        public var name: String
        public var note: String
        /// The TUI's ❯.
        public var cursor: Bool
        /// The TUI's ✔: the one in use.
        public var selected: Bool
    }
    public var kind: Kind
    public var description = ""
    public var rows: [Row] = []
    /// Lines under the list (`○ Effort not supported for Haiku`).
    public var footnotes: [String] = []
    /// `/effort`: its levels, the ▲'s, and the words at either end.
    public var levels: [String] = []
    public var level: Int?
    public var ends: (String, String)?

    public init(kind: Kind) { self.kind = kind }

    public var cursor: Int? { rows.firstIndex { $0.cursor } }

    public static func == (a: ChatPicker, b: ChatPicker) -> Bool {
        a.kind == b.kind && a.description == b.description && a.rows == b.rows && a.footnotes == b.footnotes && a.levels == b.levels
            && a.level == b.level && a.ends?.0 == b.ends?.0 && a.ends?.1 == b.ends?.1
    }
}

/// One row of a dialog, in screen order.
public struct ChatScreenRow: Sendable, Equatable {
    public enum Kind: String, Sendable { case option, other, next, submit, chat }
    public var kind: Kind
    public var n: Int?
    public var label: String
    public var cursor: Bool
    /// Multi-select tick, when the row has a box.
    public var checked: Bool?
    /// A revisited single-select marks its answer with a trailing ✔.
    public var selected = false
    /// Description lines under the label.
    public var note = ""
    /// The free-text row's typed text (empty while it shows its placeholder).
    public var value: String?
}

/// What the screen shows, read.
public struct ChatScreen: Sendable, Equatable {
    public enum Kind: String, Sendable {
        case starting, idle, busy, permission, plan, question, questionReview = "question-review", picker, unknown
        /// Chat mode can draw this (or it is about to settle): no fallback.
        public var known: Bool { self != .unknown }
    }
    public var kind: Kind
    /// What an answer is checked against right before its keys go (F-104).
    public var sig: String
    public var title: String?
    /// The permission dialog's heading: "Bash command", "Edit file".
    public var kindLabel: String?
    public var body: String?
    public var rows: [ChatScreenRow] = []
    public var amend = false
    public var mode: ChatPermissionMode?
    /// The input box's text, idle or busy; nil when there's no input box.
    public var input: String?
    /// The spinner or retry line.
    public var status: String?
    public var interrupted = false
    public var menu = false
    // AskUserQuestion.
    public var tabs: [(done: Bool, label: String)] = []
    public var question: String?
    public var multi = false
    public var preview = false
    public var notes: String?
    public var answers: String?
    public var why: String?
    /// The `/` menu Claude Code shows under what's typed, with its own descriptions.
    public var commands: [(name: String, description: String, selected: Bool)] = []
    /// `/model` or `/effort` (DL-143).
    public var picker: ChatPicker?

    public var options: [ChatScreenRow] { rows.filter { $0.kind == .option } }
    public var other: ChatScreenRow? { rows.first { $0.kind == .other } }
    public var cursor: Int { rows.firstIndex { $0.cursor } ?? -1 }

    public init(kind: Kind, sig: String) { self.kind = kind; self.sig = sig }

    public static let starting = ChatScreen(kind: .starting, sig: "starting")

    public static func == (a: ChatScreen, b: ChatScreen) -> Bool {
        a.kind == b.kind && a.sig == b.sig && a.title == b.title && a.kindLabel == b.kindLabel && a.body == b.body && a.rows == b.rows
            && a.amend == b.amend && a.mode == b.mode && a.input == b.input && a.status == b.status && a.interrupted == b.interrupted
            && a.menu == b.menu && a.tabs.map(\.label) == b.tabs.map(\.label) && a.tabs.map(\.done) == b.tabs.map(\.done)
            && a.question == b.question && a.multi == b.multi && a.preview == b.preview && a.notes == b.notes && a.answers == b.answers
            && a.commands.map(\.name) == b.commands.map(\.name) && a.commands.map(\.selected) == b.commands.map(\.selected)
            && a.picker == b.picker
    }
}

/// Regular expressions, compiled once.
final class ChatRegex: @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [String: NSRegularExpression] = [:]

    static func get(_ p: String) -> NSRegularExpression {
        lock.lock(); defer { lock.unlock() }
        if let r = cache[p] { return r }
        let r = try! NSRegularExpression(pattern: p, options: [.anchorsMatchLines])
        cache[p] = r
        return r
    }
}

extension String {
    /// The pattern's captures in this string (group 0 first), or nil when it doesn't match.
    func chatMatch(_ pattern: String) -> [String?]? {
        let r = ChatRegex.get(pattern)
        let ns = self as NSString
        guard let m = r.firstMatch(in: self, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return (0..<m.numberOfRanges).map { i in m.range(at: i).location == NSNotFound ? nil : ns.substring(with: m.range(at: i)) }
    }
    func chatIs(_ pattern: String) -> Bool { chatMatch(pattern) != nil }
    var chatTrimEnd: String { replacingOccurrences(of: #"\s+$"#, with: "", options: .regularExpression) }
    var chatTrim: String { trimmingCharacters(in: .whitespaces) }
    /// Whitespace runs folded to one space, trimmed: how labels and questions are compared.
    var chatNorm: String { replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces) }
}

/// Reads a screen (its visible rows, as text) with a signature table.
public enum ChatScreenReader {
    public static func read(_ text: String, cols: Int? = nil, table: ChatSignatures = .v2_1_291) -> ChatScreen {
        read(lines: text.components(separatedBy: "\n"), cols: cols, table: table)
    }

    public static func read(lines raw: [String], cols: Int? = nil, table s: ChatSignatures = .v2_1_291) -> ChatScreen {
        // A cell the TUI skipped over with a cursor move reads as NUL from a raw buffer; it's a space.
        let t = raw.map { $0.replacingOccurrences(of: "\u{0}", with: " ").chatTrimEnd }
        // Nothing drawn yet (a session loading its transcript, a redraw's first frame): still
        // starting, never a reason to fall back, which since DL-154 would stick.
        if t.allSatisfy({ $0.chatTrim.isEmpty }) { return .starting }
        let width = cols ?? max(t.map(\.count).max() ?? 0, 1)
        let rules = t.indices.filter { t[$0].chatTrim.chatIs(s.rule) }
        // The footer sits under the input box, which is not always at the bottom of the screen.
        let footer = (rules.last.map { Array(t[min($0 + 1, t.count)..<min($0 + 3, t.count)]) } ?? Array(t.suffix(3))).joined(separator: " ")
        let mode: ChatPermissionMode? = footer.chatIs(s.modePlan) ? .plan : footer.chatIs(s.modeAcceptEdits) ? .acceptEdits
            : footer.chatIs(s.modeManual) ? .manual : footer.chatIs(s.modeAuto) ? .auto : footer.chatIs(s.modeBypass) ? .bypass : nil
        // The input box: the last two full-width rules with "❯ " between them.
        var input: String?
        if rules.count >= 2 {
            let a = rules[rules.count - 2], b = rules[rules.count - 1]
            if b > a, a + 1 < t.count, t[a + 1].hasPrefix("❯") {
                let text = t[(a + 1)..<b].enumerated().map { i, l in
                    i == 0 ? l.replacingOccurrences(of: #"^❯\s?"#, with: "", options: .regularExpression)
                           : l.replacingOccurrences(of: #"^  "#, with: "", options: .regularExpression)
                }.joined(separator: "\n").chatTrimEnd
                input = text.chatIs(s.inputPlaceholder) && !text.contains("\n") ? "" : text
            }
        }
        let busy = footer.chatIs(s.busy)
        func find(_ p: String) -> Int { t.firstIndex { $0.chatIs(p) } ?? -1 }

        // Plan approval.
        let ready = find(s.planTitle), proceed = find(s.planQuestion)
        if ready >= 0, proceed > ready {
            var r = ChatScreen(kind: .plan, sig: "plan:" + t[proceed].chatTrim)
            r.title = "Ready to code?"
            r.body = t[proceed].chatTrim
            r.rows = options(t, from: proceed + 1, to: t.count, cols: width, s)
            r.mode = mode
            return r
        }
        // Permission: "Do you want to …?" with numbered options and "Esc to cancel".
        let dw = find(s.permissionQuestion)
        if dw >= 0, find(s.permissionCancel) > dw {
            let top = rules.filter { $0 < dw }.last ?? 0
            let head = t[min(top + 1, dw)..<dw].filter { !$0.chatTrim.isEmpty && !$0.chatTrim.chatIs(#"^╌+$"#) }
            let opts = options(t, from: dw + 1, to: t.count, cols: width, s)
            if opts.isEmpty { var u = ChatScreen(kind: .unknown, sig: "unknown"); u.why = "a question with no options"; return u }
            var r = ChatScreen(kind: .permission, sig: "perm:" + t[dw].chatTrim)
            r.title = t[dw].chatTrim
            r.kindLabel = head.first?.chatTrim
            r.body = head.dropFirst().map { $0.hasPrefix(" ") ? String($0.dropFirst()) : $0 }.joined(separator: "\n")
            r.rows = opts
            r.amend = t.joined(separator: " ").chatIs(s.amend)
            r.mode = mode
            return r
        }
        // AskUserQuestion's review page.
        let review = find(s.reviewTitle), submit = find(s.reviewQuestion)
        if review >= 0, submit > review {
            var r = ChatScreen(kind: .questionReview, sig: "review")
            r.tabs = tabs(t.first { $0.contains("☐") || $0.contains("☒") } ?? "")
            r.rows = options(t, from: submit + 1, to: t.count, cols: width, s)
            r.answers = t[(review + 1)..<submit].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            return r
        }
        let nav = find(s.questionNav)
        if nav >= 0 { return question(t, nav: nav, s) }
        if let p = picker(t, s) {
            var r = ChatScreen(kind: .picker, sig: "picker:" + p.kind.rawValue)
            r.picker = p
            return r
        }
        if let input {
            var r = ChatScreen(kind: busy ? .busy : .idle, sig: "input")
            r.input = input
            r.mode = mode
            let above = rules.count >= 2 ? Array(t[0..<rules[rules.count - 2]]) : []
            r.status = above.reversed().first { $0.chatIs(s.status) }?.chatTrim
            // "Interrupted · What should Claude do instead?" under the last reply, with nothing after it.
            if let i = above.lastIndex(where: { $0.chatIs(s.interrupted) }) {
                r.interrupted = !above[(i + 1)...].contains { $0.hasPrefix("❯") || $0.hasPrefix("⏺") }
            }
            r.menu = t.contains { $0.chatIs(s.commandMenu) }
            if rules.count >= 2 {
                r.commands = t[0..<rules[rules.count - 2]].compactMap { l in
                    l.chatMatch(s.commandRow).map { m in (m[2] ?? "", (m[3] ?? "").chatTrim, m[1] != nil) }
                }
            }
            return r
        }
        return ChatScreen(kind: .unknown, sig: "unknown")
    }

    /// A dialog read whole by the signatures (DL-145): what a newer CLI's dialog must be before chat
    /// answers it. Options numbered 1…n, one cursor, and the parts each kind has.
    public static func wellFormed(_ s: ChatScreen) -> Bool {
        func numbered(_ ns: [Int?]) -> Bool { !ns.isEmpty && ns == Array(1...ns.count).map(Optional.some) }
        switch s.kind {
        case .permission:
            return numbered(s.options.map(\.n)) && s.rows.filter(\.cursor).count == 1 && s.title?.isEmpty == false
        case .plan:
            return numbered(s.options.map(\.n)) && s.rows.filter(\.cursor).count == 1
        case .questionReview:
            return numbered(s.options.map(\.n)) && s.rows.filter(\.cursor).count == 1
        case .question:
            return numbered(s.rows.map(\.n).filter { $0 != nil }) && s.question?.isEmpty == false && s.rows.filter(\.cursor).count == 1
        case .picker:
            guard let p = s.picker else { return false }
            switch p.kind {
            case .model: return numbered(p.rows.map { Optional($0.n) }) && p.rows.filter(\.cursor).count == 1
            case .effort: return p.levels.count >= 2 && p.level != nil
            }
        default:
            return true
        }
    }

    /// `/model`'s list or `/effort`'s slider, when its title and its footer are both on screen.
    static func picker(_ t: [String], _ s: ChatSignatures) -> ChatPicker? {
        if let top = t.lastIndex(where: { $0.chatIs(s.modelTitle) }), let end = t.indices.last(where: { $0 > top && t[$0].chatIs(s.modelFooter) }) {
            var p = ChatPicker(kind: .model)
            var description: [String] = []
            for l in t[(top + 1)..<end] {
                let x = l.chatTrim
                if x.isEmpty { continue }
                if let m = l.chatMatch(#"^\s*(❯)?\s*(\d+)\.\s(.*)$"#) {
                    let rest = (m[3] ?? "").chatTrimEnd
                    let parts = rest.components(separatedBy: "  ").filter { !$0.chatTrim.isEmpty }
                    var name = parts.first?.chatTrim ?? rest
                    let selected = name.hasSuffix(" ✔") || name.hasSuffix("✔")
                    if selected { name = name.replacingOccurrences(of: #"\s*✔$"#, with: "", options: .regularExpression) }
                    p.rows.append(ChatPicker.Row(n: Int(m[2] ?? "") ?? p.rows.count + 1, name: name,
                                                 note: parts.dropFirst().map(\.chatTrim).joined(separator: " "), cursor: m[1] != nil, selected: selected))
                } else if p.rows.isEmpty {
                    description.append(x)
                } else if l.hasPrefix("        ") || l.prefix(while: { $0 == " " }).count > 10 {
                    p.rows[p.rows.count - 1].note += (p.rows[p.rows.count - 1].note.isEmpty ? "" : " ") + x   // a wrapped description
                } else {
                    p.footnotes.append(x)
                }
            }
            p.description = description.joined(separator: " ")
            return p.rows.isEmpty ? nil : p
        }
        if let top = t.lastIndex(where: { $0.chatIs(s.effortTitle) }), let end = t.indices.last(where: { $0 > top && t[$0].chatIs(s.effortFooter) }) {
            var p = ChatPicker(kind: .effort)
            let lines = Array(t[(top + 1)..<end])
            guard let marker = lines.first(where: { $0.contains("▲") }), let labels = lines.last(where: { !$0.chatTrim.isEmpty && !$0.contains("▲") && !$0.contains("─") }) else { return nil }
            if let ends = lines.first(where: { !$0.chatTrim.isEmpty && !$0.contains("▲") && $0 != labels })?.split(separator: " ", omittingEmptySubsequences: true), ends.count == 2 {
                p.ends = (String(ends[0]), String(ends[1]))
            }
            // Each level's centre column; the ▲'s column picks the nearest.
            let at = marker.distance(from: marker.startIndex, to: marker.firstIndex(of: "▲")!)
            var col = 0, best = Int.max
            for word in labels.split(separator: " ", omittingEmptySubsequences: false) {
                if !word.isEmpty {
                    let centre = col + word.count / 2
                    if abs(centre - at) < best { best = abs(centre - at); p.level = p.levels.count }
                    p.levels.append(String(word))
                }
                col += word.count + 1
            }
            return p.levels.isEmpty ? nil : p
        }
        return nil
    }

    /// Numbered options from `from`, with wrapped labels joined and description lines kept as notes.
    static func options(_ t: [String], from: Int, to: Int, cols: Int, _ s: ChatSignatures) -> [ChatScreenRow] {
        var out: [ChatScreenRow] = []
        guard from < to else { return out }
        for i in from..<to {
            if t[i].chatIs(s.optionsEnd) { break }
            if let m = t[i].chatMatch(s.option) {
                out.append(ChatScreenRow(kind: .option, n: Int(m[2] ?? ""), label: (m[4] ?? "").chatTrim, cursor: m[1] != nil,
                                         checked: m[3].map { $0.contains("✔") }))
            } else if !out.isEmpty, !t[i].chatTrim.isEmpty, !t[i].chatTrim.chatIs(#"^(Enter to|Esc to|ctrl\+g|─|╌)"#) {
                // A label wrapped at the edge continues it; anything else under a label is its note.
                if t[i - 1].count >= cols - 4, out[out.count - 1].note.isEmpty {
                    out[out.count - 1].label += " " + t[i].chatTrim
                } else {
                    out[out.count - 1].note += (out[out.count - 1].note.isEmpty ? "" : " ") + t[i].chatTrim
                }
            }
        }
        return out
    }

    /// The question strip: `←  ☐ Platforms  ☒ Timing  ✔ Submit  →`.
    static func tabs(_ strip: String) -> [(done: Bool, label: String)] {
        let r = ChatRegex.get(#"(☐|☒|✔)\s([^☐☒✔→]+?)(?=\s{2}|\s*→|$)"#)
        let ns = strip as NSString
        return r.matches(in: strip, range: NSRange(location: 0, length: ns.length)).map {
            (ns.substring(with: $0.range(at: 1)) != "☐", ns.substring(with: $0.range(at: 2)).chatTrim)
        }
    }

    // AskUserQuestion (F-106). Every row in screen order, so answers can steer the cursor row by row:
    //   option  a choice ("1. Postgres", "1. [✔] Lint"; a chosen answer on a revisited question ends " ✔")
    //   other   the free-text row ("Type something." until typed into; typing ticks it on multi-select)
    //   next / submit   the unnumbered row under a multi-select list
    //   chat    "Chat about this", below the rule (numbered, or not in the preview layout)
    // The preview layout draws the focused option's preview in a box to the right of the list, has
    // no free-text row, and takes notes with "n".
    static func isOptionRow(_ line: String, n: Int?, have: [Int], column: inout Int?) -> Bool {
        guard let n, n == (have.last ?? 0) + 1 else { return false }
        let at = line.prefix { !$0.isNumber }.count   // the number's column: only spaces and ❯ come before it
        if let c = column { return at == c }
        column = at
        return true
    }

    static func question(_ t: [String], nav: Int, _ s: ChatSignatures) -> ChatScreen {
        let tabsAt = t.firstIndex { $0.contains("☐") || $0.contains("☒") } ?? -1
        var r = ChatScreen(kind: .question, sig: "")
        r.tabs = tabsAt >= 0 ? tabs(t[tabsAt]) : []
        var qlines: [String] = []
        var afterRule = false
        let widest = t.map(\.count).max() ?? 0
        let box = #"\s{2,}(?=[┌│└├])"#   // ├ is the clipped preview's "✂ n lines hidden" row
        func left(_ l: String) -> String {
            guard let m = ChatRegex.get(box).firstMatch(in: l, range: NSRange(location: 0, length: (l as NSString).length)) else { return l }
            return (l as NSString).substring(to: m.range.location)
        }
        var optionColumn: Int?
        var i = tabsAt + 1
        while i < nav {
            defer { i += 1 }
            let raw = t[i]
            if raw.chatTrim.isEmpty { continue }
            if raw.chatTrim.chatIs(#"^─{20,}"#) { afterRule = true; continue }
            if let nm = raw.chatMatch(#"Notes: (.*)$"#) {
                let n = (nm[1] ?? "").chatTrim
                r.notes = n.chatIs(#"^(press n to add notes|Add notes on this design…)$"#) ? "" : n
                continue
            }
            if raw.chatIs(box) { r.preview = true }
            let l = left(raw)
            // An option row is at the option column (the first row's number; the ❯ cursor sits two columns
            // left of it) and counts up from 1 with no gap. A numbered line in an option's description is
            // indented deeper or breaks the count, so it is a note (F-243).
            if let m = l.chatMatch(#"^\s*(❯)?\s*(\d+)\.\s(\[([ ✔])\]\s)?(.*?)\s*$"#),
               isOptionRow(l, n: Int(m[2] ?? ""), have: r.rows.filter { $0.n != nil }.compactMap(\.n), column: &optionColumn) {
                var label = m[5] ?? "", selected = false
                if label.hasSuffix(" ✔") { selected = true; label = String(label.dropLast(2)) }
                r.rows.append(ChatScreenRow(kind: afterRule && label == s.chatAbout ? .chat : .option, n: Int(m[2] ?? ""), label: label,
                                            cursor: m[1] != nil, checked: m[3] == nil ? nil : m[4] == "✔", selected: selected))
                continue
            }
            if let m = l.chatMatch(#"^\s*(❯)?\s+(Next|Submit)\s*$"#), !r.rows.isEmpty {
                r.rows.append(ChatScreenRow(kind: m[2] == "Next" ? .next : .submit, label: m[2] ?? "", cursor: m[1] != nil))
                continue
            }
            if let m = l.chatMatch(#"^\s*(❯)?\s*Chat about this\s*$"#) {
                r.rows.append(ChatScreenRow(kind: .chat, label: s.chatAbout, cursor: m[1] != nil))
                continue
            }
            guard !r.rows.isEmpty else {
                qlines.append(l.chatTrim.replacingOccurrences(of: #"^│\s?"#, with: "", options: .regularExpression))   // the question, possibly wrapped
                continue
            }
            let last = r.rows.count - 1
            if r.rows[last].kind == .option, !l.chatTrim.isEmpty {
                if r.rows[last].note.isEmpty, t[i - 1].count >= widest - 4 { r.rows[last].label += " " + l.chatTrim }   // wrapped at the edge
                else { r.rows[last].note += (r.rows[last].note.isEmpty ? "" : " ") + l.chatTrim }
            }
        }
        // The free-text row is the last numbered row above "Chat about this" (not in the preview layout).
        if !r.preview, r.rows.count > 1 {
            let chatAt = r.rows.firstIndex { $0.kind == .chat } ?? r.rows.count
            if let o = r.rows[0..<chatAt].lastIndex(where: { $0.kind == .option }) {
                r.rows[o].kind = .other
                let v = r.rows[o].label.chatTrim
                r.rows[o].value = v.chatIs(s.otherPlaceholder) || v.isEmpty ? "" : r.rows[o].label.chatTrimEnd
            }
        }
        r.multi = r.rows.contains { $0.checked != nil }
        r.question = qlines.joined(separator: " ").chatNorm
        r.sig = "q:" + (r.question ?? "")
        return r
    }
}
