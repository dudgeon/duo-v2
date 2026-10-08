import Foundation

/// What Duo knows about the user and a GitHub repository before anything is pushed (DL-149, F-195).
/// Read with the user's own `gh` sign-in; without gh, most of it is unknown and Duo says so.
public struct GitHubAccess: Equatable, Sendable {
    public enum Permission: String, Sendable { case admin = "ADMIN", maintain = "MAINTAIN", write = "WRITE", triage = "TRIAGE", read = "READ" }
    public enum Sign: Equatable, Sendable { case noGH, signedOut, signedIn(login: String) }

    public var sign: Sign
    public var permission: Permission?
    public var visibility: String?        // "PUBLIC" / "PRIVATE" / "INTERNAL"
    public var defaultBranch: String?
    public var protectedDefault: Bool?
    public var found = true               // false: GitHub says not found (or no access, F-194)
    public var parent: RemoteRepo?         // set when the repo is itself a fork

    public init(sign: Sign, permission: Permission? = nil, defaultBranch: String? = nil, protectedDefault: Bool? = nil) {
        self.sign = sign; self.permission = permission; self.defaultBranch = defaultBranch; self.protectedDefault = protectedDefault
    }

    public var login: String? { if case .signedIn(let l) = sign { return l }; return nil }
    public var canPush: Bool? { permission.map { [.admin, .maintain, .write].contains($0) } }
    /// Read only only when GitHub *says* so: a failed probe is unknown, never read only (legacy forked anyway).
    public var readOnly: Bool { permission == .read || permission == .triage }

    /// `gh auth status --json hosts` exits 0 whatever the state (F-196), so read the JSON.
    public static func sign(host: String = "github.com") -> Sign {
        guard GitTool.ghPath != nil else { return .noGH }
        let r = GitTool.gh(["auth", "status", "--active", "--hostname", host, "--json", "hosts"], in: nil, timeout: 10)
        if let data = r.out.data(using: .utf8), let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let hosts = j["hosts"] as? [String: Any], let list = hosts[host] as? [[String: Any]] {
            for a in list where (a["state"] as? String) == "success" && (a["active"] as? Bool ?? true) {
                if let login = a["login"] as? String { return .signedIn(login: login) }
            }
            return .signedOut
        }
        // Older gh without --json: parse the text.
        let t = GitTool.gh(["auth", "status", "--hostname", host], in: nil, timeout: 10)
        if let m = t.all.range(of: #"account ([A-Za-z0-9-]+)"#, options: .regularExpression), t.status == 0 {
            return .signedIn(login: String(t.all[m].dropFirst(8)))
        }
        return .signedOut
    }

    public static func probe(_ repo: RemoteRepo) -> GitHubAccess {
        let sign = sign(host: repo.host)
        var a = GitHubAccess(sign: sign)
        guard case .signedIn = sign else { return a }
        let host = ["--hostname", repo.host]
        let v = GitTool.gh(["repo", "view", repo.slug, "--json", "viewerPermission,visibility,defaultBranchRef,isFork,parent"], in: nil, timeout: 15,
                           env: repo.host == "github.com" ? [:] : ["GH_HOST": repo.host])
        guard v.ok, let data = v.out.data(using: .utf8), let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            if GitFailure.classify(v.all).kind == .notFound { a.found = false }
            return a
        }
        a.permission = (j["viewerPermission"] as? String).flatMap(Permission.init(rawValue:))
        a.visibility = j["visibility"] as? String
        a.defaultBranch = (j["defaultBranchRef"] as? [String: Any])?["name"] as? String
        if let p = j["parent"] as? [String: Any], let o = (p["owner"] as? [String: Any])?["login"] as? String, let n = p["name"] as? String {
            a.parent = RemoteRepo(host: repo.host, owner: o, name: n)
        }
        if let b = a.defaultBranch {
            // `branches/<b>` says `protected` to any reader; `/protection` is admin-only (F-195).
            let pr = GitTool.gh(["api", "repos/\(repo.slug)/branches/\(b)", "--jq", ".protected"] + (repo.host == "github.com" ? [] : host), in: nil, timeout: 15)
            if pr.ok { a.protectedDefault = pr.out.trimmingCharacters(in: .whitespacesAndNewlines) == "true" }
            let rules = GitTool.gh(["api", "repos/\(repo.slug)/rules/branches/\(b)", "--jq", "[.[].type] | join(\",\")"] + (repo.host == "github.com" ? [] : host), in: nil, timeout: 15)
            if rules.ok, ["pull_request", "update", "non_fast_forward"].contains(where: rules.out.contains) { a.protectedDefault = true }
        }
        return a
    }
}

/// A failed git or gh step, classified once, with the words Duo shows (board 10, DL-149).
public struct GitFailure: Error, Equatable, Sendable {
    public enum Kind: String, Sendable {
        case noTools, noGH, signedOut, notFound, sso, protected, notFastForward, noWrite, secrets, offline, noIdentity, conflict, unknown
    }
    public var kind: Kind
    public var details: String
    public init(kind: Kind, details: String) { self.kind = kind; self.details = details }

