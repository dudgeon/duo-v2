import AppKit
import DuoControl
import Foundation

/// The Push sheet (board 6, DL-149): what goes, the message, the pull request. Duo commits, pushes
/// and opens the PR; Claude writes the words only when asked (`duo2 repo draft`).
@Observable public final class PushForm {
    public struct Row: Identifiable {
        public var path: String
        public var kind: FileChange.Kind
        public var stat: String      // "+18 −9", "new", "deleted"
        public var ticked: Bool
        public var duo = false       // one of Duo's own files (DL-157): unticked by default
        public var id: String { path }
    }
    public enum Mode: Equatable { case write, fork, browser }

    public let project: String
    public let repo: RemoteRepo
    public let branch: String
    public var base: String
    /// Branches a pull request can go into (GitHub's, newest first; the default first).
    public var bases: [String] = []
    public let newOnGitHub: Bool
    public let commitsAhead: Int
    public var rows: [Row]
    public var message: String
    public var openPR: Bool
    public let existingPR: Int?
    public var body: String
    /// The PR's title when Claude drafts one apart from the message; else the message.
    public var prTitle: String?
    public var draft = false
    public var mode: Mode
    public let login: String?
    public var working = false
    /// The project's own note, named in "… stays out."
    public var projectFileName = "_PROJECT.md"
    public var problem: String?

    init(project: String, repo: RemoteRepo, branch: String, base: String, newOnGitHub: Bool, commitsAhead: Int, rows: [Row],
         message: String, body: String, existingPR: Int?, mode: Mode, login: String?) {
        self.project = project; self.repo = repo; self.branch = branch; self.base = base; self.newOnGitHub = newOnGitHub
        self.commitsAhead = commitsAhead; self.rows = rows; self.message = message; self.body = body
        self.existingPR = existingPR; self.openPR = existingPR == nil; self.mode = mode; self.login = login
    }

    public var ticked: [String] { rows.filter(\.ticked).map(\.path) }
    public var forkName: String { "\(login ?? "you")/\(repo.name)" }

    /// One button, named for what it does (board 6).
    public var button: String {
        if existingPR != nil || !openPR { return mode == .fork ? "Fork and Push" : "Push" }
        switch mode {
        case .write: return "Push and Open PR"
        case .fork: return "Fork, Push and Open PR"
        case .browser: return "Push and Open in Browser"
        }
    }

