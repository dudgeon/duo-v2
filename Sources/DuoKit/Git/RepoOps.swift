import Foundation

/// The steps Duo runs for GitHub (DL-149, DL-157). Every step that changes something checks first and
/// fails closed; nothing is ever force-pushed or discarded. Each returns a `GitFailure` on failure.
public enum RepoOps {
    public typealias Outcome = Result<String, GitFailure>

    static func fail(_ r: GitTool.Result) -> Outcome { .failure(.from(r)) }

    // MARK: copy (board 3)

    /// Copies a repository into `dest` (which must not exist) on a new or existing branch, then keeps
    /// Duo's files out of git through `.git/info/exclude` when asked (the sheet's checkbox, DL-149).
    public static func clone(_ repo: RemoteRepo, into dest: URL, newBranch: String?, from base: String?, existing: String?,
                             excludeDuoFiles: Bool, cloneURL: String? = nil, progress: (@Sendable (String) -> Void)? = nil) -> Outcome {
        guard !FileManager.default.fileExists(atPath: dest.path) else {
            return .failure(GitFailure(kind: .unknown, details: "A folder already exists at \(dest.path)."))
        }
        for v in [newBranch, base, existing].compactMap({ $0 }) where !GitTool.safeValue(v) {
            return .failure(GitFailure(kind: .unknown, details: "“\(v)” can’t be a branch name."))
        }
        let parent = dest.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let useGH: Bool
        if cloneURL == nil, case .signedIn = GitHubAccess.sign(host: repo.host) { useGH = true } else { useGH = false }
        var branchArgs: [String] = []
        if let existing { branchArgs = ["--branch=\(existing)"] } else if let base { branchArgs = ["--branch=\(base)"] }
        let r = useGH
            ? GitTool.gh(["repo", "clone", repo.slug, dest.path, "--"] + branchArgs, in: parent, timeout: 900)
            : GitTool.git(["clone", "--progress"] + branchArgs + ["--", cloneURL ?? repo.httpsCloneURL, dest.path], in: parent, timeout: 900)
        guard r.ok else {
            try? FileManager.default.removeItem(at: dest)   // Cancel or failure leaves no half-made folder
            return fail(r)
        }
        progress?("cloned")
        if let newBranch {
            let b = GitTool.git(["switch", "-c", newBranch], in: dest)
            guard b.ok else { return fail(b) }
        }
        if excludeDuoFiles { excludeDuo(in: dest) }
        return .success(dest.path)
    }

    /// Adds Duo's files to the repository's own `.git/info/exclude`, which stays on this Mac.
    public static func excludeDuo(in root: URL) {
        let file = RepoProbe.gitDir(root).appending(path: "info/exclude")
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        var text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        let lines = ["/_PROJECT.md", "/PROJECT.md", ".duo/"].filter { !text.contains($0) }
        guard !lines.isEmpty else { return }
        if !text.isEmpty && !text.hasSuffix("\n") { text += "\n" }
        text += "# Duo's files (DL-149): kept out of git on this Mac only\n" + lines.joined(separator: "\n") + "\n"
        try? text.write(to: file, atomically: true, encoding: .utf8)
    }

    // MARK: push and PR (boards 6–8)

    public struct PushPlan: Sendable {
        public var files: [String]          // paths relative to the repo root, to commit
        public var message: String
        public var openPR: Bool
        public var prTitle: String
        public var prBody: String
        public var base: String
        public var draft: Bool
        public var fork: Bool               // push to the user's fork (read-only access)
        public var browser: Bool            // open GitHub's compare page instead of gh pr create
        public init(files: [String], message: String, openPR: Bool, prTitle: String, prBody: String, base: String, draft: Bool, fork: Bool, browser: Bool) {
            self.files = files; self.message = message; self.openPR = openPR; self.prTitle = prTitle
            self.prBody = prBody; self.base = base; self.draft = draft; self.fork = fork; self.browser = browser
        }
    }

    public struct PushResult: Sendable {
        public var branch: String
        public var remote: String
        public var prNumber: Int?
        public var prURL: URL?
        public var compareURL: URL?
    }

    public static func commit(_ root: URL, files: [String], message: String) -> Outcome {
        guard !files.isEmpty else { return .success("nothing to commit") }
        let add = GitTool.git(["add", "--all", "--"] + files, in: root)
        guard add.ok else { return fail(add) }
        let c = GitTool.git(["commit", "-m", message, "--"] + files, in: root, timeout: 60)
        if !c.ok && !c.all.contains("nothing to commit") { return fail(c) }
        return .success("committed")
    }

