import DuoControl
import DuoKit
import Foundation

// The director's responsibility register and its red lines (DL-319, DL-321): every duty has a rule that
// fires and one that doesn't, the facts are read right from notes, transcripts and the Claude app's
// records, and the register can't rot: each duty must be a row of the skill's table and have an eval.

nonisolated(unsafe) private let iso: ISO8601DateFormatter = { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f }()

/// Fixed times for the pure rules: Sunday 2026-11-08, mid-morning in the checks' own calendar.
private let cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "America/New_York")!; return c }()
private func at(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0, _ s: Int = 0) -> Date {
    cal.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi, second: s))!
}

typealias DNote = DirectorFacts.Note
private let now = Date(timeIntervalSince1970: 1_800_000_000)
private func ago(_ s: TimeInterval) -> Date { now.addingTimeInterval(-s) }
private let min = 60.0, hour = 3600.0, day = 86400.0

private func event(_ name: String, _ task: String?, _ when: Date, routine: Bool? = nil) -> DirectorEvent {
    DirectorEvent(at: iso.string(from: when), director: "d", event: name, task: task, detail: "x", routine: routine)
}

/// A director with nothing neglected: one worker working, a job on schedule, a message just sent.
private func healthy() -> DirectorFacts {
    DirectorFacts(now: now,
                  notes: [DNote(path: "tasks/ok.md", modified: ago(hour), checkBy: now.addingTimeInterval(hour), lastProgress: ago(hour), lastChecked: ago(hour),
                                workerState: "working", hasWorkerRecord: true, workerSince: ago(3 * hour), workerLastActivity: ago(min))],
                  jobs: [DirectorFacts.Job(id: "daily", nextDue: now.addingTimeInterval(hour),
                                           latestRun: .init(startedAt: ago(2 * hour), lastActivity: ago(2 * hour - 10 * min), mode: "auto", completedTurns: 3), lastCheck: ago(hour))],
                  me: .init(permissionMode: "auto", transcriptRead: true, lastToUser: ago(min), turnStartedAt: ago(2 * min),
                            duo: .init(running: true, reachable: true, cpu: 5, lastUpdateCheck: ago(hour))),
                  events: [])
}

/// `healthy()` changed by `edit`.
private func facts(_ edit: (inout DirectorFacts) -> Void) -> DirectorFacts { var f = healthy(); edit(&f); return f }

private func lines(_ f: DirectorFacts, all: Bool = false) -> [RedLine] { DirectorRedLines.evaluate(f, all: all) }
private func has(_ f: DirectorFacts, _ duty: DirectorDuty, path: String? = nil) -> Bool {
    lines(f).contains { $0.duty == duty && (path == nil || $0.subject == path) }
}

/// A note that has stopped: worker idle three hours, nothing checked.
private func stopped(_ path: String = "tasks/s.md", checked: Date? = nil, typing: Bool = false, status: String = "in-progress") -> DNote {
    DNote(path: path, status: status, modified: ago(day), checkBy: nil, lastProgress: ago(day), lastChecked: checked, workerState: "stopped",
          hasWorkerRecord: true, workerSince: ago(5 * hour), workerLastActivity: ago(3 * hour), userTyping: typing)
}

