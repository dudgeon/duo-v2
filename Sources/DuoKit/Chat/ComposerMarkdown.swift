import Foundation

// Your Markdown in the composer (DL-188, chat-markdown-handoff `composer`). The text is never changed:
// this type only says which ranges are what (so the field can style them) and, for the keys, what edit
// a chord makes. No view in here, so DuoChecks can test it. All ranges are UTF-16, as NSTextView's are.

public enum ComposerMarkdown {
    /// What a range is, for the field to style. A range can carry several (bold inside a heading).
    public struct Style: OptionSet, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let bold = Style(rawValue: 1)
        public static let italic = Style(rawValue: 2)
        public static let strike = Style(rawValue: 4)
        public static let code = Style(rawValue: 8)      // inline code: mono on the code ground, marks included
        public static let dim = Style(rawValue: 16)      // a mark: text2
        public static let link = Style(rawValue: 32)     // a link's text: underlined
        public static let heading = Style(rawValue: 64)  // the text after `#`: semibold
    }

    public struct Run: Equatable, Sendable {
        public var range: NSRange
        public var style: Style
    }

    /// What a line is. `range` is the line without its newline.
    public enum Kind: Equatable, Sendable {
        case plain
        case heading(mark: Int)                       // `###` and the space, in characters
        case bullet(lead: Int, marker: Int, gap: Int) // leading spaces; the marker's location; the spaces after it
        case number(lead: Int, mark: Int)             // leading spaces; `12.` and its spaces, in characters
        case quote(mark: Int)                         // `>` and its space, after up to three spaces
        case fenceMark                                // a ``` or ~~~ line
        case fenceBody                                // between the fences
    }

    public struct Line: Equatable, Sendable {
        public var range: NSRange
        public var kind: Kind
        public var inFence: Bool { kind == .fenceMark || kind == .fenceBody }
    }

    public struct Analysis: Equatable, Sendable {
        public var lines: [Line] = []
        public var runs: [Run] = []
        /// The runs of fence lines, top to bottom: opening fence line through the closing one (or the end).
        public var fences: [NSRange] = []

        public func styles(at i: Int) -> Style {
            runs.reduce(into: Style()) { if NSLocationInRange(i, $1.range) { $0.formUnion($1.style) } }
        }
    }

    // MARK: Classifying

    static let bullet = try! NSRegularExpression(pattern: "^( *)([-*+])([ \t]+)")
    static let number = try! NSRegularExpression(pattern: "^( *)(\\d{1,9}[.)])([ \t]+)")
    static let quote = try! NSRegularExpression(pattern: "^( {0,3})>[ \t]?")
    static let heading = try! NSRegularExpression(pattern: "^#{1,6}[ \t]")
    static let fence = try! NSRegularExpression(pattern: "^ {0,3}(```|~~~)")
    static let linkRe = try! NSRegularExpression(pattern: "\\[([^\\]\\n]+)\\](\\([^)\\n]*\\))")
    static let boldRe = try! NSRegularExpression(pattern: "(\\*\\*)(?=\\S)(.+?)(?<=\\S)(\\*\\*)|(__)(?=\\S)(.+?)(?<=\\S)(__)")
    static let strikeRe = try! NSRegularExpression(pattern: "(~~)(?=\\S)(.+?)(?<=\\S)(~~)")
    static let italicRe = try! NSRegularExpression(pattern: "(?<![*\\w])(\\*)(?!\\*)(?=\\S)(.+?)(?<=\\S)(?<!\\*)(\\*)(?![*\\w])|(?<![_\\w])(_)(?!_)(?=\\S)(.+?)(?<=\\S)(?<!_)(_)(?![_\\w])")

    public static func analyze(_ text: String) -> Analysis {
        let s = text as NSString
        var out = Analysis()
        var fenceChar: String?, fenceStart = 0
        var at = 0
        while at <= s.length {
            var end = s.length
            let nl = s.range(of: "\n", range: NSRange(location: at, length: s.length - at))
            if nl.location != NSNotFound { end = nl.location }
            let r = NSRange(location: at, length: end - at)
            let line = s.substring(with: r) as NSString
            let all = NSRange(location: 0, length: line.length)

            if let f = fence.firstMatch(in: line as String, range: all) {
                let ch = line.substring(with: f.range(at: 1))
                if fenceChar == nil {
                    fenceChar = ch; fenceStart = r.location
                    out.lines.append(Line(range: r, kind: .fenceMark))
                    out.runs.append(Run(range: r, style: .dim))
                } else if ch == fenceChar {
                    out.lines.append(Line(range: r, kind: .fenceMark))
                    out.runs.append(Run(range: r, style: .dim))
                    out.fences.append(NSRange(location: fenceStart, length: NSMaxRange(r) - fenceStart))
                    fenceChar = nil
                } else {
                    out.lines.append(Line(range: r, kind: .fenceBody))
                }
            } else if fenceChar != nil {
                out.lines.append(Line(range: r, kind: .fenceBody))
            } else {
                var kind = Kind.plain
                var contentFrom = 0
                var extra: Style = []
                if let m = heading.firstMatch(in: line as String, range: all) {
                    kind = .heading(mark: m.range.length); contentFrom = m.range.length; extra = .heading
                    out.runs.append(Run(range: NSRange(location: r.location, length: m.range.length), style: .dim))
                } else if let m = quote.firstMatch(in: line as String, range: all) {
                    kind = .quote(mark: m.range.length - m.range(at: 1).length); contentFrom = m.range.length
                } else if let m = bullet.firstMatch(in: line as String, range: all) {
                    kind = .bullet(lead: m.range(at: 1).length, marker: r.location + m.range(at: 2).location, gap: m.range(at: 3).length)
                    contentFrom = m.range.length
                } else if let m = number.firstMatch(in: line as String, range: all) {
                    kind = .number(lead: m.range(at: 1).length, mark: m.range(at: 2).length + m.range(at: 3).length)
                    contentFrom = m.range.length
                }
                out.lines.append(Line(range: r, kind: kind))
                let content = NSRange(location: r.location + contentFrom, length: r.length - contentFrom)
                if extra != [], content.length > 0 { out.runs.append(Run(range: content, style: extra)) }
                inline(s, content, into: &out.runs)
            }
            if nl.location == NSNotFound { break }
            at = end + 1
        }
        if fenceChar != nil { out.fences.append(NSRange(location: fenceStart, length: s.length - fenceStart)) }
        return out
    }

    /// Inline marks inside one line's content. Code first (nothing inside it is Markdown), then links,
    /// bold, strike and italic over what's left.
    static func inline(_ s: NSString, _ range: NSRange, into runs: inout [Run]) {
        guard range.length > 1 else { return }
        var taken: [NSRange] = []
        func free(_ r: NSRange) -> Bool { !taken.contains { NSIntersectionRange($0, r).length > 0 } }

        // Code spans: a run of backticks closes at the next run of the same length.
        var i = range.location
        let end = NSMaxRange(range)
        while i < end {
            if s.character(at: i) != 96 { i += 1; continue }
            var n = 0
            while i + n < end, s.character(at: i + n) == 96 { n += 1 }
            var j = i + n, close: Int?
            while j < end {
                if s.character(at: j) == 96 {
                    var m = 0
                    while j + m < end, s.character(at: j + m) == 96 { m += 1 }
                    if m == n { close = j; break }
                    j += m
                } else { j += 1 }
            }
            guard let c = close else { i += n; continue }
            let whole = NSRange(location: i, length: c + n - i)
            runs.append(Run(range: whole, style: .code))
            runs.append(Run(range: NSRange(location: i, length: n), style: .dim))
            runs.append(Run(range: NSRange(location: c, length: n), style: .dim))
            taken.append(whole)
            i = c + n
        }

        let str = s as String
        func scan(_ re: NSRegularExpression, _ body: (NSTextCheckingResult) -> Void) {
            for m in re.matches(in: str, range: range) where free(m.range) { body(m); taken.append(m.range) }
        }
        scan(linkRe) { m in
            let t = m.range(at: 1), u = m.range(at: 2)
            runs.append(Run(range: NSRange(location: m.range.location, length: 1), style: .dim))
            runs.append(Run(range: t, style: .link))
            runs.append(Run(range: NSRange(location: NSMaxRange(t), length: NSMaxRange(u) - NSMaxRange(t)), style: .dim))
        }
        func pair(_ m: NSTextCheckingResult, _ style: Style) {
            // Groups 1-3 for the first form, 4-6 for the second.
            let g = m.range(at: 1).location != NSNotFound ? 1 : 4
            runs.append(Run(range: m.range(at: g + 1), style: style))
            runs.append(Run(range: m.range(at: g), style: .dim))
            runs.append(Run(range: m.range(at: g + 2), style: .dim))
        }
        scan(boldRe) { pair($0, .bold) }
        scan(strikeRe) { pair($0, .strike) }
        scan(italicRe) { pair($0, .italic) }
    }

    // MARK: The keys

    /// An edit a chord makes: replace `range` with `text`, then select `selection`. One replacement, so one undo.
    public struct Edit: Equatable, Sendable {
        public var range: NSRange
        public var text: String
        public var selection: NSRange
    }

    /// ⌘B `**`, ⌘I `*`, ⇧⌘X `~~`, ⌘E `` ` ``: the editor's rule (`wrap()` in duo-editor.js).
    public static func toggle(_ marker: String, in doc: String, selection r: NSRange) -> Edit {
        let d = doc as NSString, n = (marker as NSString).length, total = d.length
        let text = d.substring(with: r)
        func slice(_ a: Int, _ b: Int) -> String {
            let lo = max(0, min(a, total)), hi = max(lo, min(b, total))
            return d.substring(with: NSRange(location: lo, length: hi - lo))
        }
        // A single `*` must not match half of `**`.
        func lone(_ at: Int, _ dir: Int) -> Bool { marker != "*" || slice(max(0, at - (dir < 0 ? 1 : 0)), min(total, at + (dir < 0 ? 0 : 1))) != "*" }
        let before = r.location >= n && slice(r.location - n, r.location) == marker && lone(r.location - n, -1)
        let after = NSMaxRange(r) + n <= total && slice(NSMaxRange(r), NSMaxRange(r) + n) == marker && lone(NSMaxRange(r) + n, 1)
        let t = text as NSString
        if r.length > 0, before, after {
            return Edit(range: NSRange(location: r.location - n, length: r.length + 2 * n), text: text, selection: NSRange(location: r.location - n, length: r.length))
        }
        if r.length > 0, t.length >= 2 * n, text.hasPrefix(marker), text.hasSuffix(marker), lone(r.location + n, 1), lone(NSMaxRange(r) - n, -1) {
            return Edit(range: r, text: t.substring(with: NSRange(location: n, length: t.length - 2 * n)), selection: NSRange(location: r.location, length: r.length - 2 * n))
        }
        return Edit(range: r, text: marker + text + marker, selection: NSRange(location: r.location + n, length: r.length))
    }

    /// ⌘K: `[text]()` with the caret in the parentheses; with nothing selected `[]()` with the caret in the brackets.
    public static func link(in doc: String, selection r: NSRange) -> Edit {
        let text = (doc as NSString).substring(with: r)
        let at = r.length == 0 ? r.location + 1 : r.location + (text as NSString).length + 3
        return Edit(range: r, text: "[\(text)]()", selection: NSRange(location: at, length: 0))
    }
}
