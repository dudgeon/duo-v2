import Foundation

// The style guardrail (style-audit §9, DL-252): what keeps "a future feature never thinks about a scheme" true is a check
// that fails. Views get a colour only from a token, and a font only from a style or a token; a web page only through
// `var(--duo-*)`. Colour and font are gates. Metrics (padding, stroke and radius literals) are reported, never failed.
//
// How a new view could break it: a hex colour, `Color(red:)`, a system colour (`.secondary`, `Color.accentColor`,
// `NSColor.labelColor`, `.background(.bar)`) or a font size typed by hand draws the same in every scheme, so in Classic
// (or any later scheme) it is the one thing on screen that does not change. Any of those lines fails this check.

private struct StyleRule {
    let name: String
    let pattern: String
}

/// Files that are allowed to name a colour or a size: the generated tokens, the colour plumbing, debug drawing.
private func styleAllowed(_ path: String) -> Bool {
    path.hasSuffix("Design/Tokens.swift") || path.hasSuffix("Design/ColorSupport.swift") || path.contains("/Debug/")
}

/// Strips `//` comments, so prose that names a colour does not trip the scan.
private func code(_ line: Substring) -> String {
    if let r = line.range(of: "//") {
        let before = line[..<r.lowerBound]
        // keep URLs ("https://") and string contents that hold "//"
        if before.hasSuffix(":") { return String(line) }
        return String(before)
    }
    return String(line)
}

private func styleSources(_ dir: String, ext: Set<String>) -> [URL] {
    let root = repoRoot().appending(path: dir)
    return (FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?.compactMap { $0 as? URL } ?? [])
        .filter { ext.contains($0.pathExtension) && !$0.path.contains("/dist/") && !$0.path.contains("node_modules") }
}