@MainActor func directorDutyChecks() throws {
    print("director duties: the register's rules (DL-319)")
    check(lines(healthy()).isEmpty, "healthy facts give no red lines (\(lines(healthy()).map(\.line)))")

    // One fixture per duty that makes it fire: a duty with no fixture fails.
    let fixtures: [DirectorDuty: DirectorFacts] = [
        .R1: facts { $0.notes = [stopped()] },
        .R2: facts { $0.notes[0].checkBy = ago(hour) },
        .R3: facts { $0.jobs[0].latestRun = .init(startedAt: ago(2 * hour), lastActivity: ago(hour), mode: "default", completedTurns: 0) },
        .R4: facts { $0.me.lastToUser = ago(day); $0.events = [event("check", "tasks/ok.md", ago(hour))] },
        .R5: facts { $0.notes = [DNote(path: "tasks/r.md", status: "review", modified: ago(day), hasWorkerRecord: true)] },
        .R6: facts { $0.notes = [DNote(path: "tasks/old.md", modified: ago(30 * day))] },
        .R7: facts { $0.me.lastToUser = ago(2 * hour); $0.me.turnStartedAt = ago(40 * min) },
        .R8: facts { $0.me.permissionMode = "bypassPermissions" },
        .R9: facts { $0.events = (1...3).map { event("send", "tasks/ok.md", ago(Double($0) * hour)) } },
    ]
    for duty in DirectorDuty.allCases {
        guard let f = fixtures[duty] else { check(false, "\(duty.rawValue) \(duty.title) has a fixture that makes it fire"); continue }
        let ls = lines(f).filter { $0.duty == duty }
        check(ls.count == 1 && ls[0].line.hasPrefix("RED \(duty.rawValue) ") && !ls[0].what.isEmpty, "\(duty.rawValue) \(duty.title): its fixture fires one line (\(ls.map(\.line)))")
    }
    check(DirectorDuty.allCases.map(\.rawValue) == ["R1", "R2", "R3", "R4", "R5", "R6", "R7", "R8", "R9"]
          && Set(DirectorDuty.allCases.map(\.title)).count == 9, "nine duties, R1 to R9, each with its own title")

    // R1: watch workers to a conclusion.
    do {
        let l = lines(facts { $0.notes = [stopped()] }).first
        check(l?.line == "RED R1 tasks/s.md: Its worker stopped 3 h ago and nothing you checked is recorded since. Read its report, compare it with the Request, then duo2 director check tasks/s.md \"what you found\".",
              "R1: a stopped worker with nothing checked since: the line says how long and what to do (\(l?.line ?? "none"))")
        check(lines(facts { $0.notes = [stopped(checked: ago(hour))] }).isEmpty, "R1: a Checked line after the report clears it")
        check(!lines(facts { $0.notes = [stopped(checked: ago(10 * hour))] }).isEmpty, "R1: a Checked line from before the report doesn't")
        check(lines(facts { $0.notes = [stopped(typing: true)] }).isEmpty, "R1: a stopped worker the user typed in gives no line")
        var idle = stopped(); idle.workerState = "idle"
        check(has(facts { $0.notes = [idle] }, .R1), "R1: an idle worker is a stopped one")
        var waiting = stopped(); waiting.workerState = "needs-you"; waiting.question = "permission prompt"
        check(lines(facts { $0.notes = [waiting] }).first?.what == "Its worker is waiting: \"permission prompt\".", "R1: a worker waiting on the user, with its question")
        waiting.question = nil
        check(lines(facts { $0.notes = [waiting] }).first?.what == "Its worker is waiting: \"input needed\".", "R1: and a default question when it has none")
        var silent = stopped(); silent.workerState = "working"; silent.workerLastActivity = ago(3 * hour)
        check(lines(facts { $0.notes = [silent] }).first?.what == "Its worker has been silent for 3 h.", "R1: a working worker with no write for 2 h or more is silent")
        silent.workerLastActivity = ago(hour)
        check(lines(facts { $0.notes = [silent] }).isEmpty, "R1: a working worker that wrote an hour ago is fine")
        var none = stopped(); none.hasWorkerRecord = false; none.workerState = "no worker"; none.modified = ago(min); none.lastProgress = ago(min); none.checkBy = now.addingTimeInterval(day)
        check(lines(facts { $0.notes = [none] }).isEmpty, "R1: no worker record, no line from it")
        let both = stopped(); var late = both; late.checkBy = ago(hour)
        let twice = lines(facts { $0.notes = [late] })
        check(twice.count == 1 && twice[0].duty == .R1, "a note appears under at most one rule: a stopped worker with a passed check_by is R1 alone")
    }

    // R2: follow up by check_by.
    do {
        let past = lines(facts { $0.notes[0].checkBy = ago(5 * hour) }).first
        check(past?.line == "RED R2 tasks/ok.md: Its check_by passed 5 h ago. Look now, then duo2 director check tasks/ok.md \"what you found\" --next <when>.", "R2: a passed check_by (\(past?.line ?? "none"))")
        check(lines(healthy()).isEmpty && lines(facts { $0.notes[0].checkBy = now.addingTimeInterval(min) }).isEmpty, "R2: a future check_by gives no line")
        let fail = lines(facts { $0.notes[0].title = "Failure: the run started in Default"; $0.notes[0].checkBy = ago(2 * day) })
        check(fail.count == 1 && fail[0].duty == .R9 && fail[0].what == "This failure's check_by passed 2 d ago." && fail[0].todo == "Finish the protocol: cause, duty, change, eval, ship.",
              "R2: a Failure: task past its check_by is R9, with the protocol to finish (\(fail.map(\.line)))")
        let expired = lines(facts { $0.notes = [DNote(path: "tasks/e.md", modified: ago(day), lastProgress: ago(min), workerState: "no worker", hasWorkerRecord: true, pendingExpired: true, workerName: "w-abc123")] })
        check(expired.first?.what == "Its worker w-abc123 was recorded to start and never appeared." && expired.first?.todo == "Start it again and find out why it didn't start.",
              "R2: a background start recorded and never seen")
        let live = DNote(path: "tasks/live.md", status: "in-progress", modified: ago(2 * hour), lastProgress: ago(day))
        check(lines(facts { $0.notes = [live] }).first?.line == "RED R2 live notes: 1 note is marked live with no worker and no check_by: tasks/live.md. Start each one's worker, or set when you'll look: duo2 director check <task> \"what you know\" --next <when>.",
              "R2: a live note with no worker and no check_by")
        let nine = (0..<9).map { i -> DNote in var n = live; n.path = "tasks/live\(i).md"; return n }
        let swept = lines(facts { $0.notes = nine })
        check(swept.filter { $0.duty == .R2 }.count == 1 && swept.first?.what.contains("9 notes") == true && swept.first?.what.contains("and 4 more (--all lists them)") == true,
              "R2: live notes with no worker collapse into one line, as the other sweeps do")
        var young = live; young.modified = ago(10 * min)
        var inTree = live; inTree.inWorkTree = true
        var withBy = live; withBy.checkBy = now.addingTimeInterval(hour)
        var waiting = live; waiting.status = "waiting"
        check(lines(facts { $0.notes = [young] }).isEmpty && lines(facts { $0.notes = [inTree] }).isEmpty && lines(facts { $0.notes = [withBy] }).isEmpty && lines(facts { $0.notes = [waiting] }).isEmpty,
              "R2: not for a note changed in the last 30 minutes, one in a work tree, one with a check_by, or one that's waiting")
    }

    // R3: scheduled jobs.
    do {
        func job(_ run: DirectorFacts.Run?, due: Date? = nil, check: Date? = nil) -> DirectorFacts { facts { $0.jobs = [DirectorFacts.Job(id: "disc", nextDue: due, latestRun: run, lastCheck: check)] } }
        let stuck = lines(job(.init(startedAt: ago(2 * hour), lastActivity: ago(47 * min), mode: "default", completedTurns: 0))).first
        check(stuck?.subject == "disc" && stuck?.what == "Its run started \(DirectorRedLines.clock(ago(2 * hour), now: now)) in default, with no activity for 47 min."
              && stuck?.todo == "Unstick it. If this has happened before, find out why it starts this way (the failure protocol).", "R3: a run with no finished turn and no activity: when it started, its mode, how long (\(stuck?.line ?? "none"))")
        check(lines(job(.init(startedAt: ago(hour), lastActivity: ago(47 * min), mode: nil, completedTurns: 0))).first?.what.contains("in an unknown mode") == true, "R3: an unknown mode is said so")
        check(lines(job(.init(startedAt: ago(hour), lastActivity: ago(10 * min), mode: "auto", completedTurns: 0))).isEmpty, "R3: a run that wrote 10 minutes ago isn't stuck yet")
        let done = lines(job(.init(startedAt: ago(3 * hour), lastActivity: ago(2 * hour), mode: "auto", completedTurns: 2))).first
        check(done?.what == "Its run finished 2 h ago and you haven't recorded reading it." && done?.todo == "Read it, then duo2 director check job:disc \"what it found\" (--routine if nothing new).",
              "R3: a finished run nobody recorded reading")
        check(lines(job(.init(startedAt: ago(3 * hour), lastActivity: ago(2 * hour), mode: "auto", completedTurns: 2), check: ago(hour))).isEmpty, "R3: a check after the run clears it")
        check(!lines(job(.init(startedAt: ago(3 * hour), lastActivity: ago(2 * hour), mode: "auto", completedTurns: 2), check: ago(5 * hour))).isEmpty, "R3: a check from before the run doesn't")
        check(lines(job(.init(startedAt: ago(10 * min), lastActivity: ago(2 * min), mode: "auto", completedTurns: 1))).isEmpty, "R3: a run that wrote two minutes ago is still going")
        check(lines(job(.init(startedAt: ago(9 * day), lastActivity: ago(8 * day), mode: "auto", completedTurns: 1))).isEmpty, "R3: a finished run over 7 days old is no longer chased")
        check(lines(job(.init(startedAt: ago(3 * hour), lastActivity: ago(2 * hour), mode: "default", completedTurns: 0, archived: true))).isEmpty, "R3: an archived run is the user's tidying, not a stuck one")
        let missed = lines(job(nil, due: ago(3 * hour))).first
        check(missed?.what == "A run due \(DirectorRedLines.clock(ago(3 * hour), now: now)) never started." && missed?.todo == "Start it, and find out why it was missed.", "R3: a due time that passed without a run")
        check(lines(job(nil, due: ago(30 * min))).isEmpty, "R3: a due time half an hour ago is within the hour's grace")
        let both = lines(job(.init(startedAt: ago(2 * hour), lastActivity: ago(hour), mode: "default", completedTurns: 0), due: ago(3 * hour)))
        check(both.count == 1 && both[0].what.hasPrefix("Its run started"), "R3: a stuck run shows only the stuck line, not the missed one too")
        let blind = lines(facts { $0.jobsUnreadable = "scheduled-tasks.json isn't JSON Duo can read" })
        check(blind.count == 1 && blind[0].subject == "scheduled runs" && blind[0].what == "Can't read scheduled runs: scheduled-tasks.json isn't JSON Duo can read."
              && blind[0].todo.contains("this check is blind"), "R3: when the records can't be read it says so, always")
    }

    // R4 and R7: telling the user.
    do {
        let ev = [event("check", "tasks/ok.md", ago(2 * hour))]
        let told = lines(facts { $0.me.lastToUser = ago(day); $0.events = ev }).first
        check(told?.line == "RED R4 tasks/ok.md: You recorded a check 2 h ago and haven't messaged the user since. If it matters to them, tell them in plain words with its link. If it doesn't, mark it --routine next time.",
              "R4: a check recorded after your last word to the user")
        check(lines(facts { $0.me.lastToUser = ago(hour); $0.events = ev }).isEmpty, "R4: a message to the user after it clears it")
        check(lines(facts { $0.me.lastToUser = ago(day); $0.events = [event("check", "job:daily", ago(hour), routine: true)] }).isEmpty, "R4: a routine check gives no line")
        check(lines(facts { $0.me.lastToUser = ago(day); $0.me.turnStartedAt = ago(min); $0.me.transcriptRead = false; $0.events = ev }).isEmpty, "R4: blind without your own transcript")
        check(lines(facts { $0.me.lastToUser = nil; $0.events = ev }).count == 1, "R4: never having spoken counts")
        check(lines(facts { $0.me.lastToUser = ago(30 * day); $0.events = [event("check", "tasks/ok.md", ago(9 * day))] }).isEmpty, "R4: a check over 7 days old is old news")
        let two = lines(facts { $0.me.lastToUser = ago(day); $0.events = [event("check", "tasks/a.md", ago(3 * hour)), event("check", "job:daily", ago(2 * hour))] })
        check(two.count == 1 && two[0].subject == "job:daily", "R4: one line at most, for the latest check, named by its task or job:<id>")
        check(lines(facts { $0.me.lastToUser = ago(day); $0.events = [event("check", "job:daily", ago(3 * hour)), event("check", "tasks/a.md", ago(hour), routine: true)] }).first?.subject == "job:daily",
              "R4: a routine check later on doesn't hide an earlier one the user hasn't heard of")

        let silent = lines(facts { $0.me.lastToUser = ago(2 * hour); $0.me.turnStartedAt = ago(40 * min) }).first
        check(silent?.line == "RED R7 this turn: You've gone 40 min without a word to the user. Send three lines: what's done, what's running, what's next.", "R7: a long turn with no word (\(silent?.line ?? "none"))")
        check(lines(facts { $0.me.lastToUser = ago(40 * min); $0.me.turnStartedAt = ago(2 * hour) }).first?.what == "You've gone 40 min without a word to the user.", "R7: counted from your last word when that's later than the turn's start")
        check(lines(facts { $0.me.lastToUser = ago(2 * hour); $0.me.turnStartedAt = ago(10 * min) }).isEmpty, "R7: a turn that began ten minutes ago has had no time to be silent")
        check(lines(facts { $0.me.lastToUser = ago(2 * hour); $0.me.turnStartedAt = ago(40 * min); $0.me.transcriptRead = false }).isEmpty, "R7: blind without your own transcript")
        check(lines(facts { $0.me.lastToUser = nil; $0.me.turnStartedAt = nil; $0.me.transcriptRead = true }).isEmpty, "R7: nothing to count from, no line")
    }

    // R5: verify before done, as one line.
    do {
        let review = (1...20).map { DNote(path: String(format: "tasks/r%02d.md", $0), status: "review", modified: ago(day), workerState: "stopped", hasWorkerRecord: true) }
        let l = lines(facts { $0.notes = review })
        check(l.count == 1 && l[0].duty == .R5 && l[0].subject == "review" && l[0].what.hasPrefix("20 notes wait at review with no recent check: tasks/r01.md, tasks/r02.md, tasks/r03.md, tasks/r04.md, tasks/r05.md and 15 more (--all lists them).")
              && !l[0].what.contains("r06"), "20 notes at review give exactly one R5 line, naming the count and only five paths (\(l.map(\.what)))")
        check(l[0].todo == "Check each against its Request (duo2 director check), then bring the user one sweep and one question, not a line each.", "R5: and what to do about them")
        check(lines(facts { $0.notes = [DNote(path: "tasks/r.md", status: "review", modified: ago(day), lastChecked: ago(hour), workerSince: ago(5 * hour), workerLastActivity: ago(3 * hour))] }).isEmpty, "R5: a note at review checked after its worker's last report is fine")
        check(has(facts { $0.notes = [DNote(path: "tasks/r.md", status: "review", modified: ago(day), lastChecked: ago(hour), workerLastActivity: ago(min))] }, .R5), "R5: a worker that reported again since the check brings it back")
        check(has(facts { $0.notes = [DNote(path: "tasks/r.md", status: "review", modified: ago(day), checkBy: ago(min), lastChecked: ago(hour))] }, .R5), "R5: so does a check_by that passed")
        check(has(facts { $0.notes = [DNote(path: "tasks/d.md", status: "done", modified: ago(day), hasWorkerRecord: true)] }, .R5), "R5: a done note with a worker, changed this week and never checked")
        check(lines(facts { $0.notes = [DNote(path: "tasks/d.md", status: "done", modified: ago(day), lastChecked: ago(2 * day), hasWorkerRecord: true)] }).isEmpty
              && lines(facts { $0.notes = [DNote(path: "tasks/d.md", status: "done", modified: ago(30 * day), hasWorkerRecord: true)] }).isEmpty
              && lines(facts { $0.notes = [DNote(path: "tasks/d.md", status: "done", modified: ago(day))] }).isEmpty, "R5: not a done note that was checked, is old, or never had a worker")
        // Notes at review give no R1, R2 or R6 line, whatever else is true of them.
        let messy = DNote(path: "tasks/m.md", status: "review", modified: ago(90 * day), checkBy: ago(day), lastProgress: ago(90 * day), workerState: "stopped",
                          hasWorkerRecord: true, workerSince: ago(80 * day), workerLastActivity: ago(80 * day))
        let m = lines(facts { $0.notes = [messy] })
        check(m.count == 1 && m[0].duty == .R5, "notes at review give no R1, R2 or R6 line: only R5 (\(m.map(\.line)))")
    }

    // R6: the record, as one line.
    do {
        let stale = (1...40).map { DNote(path: String(format: "tasks/n%02d.md", $0), modified: ago(30 * day), inWorkTree: $0 > 35) }
        let l = lines(facts { $0.notes = stale })
        check(l.count == 1 && l[0].duty == .R6 && l[0].subject == "the record", "40 stale notes give one R6 line (\(l.count))")
        check(l[0].what == "40 notes marked live have had nothing for over 7 days and no check_by: tasks/n01.md, tasks/n02.md, tasks/n03.md, tasks/n04.md, tasks/n05.md and 35 more (--all lists them). 5 of them exist only in work trees.",
              "R6: the count, five paths, how many more, and how many live only in work trees (\(l[0].what))")
        check(l[0].todo == "Close each, or set when you'll look. Make it one sweep and one question to the user.", "R6: and what to do about them")
        let all = lines(facts { $0.notes = stale }, all: true)
        check(all.count == 1 && all[0].what.contains("tasks/n40.md") && !all[0].what.contains("more"), "R6: --all names every one")
        let recent = DNote(path: "tasks/r.md", modified: ago(30 * day), checkBy: now.addingTimeInterval(day), lastProgress: ago(day))
        check(lines(facts { $0.notes = [recent] }).isEmpty, "R6: a note with a check_by isn't stale")
        var working = DNote(path: "tasks/w.md", modified: ago(30 * day), lastProgress: ago(30 * day), workerState: "working", hasWorkerRecord: true, workerLastActivity: ago(min))
        check(lines(facts { $0.notes = [working] }).isEmpty, "R6: nor is one whose worker is working")
        working.workerState = "no worker"; working.hasWorkerRecord = false; working.lastProgress = ago(day)
        check(lines(facts { $0.notes = [working] }).first?.duty != .R6, "R6: nor one with progress yesterday")
        check(lines(facts { $0.notes = [DNote(path: "tasks/x.md", status: "done", modified: ago(30 * day)), DNote(path: "tasks/y.md", status: "suggested", modified: ago(30 * day))] }).isEmpty, "R6: done and suggested notes are finished business")
        let odd = lines(facts { $0.notes = [DNote(path: "tasks/a.md", status: "in progress", modified: ago(hour), checkBy: now.addingTimeInterval(hour), lastProgress: ago(hour)), DNote(path: "tasks/b.md", status: "building", modified: ago(hour), checkBy: now.addingTimeInterval(hour), lastProgress: ago(hour))] })
        check(odd.count == 1 && odd[0].what == "2 notes use a status word Duo doesn't know: tasks/a.md (in progress), tasks/b.md (building)." && odd[0].todo == "Use open, in-progress, waiting, review or done.",
              "R6: a status word Duo doesn't know, with the word (\(odd.map(\.line)))")
    }

    // R8: your environment.
    do {
        func r8(_ edit: (inout DirectorFacts.Me) -> Void) -> [RedLine] { lines(facts { edit(&$0.me) }).filter { $0.duty == .R8 } }
        check(r8 { $0.permissionMode = "bypassPermissions" }.first?.line == "RED R8 your mode: This session runs in bypass, so messages to and from your workers are held and expire unseen. Switch to Auto now.", "R8: bypass mode")
        check(r8 { $0.permissionMode = "auto" }.isEmpty && r8 { $0.permissionMode = nil }.isEmpty, "R8: Auto, or a mode not read, is fine")
        check(r8 { $0.skillNote = "The installed director skill is older (revision 4) than this Duo (5)." }.first?.line == "RED R8 the skill: The installed director skill is older (revision 4) than this Duo (5).", "R8: a skill and Duo that differ, in the note's own words")
        check(r8 { $0.cliLoggedOut = true }.first?.line == "RED R8 the CLI: Claude's CLI is logged out on this Mac, so no background worker can start. Ask the user to run claude auth login here.", "R8: the CLI logged out")
        check(r8 { $0.duo = .init(running: true, reachable: false) }.first?.line == "RED R8 Duo: A Duo is running, but duo2 can't reach it. Tell the user: it may be a second instance or an old build.", "R8: a Duo running that duo2 can't reach")
        check(r8 { $0.duo = .init(running: false, reachable: false) }.isEmpty && r8 { $0.duo = nil }.isEmpty, "R8: no Duo, or none looked at, is fine")
        check(r8 { $0.duo = .init(running: true, reachable: false, cpu: 140.4) }.contains { $0.what == "Duo is using 140% CPU." && $0.todo == "Tell the user, and find out why." }, "R8: Duo above 100% CPU")
        check(r8 { $0.duo = .init(running: true, reachable: true, cpu: 100) }.isEmpty, "R8: exactly 100% is not above")
        check(r8 { $0.duo = .init(running: true, reachable: true, lastUpdateCheck: ago(3 * day)) }.first?.what == "Duo last checked for updates 3 d ago, so it may be behind.", "R8: Duo's last update check over 48 hours ago")
        check(r8 { $0.duo = .init(running: true, reachable: true, lastUpdateCheck: ago(day)) }.isEmpty && r8 { $0.duo = .init(running: true, reachable: true, lastUpdateCheck: nil) }.isEmpty, "R8: a recent check, or none known, is fine")
    }

    // R9: learn from failures.
    do {
        let sends = (1...3).map { event("send", "tasks/ok.md", ago(Double($0) * hour)) }
        let l = lines(facts { $0.events = sends }).first
        check(l?.line == "RED R9 tasks/ok.md: You've sent to this worker 3 times in a day with no check recorded. A second try is a signal: find the cause (the failure protocol).", "R9: three sends in a day and no check (\(l?.line ?? "none"))")
        check(lines(facts { $0.events = sends + [event("check", "tasks/ok.md", ago(min))] }).isEmpty, "R9: a check after the first of them clears it")
        check(!lines(facts { $0.events = sends + [event("check", "tasks/ok.md", ago(10 * hour))] }).isEmpty, "R9: a check from before them doesn't")
        check(lines(facts { $0.events = Array(sends.prefix(2)) }).isEmpty, "R9: two sends are a conversation")
        check(lines(facts { $0.events = [event("send", "tasks/ok.md", ago(hour)), event("send", "tasks/ok.md", ago(30 * hour)), event("send", "tasks/ok.md", ago(40 * hour))] }).isEmpty, "R9: only sends in the last 24 hours count")
        check(has(facts { $0.events = [event("handed", "tasks/ok.md", ago(hour)), event("handed", "tasks/ok.md", ago(2 * hour)), event("send", "tasks/ok.md", ago(3 * hour))] }, .R9),
              "R9: a message handed to the director to send counts as a send (that's what a live worker's send logs)")
        check(lines(facts { $0.events = (1...3).map { event("send", "tasks/other.md", ago(Double($0) * hour)) } }).isEmpty, "R9: sends to a task that isn't one of this director's unfinished notes give no line")
    }

    // The order, and the words around the lines.
    do {
        let everything = facts {
            $0.me.permissionMode = "bypassPermissions"; $0.me.lastToUser = ago(2 * hour); $0.me.turnStartedAt = ago(40 * min)
            $0.notes = [stopped("tasks/s.md"), DNote(path: "tasks/old.md", modified: ago(30 * day)), DNote(path: "tasks/r.md", status: "review", modified: ago(day)),
                        DNote(path: "tasks/n.md", modified: ago(day), checkBy: now.addingTimeInterval(hour), lastProgress: ago(hour), workerState: "working", hasWorkerRecord: true, workerLastActivity: ago(min)),
                        DNote(path: "tasks/p.md", modified: ago(day), checkBy: ago(hour), lastProgress: ago(hour))]
            $0.jobs[0].latestRun = .init(startedAt: ago(2 * hour), lastActivity: ago(hour), mode: "default", completedTurns: 0)
            $0.events = [event("check", "tasks/s.md", ago(hour))] + (1...3).map { event("send", "tasks/n.md", ago(Double($0) * hour)) }
        }
        let order = lines(everything).map(\.duty)
        check(order == [.R8, .R1, .R3, .R2, .R9, .R4, .R7, .R5, .R6], "order, most urgent first: R8, R1, R3, R2, R9, R4, R7, R5, R6 (\(order.map(\.rawValue)))")
        let ranks = Dictionary(uniqueKeysWithValues: DirectorRedLines.order.enumerated().map { ($1, $0) })
        check(DirectorRedLines.order == [.R8, .R1, .R3, .R2, .R9, .R4, .R7, .R5, .R6] && Set(DirectorRedLines.order) == Set(DirectorDuty.allCases)
              && ranks[.R8]! < ranks[.R1]! && ranks[.R1]! < ranks[.R6]!, "R8 comes before R1, and R1 before R6")
        check(DirectorRedLines.block([]) == ["Red lines: none."], "no red lines: \"Red lines: none.\"")
        let two = [RedLine(duty: .R1, subject: "tasks/a.md", what: "w.", todo: "t."), RedLine(duty: .R8, subject: "the skill", what: "w.", todo: "")]
        check(DirectorRedLines.block(two) == ["Red lines (2): clear what you can this turn, and put anything you can't in your next message to the user, in plain words with links.",
                                              "  RED R1 tasks/a.md: w. t.", "  RED R8 the skill: w."], "some: the count, the instruction, then each line indented two spaces (no trailing space when there's nothing to do)")
        check(DirectorRedLines.nudge(0) == nil && DirectorRedLines.nudge(1) == "1 red line: run duo2 director status." && DirectorRedLines.nudge(3) == "3 red lines: run duo2 director status.", "the nudge: nothing for none, singular and plural")
        check(DirectorRedLines.span(30) == "1 min" && DirectorRedLines.span(47 * 60) == "47 min" && DirectorRedLines.span(3 * 3600) == "3 h" && DirectorRedLines.span(60 * 3600) == "2 d", "durations read as 47 min, 3 h, 2 d")
    }

    try dutyParsingChecks()
    try dutyCronChecks()
    try dutyScheduledRunsChecks()
    try dutyReaderChecks()
    try dutyRegisterChecks()
}

