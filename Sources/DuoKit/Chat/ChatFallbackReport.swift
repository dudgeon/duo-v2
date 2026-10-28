import CryptoKit
import DuoControl
import Foundation

// The Debug report on the chat-fallback bar (DL-234): why chat handed over the terminal, what the
// reader saw, and the session's recent chat-state changes, as text Geoff can paste to us. The report
// is built on this Mac and shown in a sheet; nothing is sent anywhere. Every automatic fallback also
// writes one line, minus the full screen, to `logs/chat-fallbacks.jsonl` (ChatFallbackLog).

/// One change of a session's chat state: chat to terminal, back, or the user's toggle.
public struct ChatTransition: Sendable, Equatable, Codable {
    public var at: Date
    public var event: String
    public var reason: String
    public init(at: Date, event: String, reason: String) { self.at = at; self.event = event; self.reason = reason }
}

/// What chat saw at the moment it fell back (the full screen stays in memory only).
public struct ChatFallbackCapture: Sendable, Equatable {
    public var at: Date
    public var rule: String
    public var message: String
    public var automatic: Bool
    public var kind: String
    public var sig: String
    public var why: String?
    public var evidence: [String]
    public var lines: [String]
    public var cols: Int
    public var cliVersion: String?
    public var trust: String
    public var pending: String?
    public var unknownFor: Double?
    public var footer: Bool
    public var dialog: Bool
    public var mods: [String]
    public var session: String
    /// The reader's verdict changes just before the fallback, newest last.
    public var trail: [ChatTransition]

    public init(at: Date, rule: String, message: String, automatic: Bool, kind: String, sig: String, why: String? = nil, evidence: [String],
                lines: [String], cols: Int, cliVersion: String? = nil, trust: String, pending: String? = nil, unknownFor: Double? = nil,
                trail: [ChatTransition] = [], footer: Bool, dialog: Bool, mods: [String], session: String) {
        self.trail = trail
        self.at = at; self.rule = rule; self.message = message; self.automatic = automatic; self.kind = kind; self.sig = sig; self.why = why
        self.evidence = evidence; self.lines = lines; self.cols = cols; self.cliVersion = cliVersion; self.trust = trust; self.pending = pending
        self.unknownFor = unknownFor; self.footer = footer; self.dialog = dialog; self.mods = mods; self.session = session
    }
}

public enum ChatFallbackReport {
    /// How many of the screen's last rows the report carries.
    public static let rowsKept = 40

    /// The key patterns of the signature table, each against the screen: the row that matched, or none.
    /// This is the reader's evidence for its verdict.
    public static func evidence(_ lines: [String], table s: ChatSignatures) -> [String] {
        let t = lines.map { $0.replacingOccurrences(of: "\u{0}", with: " ").chatTrimEnd }
        func first(_ p: String) -> String {
            guard let i = t.firstIndex(where: { $0.chatTrim.chatIs(p) }) else { return "no row" }
            return "row \(i + 1): " + String(t[i].chatTrim.prefix(70))
        }
        let rules = t.indices.filter { t[$0].chatTrim.chatIs(s.rule) }
        var out = ["full-width rules: \(rules.count)" + (rules.isEmpty ? "" : " at rows " + rules.suffix(4).map { String($0 + 1) }.joined(separator: ", "))]
        if rules.count >= 2 {
            let a = rules[rules.count - 2]
            out.append("input box (❯ between the last two rules): " + (a + 1 < t.count && t[a + 1].hasPrefix("❯") ? "yes, row \(a + 2)" : "no ❯ under row \(a + 1)"))
        } else {
            out.append("input box (❯ between the last two rules): no, fewer than two rules")
        }
        let named: [(String, String)] = [
            ("plan title", s.planTitle), ("plan question", s.planQuestion), ("permission question", s.permissionQuestion),
            ("permission “Esc to cancel”", s.permissionCancel), ("review title", s.reviewTitle), ("review question", s.reviewQuestion),
            ("question nav", s.questionNav), ("model title", s.modelTitle), ("model footer", s.modelFooter),
            ("effort title", s.effortTitle), ("effort footer", s.effortFooter), ("switch/change confirm", s.confirmTitle),
            ("busy (esc to interrupt)", s.busy), ("mode row", "(\(s.modePlan)|\(s.modeAcceptEdits)|\(s.modeManual)|\(s.modeAuto)|\(s.modeBypass))"),
            ("`/` command menu", s.commandMenu),
        ]
        for (n, p) in named { out.append("\(n): " + first(p)) }
        return out
    }

    public static func hash(_ lines: [String]) -> String {
        SHA256.hash(data: Data(lines.joined(separator: "\n").utf8)).prefix(6).map { String(format: "%02x", $0) }.joined()
    }

    /// The 8 rows nearest the verdict: the last non-empty rows, where the box, footer or dialog sit.
    public static func nearest(_ lines: [String], _ n: Int = 8) -> [String] {
        Array(lines.map { $0.chatTrimEnd }.filter { !$0.chatTrim.isEmpty }.suffix(n))
    }

