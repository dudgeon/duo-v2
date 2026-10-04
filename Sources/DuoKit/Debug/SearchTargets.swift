import Foundation

/// The search-handoff targets as window states (search-handoff §6), built from the fixture's
/// `search` section. `search-jump` is superseded by DL-80 (no Jump scope) and `search-look` is a
/// component sheet, so neither is a window state.
@MainActor
public enum SearchTargets {
    nonisolated public static let screens = ["search-overview", "search-project", "search-project-narrowed", "search-empty", "search-typing",
                          "search-exact", "search-similar", "search-none", "search-first-run", "search-rebuilding", "search-error",
                          "search-actions-file", "search-actions-session", "search-multi", "search-open-file", "search-open-session"]

    public static func apply(_ screen: String, to model: AppModel) {
        let f = SearchFixture.load()
        let s = model.search
        s.reset()
        s.fixtureCoverage = f.coverage
        s.coverage = f.coverage
        s.recents = f.recents
        let inside = ["search-project", "search-project-narrowed", "search-open-file", "search-open-session"].contains(screen)
        TargetState(rawValue: inside ? "project" : "overview")?.apply(to: model)
        s.sendTargetName = inside ? f.sendInside : f.sendAll
        s.openedIn = inside ? "checkout-redesign" : nil
        let main = f.queries.first { $0.query == "where did we land on saved cards" }
        s.isOpen = true
        func results(_ q: SearchFixture.Query?) { s.query = q?.query ?? ""; s.items = q?.items ?? []; s.phase = .results; s.selected = 0 }

        switch screen {
        case "search-overview", "search-project": results(main)
        case "search-project-narrowed":
            results(main)
            s.scopeProject = "checkout-redesign"
            s.items = s.items.filter { $0.project == "checkout-redesign" }
            s.moreElsewhere = (main?.items.count ?? 0) - s.items.count
        case "search-empty": s.phase = .empty
        case "search-typing":
            results(main)
            s.items = Array(s.items.prefix(2))
            s.stillSearching = "Searching sessions…"
        case "search-exact":
            results(f.queries.first { $0.query == "ERR_REFUND_409" })
            s.exact = true
        case "search-similar":
            results(main)
            s.similarTo = main?.items.first
            s.similarReturnsTo = main?.query
            s.query = ""
            s.items = Array((main?.items ?? []).dropFirst()).map { var i = $0; i.matchedBy = ["similar"]; return i }
        case "search-none":
            s.query = "customers charged twice"
            s.kind = .memory; s.time = .week
            s.phase = .none("Nothing in memory from the past week matches “customers charged twice”.", 3)
        case "search-first-run":
            results(main)
            s.items = Array(s.items.prefix(2))
            s.firstRun = f.firstRun
        case "search-rebuilding":
            s.forcedIndexState = .rebuilding("The search model changed, so everything is being indexed again. About 4 minutes left.")
            s.phase = .rebuilding("The search model changed, so everything is being indexed again. About 4 minutes left.")
        case "search-error":
            s.forcedIndexState = .unreadable("database disk image is malformed")
            s.phase = .unreadable("database disk image is malformed")
        case "search-actions-file":
            results(main); s.menuOpen = true
        case "search-actions-session":
            results(main); s.selected = 1; s.menuOpen = true
        case "search-multi":
            results(main); s.multi = [0, 1]; s.selected = 1
        case "search-open-file":
            s.isOpen = false
            model.rightTab = "docs/prd-v2.md"
            model.searchLanding = .init(section: "What we heard", label: "L40–58 · from search")
        case "search-open-session":
            s.isOpen = false
            if let item = main?.items.first(where: { $0.kind == .session }) {
                model.readOnlySession = ReadOnlySession(item: item)
                model.rightTab = ReadOnlySession.tabKey
            }
        default: break
        }
    }
}

/// The fixture's `search` section (search-handoff `fixture-search.json`, merged into fixture.json).
struct SearchFixture {
    struct Query { var query: String; var items: [SearchItem] }
    var coverage: String?
    var firstRun: (String, String)?
    var recents: [(query: String, when: String)] = []
    var sendAll: String?
    var sendInside: String?
    var queries: [Query] = []

    static func load() -> SearchFixture {
        var out = SearchFixture()
        guard let url = Bundle.main.url(forResource: "fixture", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let s = root["search"] as? [String: Any] else { return out }
        out.coverage = s["coverage"] as? String
        if let fr = s["firstRun"] as? String {
            // "Building the index for the first time. Newest first: …" → headline, detail.
            let parts = fr.components(separatedBy: ". ")
            out.firstRun = (parts.first.map { $0 + "." } ?? fr, parts.dropFirst().joined(separator: ". "))
        }
        out.recents = (s["recent"] as? [[String: Any]] ?? []).map { ($0["query"] as? String ?? "", $0["when"] as? String ?? "") }
        if let t = s["sendTarget"] as? [String: Any] { out.sendAll = t["allProjects"] as? String; out.sendInside = t["insideProject"] as? String }
        for q in s["queries"] as? [[String: Any]] ?? [] {
            let text = q["query"] as? String ?? ""
            let items = (q["results"] as? [[String: Any]] ?? []).enumerated().map { n, r in item(r, n: n, query: text) }
            out.queries.append(.init(query: text, items: items))
        }
        return out
    }

    static func item(_ r: [String: Any], n: Int, query: String) -> SearchItem {
        let kind = SearchItem.Kind(rawValue: r["kind"] as? String ?? "file") ?? .file
        var i = SearchItem(id: "fixture:\(query):\(n)", kind: kind, project: r["project"] as? String,
                           unfiled: r["unfiled"] as? Bool ?? false, title: r["title"] as? String ?? "")
        i.location = r["where"] as? String ?? ""
        i.matchedBy = r["matchedBy"] as? [String] ?? []
        i.date = r["date"] as? String
        i.snippet = r["snippet"] as? String
        i.matchedWords = r["matchedWords"] as? [String] ?? []
        i.alsoIn = r["alsoIn"] as? [String] ?? []
        i.archived = r["archived"] as? Bool ?? false
        if i.isExact {
            i.matchedWords = [query]
            if i.snippet == nil { i.snippet = query }
        }
        i.passages = (r["passages"] as? [[String: Any]] ?? []).map {
            .init(location: $0["where"] as? String ?? "", heading: $0["heading"] as? String, snippet: $0["snippet"] as? String ?? "")
        }
        if i.passages.isEmpty, kind == .file { i.passages = [.init(location: i.location, heading: nil, snippet: i.snippet ?? "")] }
        let nums = i.location.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        i.startLine = nums.first ?? 0; i.endLine = nums.last ?? 0
        if kind == .session {
            // The matched turn and its neighbours (the fixture gives only the matched one).
            let snip = i.snippet ?? ""
            let parts = snip.components(separatedBy: " Claude: ")
            let you = parts.first.map { $0.hasPrefix("You: ") ? String($0.dropFirst(5)) : $0 }
            let n = i.startLine
            i.turns = [.init(number: n - 1, you: nil, claude: nil, matched: false),
                       .init(number: n, you: parts.count > 1 ? you : nil, claude: parts.count > 1 ? parts[1] : you, matched: true),
                       .init(number: n + 1, you: nil, claude: nil, matched: false)]
        }
        return i
    }
}
