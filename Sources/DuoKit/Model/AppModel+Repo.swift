import AppKit
import DuoControl
import Foundation

/// GitHub on a project (DL-149, DL-157): the repo state in the Files block, and the steps behind
/// its buttons. Any project whose folder is in a git repository gets them, however it got there.
extension AppModel {
    /// The view of the current project's repository, if it's in one.
    public var currentRepo: RepoView? { currentProject.flatMap { repos[$0.name] } }

    /// Reads the open project's repository off the main thread: local state each time (at most
    /// every 2 s), a quiet `git fetch` every 5 minutes, access through gh once per launch.
    public func refreshRepo(force: Bool = false, fetch forceFetch: Bool = false, then: (@MainActor () -> Void)? = nil) {
        guard let name = currentProject?.name, let folder = liveFolders[name] else { then?(); return }
        guard !repoRefreshing.contains(name) else { then?(); return }
        if !force, let last = repoChecked[name], Date().timeIntervalSince(last) < 2 { then?(); return }
        repoRefreshing.insert(name)
        repoChecked[name] = Date()
        let prev = repos[name]
        let fetchDue = forceFetch || (prev?.lastFetch.map { Date().timeIntervalSince($0) > 300 } ?? true)
        let quiet = SupportFolder.isIsolated && Env.value("DUO_REPO_FETCH") == nil   // test instances never reach GitHub unless asked
        let doFetch = fetchDue && !quiet
        Task { @MainActor in
            let view = await Task.detached(priority: .utility) { Self.readRepo(folder: folder, prev: prev, fetch: doFetch) }.value
            do {
                self.repoRefreshing.remove(name)
                if self.repos[name] != view { self.repos[name] = view }
                then?()
            }
        }
    }

    /// One read of a repository (background). Carries over what GitHub said last time.
    nonisolated static func readRepo(folder: URL, prev: RepoView?, fetch: Bool) -> RepoView? {
        guard var status = RepoProbe.status(of: folder) else { return nil }
        let root = status.root.resolvingSymlinksInPath().path
        let f = folder.resolvingSymlinksInPath().path
        let prefix = f.hasPrefix(root + "/") ? String(f.dropFirst(root.count + 1)) + "/" : ""
        var v = RepoView(status: status, projectPrefix: prefix)
        if let prev, prev.status.root == status.root {
            v.access = prev.access; v.lastFetch = prev.lastFetch; v.lastReach = prev.lastReach
            v.unreachable = prev.unreachable; v.pr = prev.pr; v.prURL = prev.prURL
            v.lastFailure = prev.lastFailure; v.busy = prev.busy
        }
        if fetch, let origin = status.origin {
            let r = RepoOps.fetch(status.root)
            v.lastFetch = Date()
            if r.ok {
                v.unreachable = false; v.lastReach = Date()
                if v.lastFailure == .signedOut || v.lastFailure == .offline { v.lastFailure = nil }
                if let again = RepoProbe.status(of: folder) { status = again; v.status = again }
            } else {
                let k = GitFailure.from(r).kind
                v.unreachable = k == .offline || k == .unknown
                if k == .signedOut { v.lastFailure = .signedOut }
            }
            if origin.isGitHub {
                if v.access == nil || v.access?.sign == .noGH { v.access = GitHubAccess.probe(origin) }
                if let b = status.branch, v.access?.login != nil {
                    let headOwner = status.forkRemote != nil ? v.access?.login : nil
                    let pr = RepoOps.openPR(status.root, origin: origin, branch: b, headOwner: headOwner)
                    v.pr = pr?.number; v.prURL = pr?.url
                }
            }
        }
        let ignored = ["_PROJECT.md", "PROJECT.md"].contains { file in
            FileManager.default.fileExists(atPath: folder.appending(path: file).path)
                && GitTool.git(["check-ignore", "-q", "--", folder.appending(path: file).path], in: status.root, timeout: 5).status == 0
        }
        v.duoFilesIgnored = ignored
        return v
    }

    // MARK: the line's buttons and menu (boards 4, 5, 9)

    public func repoAction(_ a: RepoLine.Action) {
        switch a {
        case .push, .pushNow: showPush(sendNow: a == .pushNow)
        case .latest: getLatest(from: nil)
        case .resolve: askClaudeToCombine()
        case .moveToBranch: offerMoveToBranch()
        case .signIn: signInToGitHub()
        }
    }

    /// Runs a repository step off the main thread with the line saying what's happening.
    func repoStep(_ busy: String, _ work: @escaping @Sendable (URL) -> RepoOps.Outcome, done: @escaping @MainActor (RepoOps.Outcome) -> Void) {
        guard let name = currentProject?.name, let root = repos[name]?.status.root else { return }
        repos[name]?.busy = busy
        Task { @MainActor in
            let r = await Task.detached(priority: .userInitiated) { work(root) }.value
            do {
                self.repos[name]?.busy = nil
                self.refreshRepo(force: true) { done(r) }
            }
        }
    }

