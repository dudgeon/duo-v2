import AppKit
import DuoControl
import Foundation

/// New project, From GitHub (board 1–3, DL-149). The CX study's New project sheet with its Start
/// from segment (DL-147) isn't built yet, so this is its own sheet behind File › New Project from
/// GitHub… (a stand-in entry point, Q-139); its rows are board 1's.
@Observable public final class GitHubProjectForm {
    public struct Branch: Identifiable, Hashable {
        public var name: String
        public var pr: Int?
        public var id: String { name }
    }
    public enum Found: Equatable {
        case empty, looking
        case ok(String)                    // "private · you can push · main is protected"
        case readOnly(fork: String)        // board 1's read-only box
        case unknown                       // no gh: Duo can't tell what you can push
        case problem(title: String, body: String)
    }

    public var repoText: String
    public var repo: RemoteRepo?
    public var found: Found = .empty
    public var signedInAs: String?
    public var alreadyHere: String?        // "website/launch-plan": this project gets its own copy
    public var branches: [Branch] = []
    public var useExisting = false
    public var existing: String?
    public var newBranch = ""
    public var base = "main"
    public var name = ""
    public var nameTouched = false
    public var goal = ""
    public var places: [HomePlace]
    public var into: HomePlace
    public var startSession = true
    public var keepOutOfGit = true
    public var working = false
    public var choices: [(slug: String, isPrivate: Bool, pushed: String)] = []

    init(places: [HomePlace], text: String) {
        self.places = places; self.into = places[0]; self.repoText = text
    }

    public var folderName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    public var path: String { into.folder.appending(path: folderName).path }
    public var canCreate: Bool {
        guard repo != nil, !working, !folderName.isEmpty else { return false }
        if case .problem = found { return false }
        if case .looking = found { return false }
        return useExisting ? existing != nil : GitTool.safeValue(newBranch)
    }
}

extension AppModel {
    /// File › New Project from GitHub… and `duo2 project new --from-github` without --yes.
    public func showGitHubProject(_ text: String = "") {
        guard liveRoot != nil else { return info("There's no Home folder yet: choose one first (File › Choose Home Folder…).") }
        closeSearch()
        let f = GitHubProjectForm(places: homePlaces(), text: text)
        gitHubProjectForm = f
        if !text.isEmpty { lookUpRepo() }
        if case .signedIn = GitHubAccess.sign() { loadRepoChoices() }
    }

    /// Reads the link, then asks GitHub what it is and what the user can do (the Found box).
    public func lookUpRepo() {
        guard let f = gitHubProjectForm else { return }
        guard let parsed = RemoteRepo.parse(f.repoText) else {
            f.repo = nil
            f.found = f.repoText.trimmingCharacters(in: .whitespaces).isEmpty ? .empty
                : .problem(title: "That isn’t a GitHub link", body: "Paste a repository’s link, like https://github.com/owner/repo, or choose one.")
            return
        }
        f.repo = parsed.repo
        f.found = .looking
        if !f.nameTouched { f.name = parsed.repo.name }
        // In: a topic named after the repo, made if missing (board 1).
        if let root = liveRoot, f.into == f.places.first {
            let topic = root.appending(path: parsed.repo.name)
            if let have = f.places.first(where: { $0.folder.standardizedFileURL == topic.standardizedFileURL }) { f.into = have }
            else if !FileManager.default.fileExists(atPath: topic.path) { let p = HomePlace(label: "\(parsed.repo.name) / (new)", folder: topic); f.places.append(p); f.into = p }
        }
        let folders = liveFolders
        let text = f.repoText
        Task { @MainActor in
            let (access, heads, here) = await Task.detached(priority: .userInitiated) { () -> (GitHubAccess, GitTool.Result, String?) in
                let a = GitHubAccess.probe(parsed.repo)
                var h = GitTool.git(["ls-remote", "--heads", "--", parsed.repo.httpsCloneURL], in: nil, timeout: 30)
                // gh sees a private repo git has no credential for yet (no `gh auth setup-git`): ask gh, which also copies it.
                if !h.ok, a.permission != nil {
                    let g = GitTool.gh(["api", "repos/\(parsed.repo.slug)/branches?per_page=100", "--jq", ".[].name"], in: nil, timeout: 20)
                    if g.ok { h = GitTool.Result(status: 0, out: g.out.split(separator: "\n").map { "x\trefs/heads/\($0)" }.joined(separator: "\n"), err: "") }
                }
                // Already on this Mac? Any project whose origin is this repo (board 1's fourth line).
                let here = folders.first { _, url in
                    RepoProbe.remoteURL(url, "origin").flatMap { RemoteRepo.parse($0)?.repo } == parsed.repo
                }?.key
                return (a, h, here)
            }.value
            guard let f = self.gitHubProjectForm, f.repoText == text else { return }
            f.signedInAs = access.login
            f.alreadyHere = here
            if !heads.ok {
                let fail = GitFailure.from(heads)
                let w = fail.words(repo: parsed.repo.slug, branch: "", login: access.login)
                f.found = .problem(title: w.title, body: w.body)
                return
            }
            var names = heads.out.split(separator: "\n").compactMap { l -> String? in
                let ref = l.split(separator: "\t").last.map(String.init) ?? ""
                return ref.hasPrefix("refs/heads/") ? String(ref.dropFirst(11)) : nil
            }
            let def = access.defaultBranch ?? (names.contains("main") ? "main" : names.first ?? "main")
            names.removeAll { $0 == def }
            f.branches = names.map { .init(name: $0) } + [.init(name: def)]
            f.base = def
            if let b = parsed.branch, f.branches.contains(where: { $0.name == b }) { f.useExisting = true; f.existing = b }
            let slug = Self.slug(f.folderName.isEmpty ? parsed.repo.name : f.folderName)
            if f.newBranch.isEmpty { f.newBranch = access.login.map { "\($0)/\(slug)" } ?? slug }
            var bits: [String] = []
            if let v = access.visibility { bits.append(v.lowercased()) }
            switch access.sign {
            case .noGH, .signedOut:
                f.found = .unknown
            case .signedIn:
                if access.readOnly {
                    f.found = .readOnly(fork: "\(access.login ?? "you")/\(parsed.repo.name)")
                } else {
                    if access.canPush == true { bits.append("you can push") }
                    if access.protectedDefault == true { bits.append("\(def) is protected") }
                    f.found = .ok(bits.joined(separator: " · "))
                }
            }
        }
    }

