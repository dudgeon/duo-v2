import Foundation

/// Where the terminal mic goes (DL-261): on the bottom rule of Claude's input box. A pure function over
/// the terminal's visible rows, so DuoChecks runs it on recorded screens.
public struct VoiceMicAnchor: Equatable, Sendable {
    /// The bottom rule's row (0 = top of the viewport).
    public let row: Int
    /// The mic's first and last cell on that row.
    public let firstCol: Int
    public let lastCol: Int
    public init(row: Int, firstCol: Int, lastCol: Int) { self.row = row; self.firstCol = firstCol; self.lastCol = lastCol }
}

public enum InputBoxFinder {
    /// Characters a rule row is drawn with: box drawing, and the one-eighth blocks 2.1.296 draws.
    public static func isRuleChar(_ c: Character) -> Bool {
        guard c.unicodeScalars.count == 1, let u = c.unicodeScalars.first else { return false }
        return (0x2500...0x257F).contains(u.value) || u.value == 0x2594 || u.value == 0x2581
    }

    /// A row that holds a run of at least 8 rule characters (a label may sit in it).
    static func isRuleRow(_ row: [Character]) -> Bool {
        var run = 0
        for c in row {
            if isRuleChar(c) { run += 1; if run >= 8 { return true } } else { run = 0 }
        }
        return false
    }

    /// The prompt marker as the first thing in the box's first row (after a side border), and not a
    /// question's numbered choice (`❯ 1. Yes`).
    static func startsWithPrompt(_ row: [Character]) -> Bool {
        var i = 0
        while i < row.count, row[i] == " " || row[i] == "│" || row[i] == "┃" { i += 1 }
        guard i < row.count, ["❯", ">", "›"].contains(row[i]) else { return false }
        let rest = String(row[(i + 1)...]).trimmingCharacters(in: .whitespaces)
        return rest.range(of: #"^\d+[.)]\s"#, options: .regularExpression) == nil
    }

    /// A question or picker on screen: a numbered choice under a marker, or the footer that goes with one.
    public static func questionShowing(_ rows: [String]) -> Bool {
        rows.contains { r in
            let t = r.trimmingCharacters(in: .whitespaces)
            return t.range(of: #"^[❯>›]\s+\d+[.)]\s"#, options: .regularExpression) != nil
                || t.hasPrefix("Esc to cancel") || t.contains("Enter to confirm") || t.contains("to adjust · Enter")
        }
    }

    /// The mic's cells, or nil when it must hide: no box, a question up, scrolled back, or any cell under
    /// the mic holding something but a rule character.
    /// - Parameters:
    ///   - micCells: how many cells wide the mic is (24 pt over the cell width, rounded up).
    ///   - cursor: where the terminal's cursor is; the mic hides over it.
    public static func find(rows: [String], cursor: (row: Int, col: Int)? = nil, scrolledBack: Bool = false, micCells: Int) -> VoiceMicAnchor? {
        guard !scrolledBack, micCells > 0, !questionShowing(rows) else { return nil }
        let grid = rows.map { Array($0) }
        var r = grid.count - 1
        while r >= 2 {
            let row = r
            r -= 1
            guard isRuleRow(grid[row]) else { continue }
            // The lowest box: a top rule, a prompt row right under it, then this bottom rule.
            var top = row - 1
            while top >= 0, !isRuleRow(grid[top]) { top -= 1 }
            guard top >= 0, top + 1 < row, startsWithPrompt(grid[top + 1]) else { continue }
            guard let corner = grid[row].lastIndex(where: isRuleChar) else { continue }
            let last = corner - 2, first = last - micCells + 1
            guard first >= 1, (first...last).allSatisfy({ isRuleChar(grid[row][$0]) }) else { return nil }
            if let c = cursor, c.row == row, (first...last).contains(c.col) { return nil }
            return VoiceMicAnchor(row: row, firstCol: first, lastCol: last)
        }
        return nil
    }
}