@MainActor func styleLiteralChecks() throws {
    print("style literals: colour and font only from tokens (style-audit §9)")
    let swiftColour: [StyleRule] = [
        StyleRule(name: "hex colour literal", pattern: #"0x[0-9A-Fa-f]{6}\b"#),
        StyleRule(name: "Color(red:)", pattern: #"\bColor\((?:\.sRGB, )?red:"#),
        StyleRule(name: "NSColor(srgbRed:/white:/calibrated…)", pattern: #"NSColor\((?:srgbRed|white|calibrated|deviceRed|red):"#),
        StyleRule(name: "system accent", pattern: #"\bColor\.accentColor\b|\.controlAccentColor\b|\.accentColor\b"#),
        StyleRule(name: "system label colour", pattern: #"NSColor\.(?:label|secondaryLabel|tertiaryLabel|textColor|windowBackgroundColor|controlBackgroundColor|controlTextColor)\b"#),
        StyleRule(name: "semantic style colour", pattern: #"\.foregroundStyle\(\.(?:primary|secondary|tertiary|quaternary|blue|red|green|orange|yellow|gray|white|black)\)"#),
        StyleRule(name: "named SwiftUI colour", pattern: #"\bColor\.(?:red|blue|green|orange|yellow|gray|white|black|primary|secondary|pink|purple)\b"#),
        StyleRule(name: "system material", pattern: #"\.background\(\.(?:bar|regularMaterial|thinMaterial|ultraThinMaterial|thickMaterial)\)"#),
    ]
    let swiftFont: [StyleRule] = [
        StyleRule(name: "font size typed by hand", pattern: #"\.font\(\.system\(size: ?[0-9]|\bsystemFont\(ofSize: ?[0-9]|\bmonospacedSystemFont\(ofSize: ?[0-9]"#),
        StyleRule(name: "system text style", pattern: #"\.font\(\.(?:caption2?|title[23]?|callout|headline|subheadline|footnote|largeTitle|body)\)"#),
        StyleRule(name: "system font size", pattern: #"smallSystemFontSize|\bsystemFontSize\b"#),
    ]
    let swiftMetric: [StyleRule] = [
        StyleRule(name: "padding literal", pattern: #"\.padding\((?:\.[a-z]+, ?)?[0-9]"#),
        StyleRule(name: "lineWidth literal", pattern: #"lineWidth: ?[0-9]"#),
        StyleRule(name: "cornerRadius literal", pattern: #"cornerRadius: ?[0-9]"#),
        StyleRule(name: "stack spacing literal", pattern: #"(?:HStack|VStack|LazyVStack|LazyHStack)\([^)]*spacing: ?[0-9]"#),
    ]
    func scan(_ files: [URL], _ rules: [StyleRule], allowed: (String) -> Bool = styleAllowed, extraSkip: (String) -> Bool = { _ in false }) -> [String: [String]] {
        var hits: [String: [String]] = [:]
        for f in files where !allowed(f.path) {
            guard let text = try? String(contentsOf: f, encoding: .utf8) else { continue }
            for (n, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                let c = code(line)
                if extraSkip(c) { continue }
                for r in rules where c.range(of: r.pattern, options: .regularExpression) != nil {
                    hits[r.name, default: []].append("\(f.lastPathComponent):\(n + 1)")
                }
            }
        }
        return hits
    }
    let swiftFiles = styleSources("Sources/DuoKit", ext: ["swift"])
    // The only non-token colour type view code may name is the terminal library's own, converted from a token.
    let colourHits = scan(swiftFiles, swiftColour, extraSkip: { $0.contains("SwiftTerm.Color(") })
    check(colourHits.isEmpty, "no colour literal or system colour in view code (\(colourHits.map { "\($0.key): \($0.value.prefix(4))" }))")
    let fontHits = scan(swiftFiles, swiftFont)
    check(fontHits.isEmpty, "no font typed by hand in view code: styles and symbol sizes come from tokens (\(fontHits.map { "\($0.key): \($0.value.prefix(4))" }))")
    let metricHits = scan(swiftFiles, swiftMetric)
    print("  metrics (report only): " + (metricHits.isEmpty ? "none" : metricHits.keys.sorted().map { "\($0) \(metricHits[$0]!.count)" }.joined(separator: ", ")))

    let web = styleSources("Vendor/codemirror/src", ext: ["js"]) + styleSources("Vendor/docx-viewer", ext: ["html"]) + styleSources("Vendor/pptx-renderer", ext: ["html"])
    let hexRule = try NSRegularExpression(pattern: #"#[0-9A-Fa-f]{6}\b|#[0-9A-Fa-f]{3}\b(?![\w-])|\brgba?\(|\bhsla?\("#)
    let famRule = try NSRegularExpression(pattern: #"-apple-system|BlinkMacSystemFont|ui-monospace|'SF Mono'|SFMono|system-ui|\bsans-serif\b|\bmonospace\b|\bserif\b|Helvetica|Menlo"#)
    var webColour: [String] = [], webFamily: [String] = [], webPx = 0
    for f in web {
        guard let text = try? String(contentsOf: f, encoding: .utf8) else { continue }
        for (n, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let l = String(line)
            let range = NSRange(l.startIndex..., in: l)
            // A colour in a comment is prose; var(--duo-*) is the way, so only code lines count.
            let trimmed = l.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("//") || trimmed.hasPrefix("*") || trimmed.hasPrefix("/*") { continue }
            if hexRule.firstMatch(in: l, range: range) != nil, !l.contains("--duo-shadow") { webColour.append("\(f.lastPathComponent):\(n + 1)") }
            if famRule.firstMatch(in: l, range: range) != nil { webFamily.append("\(f.lastPathComponent):\(n + 1)") }
            webPx += l.components(separatedBy: "px").count - 1
        }
    }
    check(webColour.isEmpty, "no hex or rgb() colour in the editor, Word and deck pages: only var(--duo-*) (\(webColour.prefix(6)))")
    check(webFamily.isEmpty, "no font family typed in the editor, Word and deck pages: var(--duo-font-*) (\(webFamily.prefix(6)))")
    print("  web px literals (report only): \(webPx)")

    // The generated tokens are current: regenerate to a temp file and compare.
    let root = repoRoot()
    let tmp = FileManager.default.temporaryDirectory.appending(path: "duo-tokens-check-\(getpid()).swift")
    defer { try? FileManager.default.removeItem(at: tmp) }
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
    p.arguments = [root.appending(path: "scripts/gen-tokens.py").path, "--out", tmp.path]
    p.standardOutput = Pipe()
    try p.run()
    p.waitUntilExit()
    let fresh = try? String(contentsOf: tmp, encoding: .utf8)
    let have = try? String(contentsOf: root.appending(path: "Sources/DuoKit/Design/Tokens.swift"), encoding: .utf8)
    check(p.terminationStatus == 0 && fresh != nil && fresh == have, "Tokens.swift is what gen-tokens.py makes from tokens.json (run it after editing tokens.json)")
}
