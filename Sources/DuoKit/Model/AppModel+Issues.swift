import AppKit
import DuoControl
import Foundation

/// What Duo knows of a linked issue right now: GitHub's answer, or why it can't say.
public enum IssueState: Equatable, Sendable {
    case info(IssueInfo)
    case unavailable(IssueUnavailable)
}

/// Mark Complete's notice for a task that tracks an issue (github-issues-handoff board 6): "Close #n too".
public struct IssueOffer: Equatable {
    public var project: String
    public var path: String
    public var title: String
    public var ref: IssueRef
    public var previousStatus: String?
    public var at = Date()
}

/// GitHub issues, slice 1 (DL-226): a task links one issue (`issue:`), its card and note show the
/// issue's live state, and Duo writes to GitHub only to close or reopen it, make a new one from a
/// task, and put "Closes #n" in Push's pull request. `gh` is the way in; without it, or without
/// access, the row shows what it can and says why. Nothing here creates a task from an issue.
extension AppModel {
    // MARK: Reading

    /// The repository `#n` and `n` mean for a project: its `origin` (read once, off the main thread's hot path).
    public func issueRepo(_ project: String) -> RemoteRepo? {
        if let hit = issueRepos[project] { return hit }
        if let r = repos[project]?.status.origin { issueRepos[project] = .some(r); return r }
        guard let folder = liveFolders[project] else { return nil }
        let r = RepoProbe.status(of: folder)?.origin
        issueRepos[project] = .some(r)
        return r
    }

    /// The issue a task's note names, in whichever form it was written.
    public func issueRef(project: String, raw: String?) -> IssueRef? {
        guard let raw else { return nil }
        return IssueRef.parse(raw, repo: issueRepo(project))
    }

    public func issueRef(of task: Fixture.TaskSummary) -> IssueRef? { issueRef(project: task.project, raw: task.issue) }

    /// The cached state of the issue a task tracks, nil until read (or when it tracks none).
    public func issueState(of task: Fixture.TaskSummary) -> IssueState? {
        issueRef(of: task).flatMap { issueStates[$0.url] }
    }

    /// Reads each linked issue in `project` that hasn't been read in the last two minutes, one at a
    /// time off the main thread (gh is slow). Called after a live refresh; free when nothing links.
    public func refreshIssues(project: String, force: Bool = false) {
        guard terminalsMode == .live else { return }
        let refs = (fixture.tasks ?? []).filter { $0.project == project && $0.archived != true && $0.issue != nil }
            .compactMap { issueRef(of: $0) }
        var seen = Set<String>()
        let due = refs.filter { r in
            guard seen.insert(r.url).inserted, !issueFetching.contains(r.url) else { return false }
            return force || (issueFetched[r.url].map { -$0.timeIntervalSinceNow > 120 } ?? true)
        }
        guard !due.isEmpty else { return }
        for r in due { issueFetching.insert(r.url) }
        Task.detached(priority: .utility) { [weak self] in
            for r in due.prefix(25) {
                let result = IssueTool.view(r)
                await MainActor.run {
                    guard let self else { return }
                    self.issueFetching.remove(r.url)
                    self.issueFetched[r.url] = Date()
                    switch result {
                    case .success(let info): self.issueStates[r.url] = .info(info)
                    case .failure(let why): self.issueStates[r.url] = .unavailable(why)
                    }
                    self.pushNoteContext()
                }
            }
        }
    }

    /// Reads one issue now (a verb that needs the answer).
    func readIssue(_ ref: IssueRef) -> IssueState {
        let state: IssueState
        switch IssueTool.view(ref) {
        case .success(let info): state = .info(info)
        case .failure(let why): state = .unavailable(why)
        }
        issueStates[ref.url] = state
        issueFetched[ref.url] = Date()
        return state
    }

    /// The editor's `issue:` row: what to draw for each linked issue (merged into the note context).
    func issueContext() -> [String: [String: Any]] {
        var out: [String: [String: Any]] = [:]
        for (url, s) in issueStates {
            switch s {
            case .info(let i):
                out[url] = ["number": i.ref.number, "title": i.title, "open": i.open, "detail": i.detail]
            case .unavailable(let why):
                out[url] = ["number": IssueRef.parse(url)?.number ?? 0, "why": why.words]
            }
        }
        return out
    }

    // MARK: Writing the link

