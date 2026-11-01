import AppKit

// Mac editing keys in Claude's prompt (DL-274, strategy 1 of docs/design/terminal-selection-study). Claude Code
// reads ⌘←/→, Home/End, ⌥←/→ and the Emacs keys itself (F-470); these are the four it gets wrong, turned into
// keys it reads, on 2.1.284 and 2.1.311 alike. Pure, so DuoChecks runs it on recorded screens.

/// Claude's input box as the screen shows it: its text rows and the caret.
public struct PromptBox: Equatable, Sendable {
    /// The box's first text row (the `❯` row) and its last (above the bottom rule), on the viewport.
    public let firstRow: Int
    public let lastRow: Int
    /// The rows between the rules, as drawn (`❯ ` or two spaces, then the text).
    public let rows: [String]
    /// Claude parks the terminal's cursor on its caret (F-472).
    public let caret: (row: Int, col: Int)
    /// The viewport's height: the box holds at most half of it less 5 rows, then scrolls (2.1.284, 2.1.311).
    public let viewRows: Int

    public static func == (a: PromptBox, b: PromptBox) -> Bool {
        a.firstRow == b.firstRow && a.lastRow == b.lastRow && a.rows == b.rows && a.caret == b.caret && a.viewRows == b.viewRows
    }

    /// The box, with the caret on one of its text rows and no question or picker up; nil otherwise.
    public static func find(rows: [String], cursor: (row: Int, col: Int)) -> PromptBox? {
        guard !InputBoxFinder.questionShowing(rows), let (bottom, _, prompt) = InputBoxFinder.locate(rows.map { Array($0) }),
              bottom > prompt, (prompt..<bottom).contains(cursor.row) else { return nil }
        return PromptBox(firstRow: prompt, lastRow: bottom - 1, rows: Array(rows[prompt..<bottom]), caret: cursor, viewRows: rows.count)
    }

    /// Rows above and below the caret, in the box.
    public var above: Int { caret.row - firstRow }
    public var below: Int { lastRow - caret.row }

    /// The box is as tall as Claude lets it grow, so it may hold more than it shows (rows 5 at 20, 10 at 30, 20 at 50).
    public var full: Bool { rows.count >= max(1, viewRows / 2 - 5) }
}

/// The chords this handles, in a Claude terminal.
public enum PromptKey: Equatable, Sendable {
    /// ⌘↑, the prompt's start (Geoff's pick over All Projects in a Claude terminal, DL-274).
    case toStart
    /// ⌘↓, the prompt's end.
    case toEnd
    /// ⌥⌦ (⌥fn⌫), a word forward. Claude's own ⌥⌦ kills to the line's end.
    case deleteWordForward
    /// ⌘Z, Claude's undo (⌃_), not Duo's Edit ▸ Undo.
    case undo

    public static func chord(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> PromptKey? {
        let mods = modifiers.intersection([.shift, .control, .option, .command])
        switch (keyCode, mods) {
        case (126, [.command]): return .toStart
        case (125, [.command]): return .toEnd
        case (117, [.option]): return .deleteWordForward
        case (6, [.command]): return .undo
        default: return nil
        }
    }
}

public enum PromptKeys {
    static let up: [UInt8] = Array("\u{1b}[A".utf8), down: [UInt8] = Array("\u{1b}[B".utf8)
    /// ⌃A and ⌃E, the line's start and end: Claude reads the raw bytes with the kitty protocol on or off, and in vim's
    /// NORMAL mode, where Home and End do nothing (F-504).
    static let lineStart: [UInt8] = [0x01], lineEnd: [UInt8] = [0x05]
    static let undoKey: [UInt8] = [0x1f]

    /// The keys for a chord, or nil to leave the key to the terminal as today. With the box full, ⌘↑ and ⌘↓ go on
    /// with `next` until Claude has nothing more above or below.
    public static func bytes(_ k: PromptKey, box: PromptBox?, enhanced: Bool) -> [UInt8]? {
        switch k {
        case .toStart:
            // ↑ to the box's first row, never past it: on the prompt's first row ↑ recalls the last prompt.
            guard let b = box else { return [] }   // a question or picker up: ⌘↑ does nothing in a Claude terminal
            return Array(repeating: up, count: b.above).flatMap { $0 } + lineStart
        case .toEnd:
            guard let b = box else { return nil }
            return Array(repeating: down, count: b.below).flatMap { $0 } + lineEnd
        case .deleteWordForward:
            guard box != nil else { return nil }
            // Alt+D: as a CSI u report with the protocol (a bare ESC d would leave vim's INSERT mode first).
            return enhanced ? Array("\u{1b}[100;3u".utf8) : [0x1b, 0x64]
        case .undo:
            return box == nil ? [] : undoKey
        }
    }

