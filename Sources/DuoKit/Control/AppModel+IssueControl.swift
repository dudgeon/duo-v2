import AppKit
import DuoControl
import Foundation

/// `duo2 issue …` and `duo2 task issue` (DL-226, DL-71): every button of slice 1 has a verb.
extension AppModel {
    /// `<task|issue>`: a task (path, slug or title) resolved to its issue, or an issue reference as typed.
    private func issueTarget(_ k: String, _ project: String?) -> (ref: IssueRef, task: Fixture.TaskSummary?)? {
        if let t = findTask(k, project: project) {
            return issueRef(project: t.project, raw: loadTask(t.project, t.path)?.issue).map { ($0, t) }
        }
        return IssueRef.parse(k, repo: project.flatMap { issueRepo($0) } ?? currentProject.flatMap { issueRepo($0.name) }).map { ($0, nil) }
    }

    func issueVerb(_ id: ActionID, _ inv: Invocation, _ req: ControlRequest, _ done: @escaping @MainActor (Reply) -> Void) {
        let project = inv.flags["project"] ?? projectFor(cwd: req.cwd)?.name ?? currentProject?.name
        let usage = "usage: \(id.action.usage)"
        switch id {
        case .taskIssue:
            guard let k = inv[0] else { return done(.fail(usage)) }
            guard let t = findTask(k, project: project) else { return done(.fail("no task '\(k)'" + (project.map { " in \($0)" } ?? ""))) }
            if inv.has("clear") {
                if let why = unlinkIssue(project: t.project, path: t.path) { return done(.fail(why)) }
                return done(.ok("\(t.title) no longer tracks an issue. Nothing on GitHub changed. Undo: duo2 undo"))
            }
            guard let raw = inv[1] else { return done(.fail(usage)) }
            if let why = linkIssue(project: t.project, path: t.path, raw: raw) { return done(.fail(why)) }
            done(.ok("\(t.title) tracks \(issueRef(project: t.project, raw: raw)?.url ?? raw). Undo: duo2 undo"))
        case .issueShow:
            if let k = inv[0] {
                guard let (ref, _) = issueTarget(k, project) else { return done(.fail("'\(k)' is neither a task that tracks an issue nor an issue Duo can read")) }
                return showIssue(ref, refresh: true, done)
            }
            guard let project else { return done(.fail("which project? --project <p>")) }
            let rows = (fixture.tasks ?? []).filter { $0.project == project && $0.archived != true && $0.issue != nil }
            let lines = rows.map { t -> String in
                guard let ref = issueRef(of: t) else { return "\(t.path)  \(t.issue ?? "")  (not an issue link Duo can read)" }
                return "\(t.path)  \(ref.slug)#\(ref.number)  " + stateWords(issueStates[ref.url])
            }
            done(.ok(lines.isEmpty ? "No task in \(project) tracks an issue." : lines.joined(separator: "\n"), ["tasks": rows.map { t -> [String: Any] in
                var j: [String: Any] = ["path": t.path, "title": t.title]
                if let ref = issueRef(of: t) { j.merge(issueJSON(ref, issueStates[ref.url])) { $1 } }
                return j
            }]))
        case .issueOpen:
            guard let k = inv[0] else { return done(.fail(usage)) }
            guard let (ref, _) = issueTarget(k, project) else { return done(.fail("'\(k)' tracks no issue Duo can read")) }
            AppModel.openOutside(ref.webURL)
            done(.ok("Opened \(ref.url)"))
        case .issueClose, .issueReopen:
            guard let k = inv[0] else { return done(.fail(usage)) }
            guard let (ref, task) = issueTarget(k, project) else { return done(.fail("'\(k)' tracks no issue Duo can read")) }
            guard inv.has("yes") else { return done(.fail("this changes \(ref.slug)#\(ref.number) on GitHub: add --yes")) }
            let open = id == .issueReopen
            setIssueOpen(ref, open: open, project: task?.project ?? project ?? "") { why in
                if let why { return done(.fail(why)) }
                done(.ok("\(open ? "Reopened" : "Closed") \(ref.slug)#\(ref.number). Undo: duo2 undo", self.issueJSON(ref, self.issueStates[ref.url])))
            }
        case .issueNew:
            guard let k = inv.flags["from-task"] else { return done(.fail(usage)) }
            guard let t = findTask(k, project: project) else { return done(.fail("no task '\(k)'")) }
            guard inv.has("yes") || Env.autoconfirm else {
                askNewIssue(project: t.project, path: t.path)
                return done(.ok("Asked the user in Duo: file \(t.title) as an issue?"))
            }
            askNewIssue(project: t.project, path: t.path) { r in
                switch r {
                case .failure(let why): done(.fail(why.words))
                case .success(let ref): done(.ok("Filed \(ref.url) and linked it to \(t.title). Undo: duo2 undo unlinks it; the issue stays on GitHub.", ["url": ref.url, "number": ref.number]))
                }
            }
        default: done(.fail(usage))
        }
    }

    private func showIssue(_ ref: IssueRef, refresh: Bool, _ done: @escaping @MainActor (Reply) -> Void) {
        Task { @MainActor in
            let r = await Task.detached(priority: .userInitiated) { IssueTool.view(ref) }.value
            switch r {
            case .success(let info): self.issueStates[ref.url] = .info(info)
            case .failure(let why): self.issueStates[ref.url] = .unavailable(why)
            }
            self.issueFetched[ref.url] = Date()
            done(.ok("\(ref.slug)#\(ref.number)  " + self.stateWords(self.issueStates[ref.url]), self.self.issueJSON(ref, self.issueStates[ref.url])))
        }
    }

    private func stateWords(_ s: IssueState?) -> String {
        switch s {
        case .info(let i)?: "\(i.title) · \(i.detail)"
        case .unavailable(let why)?: "can’t show its state: \(why.words)"
        case nil: "state not read yet (duo2 issue show <task> reads it)"
        }
    }

    private func issueJSON(_ ref: IssueRef, _ s: IssueState?) -> [String: Any] {
        var j: [String: Any] = ["url": ref.url, "number": ref.number, "repo": ref.slug]
        switch s {
        case .info(let i)?: j.merge(["title": i.title, "state": i.open ? "open" : "closed", "labels": i.labels, "stateReason": i.stateReason ?? ""]) { $1 }
        case .unavailable(let why)?: j["unavailable"] = why.words
        case nil: break
        }
        return j
    }
}
