import DuoSearch
import Foundation

/// `duo2 search` and `duo2 search-status` (SRCH L10, FR-7.7): open the index read-only, embed
/// the query on the CPU, print results with paths and line ranges so Claude reads only what
/// matched (FR-7.7.5). Never writes anything, and works while Duo isn't running (S-NOAPP).
func runSearch(_ name: String, _ argv: [String]) -> Int32 {
    var words: [String] = [], projects: [String] = [], k = 8, exact = false, all = false, json = false
    var i = 0
    while i < argv.count {
        switch argv[i] {
        case "-k": i += 1; k = Int(argv[safe: i] ?? "") ?? k
        case "--project", "-p": i += 1; if let p = argv[safe: i] { projects.append(p) }
        case "--exact": exact = true
        case "--all-passages": all = true
        case "--json": json = true
        default: words.append(argv[i])
        }
        i += 1
    }
    let index: SearchIndex
    do { index = try SearchIndex(readOnly: true) } catch {
        return report(json, error: "\(error)")
    }
    guard index.modelMatches else {
        return report(json, error: "the search index was built with another model and is being rebuilt; try again shortly")
    }
    let coverage = (try? index.coverage()) ?? []
    let missing = coverage.filter { !$0.complete }
    let coverageLine = missing.isEmpty ? "complete"
        : "partial: " + missing.map { "\($0.project) \($0.indexed)/\($0.known) files" }.joined(separator: ", ")

    if name == "search-status" {
        if json { emit(["coverage": coverage.map { ["project": $0.project, "known": $0.known, "indexed": $0.indexed] as [String: Any] }, "complete": missing.isEmpty]) }
        else {
            print("Search covers \(coverage.count) projects: \(coverageLine)")
            for c in coverage { print("  \(c.project): \(c.indexed) of \(c.known) files") }
        }
        return 0
    }
    guard !words.isEmpty else { return report(json, error: "usage: duo2 search <query> [-k N] [--project P] [--exact] [--json]") }
    var q = SearchQuery(text: words.joined(separator: " "))
    q.projects = projects; q.exactOnly = exact; q.limit = k; q.passagesPerItem = all ? 5 : 1
    q.currentProject = currentProject()
    do {
        let embedder = exact ? nil : try Embedder(use: .query)
        let hits = try index.search(q, embedder: embedder)
        if json {
            emit(["query": q.text, "coverage": coverageLine, "complete": missing.isEmpty,
                  "results": hits.map { ["project": $0.project, "path": $0.path, "title": $0.title, "lines": [$0.startLine, $0.endLine],
                                         "locator": $0.locator, "matched": $0.matched, "score": (round($0.score * 1e4) / 1e4), "snippet": $0.snippet] as [String: Any] }])
        } else {
            if hits.isEmpty { print("No results.") }
            for (n, h) in hits.enumerated() {
                print("\(n + 1). \(h.project) · \(h.title):\(h.locator)  (\(h.matched.joined(separator: ", ")))")
                print("   \(h.path)")
                print("   \(h.snippet)")
            }
            if !missing.isEmpty { print("\nCoverage is \(coverageLine): results may be missing.") }
        }
        return 0
    } catch {
        return report(json, error: "\(error)")
    }
}

/// The project the terminal is in: the nearest folder with PROJECT.md or HOME.md.
func currentProject() -> String? {
    var dir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    while dir.path != "/" {
        if ["PROJECT.md", "HOME.md"].contains(where: { FileManager.default.fileExists(atPath: dir.appending(path: $0).path) }) {
            return dir.lastPathComponent
        }
        dir.deleteLastPathComponent()
    }
    return nil
}

func emit(_ obj: [String: Any]) {
    if let d = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys, .withoutEscapingSlashes]) {
        print(String(decoding: d, as: UTF8.self))
    }
}

func report(_ json: Bool, error: String) -> Int32 {
    if json { emit(["error": error]) } else { FileHandle.standardError.write(Data("duo2: \(error)\n".utf8)) }
    return 1
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