    /// Link Issue…: writes `issue:` with the full URL, quoted, by key. Through the editor's buffer
    /// when the note is open (DL-13). Nil, or why not.
    @discardableResult
    public func linkIssue(project: String, path: String, raw: String) -> String? {
        guard let ref = issueRef(project: project, raw: raw) else {
            return "“\(raw)” isn’t an issue Duo can read: paste its link, owner/repo#123, or #123 (when the project is in a GitHub repository)."
        }
        if let why = writeIssueKey(project: project, path: path, TaskNotes.issueValue(ref), undoName: "Link Issue") { return why }
        refreshIssues(project: project, force: true)
        return nil
    }

    /// Unlink: `issue:` goes; the issue on GitHub is untouched.
    @discardableResult
    public func unlinkIssue(project: String, path: String) -> String? {
        guard loadTask(project, path)?.issue != nil else { return "\(path) tracks no issue" }
        return writeIssueKey(project: project, path: path, nil, undoName: "Unlink Issue")
    }

    private func writeIssueKey(project: String, path: String, _ value: String?, undoName: String) -> String? {
        guard let file = taskFile(project, path) else { return "no task '\(path)' in \(project)" }
        let edit = TaskNotes.NoteEdit.setKey("issue", value)
        if let e = editorIfLoaded, e.url?.standardizedFileURL == file.standardizedFileURL {
            let old = loadTask(project, path)?.issue
            e.applyNoteEdit(edit)
            registerUndo(undoName) { model in
                e.applyNoteEdit(.setKey("issue", old.map { TaskNotes.quoted($0) }))
                model.refreshLive()
            }
            refreshLive()
            return nil
        }
        guard let data = FileManager.default.contents(atPath: file.path), let text = String(data: data, encoding: .utf8) else { return "\(path) isn’t readable" }
        guard let new = TaskNotes.apply(edit, to: text) else { return nil }
        do { try Data(new.utf8).write(to: file, options: .atomic) } catch { return error.localizedDescription }
        registerUndo(undoName) { model in try? data.write(to: file, options: .atomic); model.refreshLive() }
        refreshLive()
        return nil
    }

    /// Link Issue… on a menu: a Duo question with a field (a stand-in for board 3's search popover, Q-231).
    public func askLinkIssue(project: String, path: String) {
        let repo = issueRepo(project)
        let field = DuoQuestion.Field(label: "Issue", text: "")
        let where_ = repo.map { " in \($0.slug)" } ?? ""
        if Env.autoconfirm { FileHandle.standardError.write(Data("question: Link an issue\(where_)\n".utf8)); return }
        SheetCenter.shared.ask(DuoQuestion(title: "Link an issue", paragraphs: ["Paste an issue’s link, or type #number\(where_). The task tracks one issue; its state shows on the card. Nothing on GitHub changes."],
                                           field: field, choices: [
            .init(label: "Cancel", isCancel: true) {},
            .init(label: "Link", isDefault: true) { if let why = self.linkIssue(project: project, path: path, raw: field.text) { self.info(why) } },
        ]))
    }

    // MARK: Writing to GitHub: Close, Reopen, New Issue

    /// Close or reopen the issue a task tracks (`gh issue close|reopen`): the only changes Duo makes to an existing issue.
    public func setIssueOpen(project: String, path: String, open: Bool, then: (@MainActor (String?) -> Void)? = nil) {
        guard let ref = issueRef(project: project, raw: loadTask(project, path)?.issue) else {
            then?("\(path) tracks no issue"); return
        }
        setIssueOpen(ref, open: open, project: project, then: then)
    }

    public func setIssueOpen(_ ref: IssueRef, open: Bool, project: String, then: (@MainActor (String?) -> Void)? = nil) {
        Task { @MainActor in
            let r = await Task.detached(priority: .userInitiated) { IssueTool.setOpen(ref, open: open) }.value
            switch r {
            case .failure(let why):
                then?("Couldn’t \(open ? "reopen" : "close") \(ref.short): \(why.words)")
            case .success:
                let now = await Task.detached(priority: .userInitiated) { IssueTool.view(ref) }.value
                self.issueFetched[ref.url] = Date()
                switch now {
                case .success(let info): self.issueStates[ref.url] = .info(info)
                case .failure(let why): self.issueStates[ref.url] = .unavailable(why)
                }
                self.registerUndo(open ? "Reopen Issue" : "Close Issue") { model in
                    model.setIssueOpen(ref, open: !open, project: project)
                }
                then?(nil)
            }
        }
    }

    /// Mark Complete's notice for a tracked, still-open issue (board 6). Offered, never automatic.
    func offerCloseIssue(project: String, path: String, previousStatus: String?) {
        guard let t = fixture.tasks?.first(where: { $0.project == project && $0.path == path }), let ref = issueRef(of: t),
              case .info(let i)? = issueStates[ref.url], i.open else { return }
        issueOffer = IssueOffer(project: project, path: path, title: t.title, ref: ref, previousStatus: previousStatus)
    }

