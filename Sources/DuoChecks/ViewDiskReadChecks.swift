import DuoKit
import Foundation

// Views never read the disk (F-442). A context menu's content is built with the row, so a disk read in a
// menu runs per row per render: SessionOrganizeMenu read every tasks/*.md for each of a few hundred Home
// rows on each live refresh, and the main thread stalled 1-4 s every few seconds (0.2.18 to 0.2.21). Views
// read what the live refresh already loaded off the main thread (`fixture.tasks`, `taskSummaries(in:)`).
//
// The scan: each `struct …: View` / `ViewModifier` in DuoKit, brace-matched, must not name a disk read below.

private let viewDiskReads: [(name: String, pattern: String)] = [
    ("taskNotes(in:) (reads tasks/*.md)", #"\btaskNotes\(in:"#),
    ("TaskNotes.load (reads tasks/*.md)", #"\bTaskNotes\.load\("#),
    ("SessionIndex.load (reads the project's index)", #"\bSessionIndex\.load\("#),
    ("directory listing", #"\bcontentsOfDirectory\("#),
]

/// The view structs in a file: (name, body text), brace-matched from the declaration.
private func viewBodies(_ text: String) -> [(String, String)] {
    guard let re = try? NSRegularExpression(pattern: #"struct (\w+)\s*:\s*(?:[\w.]+,\s*)*(?:View|ViewModifier)\b[^{]*\{"#) else { return [] }
    let ns = text as NSString
    return re.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { m in
        let name = ns.substring(with: m.range(at: 1))
        let chars = Array(ns.substring(from: m.range.location + m.range.length).utf16)
        var depth = 1, i = 0
        while i < chars.count, depth > 0 {
            if chars[i] == 123 { depth += 1 } else if chars[i] == 125 { depth -= 1 }
            i += 1
        }
        return (name, String(utf16CodeUnits: chars, count: i))
    }
}

@MainActor func viewDiskReadChecks() throws {
    print("view disk reads: no view's body reads tasks/ or the disk (F-442)")
    let root = repoRoot().appending(path: "Sources/DuoKit")
    let files = (FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?.compactMap { $0 as? URL } ?? [])
        .filter { $0.pathExtension == "swift" && !$0.path.contains("/Debug/") }
    var hits: [String] = []
    for f in files {
        guard let text = try? String(contentsOf: f, encoding: .utf8) else { continue }
        for (name, body) in viewBodies(text) {
            let lines = body.split(separator: "\n", omittingEmptySubsequences: false).map { l in l.range(of: "//").map { String(l[..<$0.lowerBound]) } ?? String(l) }
            for rule in viewDiskReads where lines.contains(where: { $0.range(of: rule.pattern, options: .regularExpression) != nil }) {
                hits.append("\(f.lastPathComponent) \(name): \(rule.name)")
            }
        }
    }
    check(hits.isEmpty, "no view reads the disk in its body (\(hits.isEmpty ? "none" : hits.joined(separator: "; ")))")
    check(viewBodies("struct A: View {\n var body: some View { let t = model.taskNotes(in: p) }\n}\nstruct B {}").first?.1.contains("taskNotes(in:") == true,
          "the scan sees a view's body (a planted taskNotes(in:) is found)")

    // The menus' source: the live refresh's summaries, by project, in path order; no folder read.
    let m = AppModel(fixture: try repoFixture())
    m.fixture.tasks = [Fixture.TaskSummary(project: "a", path: "tasks/x.md", title: "X", status: "open", sessionIds: ["s1"]),
                       Fixture.TaskSummary(project: "b", path: "tasks/y.md", title: "Y", status: nil, sessionIds: []),
                       Fixture.TaskSummary(project: "a", path: "tasks/z.md", title: "Z", status: nil, sessionIds: [], archived: true)]
    check(m.taskSummaries(in: "a").map(\.path) == ["tasks/x.md", "tasks/z.md"] && m.taskSummaries(in: "c").isEmpty,
          "taskSummaries(in:) is the project's notes from the last refresh, without a project folder")
}