// MARK: - Parsing

@MainActor private func dutyParsingChecks() throws {
    print("director duties: Progress, check_by and --next parsing")
    let note = """
    ---
    title: T
    ---
    # T

    - 2026-01-01 a dated line outside Progress: Checked: it is ignored

    ## Request

    - 2026-01-02 12:00 Checked: nor is this one

    ## Progress

    - 2026-11-05 Filed by d.
    - 2026-11-06 09:30 Worker started.
    - 2026-11-06 10:45 Checked: read the report, tests run, they pass.
    - 2026-11-07 Checked (routine): nothing new.
    - 2026-11-07 22:10 Worker stopped.
    - no date on this line
    - 2026-13-45 not a date

    ## Later

    - 2026-12-25 Checked: after the section
    """
    let p = DirectorProgress.parse(note, calendar: cal)
    check(p.lastProgress == at(2026, 11, 8), "Progress: a day-only date counts as the end of that day (\(String(describing: p.lastProgress)))")
    check(p.lastChecked == at(2026, 11, 8), "Progress: so does a day-only Checked (routine): line, and the latest Checked wins")
    let minute = DirectorProgress.parse("## Progress\n\n- 2026-11-06 10:45 Checked: x\n- 2026-11-06 09:30 Started.\n", calendar: cal)
    check(minute.lastChecked == at(2026, 11, 6, 10, 46) && minute.lastProgress == at(2026, 11, 6, 10, 46), "Progress: a minute-precise date counts as the end of that minute")
    let plain = DirectorProgress.parse("## Progress\n\n- 2026-11-06 10:45 Worker started.\n- 2026-11-07 11:00 Sent: Checked: no\n", calendar: cal)
    check(plain.lastChecked == nil && plain.lastProgress == at(2026, 11, 7, 11, 1), "Progress: a line that doesn't start Checked: isn't a check")
    let routine = DirectorProgress.parse("## Progress\n\n- 2026-11-06 10:45 Checked (routine): nothing new\n", calendar: cal)
    check(routine.lastChecked == at(2026, 11, 6, 10, 46), "Progress: Checked (routine): is a check")
    check(DirectorProgress.parse("# T\n\nno progress here\n", calendar: cal) == .init(lastProgress: nil, lastChecked: nil), "Progress: no section, no dates")
    let outside = DirectorProgress.parse("# T\n\n- 2026-11-06 10:45 Checked: x\n\n## Request\n\n- 2026-11-07 Checked: y\n", calendar: cal)
    check(outside.lastChecked == nil && outside.lastProgress == nil, "Progress: dated lines outside ## Progress are ignored")

    func by(_ s: String?) -> Date? { CheckBy.parse(s, calendar: cal) }
    check(by("2026-11-08T14:07:30") == at(2026, 11, 8, 14, 7, 30) && by("2026-11-08T14:07") == at(2026, 11, 8, 14, 7) && by("2026-11-08 14:07") == at(2026, 11, 8, 14, 7), "check_by: yyyy-MM-dd'T'HH:mm:ss, 'T'HH:mm and a space, local")
    check(by("2026-11-08T14:07:30Z") == iso.date(from: "2026-11-08T14:07:30Z") && by("2026-11-08T14:07:30-05:00") == at(2026, 11, 8, 14, 7, 30)
          && by("2026-11-08T09:07:30.250+00:00") != nil, "check_by: a full ISO-8601 time with an offset (and with fractions)")
    check(by("2026-11-08") == at(2026, 11, 9), "check_by: a bare date is the end of that day")
    check(by("\"2026-11-08T14:07:00\"") == at(2026, 11, 8, 14, 7) && by(" 2026-11-08 ") == at(2026, 11, 9), "check_by: quotes and spaces around it are dropped")
    check(by(nil) == nil && by("") == nil && by("   ") == nil && by("tomorrow") == nil && by("2026-13-01") == nil && by("2026-02-30T10:00") == nil && by("2026-11-08T25:00") == nil, "check_by: empty or unparseable is nil")
    let written = CheckBy.format(at(2026, 11, 8, 14, 7, 30))
    check(written.range(of: #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}$"#, options: .regularExpression) != nil && !written.contains("\""), "check_by is written as yyyy-MM-dd'T'HH:mm:ss, unquoted (\(written))")
    let when = Date(timeIntervalSince1970: 1_800_000_030)
    check(CheckBy.parse(CheckBy.format(when)) == when, "what Duo writes, it reads back")

    let n = Date(timeIntervalSince1970: 1_800_000_000)
    func next(_ s: String) -> CheckBy.NextLook? { try? CheckBy.parseNext(s, now: n, calendar: cal) }
    check(next("30m") == .at(n.addingTimeInterval(1800)) && next("2h") == .at(n.addingTimeInterval(7200)) && next("3d") == .at(n.addingTimeInterval(3 * 86400)), "--next: 30m, 2h, 3d from now")
    check(next("none") == CheckBy.NextLook.none && next("NONE") == CheckBy.NextLook.none, "--next: none")
    check(next("2026-11-09T08:00") == .at(at(2026, 11, 9, 8)) && next("2026-11-09") == .at(at(2026, 11, 10)), "--next: any check_by form")
    var refused = ""
    for bad in ["soon", "", "0m", "5", "m", "2w", "-3h", "1.5h", "2026-99-99"] {
        do { _ = try CheckBy.parseNext(bad, now: n, calendar: cal); check(false, "--next \(bad.debugDescription) is refused") } catch { refused = "\(error)"; check(refused.contains("30m") && refused.contains("none"), "--next \(bad.debugDescription) is refused, naming the forms") }
    }

    check(DirectorCheck.checkBy(next: nil, status: "in-progress", now: n) == n.addingTimeInterval(86400) && DirectorCheck.checkBy(next: nil, status: nil, now: n) == n.addingTimeInterval(86400), "check: check_by is a day on unless you say")
    check(DirectorCheck.checkBy(next: nil, status: "done", now: n) == nil && DirectorCheck.checkBy(next: nil, status: "Dropped", now: n) == nil, "check: a done or dropped task has none")
    check(DirectorCheck.checkBy(next: CheckBy.NextLook.none, status: "in-progress", now: n) == nil && DirectorCheck.checkBy(next: .at(n.addingTimeInterval(60)), status: "done", now: n) == n.addingTimeInterval(60), "check: --next none clears it, a --next time is used as given")
    check(DirectorCheck.startCheckBy(next: nil, now: n) == n.addingTimeInterval(7200) && DirectorCheck.startCheckBy(next: CheckBy.NextLook.none, now: n) == nil, "start: check_by is two hours on, or --next, or none")
    check(DirectorCheck.jobID("job:daily") == "daily" && DirectorCheck.jobID("tasks/x.md") == nil && DirectorCheck.jobID("job:") == "", "check: job:<id> names a job")
    check(DirectorCheck.output("tasks/x.md", nextLook: nil) == "Checked tasks/x.md. No next look set." && DirectorCheck.output("tasks/x.md", nextLook: n).hasPrefix("Checked tasks/x.md. Next look by 20"), "check: its output")
    check(DirectorCheck.progressText(evidence: "e", routine: false) == "Checked: e" && DirectorCheck.progressText(evidence: "e", routine: true) == "Checked (routine): e" && DirectorCheck.logDetail(String(repeating: "x", count: 500)).count == 200,
          "check: the Progress line, and the first 200 characters in the log")

    // A log line from an older Duo has no routine field and still reads.
    let old = try JSONDecoder().decode(DirectorEvent.self, from: Data(#"{"at":"2026-11-08T10:00:00-05:00","event":"send","task":"tasks/a.md"}"#.utf8))
    let newer = try JSONDecoder().decode(DirectorEvent.self, from: JSONEncoder().encode(DirectorEvent(at: "t", director: "d", event: "check", task: "job:x", detail: "y", routine: true)))
    check(old.routine == nil && newer.routine == true && newer.task == "job:x", "the log reads old lines (no routine) and the new ones")
    let logRoot = FileManager.default.temporaryDirectory.appending(path: "dlogtail-\(UUID().uuidString.prefix(6))")
    defer { try? FileManager.default.removeItem(at: logRoot) }
    for i in 1...200 { DirectorLog.append(DirectorEvent(at: "t\(i)", director: "d", event: "status", detail: "\(i) red lines"), project: logRoot) }
    let whole = DirectorLog.read(project: logRoot), tail = DirectorLog.read(project: logRoot, lastBytes: 1000)
    check(whole.count == 200 && !tail.isEmpty && tail.count < 20 && tail.last?.at == "t200" && tail.allSatisfy { whole.contains($0) }, "the log's tail: only whole lines from the end of a long log (\(tail.count) of 200)")
}

// MARK: - Cron

@MainActor private func dutyCronChecks() throws {
    print("director duties: cron")
    func next(_ expr: String, after: Date) -> Date? { Cron.next(after: after, expression: expr, calendar: cal) }
    check(next("0 * * * *", after: at(2026, 11, 8, 10, 30)) == at(2026, 11, 8, 11), "cron: hourly")
    check(next("15 7,19 * * *", after: at(2026, 11, 8, 7, 15)) == at(2026, 11, 8, 19, 15) && next("15 7,19 * * *", after: at(2026, 11, 8, 19, 15)) == at(2026, 11, 9, 7, 15), "cron: lists of hours, strictly after the given time")
    check(next("3 7,19 * * *", after: at(2026, 11, 8, 12, 3, 30)) == at(2026, 11, 8, 19, 3), "cron: a time with seconds past the minute")
    check(next("0 8 * * 1", after: at(2026, 11, 8, 12)) == at(2026, 11, 9, 8) && next("0 8 * * 1", after: at(2026, 11, 9, 8)) == at(2026, 11, 16, 8), "cron: weekly, Mondays")
    check(next("0 9-17 * * 1-5", after: at(2026, 11, 6, 17)) == at(2026, 11, 9, 9), "cron: ranges, weekdays 9 to 17: Friday 17:00 is followed by Monday 09:00")
    check(next("*/15 * * * *", after: at(2026, 11, 8, 10, 7)) == at(2026, 11, 8, 10, 15) && next("0 */6 * * *", after: at(2026, 11, 8, 7)) == at(2026, 11, 8, 12) && next("10-30/10 * * * *", after: at(2026, 11, 8, 10, 11)) == at(2026, 11, 8, 10, 20), "cron: steps")
    check(next("0 8 * * 0", after: at(2026, 11, 9)) == at(2026, 11, 15, 8) && next("0 8 * * 7", after: at(2026, 11, 9)) == at(2026, 11, 15, 8) && next("0 8 * * 5-7", after: at(2026, 11, 8, 9)) == at(2026, 11, 13, 8), "cron: Sunday is 0 and 7")
    check(next("0 0 1 * *", after: at(2026, 1, 31, 12)) == at(2026, 2, 1) && next("30 23 31 * *", after: at(2026, 1, 31, 23, 30)) == at(2026, 3, 31, 23, 30), "cron: across a month end, skipping months with no 31st")
    check(next("0 0 29 2 *", after: at(2026, 3, 1)) == at(2028, 2, 29) && next("0 0 1 1 *", after: at(2026, 6, 1)) == at(2027, 1, 1), "cron: a month, a leap day")
    check(next("0 0 13 * 5", after: at(2026, 11, 1)) == at(2026, 11, 6), "cron: both day fields restricted: either matches (Friday the 6th, before the 13th)")
    check(next("0 0 * * 5", after: at(2026, 11, 1)) == at(2026, 11, 6) && next("0 0 13 * *", after: at(2026, 11, 1)) == at(2026, 11, 13), "cron: one day field restricted: only it counts")
    check(next("0 0 30 2 *", after: at(2026, 1, 1)) == nil, "cron: a date that never comes is nil")
    for bad in ["", "foo", "* * * *", "* * * * * *", "61 * * * *", "* 24 * * *", "* * 0 * *", "* * * 13 *", "* * * * 8", "MON * * * *", "0 8 * * MON", "*/0 * * * *", "5-1 * * * *", "@daily", "0 8 L * *", "0 8 ? * *"] {
        check(next(bad, after: at(2026, 11, 8)) == nil, "cron: \(bad.debugDescription) is unsupported: nil, so no missed-run line")
    }
    var london = Calendar(identifier: .gregorian); london.timeZone = TimeZone(identifier: "Europe/London")!
    let spring = london.date(from: DateComponents(year: 2026, month: 3, day: 28, hour: 12))!
    check(Cron.next(after: spring, expression: "30 1 * * *", calendar: london) != nil, "cron: a daylight-saving day doesn't lose the schedule")
}

// MARK: - Scheduled runs

@MainActor private func dutyScheduledRunsChecks() throws {
    print("director duties: the Claude app's scheduled runs")
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appending(path: "dsched-\(UUID().uuidString.prefix(6))")
    defer { try? fm.removeItem(at: root) }
    let proj = root.appending(path: "proj"), other = root.appending(path: "other"), app = root.appending(path: "app")
    let dir = app.appending(path: "claude-code-sessions/acct/dev")
    for d in [proj, other, dir] { try fm.createDirectory(at: d, withIntermediateDirectories: true) }
    let nowMs = Int(Date().timeIntervalSince1970 * 1000)
    func ms(_ ago: TimeInterval) -> Int { nowMs - Int(ago * 1000) }
    func stamp(_ ago: TimeInterval) -> String { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f.string(from: Date().addingTimeInterval(-ago)) }
    func task(_ id: String, cwd: URL, cron: String = "0 * * * *", enabled: Bool = true, scheduledAgo: TimeInterval = 2 * hour) -> [String: Any] {
        ["id": id, "displayName": "Job \(id)", "cronExpression": cron, "enabled": enabled, "cwd": cwd.path, "createdAt": ms(30 * day),
         "lastRunAt": stamp(scheduledAgo), "lastScheduledFor": stamp(scheduledAgo)]
    }
    func write(_ obj: Any, _ name: String, mtime: Date? = nil) throws {
        let url = dir.appending(path: name)
        try JSONSerialization.data(withJSONObject: obj).write(to: url)
        if let mtime { try fm.setAttributes([.modificationDate: mtime], ofItemAtPath: url.path) }
    }
    func run(_ job: String, createdAgo: TimeInterval, lastAgo: TimeInterval?, turns: Int?, mode: String = "default", archived: Bool = false) -> [String: Any] {
        var r: [String: Any] = ["sessionId": "local_x", "scheduledTaskId": job, "createdAt": ms(createdAgo), "permissionMode": mode, "isArchived": archived,
                                "prompt": "do the daily job named \(job)"]
        if let lastAgo { r["lastActivityAt"] = ms(lastAgo) }
        if let turns { r["completedTurns"] = turns }
        return r
    }

    check(ScheduledRuns.read(appDir: nil, project: proj, events: [], now: Date()).jobs.isEmpty && ScheduledRuns.read(appDir: nil, project: proj, events: [], now: Date()).unreadable == nil, "scheduled runs: no app folder, no jobs and nothing to say")
    check({ let r = ScheduledRuns.read(appDir: root.appending(path: "none"), project: proj, events: [], now: Date()); return r.jobs.isEmpty && r.unreadable == nil }(), "scheduled runs: no claude-code-sessions folder: no jobs, nil")
    check({ let r = ScheduledRuns.read(appDir: app, project: proj, events: [], now: Date()); return r.jobs.isEmpty && r.unreadable == nil }(), "scheduled runs: a folder with no scheduled-tasks.json: no jobs, nil")

    try write(["scheduledTasks": [task("stuck-job", cwd: proj), task("done-job", cwd: proj, cron: "0 8 * * 1", scheduledAgo: 3 * day), task("other-job", cwd: other), task("off-job", cwd: proj, enabled: false),
                                  task("quiet-job", cwd: URL(fileURLWithPath: proj.path + "/../proj"))]], "scheduled-tasks.json")
    try write(run("stuck-job", createdAgo: 2 * hour, lastAgo: 45 * min, turns: nil, mode: "default"), "local_a1.json", mtime: Date().addingTimeInterval(-45 * min))
    try write(run("stuck-job", createdAgo: 30 * hour, lastAgo: 29 * hour, turns: 4, mode: "auto"), "local_a0.json", mtime: Date().addingTimeInterval(-29 * hour))
    try write(run("done-job", createdAgo: 3 * hour, lastAgo: 2 * hour, turns: 3, mode: "auto"), "local_b1.json", mtime: Date().addingTimeInterval(-2 * hour))
    try write(run("other-job", createdAgo: hour, lastAgo: hour, turns: 0), "local_c1.json", mtime: Date().addingTimeInterval(-hour))
    try write(run("off-job", createdAgo: hour, lastAgo: hour, turns: 0), "local_d1.json", mtime: Date().addingTimeInterval(-hour))
    try write(run("unrelated", createdAgo: hour, lastAgo: hour, turns: 0), "local_e1.json", mtime: Date().addingTimeInterval(-hour))
    let events = [DirectorEvent(at: iso.string(from: Date().addingTimeInterval(-3600)), director: "d", event: "check", task: "job:done-job", detail: "read it")]
    let r = ScheduledRuns.read(appDir: app, project: proj, events: events, now: Date())
    check(r.unreadable == nil, "scheduled runs: readable (\(r.unreadable ?? "ok"))")
    check(Set(r.jobs.map(\.id)) == ["stuck-job", "done-job", "quiet-job"], "scheduled runs: this project's enabled jobs only: another project's and a disabled one are ignored, a cwd that resolves here counts (\(r.jobs.map(\.id)))")
    let stuck = r.jobs.first { $0.id == "stuck-job" }
    check(stuck?.title == "Job stuck-job" && stuck?.latestRun?.completedTurns == 0 && stuck?.latestRun?.mode == "default" && stuck?.latestRun?.archived == false
          && abs((stuck?.latestRun?.lastActivity.timeIntervalSinceNow ?? 0) + 45 * 60) < 5, "scheduled runs: a stuck run is the newest file's, with its mode, no finished turn, and its last activity")
    let done = r.jobs.first { $0.id == "done-job" }
    check(done?.latestRun?.completedTurns == 3 && done?.latestRun?.mode == "auto" && done?.lastCheck != nil && done?.nextDue != nil, "scheduled runs: a finished run, the job's last check from the log, and when it was next due")
    let expectedDue = Cron.next(after: Date().addingTimeInterval(-3 * day), expression: "0 8 * * 1")
    check(done?.nextDue != nil && expectedDue != nil && abs(done!.nextDue!.timeIntervalSince(expectedDue!)) < 1, "scheduled runs: nextDue is the first scheduled time after the last scheduled one")
    let red = DirectorRedLines.evaluate(DirectorFacts(now: Date(), jobs: r.jobs, jobsUnreadable: r.unreadable))
    check(red.contains { $0.duty == .R3 && $0.subject == "stuck-job" && $0.what.contains("in default") } && !red.contains { $0.subject == "done-job" && $0.what.contains("finished") }, "scheduled runs: through the rules, the stuck one is red, and the finished one you checked is not (\(red.map(\.line)))")

    try write(["scheduledTasks": [task("stuck-job", cwd: proj)]], "scheduled-tasks.json")
    try write(run("stuck-job", createdAgo: hour, lastAgo: nil, turns: 1), "local_a2.json", mtime: Date())
    let noActivity = ScheduledRuns.read(appDir: app, project: proj, events: [], now: Date())
    check(noActivity.unreadable == "local_a2.json has no lastActivityAt", "scheduled runs: a matching run with no lastActivityAt makes the result unreadable, naming the file (\(noActivity.unreadable ?? "nil"))")
    try fm.removeItem(at: dir.appending(path: "local_a2.json"))

    try Data("{ this is not json".utf8).write(to: dir.appending(path: "scheduled-tasks.json"))
    let corrupt = ScheduledRuns.read(appDir: app, project: proj, events: [], now: Date())
    check(corrupt.jobs.isEmpty && corrupt.unreadable == "scheduled-tasks.json isn't JSON Duo can read" && !(corrupt.unreadable ?? "").contains(root.path), "scheduled runs: corrupt JSON is unreadable, naming the file's name only (\(corrupt.unreadable ?? "nil"))")
    try write(["somethingElse": []], "scheduled-tasks.json")
    check(ScheduledRuns.read(appDir: app, project: proj, events: [], now: Date()).unreadable == "scheduled-tasks.json has no scheduledTasks list", "scheduled runs: valid JSON with no scheduledTasks list is unreadable too")
    let blind = DirectorRedLines.evaluate(DirectorFacts(now: Date(), jobsUnreadable: corrupt.unreadable))
    check(blind.count == 1 && blind[0].duty == .R3 && blind[0].what.contains("Can't read scheduled runs: scheduled-tasks.json isn't JSON Duo can read."), "scheduled runs: and status says the check is blind, never staying quiet")

    check(ClaudeDesktop.directory(env: [ClaudeDesktop.variable: "/x/app"])?.path == "/x/app" && ClaudeDesktop.directory(env: [ClaudeDesktop.variable: "/x/app", "DUO_ISOLATED": "1"])?.path == "/x/app",
          "the Claude app's folder: DUO_CLAUDE_APP_DIR, even in a test run (how a check points at fixtures)")
    check(ClaudeDesktop.directory(env: ["DUO_ISOLATED": "1"]) == nil && ClaudeDesktop.directory(env: [ClaudeDesktop.variable: "  ", "DUO_ISOLATED": "1"]) == nil
          && ClaudeDesktop.directory(env: ["DUO_SUPPORT_DIR": "/tmp/somewhere-else"]) == nil, "the Claude app's folder: none in a test context, so a scripted run never reads the user's own records")
    check(ClaudeDesktop.directory(env: [:])?.path.hasSuffix("Library/Application Support/Claude") == true, "the Claude app's folder: otherwise Application Support/Claude")
}

// MARK: - The reader, on real folders

@MainActor private func dutyReaderChecks() throws {
    print("director duties: reading the facts")
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appending(path: "dfacts-\(UUID().uuidString.prefix(6))")
    defer { try? fm.removeItem(at: root) }
    let proj = root.appending(path: "p"), cfg = root.appending(path: "cfg"), tree = proj.appending(path: ".claude/worktrees/wt1"), app = root.appending(path: "app")
    for d in [proj.appending(path: "tasks"), cfg.appending(path: "sessions"), cfg.appending(path: "projects/x"), tree.appending(path: "tasks"), proj.appending(path: ".git/worktrees/wt1")] { try fm.createDirectory(at: d, withIntermediateDirectories: true) }
    try Data("\(tree.path)/.git\n".utf8).write(to: proj.appending(path: ".git/worktrees/wt1/gitdir"))
    let n = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970))
    let stamp = DateFormatter(); stamp.locale = Locale(identifier: "en_US_POSIX"); stamp.dateFormat = "yyyy-MM-dd HH:mm"
    func note(_ file: String, _ front: String, progress: [String] = [], in folder: URL? = nil) throws {
        let body = "# \(file)\n\n## Request\n\nx\n\n## Progress\n\n" + progress.map { "- \($0)" }.joined(separator: "\n") + "\n"
        try Data("---\n\(front)---\n\(body)".utf8).write(to: (folder ?? proj).appending(path: "tasks/\(file).md"))
    }
    func old(_ file: String, _ ago: TimeInterval, in folder: URL? = nil) throws {
        try fm.setAttributes([.modificationDate: n.addingTimeInterval(-ago)], ofItemAtPath: (folder ?? proj).appending(path: "tasks/\(file).md").path)
    }
    let by = CheckBy.format(n.addingTimeInterval(-3 * hour))
    try note("running", "title: Running\nstatus: in-progress\ndirected_by: \"d\"\ncheck_by: \(CheckBy.format(n.addingTimeInterval(day)))\n", progress: ["\(stamp.string(from: n.addingTimeInterval(-2 * hour))) started"])
    try note("stopped", "title: Stopped\nstatus: in-progress\ndirected_by: \"d\"\n", progress: ["\(stamp.string(from: n.addingTimeInterval(-6 * hour))) started"])
    try note("clean", "title: Clean\nstatus: in-progress\ndirected_by: \"d\"\ncheck_by: \(CheckBy.format(n.addingTimeInterval(day)))\n", progress: ["\(stamp.string(from: n.addingTimeInterval(-6 * hour))) started", "\(stamp.string(from: n.addingTimeInterval(-hour))) Checked: read it"])
    try note("late", "title: Late\nstatus: waiting\ndirected_by: \"d\"\ncheck_by: \(by)\n")
    try note("_record", "title: Record\nstatus: in-progress\ndirected_by: \"d\"\n")
    try note("theirs", "title: Theirs\nstatus: in-progress\n")
    try note("dup", "title: Dup\nstatus: in-progress\ndirected_by: \"d\"\ncheck_by: \(CheckBy.format(n.addingTimeInterval(day)))\n")
    try note("dup", "title: Dup in a tree\nstatus: in-progress\ndirected_by: \"d\"\n", in: tree)
    try note("treeonly", "title: Tree only\nstatus: in-progress\ndirected_by: \"d\"\n", in: tree)
    try note("treedone", "title: Tree done\nstatus: done\ndirected_by: \"d\"\n", in: tree)
    try note("_treerecord", "title: Tree record\nstatus: in-progress\ndirected_by: \"d\"\n", in: tree)
    try note("treeother", "title: Tree other\nstatus: in-progress\ndirected_by: \"someone\"\n", in: tree)
    for f in ["stopped", "treeonly"] { try old(f, 30 * day, in: f == "treeonly" ? tree : nil) }
    // Workers: one idle that stopped three hours ago (its transcript's last write), one working just now.
    var reg = DirectorRegistry()
    reg.adopt(name: "d", sessionId: "me-1", at: "t")
    reg.setWorker(task: "tasks/stopped.md", session: "s-stop", at: iso.string(from: n.addingTimeInterval(-6 * hour)), adopted: false)
    reg.setWorker(task: "tasks/running.md", session: "s-run", at: iso.string(from: n.addingTimeInterval(-2 * hour)), adopted: false)
    reg.setWorker(task: "tasks/clean.md", session: "s-clean", at: iso.string(from: n.addingTimeInterval(-6 * hour)), adopted: false)
    reg.setWorker(task: "tasks/late.md", session: "", at: iso.string(from: n.addingTimeInterval(-10 * min)), adopted: false, name: "never-up-abc123")
    for (sid, ago) in [("s-stop", 3 * hour), ("s-run", 30), ("s-clean", 3 * hour)] {
        let url = cfg.appending(path: "projects/x/\(sid).jsonl")
        try Data("{\"type\":\"assistant\",\"timestamp\":\"2026-01-01T00:00:00.000Z\"}\n".utf8).write(to: url)
        try fm.setAttributes([.modificationDate: n.addingTimeInterval(-ago)], ofItemAtPath: url.path)
    }
    for (file, sid, status) in [("run", "s-run", "busy"), ("clean", "s-clean", "idle")] {
        try JSONSerialization.data(withJSONObject: ["pid": Int(getpid()), "sessionId": sid, "cwd": proj.path, "status": status]).write(to: cfg.appending(path: "sessions/\(file).json"))
    }
    // The beacons: both alive in this process. s-stop has none: stopped.
    let beacons = DirectorOffline.beacons(claudeDir: cfg)
    check(Set(beacons.map(\.sessionId)) == ["s-run", "s-clean"], "reader: the beacons of the workers that run")

    // The director's own transcript: spoke 50 minutes ago, this turn began 40 minutes ago.
    let me = "me-1"
    func line(_ obj: [String: Any]) -> String { String(decoding: try! JSONSerialization.data(withJSONObject: obj), as: UTF8.self) }
    let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    func t(_ ago: TimeInterval) -> String { f.string(from: n.addingTimeInterval(-ago)) }
    let transcript = [
        line(["type": "user", "timestamp": t(3 * hour), "message": ["role": "user", "content": "start"]]),
        line(["type": "assistant", "timestamp": t(2 * hour), "message": ["role": "assistant", "content": [["type": "text", "text": "an old answer"]]]]),
        line(["type": "assistant", "timestamp": t(50 * 60), "message": ["role": "assistant", "content": [["type": "text", "text": "Here is where we are."]]]]),
        line(["type": "assistant", "timestamp": t(45 * 60), "message": ["role": "assistant", "content": [["type": "tool_use", "name": "Bash", "input": [:]]]]]),
        line(["type": "assistant", "timestamp": t(44 * 60), "isSidechain": true, "message": ["role": "assistant", "content": [["type": "text", "text": "a subagent talking"]]]]),
        line(["type": "assistant", "timestamp": t(43 * 60), "message": ["role": "assistant", "content": [["type": "text", "text": "   "]]]]),
        line(["type": "user", "timestamp": t(42 * 60), "isMeta": true, "message": ["role": "user", "content": "Base directory for this skill"]]),
        line(["type": "user", "timestamp": t(41 * 60), "message": ["role": "user", "content": [["type": "tool_result", "content": "ok"]]]]),
        line(["type": "user", "timestamp": t(40 * 60), "origin": ["kind": "task-notification"], "message": ["role": "user", "content": "<task-notification>w done</task-notification>"]]),
    ].joined(separator: "\n") + "\n"
    let mine = cfg.appending(path: "projects/x/\(me).jsonl")
    try Data(transcript.utf8).write(to: mine)
    let tail = DirectorFactsReader.transcriptTail(mine)
    check(tail.map { abs($0.lastToUser!.timeIntervalSince(n) + 50 * 60) < 1 } == true, "transcript: lastToUser is the last assistant entry with text (not a tool call, a blank, or a subagent's)")
    check(tail.map { abs($0.turnStartedAt!.timeIntervalSince(n) + 40 * 60) < 1 } == true, "transcript: the turn began at the last user entry that isn't meta or a tool result (a task notification starts one)")
    try Data((transcript + line(["type": "assistant", "timestamp": t(10 * 60), "message": ["role": "assistant", "content": [["type": "tool_use", "name": "AskUserQuestion", "input": [:]]]]]) + "\n").utf8).write(to: mine)
    check(DirectorFactsReader.transcriptTail(mine).map { abs($0.lastToUser!.timeIntervalSince(n) + 10 * 60) < 1 } == true, "transcript: an AskUserQuestion call is a word to the user (and so are PushNotification and SendUserFile)")
    check(DirectorFactsReader.transcriptTail(mine, tailBytes: 600).map { $0.lastToUser != nil } == true && DirectorFactsReader.transcriptTail(root.appending(path: "none.jsonl")) == nil, "transcript: a tail starts at a whole line; a missing file is nil")
    try Data(transcript.utf8).write(to: mine)

    let direct = DirectorOffline.tasks(project: proj, director: "d", reg: reg, beacons: beacons, claudeDir: cfg, now: n).map(\.path)
    check(!direct.contains("tasks/_record.md") && direct.contains("tasks/running.md") && direct.contains("tasks/late.md"), "DirectorOffline.tasks skips a note whose file name starts with _ (a record, not a task)")

    var caps = ClientCaps(); caps.sessionId = me; caps.permissionMode = "auto"; caps.name = "d"
    let facts = DirectorFactsReader.facts(project: proj, director: "d", reg: reg, beacons: beacons, caps: caps, skillNote: nil, duo: nil, claudeDir: cfg, appDir: app, now: n)
    func fact(_ file: String) -> DNote? { facts.notes.first { $0.path.hasSuffix("/\(file).md") || $0.path == "tasks/\(file).md" } }
    check(facts.notes.contains { $0.path == "tasks/running.md" } && fact("_record") == nil && fact("theirs") == nil && !facts.notes.contains { $0.path.contains("_treerecord") }, "reader: this director's notes; a `_` note, one with no directed_by and one of another director's aren't")
    check(facts.notes.filter({ $0.inWorkTree }).map(\.path) == [".claude/worktrees/wt1/tasks/treeonly.md"], "reader: a note that exists only in a work tree is added, path relative to the project; one with a main-checkout twin, a done one and another director's aren't (\(facts.notes.filter(\.inWorkTree).map(\.path)))")
    let tn = facts.notes.first { $0.inWorkTree }
    check(tn?.hasWorkerRecord == false && tn?.workerState == "no worker" && tn?.status == "in-progress", "reader: and it has no worker facts")
    let stop = fact("stopped")
    check(stop?.workerState == "stopped" && stop?.hasWorkerRecord == true && abs((stop?.workerLastActivity?.timeIntervalSince(n) ?? 0) + 3 * 3600) < 2 && stop?.lastChecked == nil && stop?.lastProgress != nil && stop?.checkBy == nil,
          "reader: a worker with no beacon is stopped, its report time is its transcript's last write, and the note's dates come from ## Progress")
    check(fact("clean")?.lastChecked != nil && fact("clean")?.checkBy != nil && fact("late")?.checkBy.map { $0 < n } == true, "reader: Checked lines and check_by are read from the note")
    check(fact("late")?.pendingExpired == false && fact("late")?.workerName == "never-up-abc123" && fact("late")?.hasWorkerRecord == true, "reader: a background start inside its half hour hasn't expired")
    check(facts.me.permissionMode == "auto" && facts.me.transcriptRead && !facts.me.cliLoggedOut && facts.me.lastToUser != nil && facts.me.turnStartedAt != nil, "reader: the director's own mode and transcript")
    let red = DirectorRedLines.evaluate(facts)
    check(red.contains { $0.duty == .R1 && $0.subject == "tasks/stopped.md" } && !red.contains { $0.subject == "tasks/clean.md" } && !red.contains { $0.subject == "tasks/running.md" },
          "reader: a stopped worker with no Checked line is red; one checked after its worker stopped, and a running one, are not (\(red.map(\.line)))")
    check(red.contains { $0.duty == .R7 && $0.what == "You've gone 40 min without a word to the user." }, "reader: R7 from the transcript: 40 minutes since the turn began")
    check(red.contains { $0.duty == .R6 && $0.what.contains(".claude/worktrees/wt1/tasks/treeonly.md") && $0.what.contains("1 of them") == false && $0.what.contains("It exists only in a work tree.") }, "reader: R6 names the work-tree-only note and says so")
    var reg2 = reg
    reg2.setWorker(task: "tasks/late.md", session: "", at: iso.string(from: n.addingTimeInterval(-3 * hour)), adopted: false, name: "never-up-abc123")
    let expired = DirectorFactsReader.facts(project: proj, director: "d", reg: reg2, beacons: beacons, caps: caps, skillNote: "a skill note", duo: .init(running: true, reachable: false), claudeDir: cfg, appDir: nil, now: n)
    check(expired.notes.first { $0.path == "tasks/late.md" }?.pendingExpired == true && expired.me.skillNote == "a skill note" && expired.me.duo?.running == true, "reader: a background start past 30 minutes with no session has expired; the skill note and Duo's health ride along")
    // Report applies to the right callers.
    check(DirectorFactsReader.applies(role: .current, callerName: "d") && DirectorFactsReader.applies(role: DirectorRegistry.Role.none, callerName: nil)
          && DirectorFactsReader.applies(role: .other(.init(name: "d", sessionId: "x", since: "t")), callerName: "d")
          && !DirectorFactsReader.applies(role: .other(.init(name: "d", sessionId: "x", since: "t")), callerName: "e")
          && !DirectorFactsReader.applies(role: .other(.init(name: "d", sessionId: "x", since: "t")), callerName: nil) && !DirectorFactsReader.applies(role: .replaced(by: nil), callerName: "d"),
          "the report applies to the current director, a session nobody directs yet, and the director resumed under a new id; not a replaced one, nor another director's project")

    // Full path with the Claude app's records: a stuck run for this project reads through to a red line.
    let dir = app.appending(path: "claude-code-sessions/a/b")
    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    let ms = { (ago: TimeInterval) in Int(n.addingTimeInterval(-ago).timeIntervalSince1970 * 1000) }
    try JSONSerialization.data(withJSONObject: ["scheduledTasks": [["id": "nightly", "displayName": "Nightly", "cronExpression": "0 * * * *", "enabled": true, "cwd": proj.path, "createdAt": ms(9 * day)]]]).write(to: dir.appending(path: "scheduled-tasks.json"))
    try JSONSerialization.data(withJSONObject: ["scheduledTaskId": "nightly", "createdAt": ms(2 * hour), "lastActivityAt": ms(hour), "permissionMode": "default", "completedTurns": 0, "isArchived": false]).write(to: dir.appending(path: "local_1.json"))
    let withJobs = DirectorFactsReader.report(project: proj, director: "d", reg: reg, beacons: beacons, caps: caps, skillNote: nil, duo: nil, claudeDir: cfg, appDir: app, now: n)
    check(withJobs.contains { $0.duty == .R3 && $0.subject == "nightly" && $0.what.contains("in default") }, "reader: the report reads the Claude app's records and a stuck run is red (\(withJobs.filter { $0.duty == .R3 }.map(\.line)))")

    // Duo's own health.
    let ps = """
      0.4 /Applications/Duo.app/Contents/MacOS/Duo
    130.2 /Users/x/Applications/Duo.app/Contents/MacOS/Duo
     55.0 /Users/x/repos/duo-v2/build/Duo.app/Contents/MacOS/Duo
     44.0 /Users/x/repos/duo-v2/.claude/worktrees/a/build/Duo.app/Contents/MacOS/Duo
     12.0 /Applications/Other.app/Contents/MacOS/Other
    abc /Applications/Duo.app/Contents/MacOS/Duo
    """
    let found = DuoHealthReader.duoProcesses(ps)
    check(found.count == 2 && found.map { $0.cpu }.max() == 130.2, "Duo's health: the installed Duo.app's processes from ps, never a build or a work tree's")
    check(DuoHealthReader.unreachable(env: ["HOME": "/x/scratch"]) == nil && ClaudeDesktop.directory(env: ["HOME": "/x/scratch"]) == nil,
          "a scratch home (the skill's evals): neither Duo's health nor the Claude app's records are read")
    check(DuoHealthReader.unreachable(env: ["DUO_ISOLATED": "1"]) == nil && DuoHealthReader.reachable(env: ["DUO_ISOLATED": "1"]).lastUpdateCheck == nil
          && DuoHealthReader.reachable(env: ["DUO_ISOLATED": "1"]).running && DuoHealthReader.reachable(env: ["DUO_ISOLATED": "1"]).cpu == nil, "Duo's health: nothing is asked about the user's Duo in a test context")
}

// MARK: - The register can't rot

@MainActor private func dutyRegisterChecks() throws {
    print("director duties: the register can't rot")
    let skill = DirectorSkill.text()
    let evals = repoRoot().appending(path: "skills/duo-director/evals")
    let cases = ((try? FileManager.default.contentsOfDirectory(atPath: evals.path)) ?? []).sorted().compactMap { name -> (String, Set<String>)? in
        guard let text = try? String(contentsOf: evals.appending(path: "\(name)/case.yaml"), encoding: .utf8),
              let tags = text.split(separator: "\n").first(where: { $0.hasPrefix("tags:") }) else { return nil }
        let words = tags.dropFirst(5).split(whereSeparator: { "[], \t".contains($0) }).map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\"'")) }
        return (name, Set(words))
    }
    check(!cases.isEmpty, "the evals are found (skills/duo-director/evals/*/case.yaml: \(cases.count))")
    for duty in DirectorDuty.allCases {
        check(skill.contains("| **\(duty.rawValue) "), "the skill's register has a row for \(duty.rawValue) (`| **\(duty.rawValue) `)")
        check(cases.contains { $0.1.contains("duty-\(duty.rawValue)") }, "some eval is tagged duty-\(duty.rawValue)")
    }
}

