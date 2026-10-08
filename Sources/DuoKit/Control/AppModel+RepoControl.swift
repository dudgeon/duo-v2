import AppKit
import DuoControl
import Foundation

/// `duo2 repo …` (DL-71, DL-149, DL-157): every button in the Files block's repo state has a verb.
/// Anything that publishes under the user's name needs `--yes`, or opens the Push sheet (C-54).
extension AppModel {
    func repoVerb(_ id: ActionID, _ inv: Invocation, _ req: ControlRequest, _ done: @escaping @MainActor (Reply) -> Void) {
        if id == .repoCheck, let slug = inv[0], let parsed = RemoteRepo.parse(slug) {
            return Task { @MainActor in
                let a = await Task.detached { GitHubAccess.probe(parsed.repo) }.value
                done(.ok(Self.describe(a, repo: parsed.repo), Self.json(a)))
            }.ignore()
        }
        // The project named, else the terminal's, else the one on screen; repo verbs act on the shown one.
        let name = inv.flags["project"] ?? projectFor(cwd: req.cwd)?.name ?? currentProject?.name
        guard let name, project(named: name) != nil else { return done(.fail("no project '\(inv.flags["project"] ?? "")': open one or pass --project")) }
        if currentProject?.name != name { open(project: name) }
        refreshRepo(force: true, fetch: id == .repoCheck || id == .repoStatus && inv.has("fetch")) { [self] in
            guard let v = repos[name] else { return done(.fail("\(name) isn't in a git repository.")) }
            switch id {
            case .repoStatus:
                if inv.has("copy") { copyBranchName() }   // Copy Branch Name
                done(.ok(Self.describe(v), Self.json(v)))
            case .repoCheck:
                done(.ok(v.access.map { Self.describe($0, repo: v.status.origin) } ?? "No GitHub remote: Duo can't check access.", v.access.map(Self.json)))
            case .repoLatest, .repoUpdate:
                let from: String? = id == .repoUpdate ? (inv.flags["from"] ?? v.base) : nil
                if let from, !GitTool.safeValue(from) { return done(.fail("'\(from)' can't be a branch name")) }
                getLatest(from: from) { r in
                    switch r {
                    case .success(let how): done(.ok(how == "up to date" ? "Already up to date." : (from.map { "Brought in the changes from \($0)." } ?? "Got the latest from GitHub.")))
                    case .failure(let f): done(.fail(Self.failText(f, v)))
                    }
                }
            case .repoPutBack:
                putBack { r in
                    if case .failure(let f) = r { done(.fail(Self.failText(f, v))) } else { done(.ok("Put back: the stopped Get Latest is undone; your changes are as they were.")) }
                }
            case .repoPush, .repoPR:
                guard inv.has("yes") else {
                    // Without --yes the user confirms in the sheet; the reply waits for it.
                    showPush(fork: inv.has("fork"))
                    return done(.ok("Opened the Push sheet in Duo for the user to confirm. Pushing publishes under their name, so it needs them (or --yes when they've asked you to)."))
                }
                pushFromCLI(id, inv, v, done)
            case .repoDraft:
                guard let f = pushForm else { return done(.fail("The Push sheet isn't open. The user opens it with Push… in the Files block.")) }
                if let m = inv.flags["message"] { f.message = m }
                if let t = inv.flags["title"] { f.prTitle = t }
                if let b = inv.flags["body"] { f.body = b.replacingOccurrences(of: "\\n", with: "\n") }
                done(.ok("Filled in the Push sheet. The user reviews it and presses \(f.button)."))
            case .repoMoveToBranch:
                guard let b = inv[0], GitTool.safeValue(b) else { return done(.fail("usage: \(id.action.usage)")) }
                guard inv.has("yes") else { offerMoveToBranch(); return done(.ok("Asked the user in Duo: move to a new branch and push?")) }
                moveToBranch(b, thenPush: false) { r in
                    if case .failure(let f) = r { done(.fail(Self.failText(f, v))) } else { done(.ok("Moved to \(b); \(v.base) here matches GitHub again. Push it with `duo2 repo pr --yes`.")) }
                }
            case .repoSignin:
                signInToGitHub()
                done(.ok(GitTool.ghPath == nil ? "The GitHub CLI isn't installed: opened a shell tab with `brew install gh` typed (or its download page)." : "Opened a shell tab running the GitHub CLI's browser sign-in."))
            case .repoOpen:
                openRepoOnGitHub(pr: inv.has("pr"))
                done(.ok(inv.has("pr") && v.prURL == nil ? "No pull request open from this branch: opened the repository." : "Opened on GitHub."))
            default:
                done(.fail("not a repo verb"))
            }
        }
    }

