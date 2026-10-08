import DuoKit
import Foundation

// The task board (DL-148, DL-150, task-board-handoff): lanes from the brief, lenient status
// matching, computed order, Done's folds, and the surgical writes.
@MainActor func taskBoardChecks() throws {
    print("task board: lanes, order, folds and writes (DL-148, DL-150)")
    let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX")
    let today = f.date(from: "2026-10-07")!
    func t(_ title: String, _ status: String?, due: String? = nil, created: String? = nil, completed: String? = nil, sessions: [String] = [], archived: Bool = false) -> Fixture.TaskSummary {
        var s = Fixture.TaskSummary(project: "p", path: "tasks/\(TaskNotes.slug(title)).md", title: title, status: status, sessionIds: sessions, archived: archived ? true : nil)
        s.due = due; s.created = created; s.completed = completed
        return s
    }

    // Lanes: the default five, the brief's list, Open and Done always kept, dropped never a lane.
    check(TaskBoard.lanes(brief: nil) == TaskBoard.defaultLanes, "no brief: the default five lanes")
    check(TaskBoard.lanes(brief: "---\ntype: project\n---\n") == TaskBoard.defaultLanes, "a brief without lanes: the default five")
    check(TaskBoard.lanes(brief: "---\nlanes:\n  - open\n  - in-progress\n  - Blocked\n  - review\n  - done\n---\n") == ["open", "in-progress", "blocked", "review", "done"], "lanes: from the brief, matched lowercased")
    check(TaskBoard.lanes(brief: "---\nlanes: [doing, dropped, doing]\n---\n") == ["open", "doing", "done"], "Open and Done kept; dropped and repeats left out")
    check(TaskBoard.title("in-progress") == "In progress" && TaskBoard.title("blocked") == "Blocked", "lane titles")
    check(TaskBoard.status(forColumn: "Blocked") == "blocked" && TaskBoard.status(forColumn: "On hold") == "on-hold" && TaskBoard.status(forColumn: "  ") == nil, "a column's status is its name's slug")

    // Lenient matching: trimmed, case-insensitive, missing is open; unknown values are extra lanes.
    let tasks = [
        t("A", "Open "), t("B", nil), t("C", "IN-PROGRESS"), t("D", "blocked"), t("E", "waiting"),
        t("F", "done", completed: "2026-10-05"), t("G", "done", completed: "2026-09-01"), t("H", "dropped", completed: "2026-10-01"),
        t("I", "open", archived: true),
    ]
    let board = TaskBoard.lanes(tasks: tasks, lanes: TaskBoard.defaultLanes, state: { _ in nil }, today: today)
    check(board.map(\.status) == ["open", "in-progress", "waiting", "review", "done", "blocked"], "listed lanes in order, then unlisted statuses at the end")
    check(board.last?.extra == true && board.first?.extra == false, "an unlisted status is marked extra (Keep as Column)")
    check(board[0].cards.map(\.task.title) == ["A", "B"], "\"Open \" and a missing status are Open; an archived task never shows")
    check(board[1].cards.map(\.task.title) == ["C"], "IN-PROGRESS is in progress")
    check(board[3].cards.isEmpty, "an empty lane still shows")
    let done = board[4]
    check(done.cards.map(\.task.title) == ["F"] && done.earlier.map(\.task.title) == ["G"] && done.dropped.map(\.task.title) == ["H"], "Done: the last 7 days, then Earlier, then Dropped")
    check(done.count == 1, "Done's count is its shown cards; Earlier and Dropped count in their folds")

    // Order: needs you, then due, then oldest created.
    let order = [
        t("late created", "open", created: "2026-10-03"), t("early created", "open", created: "2026-09-01"),
        t("due later", "open", due: "2026-10-20"), t("due soon", "open", due: "2026-10-09"),
        t("needs you", "open", sessions: ["s1"]),
    ]
    let lane = TaskBoard.lanes(tasks: order, lanes: TaskBoard.defaultLanes, state: { $0 == "s1" ? .needsYou : nil }, today: today)[0]
    check(lane.cards.map(\.task.title) == ["needs you", "due soon", "due later", "early created", "late created"], "needs you, then due, then oldest created")
    let moving = TaskBoard.Card(task: t("due mid", "open", due: "2026-10-12"), urgent: nil)
    check(TaskBoard.slot(of: moving, in: lane) == 2, "a dragged card's slot is its computed place")

    // Dates and people.
    var overdue = t("x", "waiting", due: "2026-10-03")
    check(TaskBoard.overdue(overdue, today: today), "past due and open is overdue")
    overdue.status = "done"
    check(!TaskBoard.overdue(overdue, today: today), "done is never overdue")
    check(TaskBoard.short("2026-10-10") == "Oct 10" && TaskBoard.short("soon") == nil, "a card's short date")
    check(TaskBoard.plain("[[Sam Ortiz]]") == "Sam Ortiz" && TaskBoard.plain("[Priya Shah](people/priya.md)") == "Priya Shah" && TaskBoard.plain("Data team") == "Data team", "a person as written")
    check(TaskBoard.isYou("Geoff", user: "Geoff Dudgeon") && TaskBoard.isYou("me", user: "X Y") && !TaskBoard.isYou("[[Sam Ortiz]]", user: "Geoff Dudgeon"), "the owner shows only when it isn't you")

    // Notes: the card's fields are read, nothing else changes.
    let note = "---\ntype: task\ntitle: PRD v2\nstatus: in-progress\nowner: Geoff\nwaiting_on: \"[[Priya Shah]]\"\ndue: 2026-10-10\nreferences:\n  - \"[PRD v2](../docs/prd-v2.md)\"\n  - \"[research](../research/)\"\ncreated: 2026-10-01\ntasknotes_manual_order: \"0|hzzzzz:\"\n---\n\n# PRD v2\n"
    let n = TaskNotes.parse(note, path: "tasks/prd-v2.md")
    check(n.owner == "Geoff" && n.waitingOn == "[[Priya Shah]]" && n.due == "2026-10-10" && n.created == "2026-10-01" && n.references.count == 2, "a task's card fields and references are read")
    let moved = TaskNotes.settingStatus("review", in: note, today: today)
    check(moved == note.replacingOccurrences(of: "status: in-progress", with: "status: review"), "a drag writes the status line only; other keys (TaskNotes' rank too) are untouched")

    // The brief's lanes: written as a block list, in place, nothing else touched.
    let brief = "---\ntype: project\ntitle: Checkout\nstatus: active\n---\n\n# Checkout\n"
    let added = ProjectBrief.settingLanes(["open", "in-progress", "blocked", "review", "done"], in: brief)
    check(added == "---\ntype: project\ntitle: Checkout\nstatus: active\nlanes:\n  - open\n  - in-progress\n  - blocked\n  - review\n  - done\n---\n\n# Checkout\n", "lanes: is added before the closing fence")
    let again = ProjectBrief.settingLanes(["open", "blocked", "done"], in: added)
    check(again == "---\ntype: project\ntitle: Checkout\nstatus: active\nlanes:\n  - open\n  - blocked\n  - done\n---\n\n# Checkout\n", "lanes: is edited in place")
    let inline = ProjectBrief.settingLanes(["open", "done"], in: "---\nlanes: [open, review, done]\ngoal: x\n---\n")
    check(inline == "---\nlanes:\n  - open\n  - done\ngoal: x\n---\n", "an inline lanes list becomes a block list, the next key kept")

    // The brief (DL-147): _PROJECT.md, then PROJECT.md, then a note marked project_brief.
    let root = URL(fileURLWithPath: "/tmp/duo-board-\(UUID().uuidString.prefix(8))")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    check(ProjectBrief.url(in: root) == nil, "no brief")
    try Data("---\nproject_brief: true\n---\n".utf8).write(to: root.appending(path: "Checkout.md"))
    check(ProjectBrief.url(in: root)?.lastPathComponent == "Checkout.md", "a note marked project_brief is the brief")
    try Data("# p\n".utf8).write(to: root.appending(path: "PROJECT.md"))
    check(ProjectBrief.url(in: root)?.lastPathComponent == "PROJECT.md", "PROJECT.md wins over a marked note")
    try Data("# p\n".utf8).write(to: root.appending(path: "_PROJECT.md"))
    check(ProjectBrief.url(in: root)?.lastPathComponent == "_PROJECT.md", "_PROJECT.md wins")
}