    /// Choose…: the user's repositories and their organizations', newest push first (gh).
    func loadRepoChoices() {
        Task { @MainActor in
            let r = await Task.detached(priority: .utility) {
                GitTool.gh(["api", "user/repos?affiliation=owner,collaborator,organization_member&sort=pushed&per_page=40",
                            "--jq", ".[] | [.full_name, (.private|tostring), .pushed_at] | @tsv"], in: nil, timeout: 20)
            }.value
            guard r.ok, let f = self.gitHubProjectForm else { return }
            f.choices = r.out.split(separator: "\n").compactMap { line in
                let c = line.split(separator: "\t").map(String.init)
                return c.count == 3 ? (c[0], c[1] == "true", String(c[2].prefix(10))) : nil
            }
        }
    }

    /// Create Project: copy the repo into Home on its branch, write the brief, open it (board 3).
    public func commitGitHubProject(reply: (@MainActor (String?) -> Void)? = nil) {
        guard let f = gitHubProjectForm, let repo = f.repo, f.canCreate else { reply?("Nothing to create yet."); return }
        let name = f.folderName
        if let why = newProjectProblem(name, in: f.into.folder) { info(why); reply?(why); return }
        let dest = f.into.folder.appending(path: name)
        let newBranch = f.useExisting ? nil : f.newBranch
        let existing = f.useExisting ? f.existing : nil
        let base = f.base, keep = f.keepOutOfGit, goal = f.goal.trimmingCharacters(in: .whitespacesAndNewlines)
        let start = f.startSession
        let starter = Templates.make(.project, title: name, project: nil, home: homeFolder, values: goal.isEmpty ? [] : [("goal", .scalar(goal))])
        f.working = true
        Task { @MainActor in
            let r = await Task.detached(priority: .userInitiated) {
                RepoOps.clone(repo, into: dest, newBranch: newBranch, from: newBranch == nil ? nil : base, existing: existing, excludeDuoFiles: keep)
            }.value
            switch r {
            case .failure(let e):
                f.working = false
                let w = e.words(repo: repo.slug, branch: newBranch ?? existing ?? "", login: f.signedInAs)
                f.found = .problem(title: w.title, body: w.body)
                reply?(w.title)
            case .success:
                // The brief: DL-147 names new ones `_PROJECT.md`, but until the CX build Duo finds projects by `PROJECT.md` (C-62).
                try? Data(starter.utf8).write(to: dest.appending(path: "PROJECT.md"), options: .withoutOverwriting)
                self.gitHubProjectForm = nil
                self.liveFolders[name] = dest
                self.registerUndo("New Project from GitHub") { model in
                    try? FileManager.default.trashItem(at: dest, resultingItemURL: nil); model.refreshLive()
                }
                let started = start ? self.newSession(in: name) : nil
                self.refreshLive()
                let branch = newBranch ?? existing ?? ""
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    MainActor.assumeIsolated {
                        self.open(project: name)
                        if let started { self.consoleTab = started }
                        self.repoNotice = RepoNotice(text: "Copied \(repo.slug) into \(Self.short(dest.path)), on \(newBranch != nil ? "a new branch, " : "")\(branch). Nothing changes on GitHub until you push."
                                                     + (keep ? " PROJECT.md is listed in .git/info/exclude, so it stays out of git." : ""), button: nil, url: nil)
                    }
                }
                reply?(nil)
            }
        }
    }

    public func cancelGitHubProject() { gitHubProjectForm = nil }
}
