import Foundation

/// One GitHub issue a task links (DL-226, github-issues-handoff board 3): `issue:` in the task's
/// frontmatter, one quoted URL. Read as written in any form a person might type (a URL,
/// `owner/repo#123`, `#123` in the project's repo), written back only as the full URL.
public struct IssueRef: Equatable, Hashable, Sendable {
    public var host: String
    public var owner: String
    public var name: String
    public var number: Int

    public init(host: String = "github.com", owner: String, name: String, number: Int) {
        self.host = host.lowercased(); self.owner = owner; self.name = name; self.number = number
    }

    public var repo: RemoteRepo { RemoteRepo(host: host, owner: owner, name: name) }
    public var slug: String { "\(owner)/\(name)" }
    public var short: String { "#\(number)" }
    public var url: String { "https://\(host)/\(owner)/\(name)/issues/\(number)" }
    public var webURL: URL { URL(string: url)! }

    /// Reads `https://host/o/r/issues/n` (also `/pull/n`, a trailing slash or fragment), `o/r#n`,
    /// and `#n` or `n` when `repo` (the project's own) is given. Nil for anything else.
    public static func parse(_ raw: String, repo: RemoteRepo? = nil) -> IssueRef? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // A markdown link, quoted or not: [#451 title](url).
        if let r = s.range(of: #"\]\(([^)\s]+)\)"#, options: .regularExpression) {
            s = String(s[r].dropFirst(2).dropLast())
        }
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
        guard !s.isEmpty else { return nil }
        if s.contains("://") {
            guard let u = URL(string: s), let host = u.host else { return nil }
            let parts = u.pathComponents.filter { $0 != "/" }
            guard parts.count >= 4, ["issues", "pull"].contains(parts[2]), let n = Int(parts[3]), n > 0 else { return nil }
            return IssueRef(host: host, owner: parts[0], name: parts[1], number: n)
        }
        if let m = s.range(of: #"^([A-Za-z0-9._-]+)/([A-Za-z0-9._-]+)#([0-9]+)$"#, options: .regularExpression) {
            let t = s[m]
            let hash = t.firstIndex(of: "#")!
            let slug = t[..<hash].split(separator: "/")
            guard let n = Int(t[t.index(after: hash)...]), n > 0 else { return nil }
            return IssueRef(host: repo?.host ?? "github.com", owner: String(slug[0]), name: String(slug[1]), number: n)
        }
        let digits = s.hasPrefix("#") ? String(s.dropFirst()) : s
        if let n = Int(digits), n > 0, let repo {
            return IssueRef(host: repo.host, owner: repo.owner, name: repo.name, number: n)
        }
        return nil
    }
}

/// What GitHub says about an issue now (a cached read).
public struct IssueInfo: Equatable, Sendable {
    public var ref: IssueRef
    public var title: String
    public var open: Bool
    /// "completed", "not_planned", "reopened" or nil, as gh reports it.
    public var stateReason: String?
    public var labels: [String]
    public var updated: String?
    public init(ref: IssueRef, title: String, open: Bool, stateReason: String? = nil, labels: [String] = [], updated: String? = nil) {
        self.ref = ref; self.title = title; self.open = open; self.stateReason = stateReason; self.labels = labels; self.updated = updated
    }

    /// "open · bug, p1" or "closed · bug" (board 3): the state, then the labels, in text2.
    public var detail: String {
        let state = open ? "open" : (stateReason == "not_planned" ? "closed · not planned" : "closed")
        return ([state] + (labels.isEmpty ? [] : [labels.joined(separator: ", ")])).joined(separator: " · ")
    }

    /// Parses `gh issue view --json number,title,state,stateReason,labels,url,updatedAt`.
    public static func parse(_ json: String, ref: IssueRef) -> IssueInfo? {
        guard let data = json.data(using: .utf8), let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let title = j["title"] as? String, let state = (j["state"] as? String)?.uppercased() else { return nil }
        let labels = (j["labels"] as? [[String: Any]])?.compactMap { $0["name"] as? String } ?? []
        let reason = (j["stateReason"] as? String).flatMap { $0.isEmpty ? nil : $0.lowercased() }
        return IssueInfo(ref: ref, title: title, open: state == "OPEN", stateReason: reason, labels: labels, updated: j["updatedAt"] as? String)
    }
}

/// Why an issue's state can't be shown (a repo without gh, or without access): the row says so.
public enum IssueUnavailable: Error, Equatable, Sendable {
    case noGH, signedOut, noAccess, offline, other(String)