    /// Get Latest (`from` nil) or Bring In Changes from `from` (board 9).
    public func getLatest(from: String?, reply: (@MainActor (Result<String, GitFailure>) -> Void)? = nil) {
        repoStep(from == nil ? "Getting the latest…" : "Bringing in \(from!)…", { RepoOps.merge($0, from: from) }) { r in
            if case .failure(let f) = r {
                if f.kind == .conflict { self.askAboutConflict() } else { self.showRepoFailure(f) }
            }
            reply?(r)
        }
    }

    /// Board 9: "Your changes and GitHub's both changed content/faq.md".
    func askAboutConflict() {
        guard let v = currentRepo else { return }
        let file = v.status.conflicts.first?.path ?? "a file"
        let w = GitFailure(kind: .conflict, details: "").words(repo: v.status.origin?.slug ?? "", branch: v.status.branch ?? "", login: v.access?.login, file: file)
        if Env.autoconfirm { FileHandle.standardError.write(Data("question: \(w.title)\n".utf8)); return }
        SheetCenter.shared.ask(DuoQuestion(title: w.title, paragraphs: [w.body, "Claude can combine the two versions and tell you what it chose, or you can put things back as they were before Get Latest."], choices: [
            .init(label: "Show the File") { self.openDocument(String(file.dropFirst(v.projectPrefix.count))) },
            .init(label: "Put Back", isCancel: true) { self.putBack() },
            .init(label: "Ask Claude to Combine", isDefault: true) { self.askClaudeToCombine() },
        ]))
    }

    public func putBack(reply: (@MainActor (Result<String, GitFailure>) -> Void)? = nil) {
        repoStep("Putting back…", { RepoOps.putBack($0) }) { r in
            if case .failure(let f) = r { self.showRepoFailure(f) }
            reply?(r)
        }
    }

    // MARK: Claude (board 11)

    /// Puts an instruction in the project's open Claude session's prompt, unsent, or starts a
    /// session and drafts it there (DL-112's "drafted, not sent"): the user reads it, then presses Return.
    public func draftForClaude(_ text: String) {
        guard let project = currentProject?.name else { return }
        let sessions = fixture.sessions(inProject: project)
        if let key = consoleTab, sessions.contains(where: { $0.tabKey == key }), let t = terminals.existing(key), t.isLiveClaude, t.notReadyReason == nil {
            send(text, to: key)
        } else if let id = newSession(in: project) {
            consoleTab = id
            draft(text, into: id)
        }
        lastDrafted = (consoleTab ?? "", text)
    }

    public func askClaudeToCombine() {
        guard let v = currentRepo else { return }
        let files = v.status.conflicts.map(\.path)
        let into = v.status.branch ?? "this branch"
        draftForClaude("""
        Bringing new commits into \(into) stopped with a conflict in \(files.isEmpty ? "a file" : files.joined(separator: ", ")). \
        Combine both versions keeping what each side meant, then `git add` the file and `git commit --no-edit`. \
        Don't push. Then tell me in two lines what you kept from each side.
        """)
    }

    /// What Claude is told about the repository when a session starts here (board 11).
    public static func repoContext(_ v: RepoView) -> String? {
        guard let origin = v.status.origin, let branch = v.status.branch else { return nil }
        var lines = ["This project is a copy of \(origin.slug) on branch \(branch)" + (v.status.upstream == nil ? ", not yet pushed." : ".")]
        if v.access?.readOnly == true, let login = v.access?.login {
            lines.append("You can read \(origin.slug) but not push to it: pushes go to the user's fork \(login)/\(origin.name) (remote `fork`), never to `origin`.")
        } else if v.access?.canPush == true {
            lines.append("The user can push to \(origin.slug).")
        }
        if v.access?.protectedDefault == true { lines.append("\(v.base) is protected: never commit to it.") }
        lines.append("_PROJECT.md and .duo/ are Duo's: don't add them to commits.")
        lines.append("To share work, the user presses Push in Duo's Files block; don't push or open pull requests unless asked.")
        return lines.joined(separator: "\n")
    }

    // MARK: sign in, protected branch, GitHub links

    /// A Duo shell tab running GitHub's own browser sign-in; Duo never sees a token (board 10).
    public func signInToGitHub() {
        guard GitTool.ghPath != nil else { return offerInstallGH() }
        newShell()
        typeInShell("gh auth login --web --git-protocol https && gh auth setup-git", run: true)
        currentProject.map { repos[$0.name]?.lastFailure = nil }
    }

    /// Install in a Shell…: `brew install gh` typed, not run; without Homebrew, the download page.
    public func offerInstallGH() {
        guard GitTool.brewPath != nil else { NSWorkspace.shared.open(URL(string: "https://cli.github.com")!); return }
        newShell()
        typeInShell("brew install gh", run: false)
    }