    static let duoVersion = "\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"))"

    static func stamp(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.string(from: d)
    }

    /// The report as plain text. `capture` is the last automatic fallback (nil: none this run);
    /// `current` the session's screen now.
    public static func text(capture c: ChatFallbackCapture?, current: ChatScreen, history: [ChatTransition], session: String,
                            fallback: ChatFallback?, cliVersion: String?, nowLines: [String] = []) -> String {
        var o: [String] = ["Duo chat-mode fallback report", ""]
        o.append("Duo \(duoVersion)")
        o.append("Claude Code \(cliVersion ?? "unknown") · session \(session)")
        o.append("Reader's verdict now: \(current.kind.rawValue)" + (current.why.map { " (\($0))" } ?? ""))
        o.append("Bar now: " + (fallback.map { "“\($0.message)”" } ?? "none (chat is showing)"))
        o.append("")
        if let c {
            o.append("Fallback")
            o.append("  rule: \(c.rule)")
            o.append("  message: \(c.message)")
            o.append("  when: \(stamp(c.at)) (\(c.automatic ? "automatic" : "handed over"))")
            o.append("  verdict: \(c.kind), sig \(c.sig)" + (c.why.map { ", \($0)" } ?? ""))
            if let u = c.unknownFor { o.append(String(format: "  unknown for: %.2f s", u)) }
            o.append("  version trust: \(c.trust), Claude Code \(c.cliVersion ?? "unknown")")
            o.append("  request pending: \(c.pending ?? "none")")
            o.append("  screen shows: footer \(c.footer ? "yes" : "no"), dialog \(c.dialog ? "yes" : "no"), mods \(c.mods.isEmpty ? "none" : c.mods.joined(separator: " | "))")
            o.append("")
            o.append("Evidence")
            o += c.evidence.map { "  " + $0 }
            o.append("")
            let shown = Array(c.lines.suffix(rowsKept))
            o.append("Screen the reader judged: last \(shown.count) of \(c.lines.count) rows, \(c.cols) columns")
            let first = c.lines.count - shown.count
            for (i, l) in shown.enumerated() { o.append(String(format: "%3d | ", first + i + 1) + l.chatTrimEnd) }
            o.append("")
            o.append("Reader's verdict changes before the fallback (newest last)")
            if c.trail.isEmpty { o.append("  none") }
            for h in c.trail.suffix(12) { o.append("  \(stamp(h.at))  \(h.reason)") }
            // The bar stays until Back to Chat (DL-154): when the screen has moved on, show it now too.
            if fallback != nil, current.kind.rawValue != c.kind, !nowLines.isEmpty {
                let tail = Array(nowLines.suffix(12))
                o.append("")
                o.append("Screen now (verdict \(current.kind.rawValue)): last \(tail.count) of \(nowLines.count) rows")
                for l in tail { o.append("    | " + l.chatTrimEnd) }
            }
        } else {
            o.append("No fallback has been recorded for this session since Duo started.")
        }
        o.append("")
        o.append("Chat state history (newest last)")
        if history.isEmpty { o.append("  none") }
        for h in history.suffix(10) { o.append("  \(stamp(h.at))  \(h.event): \(h.reason)") }
        return o.joined(separator: "\n")
    }
}

/// `logs/chat-fallbacks.jsonl`: every automatic fallback, kept in Duo's support folder, capped.
public enum ChatFallbackLog {
    /// Set by DuoChecks, so a check's fallbacks never reach the real support folder.
    nonisolated(unsafe) public static var override: URL?
    public static var file: URL { override ?? SupportFolder.duo.appending(path: "logs/chat-fallbacks.jsonl") }
    public static let cap = 256 * 1024

    public struct Record: Codable, Sendable, Equatable {
        public var at: Date
        public var rule: String
        public var message: String
        public var kind: String
        public var sig: String
        public var why: String?
        public var evidence: [String]
        public var cliVersion: String?
        public var trust: String
        public var duo: String
        public var session: String
        public var rows: Int
        public var cols: Int
        public var footer: Bool
        public var dialog: Bool
        public var mods: [String]
        /// A hash of the whole screen, to count the same screen across days.
        public var screenHash: String
        /// The 8 rows nearest the verdict.
        public var nearRows: [String]
    }

    static let encoder: JSONEncoder = { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.sortedKeys]; return e }()
    static let decoder: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }()

    public static func record(_ c: ChatFallbackCapture) -> Record {
        Record(at: c.at, rule: c.rule, message: c.message, kind: c.kind, sig: c.sig, why: c.why, evidence: c.evidence,
               cliVersion: c.cliVersion, trust: c.trust, duo: ChatFallbackReport.duoVersion, session: c.session,
               rows: c.lines.count, cols: c.cols, footer: c.footer, dialog: c.dialog, mods: c.mods,
               screenHash: ChatFallbackReport.hash(c.lines), nearRows: ChatFallbackReport.nearest(c.lines))
    }

    public static func append(_ r: Record, to url: URL = file) {
        guard let line = try? encoder.encode(r) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var data = (try? Data(contentsOf: url)) ?? Data()
        data.append(line); data.append(0x0A)
        if data.count > cap {
            let half = data.count - cap / 2
            data = Data(data[(data[half...].firstIndex(of: 0x0A).map { $0 + 1 } ?? data.endIndex)...])
        }
        try? data.write(to: url, options: .atomic)
    }

    public static func read(from url: URL = file) -> [Record] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return data.split(separator: 0x0A).compactMap { try? decoder.decode(Record.self, from: Data($0)) }
    }

    /// `duo2 session chat why --log`: the recent ones, two lines each.
    public static func report(_ records: [Record], last: Int = 20) -> String {
        guard !records.isEmpty else { return "No automatic chat fallbacks logged." }
        var o = ["\(records.count) automatic fallback\(records.count == 1 ? "" : "s") logged; the latest \(min(last, records.count)):"]
        for r in records.suffix(last) {
            o.append("\(ChatFallbackReport.stamp(r.at))  [\(r.rule)] \(r.kind)/\(r.sig)  Claude Code \(r.cliVersion ?? "?")  session \(r.session.prefix(8))  screen \(r.screenHash)")
            o.append("    \(r.message)")
        }
        return o.joined(separator: "\n")
    }
}