    public var words: String {
        switch self {
        case .noGH: "GitHub’s command-line tool (gh) isn’t on this Mac"
        case .signedOut: "you’re not signed in to GitHub (gh auth login)"
        case .noAccess: "GitHub says this account can’t see it"
        case .offline: "Duo couldn’t reach GitHub"
        case .other(let s): s
        }
    }

    static func from(_ r: GitTool.Result) -> IssueUnavailable {
        switch GitFailure.from(r).kind {
        case .noGH: .noGH
        case .signedOut: .signedOut
        case .notFound, .noWrite, .sso: .noAccess
        case .offline: .offline
        default: .other(r.all.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "\n").first.map(String.init) ?? "gh failed")
        }
    }
}

/// Reads and writes issues through `gh` (never a token of Duo's own). Writes are only these:
/// close, reopen, and a new issue (DL-226).
public enum IssueTool {
    static func env(_ host: String) -> [String: String] { host == "github.com" ? [:] : ["GH_HOST": host] }

    public static func view(_ ref: IssueRef) -> Result<IssueInfo, IssueUnavailable> {
        let r = GitTool.gh(["issue", "view", String(ref.number), "-R", ref.slug, "--json", "number,title,state,stateReason,labels,url,updatedAt"],
                           in: nil, timeout: 15, env: env(ref.host))
        guard r.ok else { return .failure(.from(r)) }
        guard let info = IssueInfo.parse(r.out, ref: ref) else { return .failure(.other("gh gave an answer Duo couldn’t read")) }
        return .success(info)
    }

    /// The repo's open issues matching `query` (words match titles, `#n` matches numbers), for Link Issue….
    public static func search(_ repo: RemoteRepo, query: String, limit: Int = 8) -> Result<[IssueInfo], IssueUnavailable> {
        let q = query.trimmingCharacters(in: .whitespaces)
        var args = ["issue", "list", "-R", repo.slug, "--state", "open", "--limit", String(limit), "--json", "number,title,state,stateReason,labels,url,updatedAt"]
        if q.hasPrefix("#"), let n = Int(q.dropFirst()) {
            let one = view(IssueRef(host: repo.host, owner: repo.owner, name: repo.name, number: n))
            return one.map { [$0] }
        }
        if !q.isEmpty { args += ["--search", q] }
        let r = GitTool.gh(args, in: nil, timeout: 15, env: env(repo.host))
        guard r.ok else { return .failure(.from(r)) }
        guard let data = r.out.data(using: .utf8), let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return .failure(.other("gh gave an answer Duo couldn’t read"))
        }
        return .success(list.compactMap { j in
            guard let n = j["number"] as? Int, let d = try? JSONSerialization.data(withJSONObject: j), let s = String(data: d, encoding: .utf8) else { return nil }
            return IssueInfo.parse(s, ref: IssueRef(host: repo.host, owner: repo.owner, name: repo.name, number: n))
        })
    }

    /// `gh issue close` / `reopen`: the only changes Duo makes to an existing issue.
    public static func setOpen(_ ref: IssueRef, open: Bool) -> Result<Void, IssueUnavailable> {
        let r = GitTool.gh(["issue", open ? "reopen" : "close", String(ref.number), "-R", ref.slug], in: nil, timeout: 20, env: env(ref.host))
        // Already in that state is a success for our purposes (gh says so on stderr, exit 0).
        return r.ok ? .success(()) : .failure(.from(r))
    }

    /// New Issue from Task: the title and body written by the person (or drafted by Claude on request).
    public static func create(_ repo: RemoteRepo, title: String, body: String) -> Result<IssueRef, IssueUnavailable> {
        let file = FileManager.default.temporaryDirectory.appending(path: "duo-issue-\(UUID().uuidString).md")
        try? body.write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }
        let r = GitTool.gh(["issue", "create", "-R", repo.slug, "--title", title, "--body-file", file.path], in: nil, timeout: 30, env: env(repo.host))
        guard r.ok else { return .failure(.from(r)) }
        // gh prints the new issue's URL; its presence is the proof (F-196: exit codes lie).
        guard let line = r.out.split(separator: "\n").last(where: { $0.contains("/issues/") }),
              let ref = IssueRef.parse(String(line)) else { return .failure(.other("gh didn’t say where the issue is")) }
        return .success(ref)
    }

    /// The "Closes #n" lines for a pull request: one per ticked task issue in the repo (board 6).
    public static func closesLine(_ ref: IssueRef, in repo: RemoteRepo) -> String {
        ref.owner.lowercased() == repo.owner.lowercased() && ref.name.lowercased() == repo.name.lowercased() && ref.host == repo.host
            ? "Closes #\(ref.number)" : "Closes \(ref.slug)#\(ref.number)"
    }
}