    private func pushFromCLI(_ id: ActionID, _ inv: Invocation, _ v: RepoView, _ done: @escaping @MainActor (Reply) -> Void) {
        guard let origin = v.status.origin, let branch = v.status.branch else { return done(.fail("No GitHub remote or no branch: nothing to push.")) }
        var files = v.userChanges.filter { $0.kind != .conflict }.map(\.path)
        if let only = inv.flags["files"] { files = only.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) } }
        let message = inv.flags["message"] ?? inv.flags["title"] ?? currentProject?.goal ?? "Changes from \(currentProject?.name ?? "Duo")"
        let fork = inv.has("fork") || v.access?.readOnly == true
        let form = PushForm(project: currentProject?.name ?? "", repo: origin, branch: branch, base: v.base, newOnGitHub: v.status.upstream == nil,
                            commitsAhead: v.status.ahead, rows: files.map { .init(path: $0, kind: .changed, stat: "", ticked: true) },
                            message: message, body: inv.flags["body"]?.replacingOccurrences(of: "\\n", with: "\n") ?? "", existingPR: v.pr,
                            mode: fork ? .fork : (inv.has("browser") || GitTool.ghPath == nil || v.access?.login == nil ? .browser : .write), login: v.access?.login)
        form.openPR = id == .repoPR && v.pr == nil
        form.draft = inv.has("draft")
        form.prTitle = inv.flags["title"]
        pushForm = form
        commitPush { r in
            switch r {
            case .success(let p):
                var j: [String: Any] = ["branch": p.branch, "remote": p.remote]
                if let n = p.prNumber { j["pr"] = n }
                if let u = p.prURL { j["prURL"] = u.absoluteString }
                if let u = p.compareURL { j["compareURL"] = u.absoluteString }
                done(.ok(Self.pushNotice(p, repo: origin, base: form.base, session: nil).text + (p.compareURL.map { " (\($0.absoluteString))" } ?? ""), j))
            case .failure(let f):
                done(.fail(Self.failText(f, v)))
            }
        }
    }

    static func failText(_ f: GitFailure, _ v: RepoView) -> String {
        let w = f.words(repo: v.status.origin?.slug ?? "this repository", branch: v.status.branch ?? "", login: v.access?.login, ahead: v.status.ahead)
        return "\(w.title). \(w.body)" + (f.details.isEmpty ? "" : "\n\n" + f.details)
    }

    static func describe(_ v: RepoView) -> String {
        let s = v.status
        let line = RepoLine.of(v)
        var out = ["\(s.branch ?? "detached")" + (s.origin.map { " · \($0.slug)" } ?? " · no GitHub remote") + (s.upstream == nil ? " · not on GitHub yet" : "")]
        out.append("Line: \(line.fact)" + (line.action.map { " [\($0.rawValue)]" } ?? ""))
        if !line.all.isEmpty { out.append("All: " + line.all.joined(separator: " · ")) }
        for c in v.userChanges { out.append("  \(c.kind.rawValue)\t\(c.path)") }
        if let a = v.access { out.append(describe(a, repo: s.origin)) }
        return out.joined(separator: "\n")
    }

    static func describe(_ a: GitHubAccess, repo: RemoteRepo?) -> String {
        switch a.sign {
        case .noGH: return "The GitHub CLI isn't installed: Duo can copy and push with git, and opens pull requests on GitHub's page. `duo2 repo signin` helps install it."
        case .signedOut: return "The GitHub CLI is signed out: `duo2 repo signin` opens its browser sign-in."
        case .signedIn(let login):
            guard let repo else { return "Signed in to GitHub as \(login)." }
            if !a.found { return "Signed in as \(login), but GitHub doesn't show \(repo.slug) to this account: private, a wrong link, or no access." }
            var parts = ["Signed in as \(login)."]
            if let p = a.permission { parts.append(a.readOnly ? "You can read \(repo.slug) but not push to it: pushes go to your fork, \(login)/\(repo.name)." : "You can push to \(repo.slug) (\(p.rawValue.lowercased())).") }
            if let b = a.defaultBranch { parts.append(a.protectedDefault == true ? "\(b) is protected: changes go in through a pull request." : "\(b) is the default branch.") }
            return parts.joined(separator: " ")
        }
    }

    static func json(_ v: RepoView) -> [String: Any] {
        let s = v.status
        let line = RepoLine.of(v)
        var j: [String: Any] = ["root": s.root.path, "ahead": s.ahead, "behind": s.behind, "base": v.base, "line": line.fact,
                                "changes": v.userChanges.map { ["path": $0.path, "kind": $0.kind.rawValue] }, "conflict": s.hasConflict || s.merging]
        if let b = s.branch { j["branch"] = b }
        if let u = s.upstream { j["upstream"] = u }
        if let o = s.origin { j["repo"] = o.slug; j["host"] = o.host }
        if let a = line.action { j["action"] = a.rawValue }
        if let pr = v.pr { j["pr"] = pr }
        if let a = v.access { j["access"] = json(a) }
        j["reachable"] = !v.unreachable
        return j
    }

    static func json(_ a: GitHubAccess) -> [String: Any] {
        var j: [String: Any] = ["readOnly": a.readOnly, "found": a.found]
        switch a.sign { case .noGH: j["gh"] = "missing"; case .signedOut: j["gh"] = "signed out"; case .signedIn(let l): j["gh"] = "signed in"; j["login"] = l }
        if let p = a.permission { j["permission"] = p.rawValue }
        if let b = a.defaultBranch { j["defaultBranch"] = b }
        if let p = a.protectedDefault { j["protected"] = p }
        return j
    }
}

private extension Task { func ignore() {} }
