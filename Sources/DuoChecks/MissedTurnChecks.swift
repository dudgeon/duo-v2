import DuoControl
import DuoKit
import Foundation

// The missed-turns failure (tasks/failure-missed-worker-turns.md, docs/research/director-worker-skill.md §3, F-698):
// Geoff talks to workers directly about as often as to the director, and a turn he drives can end on a proposal,
// a question or "I'll pass this to the director" that never reaches it. `duo2 director status` must show it.
//
// `DUO_CHECKS=missed-turns swift run DuoChecks`. Written to FAIL on main (2026-11-14): today a worker the user
// typed in is skipped by R1 altogether (`DirectorDuties.swift`, `where n.hasWorkerRecord && !n.userTyping`), and
// sessions the registry doesn't know are never read. Not in the default run until the fix lands; then it joins
// `directorDutyChecks()` and the old "a stopped worker the user typed in gives no line" check is replaced.
//
// The words the fix must print are this check's contract: a line for the note (or, for an unregistered session,
// the session) that says the user drove the turn and quotes how it ended.

nonisolated(unsafe) private let isoMs: ISO8601DateFormatter = { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f }()

private let hour = 3600.0, day = 86400.0

/// One transcript line.
private func jl(_ obj: [String: Any]) -> String { String(decoding: try! JSONSerialization.data(withJSONObject: obj), as: UTF8.self) }

/// A turn the user typed (Remote Control, Duo, the terminal: Claude marks it human).
private func human(_ text: String, _ at: Date, cwd: String) -> String {
    jl(["type": "user", "timestamp": isoMs.string(from: at), "cwd": cwd, "origin": ["kind": "human"], "message": ["role": "user", "content": text]])
}
/// The director's brief or send: its tag first.
private func directorTurn(_ text: String, _ at: Date, director: String, cwd: String) -> String {
    jl(["type": "user", "timestamp": isoMs.string(from: at), "cwd": cwd, "message": ["role": "user", "content": Director.tag(director) + text]])
}
private func say(_ text: String, _ at: Date) -> String {
    jl(["type": "assistant", "timestamp": isoMs.string(from: at), "message": ["role": "assistant", "content": [["type": "text", "text": text]]]])
}
private func tool(_ name: String, _ input: [String: Any], _ at: Date) -> String {
    jl(["type": "assistant", "timestamp": isoMs.string(from: at), "message": ["role": "assistant", "content": [["type": "tool_use", "id": "t\(Int(at.timeIntervalSince1970))", "name": name, "input": input]]]])
}

/// The words of 7a3c28cd's last reply on 2026-11-10, shortened: what the director never heard.
let missedOffer = "If you agree, I'll pass this to the director as a change to steps 3 and 6."

