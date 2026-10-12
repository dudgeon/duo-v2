import DuoKit
import Foundation

// C-84, F-292: the guards for the 0.2.5 and 0.2.6 chat freezes (F-208, F-225, F-226) are source scans.
// They find code by declaration, not by file path, so moving a type to another file can't switch them
// off, and each fails when its target isn't found, so a rename can't either.

/// Every Swift file under `Sources/`, read once, with the declarations found in them.
struct SourceIndex {
    struct File { let path: String; let text: String }
    let files: [File]

    init(root: URL = repoRoot().appending(path: "Sources")) {
        var found: [File] = []
        let urls = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?.compactMap { $0 as? URL } ?? []
        for u in urls where u.pathExtension == "swift" {
            if let t = try? String(contentsOf: u, encoding: .utf8) { found.append(File(path: String(u.path.dropFirst(root.path.count + 1)), text: t)) }
        }
        files = found.sorted { $0.path < $1.path }
    }

    /// The bodies (between the braces) of `struct/class/enum/extension Name`, wherever they are.
    /// Empty when the type isn't declared anywhere.
    func declarations(of name: String) -> [(path: String, body: String)] {
        let pattern = #"(?m)^[ \t]*(?:@\w+[ \t]+)*(?:(?:public|internal|private|fileprivate|final|open|nonisolated)[ \t]+)*(?:struct|class|enum|extension)[ \t]+"# + NSRegularExpression.escapedPattern(for: name) + #"\b"#
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        var out: [(path: String, body: String)] = []
        for f in files {
            let ns = f.text as NSString
            for m in re.matches(in: f.text, range: NSRange(location: 0, length: ns.length)) {
                guard let body = Self.braced(ns, from: m.range.location + m.range.length) else { continue }
                out.append((f.path, body))
            }
        }
        return out
    }

    /// The text between the first `{` at or after `start` and its matching `}`.
    private static func braced(_ s: NSString, from start: Int) -> String? {
        var i = start, depth = 0, open = -1
        while i < s.length {
            let c = s.character(at: i)
            if c == 0x7B { if depth == 0 { open = i + 1 }; depth += 1 }
            else if c == 0x7D, depth > 0 { depth -= 1; if depth == 0 { return s.substring(with: NSRange(location: open, length: i - open)) } }
            i += 1
        }
        return nil
    }

    /// The code lines of `text` (comment lines dropped), trimmed.
    static func codeLines(_ text: String) -> [String] {
        text.split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.hasPrefix("//") }
    }
}

/// Lines of the named types' declarations (and their extensions) matching `forbidden`, as "Type (file): line".
/// A type that isn't declared is itself a finding: "type X not found".
func freezeGuardFindings(index: SourceIndex, types: [String], forbidden: String) -> [String] {
    var found: [String] = []
    for t in types {
        let decls = index.declarations(of: t)
        if decls.isEmpty { found.append("type \(t) not found"); continue }
        for d in decls {
            for line in SourceIndex.codeLines(d.body) where line.range(of: forbidden, options: .regularExpression) != nil {
                found.append("\(t) (\(d.path)): \(line)")
            }
        }
    }
    return found
}

/// Re-anchoring on size changes (F-225), anywhere the chat feed can live: every file of `Chat/`, plus
/// any file that declares `ChatPane` or `ChatFeedShape`. Fails when a target type isn't found.
func sizeChangesFindings(index: SourceIndex) -> [String] {
    var paths = Set(index.files.filter { $0.path.hasPrefix("DuoKit/Chat/") }.map(\.path))
    var found: [String] = paths.isEmpty ? ["no files in DuoKit/Chat/"] : []
    for t in ["ChatPane", "ChatFeedShape"] {
        let decls = index.declarations(of: t)
        if decls.isEmpty { found.append("type \(t) not found") }
        decls.forEach { paths.insert($0.path) }
    }
    for f in index.files where paths.contains(f.path) {
        for line in SourceIndex.codeLines(f.text) where line.contains(".sizeChanges") { found.append("\(f.path): \(line)") }
    }
    return found
}

@MainActor func freezeGuardChecks() {
    print("the freeze guards find their targets by declaration (C-84, F-292)")
    let index = SourceIndex()
    check(index.files.count > 50, "the source index reads Sources/ (\(index.files.count) files)")

    let sizeChanges = sizeChangesFindings(index: index)
    check(sizeChanges.isEmpty, "no file of the chat feed asks SwiftUI to re-anchor on size changes (\(sizeChanges))")

    // F-208: a root-level view that reads a session's chat state re-lays out the whole window when that
    // session changes. Panes read it; the root never does.
    let chatState = #"model\.(homeShowsChat|consoleShowsChat|chats|chat\(|fixtureChats|terminals)|\.fallback\b|\.showsChat\b|\.screen\b"#
    let layout = freezeGuardFindings(index: index, types: ["RootView", "AllProjectsLayout", "ProjectLayout"], forbidden: chatState)
    check(layout.isEmpty, "RootView, AllProjectsLayout and ProjectLayout read no chat or terminal state (\(layout))")

    // The root also hosts the toolbar and the overlays; none may read every session or a key DuoState
    // writes on every look (`seen`), or each write re-lays out the window.
    let broad = #"\bfixture\.sessions\b|\.seen\b"#
    let hosted = freezeGuardFindings(index: index,
        types: ["RootView", "AllProjectsLayout", "ProjectLayout", "DuoToolbar", "SheetOverlay", "ExplainerOverlay", "SearchOverlay", "DimmedUnderSheet"],
        forbidden: broad)
    check(hosted.isEmpty, "the root, toolbar and overlays never read model.fixture.sessions or DuoState.seen (\(hosted))")

    let split = index.files.filter { $0.path.hasSuffix("PaneSplit.swift") }.map(\.text).joined(separator: "\n")
    let update = split.range(of: "func updateNSView").map { String(split[$0.lowerBound...].prefix(400)) } ?? ""
    check(!update.isEmpty && !update.contains("rootView ="), "PaneSplit never replaces a pane's root view on update (PaneSplit.swift and func updateNSView found)")

    // F-226: the feed's stack choice, found in whichever file declares ChatPane.
    let pane = index.declarations(of: "ChatPane").map(\.body).joined(separator: "\n")
    check(!pane.isEmpty, "type ChatPane found")
    check(pane.contains("ChatFeedShape.isLazy(items: chat.log.items.count, steps: chat.log.steps.count)") && pane.contains("VStack(alignment: .leading, spacing: 16) { rows }"),
          "and ChatPane chooses its stack by that rule")
}
