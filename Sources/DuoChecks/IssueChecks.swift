import Darwin
import DuoKit
import Foundation

// DL-226: a task links one GitHub issue. Parsing, the note's `issue:` key, the live read, the
// two writes (close, reopen) and New Issue, against a stub `gh` with recorded output. Nothing here
// reaches GitHub, and no real repository's issues are touched.

private func stubIssueGH(_ dir: URL) -> URL {
    let log = dir.appending(path: "gh.log")
    // Output recorded from `gh issue view --json number,title,state,stateReason,labels,url,updatedAt`.
    let open451 = #"{"number":451,"title":"Checkout spinner never ends on slow networks","state":"OPEN","stateReason":"","labels":[{"name":"bug"},{"name":"p1"}],"url":"https://github.com/acme/checkout/issues/451","updatedAt":"2026-10-16T10:00:00Z"}"#
    let closed440 = #"{"number":440,"title":"Analytics events","state":"CLOSED","stateReason":"COMPLETED","labels":[],"url":"https://github.com/acme/checkout/issues/440","updatedAt":"2026-10-03T10:00:00Z"}"#
    let list = #"[{"number":451,"title":"Checkout spinner never ends on slow networks","state":"OPEN","labels":[{"name":"bug"}],"url":"https://github.com/acme/checkout/issues/451"},{"number":448,"title":"Spinner overlaps the total on iPad","state":"OPEN","labels":[],"url":"https://github.com/acme/checkout/issues/448"}]"#
    let script = """
    #!/bin/sh
    echo "$*" >> '\(log.path)'
    case "$1 $2 $3" in
      "issue view 451") echo '\(open451)' ;;
      "issue view 440") echo '\(closed440)' ;;
      "issue view 999") echo "GraphQL: Could not resolve to an Issue with the number of 999. (repository.issue)" >&2; exit 1 ;;
      "issue list -R") echo '\(list)' ;;
      "issue close 451"|"issue reopen 451"|"issue close 440"|"issue reopen 440") echo "done" ;;
      "issue create -R") echo "https://github.com/acme/checkout/issues/482" ;;
      *) echo "stub: $*" >&2; exit 1 ;;
    esac
    """
    let url = dir.appending(path: "gh")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try? script.write(to: url, atomically: true, encoding: .utf8)
    chmod(url.path, 0o755)
    return url
}