@MainActor func missedTurnChecks() throws {
    print("missed turns: a turn the user drove in a worker reaches the director (F-698; fails on main until the fix)")
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appending(path: "dmissed-\(UUID().uuidString.prefix(6))")
    defer { try? fm.removeItem(at: root) }
    let proj = root.appending(path: "p"), cfg = root.appending(path: "cfg")
    let projFolder = cfg.appending(path: "projects/" + ClaudeStorage.encode(proj.path))
    for d in [proj.appending(path: "tasks"), cfg.appending(path: "sessions"), projFolder] { try fm.createDirectory(at: d, withIntermediateDirectories: true) }
    try Data("---\ntitle: P\n---\n".utf8).write(to: proj.appending(path: "_PROJECT.md"))
    let n = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970))
    let stamp = DateFormatter(); stamp.locale = Locale(identifier: "en_US_POSIX"); stamp.dateFormat = "yyyy-MM-dd HH:mm"
    let iso = ISO8601DateFormatter()
    let director = "director-p"
    func note(_ file: String, progress: [String]) throws {
        let body = "# \(file)\n\n## Request\n\nx\n\n## Progress\n\n" + progress.map { "- \($0)" }.joined(separator: "\n") + "\n"
        try Data("---\ntitle: \(file)\nstatus: in-progress\ndirected_by: \"\(director)\"\ncheck_by: \(CheckBy.format(n.addingTimeInterval(2 * day)))\n---\n\(body)".utf8)
            .write(to: proj.appending(path: "tasks/\(file).md"))
    }
    func transcript(_ sid: String, _ lines: [String], lastWrite: Date) throws {
        let url = projFolder.appending(path: "\(sid).jsonl")
        try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: url)
        try fm.setAttributes([.modificationDate: lastWrite], ofItemAtPath: url.path)
    }

    // The registered worker: the director's brief, a finished report (sent, and checked by the director), then
    // the user's own question four days ago, answered with an offer and no SendMessage. Its session has ended.
    let t0 = n.addingTimeInterval(-5 * day)
    try note("article", progress: ["\(stamp.string(from: t0)) started", "\(stamp.string(from: t0.addingTimeInterval(2 * hour))) Checked: read the report"])
    let offered = n.addingTimeInterval(-4 * day)
    try transcript("s-article", [
        directorTurn("You're the worker on the task whose note is tasks/article.md.", t0, director: director, cwd: proj.path),
        say("Report: the study is written.", t0.addingTimeInterval(3600)),
        tool("SendMessage", ["to": director, "message": "Report: the study is written."], t0.addingTimeInterval(3601)),
        human("instead of jamming all of the enhancements into the director skill, we should consider a worker skill and a librarian skill", offered, cwd: proj.path),
        say("I think you're right. Worker skill now; librarian skill during the trial; stop at three.\n\n" + missedOffer, offered.addingTimeInterval(30)),
    ], lastWrite: offered.addingTimeInterval(30))

    // The same, except the worker told the director after the user's turn: nothing missed.
    try note("reported", progress: ["\(stamp.string(from: t0)) started"])
    try transcript("s-reported", [
        directorTurn("You're the worker on the task whose note is tasks/reported.md.", t0, director: director, cwd: proj.path),
        human("let's call the section Options", offered, cwd: proj.path),
        say("Renamed.", offered.addingTimeInterval(20)),
        tool("SendMessage", ["to": director, "message": "The user drove a turn: renamed the section to Options at their ask. Nothing waits on anyone."], offered.addingTimeInterval(25)),
        say("Done, and the director knows.", offered.addingTimeInterval(30)),
    ], lastWrite: offered.addingTimeInterval(30))

    // A session the registry never knew (started by hand, or before the registry), in this project, where the user
    // asked for research and the worker said it would ask the director.
    try transcript("s-unregistered", [
        human("this is an issue in typed inputs too -- ask the director to spin up research", n.addingTimeInterval(-14 * day), cwd: proj.path),
        say("Understood. I'll ask the director to start research on lost typed input.", n.addingTimeInterval(-14 * day + 20)),
    ], lastWrite: n.addingTimeInterval(-14 * day + 20))

    var reg = DirectorRegistry()
    reg.adopt(name: director, sessionId: "me-1", at: "t")
    reg.setWorker(task: "tasks/article.md", session: "s-article", at: iso.string(from: t0), adopted: false)
    reg.setWorker(task: "tasks/reported.md", session: "s-reported", at: iso.string(from: t0), adopted: false)
    var caps = ClientCaps(); caps.sessionId = "me-1"; caps.permissionMode = "auto"; caps.name = director
    let facts = DirectorFactsReader.facts(project: proj, director: director, reg: reg, beacons: [], caps: caps, skillNote: nil, duo: nil, claudeDir: cfg, appDir: nil, now: n)
    let red = DirectorRedLines.evaluate(facts, all: true)
    let shown = red.map(\.line)

    // 1. The eval case: the offer reaches status.
    let article = red.first { $0.subject == "tasks/article.md" }
    check(article?.duty == .R1, "a stopped worker whose last turn the user drove, with no report since, is R1 red for its note (\(shown))")
    check(article.map { $0.what.contains("the user drove") && $0.what.contains("pass this to the director") } == true,
          "…and the line says the user drove it and quotes how it ended (\(article?.line ?? "no line"))")

    // 2. Reported after the user's turn: not the missed-turn line (an ordinary R1 'read its report' may stand).
    check(!red.contains { $0.subject == "tasks/reported.md" && $0.what.contains("the user drove") }, "a worker that reported to the director after the user's turn isn't flagged as missed")

    // 3. A session the registry doesn't know, in this project, with the user's turn and an unkept promise.
    check(red.contains { $0.line.contains("s-unregistered") && $0.what.contains("the user drove") }, "an unregistered session in this project whose user-driven turn ended without a report is red, by session (\(shown))")

    // 4. Pure facts: what the reader hands the rules today already says enough for two of the four conditions.
    let now = n
    func stoppedTyped(_ state: String, since: TimeInterval, last: TimeInterval, question: String? = nil) -> DirectorFacts.Note {
        DirectorFacts.Note(path: "tasks/x.md", modified: now.addingTimeInterval(-day), lastProgress: now.addingTimeInterval(-day), workerState: state, hasWorkerRecord: true,
                           question: question, workerSince: now.addingTimeInterval(-since), workerLastActivity: now.addingTimeInterval(-last), userTyping: true)
    }
    func evalNote(_ note: DirectorFacts.Note) -> [RedLine] { DirectorRedLines.evaluate(DirectorFacts(now: now, notes: [note], me: .init(permissionMode: "auto"))) }
    check(evalNote(stoppedTyped("stopped", since: 5 * day, last: 4 * day)).contains { $0.duty == .R1 },
          "a worker the user typed in that then stopped is still R1 red: 'the user took it over' means read it, not skip it")
    check(evalNote(stoppedTyped("needs-you", since: 5 * day, last: 3 * day, question: "AskUserQuestion")).contains { $0.duty == .R1 && $0.what.contains("over a day") },
          "a worker blocked on a question for over a day is R1 red even when the user typed in it")
    check(evalNote(stoppedTyped("working", since: hour, last: 60)).isEmpty, "a worker the user is talking to right now gives no line (don't nag mid-conversation)")
}