    /// What one more ↑ (or ↓) did to a full box, and what to send next.
    public enum Next: Equatable, Sendable {
        /// Nothing more that way: the line's start (end) and stop.
        case done([UInt8])
        /// The box scrolled: back to its edge and probe again.
        case more([UInt8])
        /// ↑ on the prompt's first row recalled the last prompt; ↓ brings the draft back with the caret at its start.
        case history([UInt8])
        /// Anything else: stop and send nothing.
        case stop
    }

    /// `before` is the box with the caret on its first (last) row; `after` is it once the probe key is drawn.
    public static func next(toStart: Bool, before: PromptBox, after: PromptBox?) -> Next {
        guard let a = after else { return .stop }
        if a == before { return .done(toStart ? lineStart : lineEnd) }
        // Scrolled: the old rows are still there, moved down (up) by some rows, and the caret sits in the box.
        if scrolled(toStart ? before.rows : a.rows, toStart ? a.rows : before.rows) {
            return .more(Array(repeating: toStart ? up : down, count: toStart ? a.above : a.below).flatMap { $0 })
        }
        return toStart ? .history(down) : .stop
    }

    /// Whether `lower` is `upper` moved down by one row or more: the rows `upper` starts with end `lower`.
    static func scrolled(_ upper: [String], _ lower: [String]) -> Bool {
        guard upper.count == lower.count, upper.count > 1 else { return false }
        let n = upper.count
        // The `❯ ` row moves too, and the caret's cell can end a row with a space: compare without either.
        let text = { (r: String) in String(r.dropFirst(2)).trimmingTrailingSpaces }
        return (1..<n).contains { k in (0..<(n - k)).allSatisfy { text(lower[$0 + k]) == text(upper[$0]) } }
    }
}

/// Text Claude copies from its own prompt (a drag, a double or triple click, OSC 52) or SwiftTerm copies from the box
/// is screen text: rows after the first keep the box's two-space indent, and a soft wrap is a line break. Geoff's
/// pick (DL-274, Q-361): clean it up from the screen alone, never through Ctrl+G (which blanks the terminal, F-473).
public enum PromptCopy {
    /// The copied text as it was typed, when its lines are rows of the box on screen; else unchanged.
    /// `cols` is the terminal's width: Claude wraps the prompt at `cols - 4` cells (F-504).
    public static func clean(_ copied: String, rows screen: [String], cols: Int) -> String {
        let lines = copied.components(separatedBy: "\n")
        guard let (bottom, _, prompt) = InputBoxFinder.locate(screen.map { Array($0) }), bottom > prompt,
              lines.count <= bottom - prompt else { return copied }
        let box = screen[prompt..<bottom].enumerated().map { i, r in
            (i == 0 ? String(r.drop { $0 != "❯" }.dropFirst().drop { $0 == " " || $0 == "\u{a0}" }) : String(r.dropFirst(2)))
                .replacingOccurrences(of: "\u{a0}", with: " ").trimmingTrailingSpaces
        }
        let body = { (l: String) -> String in
            var s = l.replacingOccurrences(of: "\u{a0}", with: " ")
            if s.hasPrefix("❯ ") { s.removeFirst(2) } else if s.hasPrefix("  ") { s.removeFirst(2) }
            return s.trimmingTrailingSpaces
        }
        // The first line ends a box row; the middle ones are box rows whole; the last starts one.
        let first = lines[0].replacingOccurrences(of: "\u{a0}", with: " ").trimmingTrailingSpaces
        let head = first.hasPrefix("❯ ") ? String(first.dropFirst(2)) : first.hasPrefix("  ") ? String(first.dropFirst(2)) : first
        let n = lines.count
        // One line: only a whole row copied with its indent or marker (a triple click) changes.
        if n == 1 { return head != first && box.contains(head) ? head : copied }
        guard let a = (0...(box.count - n)).first(where: { a in
            box[a].hasSuffix(head) && (1..<(n - 1)).allSatisfy { box[a + $0] == body(lines[$0]) }
                && box[a + n - 1].hasPrefix(body(lines[n - 1]))
        }) else { return copied }
        let width = cols - 4
        var out = head
        for j in 1..<n {
            let prev = box[a + j - 1], next = box[a + j]
            out += softWrap(prev, next, width: width) ? (cells(prev) >= width ? "" : " ") : "\n"
            out += body(lines[j])
        }
        return out
    }

    /// A row break is a soft wrap when the next row's first word would have fit on this row (Claude breaks between words),
    /// or this row is full (a word longer than a row is broken inside it).
    static func softWrap(_ row: String, _ next: String, width: Int) -> Bool {
        guard !row.isEmpty, !next.isEmpty, !next.hasPrefix(" ") else { return false }
        let word = next.prefix { $0 != " " }
        return cells(row) >= width || cells(row) + 1 + cells(String(word)) > width
    }

    static func cells(_ s: String) -> Int { s.reduce(0) { $0 + ChatScreenReader.cellWidth($1) } }
}

extension String {
    var trimmingTrailingSpaces: String {
        var s = self
        while s.last == " " { s.removeLast() }
        return s
    }
}