    public var canSend: Bool { !working && (!ticked.isEmpty || commitsAhead > 0 || newOnGitHub) && (ticked.isEmpty || !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
}

extension AppModel {
    /// Push… on the repo line (or Project › Push to GitHub…, ⇧⌘P). `sendNow`: a PR is open and there's
    /// nothing to ask, so Push goes straight away (board 5).
    public func showPush(sendNow: Bool = false, fork: Bool = false) {
        guard let name = currentProject?.name, let v = repos[name] else { return }
        guard let origin = v.status.origin, let branch = v.status.branch else {
            return info(v.status.origin == nil ? "This project’s repository has no GitHub remote, so there’s nowhere to push it." : "This repository isn’t on a branch, so there’s nothing to push.")
        }
        if v.status.hasConflict || v.status.merging { return askAboutConflict() }
        let root = v.status.root
        let goal = currentProject?.goal ?? ""
        let sessions = fixture.sessions(inProject: name).prefix(3).map(\.name).filter { !$0.isEmpty }
        Task { @MainActor in
            let stats = await Task.detached(priority: .userInitiated) { Self.numstat(root) }.value
            let bases = await Task.detached(priority: .utility) { Self.remoteBranches(root) }.value
            let rows: [PushForm.Row] = v.status.changes.filter { $0.kind != .conflict }.map { c in
                let duo = c.kind == .new && RepoView.isDuoFile(c.path)
                let stat = c.kind == .new ? "new" : (c.kind == .deleted ? "deleted" : (stats[c.path] ?? ""))
                return PushForm.Row(path: c.path, kind: c.kind, stat: stat, ticked: !duo, duo: duo)
            }.sorted { ($0.duo ? 1 : 0, $0.path) < ($1.duo ? 1 : 0, $1.path) }
            do {
                let mode: PushForm.Mode = (fork || v.access?.readOnly == true) ? .fork : (GitTool.ghPath == nil || v.access?.login == nil ? .browser : .write)
                let message = goal.isEmpty ? (sessions.first ?? "Changes from \(name)") : goal
                let body = ([goal.isEmpty ? nil : goal] + (sessions.isEmpty ? [] : ["From the sessions: " + sessions.joined(separator: ", ") + "."])).compactMap { $0 }.joined(separator: "\n\n")
                let form = PushForm(project: name, repo: origin, branch: branch, base: v.base, newOnGitHub: v.status.upstream == nil,
                                    commitsAhead: v.status.ahead, rows: rows, message: message, body: body, existingPR: v.pr, mode: mode, login: v.access?.login)
                form.projectFileName = self.projectFile ?? "_PROJECT.md"
                form.bases = [v.base] + bases.filter { $0 != v.base && $0 != branch }
                if sendNow, form.ticked.isEmpty, v.pr != nil, mode != .fork {
                    form.openPR = false
                    self.pushForm = form
                    return self.commitPush()
                }
                self.closeSearch()
                self.pushForm = form
                if Env.autoconfirm { self.commitPush() }   // scripted runs confirm the sheet
            }
        }
    }

    nonisolated static func remoteBranches(_ root: URL) -> [String] {
        let r = GitTool.git(["for-each-ref", "--sort=-committerdate", "--format=%(refname:lstrip=3)", "refs/remotes/origin"], in: root, timeout: 10)
        return r.out.split(separator: "\n").map(String.init).filter { $0 != "HEAD" && !$0.isEmpty }
    }

    nonisolated static func numstat(_ root: URL) -> [String: String] {
        let r = GitTool.git(["diff", "--numstat", "HEAD"], in: root, timeout: 10)
        var m: [String: String] = [:]
        for line in r.out.split(separator: "\n") {
            let c = line.split(separator: "\t")
            guard c.count == 3 else { continue }
            m[String(c[2])] = c[0] == "-" ? "binary" : "+\(c[0]) −\(c[1])"
        }
        return m
    }

    /// The sheet's button: commit the ticked files, push, open the PR. Publishes under the
    /// user's name, so only from this sheet (C-54).
    public func commitPush(reply: (@MainActor (Result<RepoOps.PushResult, GitFailure>) -> Void)? = nil) {
        guard let f = pushForm, let v = repos[f.project], f.canSend else { reply?(.failure(GitFailure(kind: .unknown, details: "Nothing to push."))); return }
        f.working = true
        let plan = RepoOps.PushPlan(files: f.ticked, message: f.message.trimmingCharacters(in: .whitespacesAndNewlines), openPR: f.openPR && f.existingPR == nil,
                                    prTitle: (f.prTitle ?? f.message).trimmingCharacters(in: .whitespacesAndNewlines), prBody: f.body, base: f.base,
                                    draft: f.draft, fork: f.mode == .fork, browser: f.mode == .browser)
        let root = v.status.root, login = f.login, project = f.project
        repos[project]?.busy = "Pushing…"
        Task { @MainActor in
            let r = await Task.detached(priority: .userInitiated) { RepoOps.push(root, plan: plan, login: login) }.value
            do {
                self.repos[project]?.busy = nil
                self.pushForm = nil
                switch r {
                case .success(let p):
                    if let n = p.prNumber { self.repos[project]?.pr = n; self.repos[project]?.prURL = p.prURL }
                    if let u = p.compareURL { AppModel.openOutside(u) }
                    self.repoNotice = Self.pushNotice(p, repo: f.repo, base: f.base, session: self.fixture.sessions(inProject: project).first?.name)
                case .failure(let e):
                    self.showRepoFailure(e)
                }
                self.refreshRepo(force: true) { reply?(r) }
            }
        }
    }

    static func pushNotice(_ p: RepoOps.PushResult, repo: RemoteRepo, base: String, session: String?) -> RepoNotice {
        let told = session.map { " The session “\($0)” is told." } ?? ""
        if let n = p.prNumber {
            return RepoNotice(text: "Pushed \(p.branch) and opened PR #\(n) into \(repo.slug) \(base).\(told)", button: "Open PR", url: p.prURL)
        }
        if p.compareURL != nil {
            return RepoNotice(text: "Pushed \(p.branch). GitHub’s page for the pull request is open in your browser.", button: nil, url: nil)
        }
        return RepoNotice(text: "Pushed \(p.branch) to \(p.remote == "fork" ? "your fork" : repo.slug).", button: nil, url: nil)
    }

    /// Ask Claude to Write These (board 11): the instruction, drafted in the project's session.
    public func askClaudeToWritePush() {
        guard let f = pushForm else { return }
        let n = f.ticked.count
        draftForClaude("""
        Write a commit message and a pull request title and description for the changes in this project \
        (git diff origin/\(f.base)\(n > 0 ? ", plus the \(n) uncommitted file\(n == 1 ? "" : "s")" : "")). Keep the title under 70 characters; \
        the description says what changed and why, for a reviewer who hasn't seen this work. Don't commit or push. \
        Put them in Duo's Push sheet with: duo2 repo draft --message "…" --title "…" --body "…"
        """)
    }

    public func cancelPush() { pushForm = nil }
}

/// What a finished push says (the CX study's notice pattern, built here as a stand-in until it is).
public struct RepoNotice: Equatable {
    public var text: String
    public var button: String?
    public var url: URL?
    public var at = Date()
}
