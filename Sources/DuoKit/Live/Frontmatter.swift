import Foundation

/// Reads YAML frontmatter from markdown files (`PROJECT.md`, `HOME.md`, `tasks/*.md`).
///
/// Read-only and deliberately small: flat `key: value` pairs, quoted strings, inline lists
/// (`[a, b]`) and block lists (`- a`). That covers the Obsidian-compatible schema (DL-6,
/// docs/research/obsidian-compatible-task-format.md: no nested YAML in Duo-owned keys).
/// Anything it doesn't understand is skipped, never fatal. Writing frontmatter is a separate,
/// surgical operation (LR-37) that never round-trips through this parser.
public struct Frontmatter: Sendable, Equatable {
    public var values: [String: FrontmatterValue] = [:]
    /// The markdown after the closing `---`.
    public var body: Substring = ""

    public subscript(_ key: String) -> FrontmatterValue? { values[key] }

    public func string(_ key: String) -> String? {
        if case .string(let s)? = values[key] { return s }
        return nil
    }

    public func list(_ key: String) -> [String] {
        switch values[key] {
        case .list(let l)?: l
        case .string(let s)?: [s]
        default: []
        }
    }

    public static func parse(_ text: String) -> Frontmatter {
        var fm = Frontmatter()
        // CRLF-safe; the fence must be the very first line (LR-37: split/join rules).
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        guard normalized.hasPrefix("---\n") else { fm.body = Substring(normalized); return fm }
        let afterOpen = normalized.dropFirst(4)
        guard let close = afterOpen.range(of: "\n---") else { fm.body = Substring(normalized); return fm }
        let yaml = afterOpen[..<close.lowerBound]
        var rest = afterOpen[close.upperBound...]
        if rest.hasPrefix("\n") { rest = rest.dropFirst() }
        fm.body = rest

        var currentListKey: String?
        for rawLine in yaml.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("#") || line.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            if let key = currentListKey, line.hasPrefix("  - ") || line.hasPrefix("- ") {
                let item = unquote(line.trimmingCharacters(in: .whitespaces).dropFirst(2).trimmingCharacters(in: .whitespaces))
                if case .list(var l)? = fm.values[key] { l.append(item); fm.values[key] = .list(l) }
                continue
            }
            currentListKey = nil
            guard !line.hasPrefix(" "), let colon = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            if value.isEmpty {
                fm.values[key] = .list([])
                currentListKey = key
            } else if value.hasPrefix("[") && value.hasSuffix("]") {
                let inner = value.dropFirst().dropLast()
                fm.values[key] = .list(inner.isEmpty ? [] : splitInlineList(String(inner)).map(unquote))
            } else {
                fm.values[key] = .string(unquote(value))
            }
        }
        // A key followed by nothing and no list items is an empty value.
        for (k, v) in fm.values { if case .list(let l) = v, l.isEmpty, k == currentListKey { fm.values[k] = .list([]) } }
        return fm
    }

    static func unquote(_ s: String) -> String {
        // Quoted YAML scalars: `\"` and `\\` inside double quotes, `''` inside single quotes.
        if s.count >= 2, s.hasPrefix("\""), s.hasSuffix("\"") {
            return String(s.dropFirst().dropLast()).replacing(/\\(["\\])/) { String($0.1) }
        }
        if s.count >= 2, s.hasPrefix("'"), s.hasSuffix("'") {
            return String(s.dropFirst().dropLast()).replacingOccurrences(of: "''", with: "'")
        }
        return s
    }

    /// Splits `a, "b, c", d` on commas outside quotes.
    static func splitInlineList(_ s: String) -> [String] {
        var items: [String] = [], current = "", quote: Character?
        for ch in s {
            if let q = quote { current.append(ch); if ch == q { quote = nil }; continue }
            if ch == "\"" || ch == "'" { quote = ch; current.append(ch); continue }
            if ch == "," { items.append(current.trimmingCharacters(in: .whitespaces)); current = ""; continue }
            current.append(ch)
        }
        let last = current.trimmingCharacters(in: .whitespaces)
        if !last.isEmpty { items.append(last) }
        return items
    }
}

public enum FrontmatterValue: Sendable, Equatable {
    case string(String)
    case list([String])
}