@MainActor func issueChecks() throws {
    print("GitHub issues: a task links one (DL-226)")
    let repo = RemoteRepo(host: "github.com", owner: "acme", name: "checkout")
    // Every form a person types or Obsidian keeps.
    check(IssueRef.parse("https://github.com/acme/checkout/issues/451")?.url == "https://github.com/acme/checkout/issues/451", "a URL")
    check(IssueRef.parse("\"https://github.com/acme/checkout/issues/451/\"")?.number == 451, "a quoted URL with a trailing slash")
    check(IssueRef.parse("https://github.com/acme/checkout/pull/12#issuecomment-1")?.number == 12, "a pull request link, with a fragment")
    check(IssueRef.parse("acme/checkout#451")?.slug == "acme/checkout", "owner/repo#n")
    check(IssueRef.parse("#451", repo: repo)?.url == "https://github.com/acme/checkout/issues/451", "#n in the project's repo")
    check(IssueRef.parse("#451") == nil, "#n with no repo is nothing")
    check(IssueRef.parse("[Checkout #451](https://github.com/acme/checkout/issues/451)")?.number == 451, "a markdown link")
    check(IssueRef.parse("https://github.example.com/acme/checkout/issues/9")?.host == "github.example.com", "an Enterprise host keeps its own")
    check(IssueRef.parse("https://github.com/acme/checkout") == nil && IssueRef.parse("hello") == nil, "not an issue")
    check(IssueTool.closesLine(IssueRef.parse("#451", repo: repo)!, in: repo) == "Closes #451", "Closes #n in the same repo")
    check(IssueTool.closesLine(IssueRef.parse("other/repo#7")!, in: repo) == "Closes other/repo#7", "Closes owner/repo#n for another repo")

    // The note: `issue:` read as written, written as one quoted URL, by key, touching nothing else.
    let note = """
    ---
    type: task
    title: Guest checkout times out on slow 3G
    status: in-progress
    sessions:
      - "[Timeout repro on 3G](duo2://session/5f0c0000-0000-0000-0000-000000000000)"
    created: 2026-10-09
    ---
    # Guest checkout times out on slow 3G

    Text.
    """
    check(TaskNotes.parse(note, path: "tasks/x.md").issue == nil, "a note with no issue tracks none")
    let ref = IssueRef.parse("acme/checkout#451")!
    let linked = TaskNotes.apply(.setKey("issue", TaskNotes.issueValue(ref)), to: note)!
    check(linked.contains("issue: \"https://github.com/acme/checkout/issues/451\"\n"), "issue: is written as the full URL, quoted")
    check(TaskNotes.parse(linked, path: "tasks/x.md").issue == "https://github.com/acme/checkout/issues/451", "and read back")
    check(linked.replacingOccurrences(of: "issue: \"https://github.com/acme/checkout/issues/451\"\n", with: "") == note, "nothing else in the note changed")
    check(TaskNotes.apply(.setKey("issue", nil), to: linked) == note, "Unlink restores the note byte for byte")
    check(TaskNotes.parse(note.replacingOccurrences(of: "status:", with: "issue: '#12'\nstatus:"), path: "tasks/x.md").issue == "#12", "#n is read as written, never rewritten")
    check(TaskNotes.parse(note.replacingOccurrences(of: "status:", with: "issues:\n  - acme/checkout#9\nstatus:"), path: "tasks/x.md").issue == "acme/checkout#9", "an issues: list's first item is read")
    check(Fixture.TaskSummary(project: "p", note: TaskNotes.parse(linked, path: "tasks/x.md")).issue == ref.url, "the card's summary carries the link")
    check(AppModel.issueBody(fromNote: note, path: "tasks/x.md") == "Text.", "New Issue's body is the note's text, without frontmatter or its own title")

    // The live read and the writes, through a stub gh.
    let sand = FileManager.default.temporaryDirectory.appending(path: "duo-issues-\(getpid())").resolvingSymlinksInPath()
    try? FileManager.default.removeItem(at: sand)
    let gh = stubIssueGH(sand)
    setenv("DUO_GH_PATH", gh.path, 1)
    defer { unsetenv("DUO_GH_PATH"); try? FileManager.default.removeItem(at: sand) }
    switch IssueTool.view(ref) {
    case .success(let i):
        check(i.open && i.title.hasPrefix("Checkout spinner") && i.labels == ["bug", "p1"], "an open issue's title and labels")
        check(i.detail == "open · bug, p1", "its detail reads open · labels (board 3)")
    case .failure(let w): check(false, "read an open issue: \(w.words)")
    }
    if case .success(let i) = IssueTool.view(IssueRef.parse("acme/checkout#440")!) { check(!i.open && i.detail == "closed", "a closed issue") } else { check(false, "read a closed issue") }
    if case .failure(let w) = IssueTool.view(IssueRef.parse("acme/checkout#999")!) { check(w != .noGH, "a missing issue says why: \(w.words)") } else { check(false, "a missing issue fails") }
    if case .success(let l) = IssueTool.search(repo, query: "spinner") { check(l.count == 2 && l[1].ref.number == 448, "Link Issue… completes from the repo's open issues") } else { check(false, "search") }
    check({ if case .success = IssueTool.setOpen(ref, open: false) { return true }; return false }(), "Close")
    check({ if case .success = IssueTool.setOpen(ref, open: true) { return true }; return false }(), "Reopen")
    if case .success(let made) = IssueTool.create(repo, title: "T", body: "B") { check(made.number == 482, "New Issue returns the new issue's URL") } else { check(false, "create") }
    let log = (try? String(contentsOf: sand.appending(path: "gh.log"), encoding: .utf8)) ?? ""
    check(log.contains("issue close 451 -R acme/checkout") && log.contains("issue reopen 451 -R acme/checkout"), "gh was asked only to close and reopen")
    check(!log.contains("issue edit") && !log.contains("issue comment") && !log.contains("issue delete"), "and never to edit, comment or delete")

    // Without gh: the state it can show, and why.
    setenv("DUO_GH_PATH", "none", 1)
    if case .failure(let w) = IssueTool.view(ref) { check(w == .noGH && w.words.contains("gh"), "without gh the row says so") } else { check(false, "no gh") }
}
