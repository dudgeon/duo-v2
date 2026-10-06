import Foundation

// Claude's Markdown, parsed into blocks chat mode draws natively (chat-mode-handoff `text`):
// headings, paragraphs (soft breaks kept as breaks, as the TUI shows them), bullet and numbered
// lists (nested), fenced code, tables, quotes and rules. Inline text (bold, italic, code, links)
// goes through Foundation's Markdown parser; file paths become links that open in Duo.

public indirect enum ChatBlock: Equatable, Sendable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case list(ordered: Bool, start: Int, items: [[ChatBlock]])
    case code(language: String?, text: String)
    case table(header: [String], rows: [[String]])
    case quote([ChatBlock])
    case rule
}

public enum ChatMarkdown {
    public static func parse(_ md: String) -> [ChatBlock] {
        parse(lines: md.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n"))
    }

    static func indent(_ l: String) -> Int { l.prefix { $0 == " " }.count + l.prefix { $0 == "\t" }.count * 4 }

    static func listMarker(_ l: String) -> (ordered: Bool, n: Int, indent: Int, content: Int)? {
        if let m = l.chatMatch(#"^(\s*)([-*+])\s+"#) { return (false, 1, m[1]?.count ?? 0, m[0]?.count ?? 0) }
        if let m = l.chatMatch(#"^(\s*)(\d{1,9})[.)]\s+"#) { return (true, Int(m[2] ?? "1") ?? 1, m[1]?.count ?? 0, m[0]?.count ?? 0) }
        return nil
    }

    static func isTableRow(_ l: String) -> Bool { l.trimmingCharacters(in: .whitespaces).hasPrefix("|") }
    static func isTableRule(_ l: String) -> Bool { l.chatTrim.chatIs(#"^\|?\s*:?-{2,}:?\s*(\|\s*:?-{2,}:?\s*)*\|?$"#) }
    static func cells(_ l: String) -> [String] {
        var t = l.chatTrim
        if t.hasPrefix("|") { t.removeFirst() }
        if t.hasSuffix("|") { t.removeLast() }
        return t.components(separatedBy: "|").map { $0.chatTrim }
    }

    static func parse(lines: [String]) -> [ChatBlock] {
        var out: [ChatBlock] = []
        var i = 0
        var para: [String] = []
        func flush() { if !para.isEmpty { out.append(.paragraph(para.joined(separator: "\n"))); para = [] } }
        while i < lines.count {
            let line = lines[i]
            let t = line.chatTrim
            if t.isEmpty { flush(); i += 1; continue }
            // Fenced code.
            if let m = t.chatMatch(#"^(```+|~~~+)\s*([\w+-]*)"#) {
                flush()
                let fence = m[1] ?? "```"
                var body: [String] = []
                let pad = indent(line)
                i += 1
                while i < lines.count, !lines[i].chatTrim.hasPrefix(fence) { body.append(String(lines[i].dropFirst(min(pad, indent(lines[i]))))); i += 1 }
                i += 1
                out.append(.code(language: (m[2] ?? "").isEmpty ? nil : m[2], text: body.joined(separator: "\n")))
                continue
            }
            if let m = t.chatMatch(#"^(#{1,6})\s+(.*?)\s*#*$"#) {
                flush(); out.append(.heading(level: m[1]?.count ?? 1, text: m[2] ?? "")); i += 1; continue
            }
            if t.chatIs(#"^([-*_])(\s*\1){2,}$"#) { flush(); out.append(.rule); i += 1; continue }
            if isTableRow(line), i + 1 < lines.count, isTableRule(lines[i + 1]) {
                flush()
                let header = cells(line)
                var rows: [[String]] = []
                i += 2
                while i < lines.count, isTableRow(lines[i]) { rows.append(cells(lines[i])); i += 1 }
                out.append(.table(header: header, rows: rows))
                continue
            }
            if t.hasPrefix(">") {
                flush()
                var body: [String] = []
                while i < lines.count, lines[i].chatTrim.hasPrefix(">") {
                    body.append(lines[i].chatTrim.replacingOccurrences(of: #"^>\s?"#, with: "", options: .regularExpression)); i += 1
                }
                out.append(.quote(parse(lines: body)))
                continue
            }
            if let first = listMarker(line), para.isEmpty || first.ordered == false || first.n == 1 {
                flush()
                var items: [[String]] = []
                let base = first.indent
                while i < lines.count {
                    let l = lines[i]
                    if let mk = listMarker(l), mk.indent <= base + 1, mk.ordered == first.ordered {
                        items.append([String(l.dropFirst(mk.content))]); i += 1; continue
                    }
                    if l.chatTrim.isEmpty {
                        // A blank line ends the list unless the next line continues it.
                        if i + 1 < lines.count, let mk = listMarker(lines[i + 1]), mk.indent <= base + 1, mk.ordered == first.ordered { i += 1; continue }
                        if i + 1 < lines.count, indent(lines[i + 1]) > base + 1, !items.isEmpty { items[items.count - 1].append(""); i += 1; continue }
                        break
                    }
                    if indent(l) > base, !items.isEmpty {
                        items[items.count - 1].append(String(l.dropFirst(min(indent(l), first.content - first.indent + base)))); i += 1; continue
                    }
                    if listMarker(l) == nil, !items.isEmpty, !isTableRow(l), !t.hasPrefix("#") {
                        items[items.count - 1].append(l.chatTrim); i += 1; continue   // a lazy continuation
                    }
                    break
                }
                out.append(.list(ordered: first.ordered, start: first.n, items: items.map { parse(lines: $0) }))
                continue
            }
            para.append(t)
            i += 1
        }
        flush()
        return out
    }

    // MARK: Inline

    /// Inline Markdown as an attributed string: Foundation parses emphasis, code and links; bare
    /// URLs and file paths (`docs/prd-v2.md`, `flows.md:42`) become links. File links use the
    /// `duo-file:` scheme, which the chat opens in Duo's editor.
    public static func inline(_ text: String) -> AttributedString {
        let opts = AttributedString.MarkdownParsingOptions(allowsExtendedAttributes: false, interpretedSyntax: .inlineOnlyPreservingWhitespace,
                                                           failurePolicy: .returnPartiallyParsedIfPossible)
        var a = (try? AttributedString(markdown: text, options: opts)) ?? AttributedString(text)
        linkify(&a)
        return a
    }

    /// Path-looking tokens: something/with/slashes.ext, or name.ext, optionally :line.
    static let pathPattern = #"(?<![\w/@.:-])((?:~|\.{1,2})?/?(?:[\w.@-]+/)*[\w@-][\w.@-]*\.[A-Za-z][A-Za-z0-9]{0,7}(?::\d+)?)(?![\w/])"#
    static let urlPattern = #"https?://[^\s)>\]]+[^\s)>\].,;:!?'\"]"#
    /// Extensions that make a bare name (no slash) a file.
    static let fileExtensions: Set<String> = ["md", "markdown", "txt", "swift", "js", "mjs", "ts", "tsx", "jsx", "py", "rb", "go", "rs", "json", "jsonl", "yaml", "yml",
                                              "toml", "html", "htm", "css", "csv", "sh", "zsh", "c", "h", "m", "cpp", "java", "kt", "sql", "xml", "plist", "log", "pdf", "png", "jpg"]

    static func linkify(_ a: inout AttributedString) {
        let plain = String(a.characters)
        let ns = plain as NSString
        var hits: [(NSRange, URL)] = []
        for m in ChatRegex.get(urlPattern).matches(in: plain, range: NSRange(location: 0, length: ns.length)) {
            if let u = URL(string: ns.substring(with: m.range)) { hits.append((m.range, u)) }
        }
        for m in ChatRegex.get(pathPattern).matches(in: plain, range: NSRange(location: 0, length: ns.length)) {
            let r = m.range(at: 1)
            guard !hits.contains(where: { NSIntersectionRange($0.0, r).length > 0 }) else { continue }
            let token = ns.substring(with: r)
            let file = token.replacingOccurrences(of: #":\d+$"#, with: "", options: .regularExpression)
            let ext = (file as NSString).pathExtension.lowercased()
            guard file.contains("/") || fileExtensions.contains(ext), !file.hasPrefix("www."), !file.chatIs(#"^\d+\.\d+"#) else { continue }
            if let u = fileURL(token) { hits.append((r, u)) }
        }
        for (r, u) in hits {
            guard let lo = AttributedString.Index(String.Index(utf16Offset: r.location, in: plain), within: a),
                  let hi = AttributedString.Index(String.Index(utf16Offset: r.location + r.length, in: plain), within: a) else { continue }
            if a[lo..<hi].link == nil { a[lo..<hi].link = u }
        }
    }

    /// `duo-file:<path>?line=<n>`.
    public static func fileURL(_ token: String) -> URL? {
        var c = URLComponents()
        c.scheme = "duo-file"
        if let m = token.chatMatch(#"^(.*):(\d+)$"#) {
            c.path = m[1] ?? token
            c.queryItems = [URLQueryItem(name: "line", value: m[2])]
        } else {
            c.path = token
        }
        return c.url
    }
}