    func typeInShell(_ command: String, run: Bool) {
        guard let key = consoleTab, let t = terminals.existing(key) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            t.view.send(txt: command + (run ? "\r" : ""))
            t.view.window?.makeFirstResponder(t.view)
        }
    }

    func offerMoveToBranch() {
        guard let v = currentRepo, let b = v.status.branch else { return }
        let suggestion = (v.access?.login.map { "\($0)/" } ?? "") + (currentProject.map { Self.slug($0.name) } ?? "changes")
        let w = GitFailure(kind: .protected, details: "").words(repo: v.status.origin?.slug ?? "", branch: b, login: v.access?.login, ahead: max(1, v.status.ahead))
        let field = DuoQuestion.Field(label: "New branch", text: suggestion)
        if Env.autoconfirm { FileHandle.standardError.write(Data("question: \(w.title)\n".utf8)); return }
        SheetCenter.shared.ask(DuoQuestion(title: w.title, paragraphs: [w.body], field: field, choices: [
            .init(label: "Cancel", isCancel: true) {},
            .init(label: "Move to a Branch and Push", isDefault: true) { self.moveToBranch(field.text, thenPush: true) },
        ]))
    }

    public func moveToBranch(_ name: String, thenPush: Bool, reply: (@MainActor (Result<String, GitFailure>) -> Void)? = nil) {
        repoStep("Moving to \(name)…", { RepoOps.moveToBranch($0, newBranch: name) }) { r in
            switch r {
            case .failure(let f): self.showRepoFailure(f)
            case .success: if thenPush { self.showPush(sendNow: false) }
            }
            reply?(r)
        }
    }

    public func openRepoOnGitHub(pr: Bool = false) {
        guard let v = currentRepo, let origin = v.status.origin else { return }
        if pr, let u = v.prURL { NSWorkspace.shared.open(u); return }
        var u = origin.webURL
        if let b = v.status.branch, v.status.upstream != nil { u = u.appending(path: "tree/\(b)") }
        NSWorkspace.shared.open(u)
    }

    public func copyBranchName() {
        guard let b = currentRepo?.status.branch else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(b, forType: .string)
    }

    static func slug(_ s: String) -> String {
        let lowered = s.lowercased().map { $0.isLetter || $0.isNumber ? String($0) : "-" }.joined()
        return lowered.split(separator: "-").joined(separator: "-")
    }

    // MARK: failures (board 10)

    /// Duo's question for a failed step: what happened, what wasn't changed, one way forward;
    /// git's own words behind Details (never shown first).
    public func showRepoFailure(_ f: GitFailure) {
        guard let v = currentRepo else { return }
        if f.kind == .signedOut, let n = currentProject?.name { repos[n]?.lastFailure = .signedOut }
        let w = f.words(repo: v.status.origin?.slug ?? "this repository", branch: v.status.branch ?? "", login: v.access?.login,
                        ahead: v.status.ahead, file: f.details.components(separatedBy: "\n").first { $0.contains("path:") }.map { String($0.split(separator: ":").last ?? "").trimmingCharacters(in: .whitespaces) })
        if Env.autoconfirm { FileHandle.standardError.write(Data("question: \(w.title) | \(f.kind.rawValue)\n".utf8)); return }
        var choices: [DuoQuestion.Choice]
        switch f.kind {
        case .noGH: choices = [.init(label: "Cancel", isCancel: true) {}, .init(label: "Install in a Shell…", isDefault: true) { self.offerInstallGH() }]
        case .signedOut: choices = [.init(label: "Cancel", isCancel: true) {}, .init(label: "Sign In in a Shell…", isDefault: true) { self.signInToGitHub() }]
        case .notFound: choices = [.init(label: "Switch Account…", isCancel: true) { self.signInToGitHub() }, .init(label: "Open on GitHub", isDefault: true) { self.openRepoOnGitHub() }]
        case .sso: choices = [.init(label: "Cancel", isCancel: true) {}, .init(label: "Open GitHub", isDefault: true) { NSWorkspace.shared.open(URL(string: "https://github.com/settings/applications")!) }]
        case .protected: return offerMoveToBranch()
        case .notFastForward: choices = [.init(label: "Cancel", isCancel: true) {}, .init(label: "Get Latest and Push", isDefault: true) { self.getLatest(from: nil) { r in if case .success = r { self.showPush(sendNow: false) } } }]
        case .noWrite: choices = [.init(label: "Cancel", isCancel: true) {}, .init(label: "Fork and Push", isDefault: true) { self.showPush(sendNow: false, fork: true) }]
        case .secrets: choices = [.init(label: "Show Details", isCancel: true) {}, .init(label: "Ask Claude to Remove It", isDefault: true) { self.draftForClaude("GitHub's secret scanning refused my push: it found something like a password or key. Here is what git reported:\n\n\(f.details)\n\nRemove the secret from the files and from the commits that aren't on GitHub yet, and tell me what you changed. Don't push.") }]
        case .offline: choices = [.init(label: "OK", isCancel: true) {}, .init(label: "Try Again", isDefault: true) { self.refreshRepo(force: true, fetch: true) }]
        case .noIdentity: choices = [.init(label: "OK", isDefault: true, isCancel: true) {}]
        case .conflict: return askAboutConflict()
        case .noTools, .unknown: choices = [.init(label: "OK", isDefault: true, isCancel: true) {}]
        }
        SheetCenter.shared.ask(DuoQuestion(title: w.title, paragraphs: [w.body], note: f.details.isEmpty ? nil : "Details: " + f.details, choices: choices))
    }
}
