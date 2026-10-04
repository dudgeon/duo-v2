import Foundation

/// Splits a file into passages for embedding, like the POC (smol-sim-search): Markdown and text by
/// paragraphs and headings, code by blank-line blocks, JSONL and CSV one record per unit; units
/// gathered up to 300 tokens with 15% overlap when a unit has to be split (SRCH FR-7.1.2).
public struct Chunk: Sendable, Equatable {
    public var text: String
    public var startLine: Int   // 1-based, inclusive
    public var endLine: Int
    public var locator: String { startLine == endLine ? "L\(startLine)" : "L\(startLine)-\(endLine)" }
}

public enum Chunker {
    public static let budget = 300
    public static let overlap = 45

    static let markdownExt: Set<String> = ["md", "markdown", "mdx", "rst", "txt", "text", "org", "adoc"]
    static let recordExt: Set<String> = ["jsonl", "ndjson"]
    static let tableExt: Set<String> = ["csv", "tsv"]

    struct Unit { var text: String; var start: Int; var end: Int }

    public static func chunks(path: String, text: String, tokenizer: WordPiece) -> [Chunk] {
        let ext = (path as NSString).pathExtension.lowercased()
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        let units: [Unit]
        if recordExt.contains(ext) {
            units = lines.enumerated().compactMap { i, l in l.trimmingCharacters(in: .whitespaces).isEmpty ? nil : Unit(text: l, start: i + 1, end: i + 1) }
        } else if tableExt.contains(ext) {
            units = tableUnits(lines, separator: ext == "tsv" ? "\t" : ",")
        } else {
            units = blockUnits(lines, headingsSplit: markdownExt.contains(ext))
        }
        return pack(units, tokenizer: tokenizer)
    }

    /// Paragraphs (Markdown, text) or blank-line blocks (code). A Markdown heading starts a unit.
    static func blockUnits(_ lines: [String], headingsSplit: Bool) -> [Unit] {
        var out: [Unit] = []
        var buf: [String] = [], start = 0
        func flush(_ end: Int) {
            let t = buf.joined(separator: "\n")
            if !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { out.append(Unit(text: t, start: start + 1, end: end)) }
            buf = []
        }
        for (i, line) in lines.enumerated() {
            if line.trimmingCharacters(in: .whitespaces).isEmpty { flush(i); start = i + 1; continue }
            if headingsSplit, line.hasPrefix("#"), !buf.isEmpty { flush(i); start = i }
            if buf.isEmpty { start = i }
            buf.append(line)
        }
        flush(lines.count)
        return out
    }

    /// One unit per row, as "column: value" pairs so each row reads on its own.
    static func tableUnits(_ lines: [String], separator: Character) -> [Unit] {
        guard let header = lines.first?.split(separator: separator, omittingEmptySubsequences: false).map(String.init) else { return [] }
        return lines.enumerated().dropFirst().compactMap { i, line in
            let cells = line.split(separator: separator, omittingEmptySubsequences: false).map(String.init)
            guard cells.contains(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else { return nil }
            let text = zip(header, cells).map { "\($0): \($1)" }.joined(separator: "; ")
            return Unit(text: text, start: i + 1, end: i + 1)
        }
    }

    /// Gathers units up to the budget; a unit over budget is split into overlapping windows.
    static func pack(_ units: [Unit], tokenizer: WordPiece) -> [Chunk] {
        var out: [Chunk] = []
        var cur: [Unit] = [], tokens = 0
        func emit() {
            guard let first = cur.first, let last = cur.last else { return }
            out.append(Chunk(text: cur.map(\.text).joined(separator: "\n\n"), startLine: first.start, endLine: last.end))
            cur = []; tokens = 0
        }
        for u in units {
            let n = tokenizer.tokenCount(u.text)
            if n > budget {
                emit()
                out += split(u, tokenizer: tokenizer)
                continue
            }
            if tokens + n > budget { emit() }
            cur.append(u); tokens += n
        }
        emit()
        return out
    }

    /// Word windows of about `budget` tokens, stepping by budget − overlap.
    static func split(_ u: Unit, tokenizer: WordPiece) -> [Chunk] {
        let lines = u.text.components(separatedBy: "\n")
        // (word, line) pairs so each window knows its lines.
        var words: [(String, Int)] = []
        for (i, l) in lines.enumerated() { for w in l.split(separator: " ") { words.append((String(w), u.start + i)) } }
        guard !words.isEmpty else { return [] }
        let costs = words.map { max(1, tokenizer.tokenCount($0.0)) }
        var out: [Chunk] = []
        var s = 0
        while s < words.count {
            var e = s, t = 0
            while e < words.count, t + costs[e] <= budget || e == s { t += costs[e]; e += 1 }
            out.append(Chunk(text: words[s..<e].map(\.0).joined(separator: " "), startLine: words[s].1, endLine: words[e - 1].1))
            if e >= words.count { break }
            // Step back about `overlap` tokens.
            var back = e, bt = 0
            while back > s + 1, bt < overlap { back -= 1; bt += costs[back] }
            s = max(back, s + 1)
        }
        return out
    }
}