    /// Stable tokens only (F-196, F-197): exit codes lie, so the words decide.
    public static func classify(_ text: String, timedOut: Bool = false, notFound: Bool = false) -> GitFailure {
        let t = text.lowercased()
        func has(_ s: String...) -> Bool { s.contains { t.contains($0.lowercased()) } }
        let k: Kind
        if notFound && has("command line tools") { k = .noTools }
        else if notFound && has("gh:") { k = .noGH }
        else if timedOut { k = .offline }
        else if has("saml enforcement", "saml sso", "single sign-on") { k = .sso }
        else if has("gh006", "protected branch") { k = .protected }
        else if has("gh009", "secret scanning", "secrets detected", "push protection") { k = .secrets }
        else if has("conflict (", "automatic merge failed", "fix conflicts") { k = .conflict }
        else if has("(fetch first)", "(non-fast-forward)", "updates were rejected because the remote contains") { k = .notFastForward }
        else if has("please tell me who you are", "author identity unknown", "unable to auto-detect email") { k = .noIdentity }
        else if has("permission to ", "the requested url returned error: 403", "must have push access", "write access to repository not granted") { k = .noWrite }
        else if has("could not read username", "authentication failed", "not logged into", "gh auth login", "terminal prompts disabled", "http 401", "bad credentials") { k = .signedOut }
        else if has("repository not found", "could not resolve to a repository", "http 404", "not found") { k = .notFound }
        else if has("could not resolve host", "network is unreachable", "connection timed out", "operation timed out", "unable to access", "connection refused") { k = .offline }
        else { k = .unknown }
        return GitFailure(kind: k, details: text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    public static func from(_ r: GitTool.Result) -> GitFailure { classify(r.all, timedOut: r.timedOut, notFound: r.notFound) }

    /// Title and body for Duo's question (board 10). `repo` is owner/name; `branch` the project's branch.
    public func words(repo: String, branch: String, login: String?, ahead: Int = 0, file: String? = nil) -> (title: String, body: String) {
        let acct = login.map { "your account, \($0)," } ?? "your account"
        switch kind {
        case .noTools: return ("Duo needs Apple’s command line tools for git", "git comes with Apple’s Command Line Tools, and they aren’t on this Mac. Install them, then try again. Nothing was changed.")
        case .noGH: return ("Duo needs the GitHub CLI for this", "Listing your repos and making a fork use GitHub’s own command-line tool, gh. It isn’t on this Mac. You can still paste a repo’s link: Duo copies and pushes with git.")
        case .signedOut: return ("Sign in to GitHub", "Duo never sees your password or keeps a token. The GitHub CLI signs you in through your browser and keeps the sign-in in your Mac’s keychain, where git uses it too.")
        case .notFound: return login == nil
            ? ("Sign in to see \(repo)", "\(repo) may be private, or the link may be wrong. Sign in to GitHub, then try again.")
            : ("Duo can’t see \(repo)", "It may be private, the link may be wrong, or \(login.map { "your GitHub account (\($0))" } ?? "your GitHub account") hasn’t been given access. Ask the repo’s owner to add you, or sign in with another account.")
        case .sso: return ("\(repo.split(separator: "/").first.map(String.init) ?? "This organization") needs you to authorize single sign-on", "Your organization requires single sign-on for the GitHub CLI. Authorize it on GitHub once, then try again.")
        case .protected: return ("\(branch) is protected on \(repo)", "Changes to \(branch) go in through a pull request. Duo can move your \(ahead == 1 ? "commit" : "\(ahead) commits") to a new branch, push that and open the pull request. \(branch) here goes back to match GitHub.")
        case .notFastForward: return ("GitHub has newer work on \(branch)", "Someone pushed to this branch (or you did from another Mac). Get it first, then push.")
        case .noWrite: return ("You can’t push to \(repo)", "GitHub says \(acct) can read it but not push to it. If you should be able to, check with the repo’s owner. Or Duo can push to your own copy (a fork) and open the pull request from there.")
        case .secrets: return ("GitHub refused files that look like secrets", "GitHub’s secret scanning found something like a password or key\(file.map { " in \($0)" } ?? "") and refused the push. Nothing was pushed. Remove it (Claude can help), then push again.")
        case .offline: return ("Duo couldn’t reach GitHub", "Check you’re online and try again. Nothing was changed.")
        case .noIdentity: return ("Tell git who you are", "Commits carry a name and email, and this Mac has none set for git. They show on GitHub next to your changes.")
        case .conflict: return ("Your changes and GitHub’s both changed \(file ?? "a file")", "Duo stopped bringing in the new commits. Nothing is lost: your changes are as they were.")
        case .unknown: return ("GitHub refused the push", "Nothing more was changed. The details below say what git reported; whoever helps you with git will know what it means.")
        }
    }
}