    public func closeOfferedIssue() {
        guard let o = issueOffer else { return }
        issueOffer = nil
        setIssueOpen(o.ref, open: false, project: o.project) { why in if let why { self.info(why) } }
    }

    public func undoOffer() {
        guard let o = issueOffer else { return }
        issueOffer = nil
        if let why = setTaskStatus(project: o.project, path: o.path, o.previousStatus ?? "open") { info(why) }
    }

    /// The note's issue row offers the other fact's move (board 6): Mark Done when GitHub closed it,
    /// Reopen Task when it was reopened.
    public func issueOpenedOnGitHub(_ task: Fixture.TaskSummary) -> Bool? {
        guard case .info(let i)? = issueState(of: task) else { return nil }
        return i.open
    }

    /// New Issue from Task: creates an issue in the project's GitHub repo titled after the task, its
    /// text as the body, and links it. A Duo question first (it publishes under the user's name).
    public func askNewIssue(project: String, path: String, then: (@MainActor (Result<IssueRef, IssueUnavailable>) -> Void)? = nil) {
        guard let t = loadTask(project, path) else { then?(.failure(.other("no task '\(path)' in \(project)"))); return }
        guard t.issue == nil else { let why = "\(t.title) already tracks \(t.issue ?? "an issue")"; then?(.failure(.other(why))); info(why); return }
        guard let repo = issueRepo(project), repo.isGitHub else {
            let why = "This project isn’t in a GitHub repository, so there’s nowhere to file the issue."
            then?(.failure(.other(why))); info(why); return
        }
        let go = { self.createIssue(project: project, path: path, title: t.title, repo: repo, then: then) }
        if Env.autoconfirm { return go() }
        SheetCenter.shared.ask(DuoQuestion(title: "New issue in \(repo.slug)?", paragraphs: ["Duo files “\(t.title)” as an issue on GitHub, under your name, with this task’s text, and links it to the task."], choices: [
            .init(label: "Cancel", isCancel: true) {},
            .init(label: "Create Issue", isDefault: true) { go() },
        ]))
    }

    public func createIssue(project: String, path: String, title: String, repo: RemoteRepo, then: (@MainActor (Result<IssueRef, IssueUnavailable>) -> Void)? = nil) {
        guard let file = taskFile(project, path), let text = try? String(contentsOf: file, encoding: .utf8) else { then?(.failure(.other("\(path) isn’t readable"))); return }
        let body = Self.issueBody(fromNote: text, path: path)
        Task { @MainActor in
            let r = await Task.detached(priority: .userInitiated) { IssueTool.create(repo, title: title, body: body) }.value
            switch r {
            case .failure(let why): then?(.failure(.other("Couldn’t create the issue: \(why.words)")))
            case .success(let ref):
                if let why = self.writeIssueKey(project: project, path: path, TaskNotes.issueValue(ref), undoName: "New Issue from Task") { then?(.failure(.other(why))); return }
                self.refreshIssues(project: project, force: true)
                then?(.success(ref))
            }
        }
    }

    /// The issue's body from a task note: the note's text without its frontmatter and its own `# ` title.
    public static func issueBody(fromNote text: String, path: String) -> String {
        var body = String(Frontmatter.parse(text).body).trimmingCharacters(in: .whitespacesAndNewlines)
        if body.hasPrefix("# "), let nl = body.firstIndex(of: "\n") { body = String(body[nl...]).trimmingCharacters(in: .whitespacesAndNewlines) }
        else if body.hasPrefix("# ") { body = "" }
        if body.count > 8000 { body = String(body.prefix(8000)) + "…" }
        return body
    }

    // MARK: Push's pull request

    /// The tasks in a project that track an issue in `repo`, for Push's "Closes #n" rows (board 6):
    /// in-progress tasks are ticked, the rest not.
    public func closesCandidates(project: String, repo: RemoteRepo) -> [PushForm.Closes] {
        (fixture.tasks ?? []).filter { $0.project == project && $0.archived != true && $0.isOpen }.compactMap { t in
            guard let ref = issueRef(of: t), ref.host == repo.host, ref.owner.lowercased() == repo.owner.lowercased(), ref.name.lowercased() == repo.name.lowercased() else { return nil }
            if case .info(let i)? = issueStates[ref.url], !i.open { return nil }   // already closed
            return PushForm.Closes(ref: ref, title: t.title, status: TaskBoard.key(t.status), ticked: TaskBoard.key(t.status) == "in-progress")
        }.sorted { $0.ref.number < $1.ref.number }
    }
}