    /// Commits, pushes (never `--force`), and opens the pull request (gh, or the compare page).
    public static func push(_ root: URL, plan: PushPlan, login: String?) -> Result<PushResult, GitFailure> {
        guard let st = RepoProbe.status(of: root), let branch = st.branch, let origin = st.origin else {
            return .failure(GitFailure(kind: .unknown, details: "This project isn’t on a branch with a GitHub remote."))
        }
        if case .failure(let f) = commit(root, files: plan.files, message: plan.message) { return .failure(f) }
        var remote = "origin"
        var headOwner: String?
        if plan.fork {
            guard let login else { return .failure(GitFailure(kind: GitTool.ghPath == nil ? .noGH : .signedOut, details: "")) }
            if RepoProbe.remoteURL(root, "fork") == nil {
                // Keep origin meaning the original: by default gh renames it to upstream (F-196).
                let f = GitTool.gh(["repo", "fork", origin.slug, "--clone=false", "--remote", "--remote-name", "fork"], in: root, timeout: 120)
                if !f.ok && !f.all.contains("already exists") { return .failure(.from(f)) }
                if RepoProbe.remoteURL(root, "fork") == nil {
                    let add = GitTool.git(["remote", "add", "fork", "https://\(origin.host)/\(login)/\(origin.name).git"], in: root)
                    guard add.ok else { return .failure(.from(add)) }
                }
            }
            remote = "fork"; headOwner = login
        }
        let p = GitTool.git(["push", "-u", remote, branch], in: root, timeout: 300)
        guard p.ok else { return .failure(.from(p)) }
        var result = PushResult(branch: branch, remote: remote)
        guard plan.openPR else { return .success(result) }
        if plan.browser || GitTool.ghPath == nil {
            result.compareURL = origin.compareURL(base: plan.base, head: branch, headOwner: headOwner, title: plan.prTitle, body: plan.prBody)
            return .success(result)
        }
        if let existing = openPR(root, origin: origin, branch: branch, headOwner: headOwner) {
            result.prNumber = existing.number; result.prURL = existing.url   // the push updated it
            return .success(result)
        }
        let bodyFile = FileManager.default.temporaryDirectory.appending(path: "duo-pr-\(UUID().uuidString).md")
        try? plan.prBody.write(to: bodyFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: bodyFile) }
        var args = ["pr", "create", "--repo", origin.slug, "--base", plan.base, "--head", headOwner.map { "\($0):\(branch)" } ?? branch,
                    "--title", plan.prTitle, "--body-file", bodyFile.path]
        if plan.draft { args.append("--draft") }
        let pr = GitTool.gh(args, in: root, timeout: 60)
        // gh can exit 0 having done nothing (F-196): the PR's URL on stdout is the proof.
        guard let line = pr.out.split(separator: "\n").last(where: { $0.contains("/pull/") }), let url = URL(string: String(line).trimmingCharacters(in: .whitespaces)) else {
            return .failure(.from(pr))
        }
        result.prURL = url
        result.prNumber = Int(url.lastPathComponent)
        return .success(result)
    }

    public static func openPR(_ root: URL, origin: RemoteRepo, branch: String, headOwner: String?) -> (number: Int, url: URL)? {
        guard GitTool.ghPath != nil else { return nil }
        let r = GitTool.gh(["pr", "list", "--repo", origin.slug, "--head", branch, "--state", "open", "--json", "number,url,headRepositoryOwner"], in: root, timeout: 20)
        guard r.ok, let data = r.out.data(using: .utf8), let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return nil }
        for pr in list {
            let owner = (pr["headRepositoryOwner"] as? [String: Any])?["login"] as? String
            // A stranger's PR from a branch of the same name isn't ours (legacy's head:main bug).
            if let headOwner, owner != headOwner { continue }
            if headOwner == nil, owner != nil, owner != origin.owner { continue }
            if let n = pr["number"] as? Int, let u = (pr["url"] as? String).flatMap(URL.init(string:)) { return (n, u) }
        }
        return nil
    }

    // MARK: protected branch (board 10)

    /// Moves commits made on a protected branch to a new one; the old branch goes back to GitHub's
    /// only after the new branch holds every commit.
    public static func moveToBranch(_ root: URL, newBranch: String) -> Outcome {
        guard GitTool.safeValue(newBranch), let st = RepoProbe.status(of: root), let old = st.branch, let up = st.upstream else {
            return .failure(GitFailure(kind: .unknown, details: "Can’t move: no branch or no upstream."))
        }
        let c = GitTool.git(["switch", "-c", newBranch], in: root)
        guard c.ok else { return fail(c) }
        let contains = GitTool.git(["merge-base", "--is-ancestor", old, newBranch], in: root)
        guard contains.ok else { return .failure(GitFailure(kind: .unknown, details: "The new branch doesn’t hold every commit; \(old) was left as it was.")) }
        let reset = GitTool.git(["branch", "-f", old, up], in: root)
        guard reset.ok else { return fail(reset) }
        return .success(newBranch)
    }

    // MARK: Get Latest (board 9)

    public static func fetch(_ root: URL) -> GitTool.Result {
        GitTool.git(["fetch", "--quiet", "--prune", "origin"], in: root, timeout: 60)
    }

    /// Get Latest (`from` nil: the branch's own upstream) or Bring In Changes from `from`. Merge, never
    /// rebase; uncommitted files ride along; on a conflict the merge stays stopped for Put Back or Claude.
    public static func merge(_ root: URL, from: String?) -> Outcome {
        guard let st = RepoProbe.status(of: root) else { return .failure(GitFailure(kind: .unknown, details: "Duo couldn’t read this repository; nothing was changed.")) }
        guard !st.merging, !st.hasConflict else { return .failure(GitFailure(kind: .conflict, details: "A merge is already stopped part way.")) }
        let f = fetch(root)
        guard f.ok else { return fail(f) }
        let target: String
        if let from { guard GitTool.safeValue(from) else { return .failure(GitFailure(kind: .unknown, details: "Bad branch name.")) }; target = "origin/\(from)" }
        else { guard st.upstream != nil else { return .failure(GitFailure(kind: .unknown, details: "This branch isn’t on GitHub yet: there’s nothing to get.")) }; target = "@{u}" }
        let ff = GitTool.git(["merge", "--ff-only", "--autostash", target], in: root, timeout: 120)
        if ff.ok { return .success(ff.out.contains("Already up to date") ? "up to date" : "fast-forward") }
        let m = GitTool.git(["merge", "--no-edit", "--autostash", target], in: root, timeout: 120)
        if m.ok { return .success("merged") }
        return fail(m)
    }

    /// Put Back: undoes a stopped merge (`git merge --abort`).
    public static func putBack(_ root: URL) -> Outcome {
        let r = GitTool.git(["merge", "--abort"], in: root)
        return r.ok ? .success("put back") : fail(r)
    }
}