// MARK: - The verbs, end to end (called from directorEndToEnd, which owns the model and its helpers)

/// `director check`, `director start --next`, `_` notes and status's red lines, through the control plane.
/// `run` is directorEndToEnd's helper; `D` is the project's director session, `proj` its folder.
@MainActor func directorCheckVerbChecks(proj: URL, director: String, session D: String, other D2: String,
                                        run: (_ verb: String, _ args: [String], _ session: String, _ name: String?) -> ControlResponse) throws {
    print("director duties: the verbs end to end (check, start --next, status)")
    let fm = FileManager.default
    func read(_ path: String) -> String { (try? String(contentsOf: proj.appending(path: path), encoding: .utf8)) ?? "" }
    func checkBy(_ path: String) -> Date? { CheckBy.parse(Director.frontmatter("check_by", in: read(path))) }
    func near(_ d: Date?, _ ahead: TimeInterval) -> Bool { d.map { abs($0.timeIntervalSinceNow - ahead) < 120 } ?? false }
    func events() -> [DirectorEvent] { DirectorLog.read(project: proj) }
    func go(_ verb: String, _ args: [String], as s: String? = nil, name: String? = nil) -> ControlResponse { run(verb, args, s ?? D, name ?? director) }

    var r = go("director start", ["--title", "Evidence task", "--request", "r", "--no-worker"])
    check(r.ok && near(checkBy("tasks/evidence-task.md"), 2 * 3600) && r.output.contains("check_by is "), "start --no-worker: check_by is two hours on, and the output says so (\(r.output.suffix(90)))")
    r = go("director start", ["--title", "Soon task", "--request", "r", "--no-worker", "--next", "30m"])
    check(r.ok && near(checkBy("tasks/soon-task.md"), 1800), "start --next 30m: check_by is that")
    r = go("director start", ["--title", "No look task", "--request", "r", "--no-worker", "--next", "none"])
    check(r.ok && !read("tasks/no-look-task.md").contains("check_by") && r.output.contains("No check_by set"), "start --next none: no check_by")
    r = go("director start", ["--title", "Suggested task", "--request", "r", "--suggest"])
    check(r.ok && !read("tasks/suggested-task.md").contains("check_by"), "start --suggest: no check_by")
    r = go("director start", ["--title", "Bad next task", "--request", "r", "--no-worker", "--next", "soon"])
    check(!r.ok && r.output.contains("30m") && !fm.fileExists(atPath: proj.appending(path: "tasks/bad-next-task.md").path), "start --next soon: refused, naming the forms, before anything is written")
    r = go("director start", ["--title", "Background task", "--request", "r", "--background", "--next", "3d"])
    check(r.ok && near(checkBy("tasks/background-task.md"), 3 * 86400) && r.output.contains("check_by is "), "start of a background worker: check_by is --next")

    // check: the Progress line, check_by, the log.
    r = go("director check", ["tasks/evidence-task.md", "read the output, tests pass"])
    let note = read("tasks/evidence-task.md")
    check(r.ok && r.output.hasPrefix("Checked tasks/evidence-task.md. Next look by ") && note.contains(" Checked: read the output, tests pass\n") && near(checkBy("tasks/evidence-task.md"), 86400),
          "check: a Checked: line in Progress, check_by a day on, and the output says when (\(r.output))")
    check(DirectorProgress.parse(note).lastChecked.map { abs($0.timeIntervalSinceNow) < 120 } == true && !note.contains("check_by: \""), "check: the line reads back as a check, and check_by is written unquoted")
    let logged = events().last { $0.event == "check" && $0.task == "tasks/evidence-task.md" }
    check(logged?.detail == "read the output, tests pass" && logged?.routine == nil && logged?.director == director, "check: logged as a check event with its task and evidence")
    r = go("director check", ["tasks/evidence-task.md", "again, with a plan", "--next", "2h", "--routine"])
    check(r.ok && read("tasks/evidence-task.md").contains(" Checked (routine): again, with a plan") && near(checkBy("tasks/evidence-task.md"), 7200)
          && events().last { $0.event == "check" }?.routine == true, "check --routine --next 2h: Checked (routine): line, check_by in two hours, logged routine")
    r = go("director check", ["tasks/evidence-task.md", "all done here", "--next", "none"])
    check(r.ok && !read("tasks/evidence-task.md").contains("check_by:") && r.output.contains("No next look set."), "check --next none: the key is removed")
    check(read("tasks/evidence-task.md").contains("Evidence task") && read("tasks/evidence-task.md").contains("## Request\n\nr\n"), "check: nothing else in the note moves")
    try Data(read("tasks/evidence-task.md").replacingOccurrences(of: "status: in-progress", with: "status: done").utf8).write(to: proj.appending(path: "tasks/evidence-task.md"))
    _ = go("director check", ["tasks/evidence-task.md", "next", "--next", "1d"])
    r = go("director check", ["tasks/evidence-task.md", "closing look"])
    check(r.ok && checkBy("tasks/evidence-task.md") == nil && !read("tasks/evidence-task.md").contains("check_by:"), "check on a done task: check_by is cleared, not set a day on")

    // Refusals.
    let before = read("tasks/soon-task.md")
    r = go("director check", ["tasks/soon-task.md"])
    check(!r.ok && r.output.contains(DirectorCheck.emptyRefusal) && read("tasks/soon-task.md") == before, "check: no evidence is refused: \"a check needs what you verified and the evidence\"")
    r = go("director check", ["tasks/soon-task.md", "   "])
    check(!r.ok && r.output.contains(DirectorCheck.emptyRefusal), "check: blank evidence is refused")
    r = go("director check", ["tasks/soon-task.md", "looked", "--next", "whenever"])
    check(!r.ok && r.output.contains("30m") && r.output.contains("none") && read("tasks/soon-task.md") == before, "check: a bad --next is refused, naming the accepted forms, and writes nothing")
    r = go("director check", ["tasks/soon-task.md", "looked"], as: D2, name: "worker-z")
    check(!r.ok && r.output.contains("You're not") && read("tasks/soon-task.md") == before, "check: refused unless the caller is the project's director, in send's words")
    try Data("---\ntitle: Others\nstatus: in-progress\ndirected_by: \"someone-else\"\n---\n# Others\n".utf8).write(to: proj.appending(path: "tasks/others.md"))
    let others = read("tasks/others.md")
    r = go("director check", ["tasks/others.md", "looked"])
    check(!r.ok && r.output.contains("directed by someone-else") && read("tasks/others.md") == others && events().contains { $0.event == "refused" && $0.task == "tasks/others.md" }, "check: another director's task is refused, and the refusal is logged")
    let theirs = read("tasks/theirs.md")
    r = go("director check", ["tasks/theirs.md", "looked"])
    check(!r.ok && r.output.contains("directed_by") && read("tasks/theirs.md") == theirs, "check: the user's own task (no directed_by:) is refused")
    r = go("director check", ["tasks/no-such-task.md", "looked"])
    check(!r.ok && r.output.contains("no task"), "check: a task that isn't there")

    // A job: only the log.
    let notes = (try? fm.contentsOfDirectory(atPath: proj.appending(path: "tasks").path).sorted().map { ($0, read("tasks/\($0)")) }) ?? []
    r = go("director check", ["job:nightly", "read the run: nothing new", "--routine"])
    let after = (try? fm.contentsOfDirectory(atPath: proj.appending(path: "tasks").path).sorted().map { ($0, read("tasks/\($0)")) }) ?? []
    let job = events().last { $0.event == "check" && $0.task == "job:nightly" }
    check(r.ok && r.output.contains("Checked job:nightly. No next look set.") && job?.routine == true && job?.detail == "read the run: nothing new" && notes.map(\.0) == after.map(\.0) && notes.map(\.1) == after.map(\.1),
          "check job:<id>: only the log (routine, with its evidence); no note changes (\(r.output))")
    r = go("director check", ["job:nightly"])
    check(!r.ok && r.output.contains(DirectorCheck.emptyRefusal), "check job:<id> with no evidence is refused too")

    // `_` notes are records, not tasks.
    try Data("---\ntitle: Reservations\nstatus: in-progress\ndirected_by: \"\(director)\"\n---\n# Reservations\n".utf8).write(to: proj.appending(path: "tasks/_record-reservations.md"))
    let status = go("director status", ["--json", "--all"])
    let json = (try? JSONSerialization.jsonObject(with: Data(status.output.utf8))) as? [String: Any]
    let paths = ((json?["workers"] as? [[String: Any]]) ?? []).compactMap { $0["task"] as? String }
    check(status.ok && !paths.contains("tasks/_record-reservations.md") && paths.contains("tasks/evidence-task.md"), "status: a note whose file name starts with _ isn't a task")

    // Status: red lines first, shrunk list, JSON, and the log.
    let red = (json?["redLines"] as? [[String: Any]]) ?? []
    check(status.ok && json?["redLines"] != nil && red.allSatisfy { ($0["duty"] as? String)?.hasPrefix("R") == true && $0["subject"] is String && $0["what"] is String && $0["todo"] is String },
          "status --json: redLines is an array of duty, subject, what and todo (\(red.count))")
    let polled = go("director status", ["--json", "--no-red-lines"])
    check(((try? JSONSerialization.jsonObject(with: Data(polled.output.utf8))) as? [String: Any])?["redLines"] == nil, "status --no-red-lines (what `watch` polls): computes none")
    let statusEventsBefore = events().filter { $0.event == "status" }.count
    let text = go("director status", [])
    check(text.ok && (text.output.hasPrefix("Red lines (") || text.output.hasPrefix("Red lines: none.")) && text.output.contains("Project: "), "status: the red lines are the first lines")
    let statusEvents = events().filter { $0.event == "status" }
    check(statusEvents.count == statusEventsBefore + 1 && statusEvents.last?.detail?.hasSuffix(" red lines") == true, "status: a text run is logged (\(statusEvents.last?.detail ?? "nothing")); a JSON run isn't")
    let short = go("director status", [])
    check(short.output.contains("other task") && short.output.contains("(--all lists them)"), "status: the worker list is shortened and says --all lists the rest")
    let full = go("director status", ["--all"])
    check(full.output.contains("tasks/evidence-task.md") && full.output.contains("tasks/soon-task.md") && !full.output.contains("other tasks (--all"), "status --all: every task is listed")
    check((full.output.range(of: "Red lines")?.lowerBound).map { r in full.output.range(of: "Project: ").map { r < $0.lowerBound } ?? false } == true, "status: red lines come before the project line")
    let replaced = go("director status", [], as: "no-such-session", name: "director-other")
    check(replaced.ok && !replaced.output.hasPrefix("Red lines"), "status: a session working in another director's project gets no red lines")
}
