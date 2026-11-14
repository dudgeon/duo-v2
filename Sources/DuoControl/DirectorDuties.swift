import Foundation

// The director's responsibility register as code (DL-319, docs/research/director-learning-loop.md §3,
// §4): nine duties a director owes without being asked, and for each the "red line" `duo2 director
// status` prints when it's being neglected right now. This file is pure: facts in, lines out, no file
// access, so `duo2` (Duo closed or open), the app and the checks share one evaluation. Reading the
// facts is `DirectorFactsReader`; the scheduled runs come from `ScheduledRuns`.

/// A duty a director owes without being asked (R1 to R9 in the skill's register).
public enum DirectorDuty: String, CaseIterable, Sendable {
    case R1, R2, R3, R4, R5, R6, R7, R8, R9

    public var title: String {
        switch self {
        case .R1: "Watch workers to a conclusion"
        case .R2: "Follow up by check_by"
        case .R3: "Watch recurring jobs"
        case .R4: "Deliver findings"
        case .R5: "Verify before done"
        case .R6: "Keep the record current"
        case .R7: "Check in on a clock"
        case .R8: "Keep your environment healthy"
        case .R9: "Learn from failures"
        }
    }
}

/// One neglected duty: what it is about, what's wrong, what to do.
public struct RedLine: Equatable, Sendable {
    public var duty: DirectorDuty
    /// The note path, `job:<id>`, or the thing itself (`your mode`, `the record`, `review`…).
    public var subject: String
    public var what: String
    public var todo: String

    public init(duty: DirectorDuty, subject: String, what: String, todo: String) {
        self.duty = duty; self.subject = subject; self.what = what; self.todo = todo
    }

    /// `RED <duty> <subject>: <what> <todo>`
    public var line: String { "RED \(duty.rawValue) \(subject): \(what)" + (todo.isEmpty ? "" : " " + todo) }
}

/// Everything the evaluation looks at, read once by `DirectorFactsReader` (or built by hand in a check).
public struct DirectorFacts: Sendable {
    public var now: Date
    public var notes: [Note]
    public var jobs: [Job]
    /// Why the scheduled runs couldn't be read, if they couldn't (the check is then blind, and says so).
    public var jobsUnreadable: String?
    public var me: Me
    public var events: [DirectorEvent]

    public init(now: Date, notes: [Note] = [], jobs: [Job] = [], jobsUnreadable: String? = nil, me: Me = Me(), events: [DirectorEvent] = []) {
        self.now = now; self.notes = notes; self.jobs = jobs; self.jobsUnreadable = jobsUnreadable; self.me = me; self.events = events
    }

    /// A task note this director directs, with its worker as the registry, the beacons and the
    /// transcript show it.
    public struct Note: Sendable, Equatable {
        public var path: String
        public var title: String
        public var status: String?
        public var modified: Date
        public var checkBy: Date?
        /// The latest date on any dated line of `## Progress`.
        public var lastProgress: Date?
        /// The latest date on a `Checked:` line (rounded up: a day counts to its end, a minute to its end).
        public var lastChecked: Date?
        /// The note exists only in a git work tree, not in the main checkout.
        public var inWorkTree: Bool
        /// `DirectorOffline.Task.state`'s words: starting, working, idle, needs-you, stopped, no worker.
        public var workerState: String
        public var hasWorkerRecord: Bool
        /// A background start recorded and never seen within `Director.pendingLasts`.
        public var pendingExpired: Bool
        public var workerName: String?
        public var question: String?
        public var workerSince: Date?
        /// The worker's transcript's modification date.
        public var workerLastActivity: Date?
        public var userTyping: Bool

        public init(path: String, title: String = "", status: String? = "in-progress", modified: Date, checkBy: Date? = nil, lastProgress: Date? = nil,
                    lastChecked: Date? = nil, inWorkTree: Bool = false, workerState: String = "no worker", hasWorkerRecord: Bool = false,
                    pendingExpired: Bool = false, workerName: String? = nil, question: String? = nil, workerSince: Date? = nil,
                    workerLastActivity: Date? = nil, userTyping: Bool = false) {
            self.path = path; self.title = title.isEmpty ? path : title; self.status = status; self.modified = modified; self.checkBy = checkBy
            self.lastProgress = lastProgress; self.lastChecked = lastChecked; self.inWorkTree = inWorkTree; self.workerState = workerState
            self.hasWorkerRecord = hasWorkerRecord; self.pendingExpired = pendingExpired; self.workerName = workerName; self.question = question
            self.workerSince = workerSince; self.workerLastActivity = workerLastActivity; self.userTyping = userTyping
        }
    }

    /// A scheduled job of the Claude desktop app, for this project.
    public struct Job: Sendable, Equatable {
        public var id: String
        public var title: String
        /// The first scheduled time after its last scheduled one.
        public var nextDue: Date?
        public var latestRun: Run?
        /// The latest `check` event with task `job:<id>`.
        public var lastCheck: Date?

        public init(id: String, title: String = "", nextDue: Date? = nil, latestRun: Run? = nil, lastCheck: Date? = nil) {
            self.id = id; self.title = title.isEmpty ? id : title; self.nextDue = nextDue; self.latestRun = latestRun; self.lastCheck = lastCheck
        }
    }

    public struct Run: Sendable, Equatable {
        public var startedAt: Date
        public var lastActivity: Date
        public var mode: String?
        public var completedTurns: Int
        public var archived: Bool

        public init(startedAt: Date, lastActivity: Date, mode: String? = nil, completedTurns: Int = 0, archived: Bool = false) {
            self.startedAt = startedAt; self.lastActivity = lastActivity; self.mode = mode; self.completedTurns = completedTurns; self.archived = archived
        }
    }

    /// The calling director: its own session and environment.
    public struct Me: Sendable, Equatable {
        public var permissionMode: String?
        /// Its own transcript was found and read; R4 and R7 are blind without it.
        public var transcriptRead: Bool
        /// When it last said something to the user (text, or AskUserQuestion, PushNotification, SendUserFile).
        public var lastToUser: Date?
        /// When its current turn began (the last user entry that isn't meta or a tool result).
        public var turnStartedAt: Date?
        public var skillNote: String?
        public var cliLoggedOut: Bool
        public var duo: DuoHealth?

        public init(permissionMode: String? = nil, transcriptRead: Bool = false, lastToUser: Date? = nil, turnStartedAt: Date? = nil,
                    skillNote: String? = nil, cliLoggedOut: Bool = false, duo: DuoHealth? = nil) {
            self.permissionMode = permissionMode; self.transcriptRead = transcriptRead; self.lastToUser = lastToUser
            self.turnStartedAt = turnStartedAt; self.skillNote = skillNote; self.cliLoggedOut = cliLoggedOut; self.duo = duo
        }
    }

    public struct DuoHealth: Sendable, Equatable {
        public var running: Bool
        public var reachable: Bool
        public var cpu: Double?
        public var lastUpdateCheck: Date?

        public init(running: Bool, reachable: Bool, cpu: Double? = nil, lastUpdateCheck: Date? = nil) {
            self.running = running; self.reachable = reachable; self.cpu = cpu; self.lastUpdateCheck = lastUpdateCheck
        }
    }
}

/// The red lines (DL-319): one function from facts to lines, and the words status wraps them in.
public enum DirectorRedLines {
    /// The thresholds. Guesses until they've run for a while (the design doc says so).
    public enum Limits {
        /// A worker "working" with no transcript write for this long (R1).
        public static let workerSilent: TimeInterval = 2 * 3600
        /// A scheduled run with no finished turn and no activity for this long is stuck (R3).
        public static let runStuck: TimeInterval = 30 * 60
        /// Activity this recent means a run is still going (R3).
        public static let runBusy: TimeInterval = 5 * 60
        /// A scheduled time that passed this long ago with no run started (R3).
        public static let jobMissedBy: TimeInterval = 3600
        /// A finished run older than this is no longer chased (R3).
        public static let runFinishedWindow: TimeInterval = 7 * 86400
        /// Your own turn this long with no word to the user (R7).
        public static let turnSilent: TimeInterval = 30 * 60
        /// A live note with nothing for this long is stale (R2, R6).
        public static let staleNote: TimeInterval = 7 * 86400
        /// A done note is checked for this long after it last changed (R5).
        public static let doneWindow: TimeInterval = 7 * 86400
        /// A live note this new hasn't had its worker started yet (R2).
        public static let newNote: TimeInterval = 30 * 60
        /// This many sends to one task inside `repeatWindow`, with no check after the first, is a signal (R9).
        public static let repeatSends = 3
        public static let repeatWindow: TimeInterval = 24 * 3600
        /// Duo above this much CPU (R8), and an update check older than this (R8).
        public static let duoCPU = 100.0
        public static let updateCheckAge: TimeInterval = 48 * 3600
        /// A check the user hasn't heard about is chased for this long (R4).
        public static let findingWindow: TimeInterval = 7 * 86400
        /// How many paths a collapsed line names.
        public static let listShown = 5
    }

    /// The statuses Duo knows (anything else is R6's "status word Duo doesn't know").
    static let knownStatuses: Set<String> = ["open", "in-progress", "waiting", "review", "done", "dropped", "suggested"]

    /// The order status prints them in, most urgent first.
    public static let order: [DirectorDuty] = [.R8, .R1, .R3, .R2, .R9, .R4, .R7, .R5, .R6]

    // MARK: Words

    /// `47 min`, `3 h`, `2 d`.
    public static func span(_ seconds: TimeInterval) -> String {
        let m = max(1, Int(seconds / 60))
        if m < 120 { return "\(m) min" }
        let h = m / 60
        return h < 48 ? "\(h) h" : "\(h / 24) d"
    }

    /// `07:15` for today, else `2026-11-08 07:15` (local time).
    public static func clock(_ d: Date, now: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = Calendar.current.isDate(d, inSameDayAs: now) ? "HH:mm" : "yyyy-MM-dd HH:mm"
        return f.string(from: d)
    }

    static func eventDate(_ e: DirectorEvent) -> Date? { DirectorTranscript.parseDate(e.at) }

    static func atReview(_ n: DirectorFacts.Note) -> Bool { (n.status ?? "").trimmingCharacters(in: .whitespaces).lowercased() == "review" }

    // MARK: Evaluation

    /// The red lines for `f`, most urgent first. `all` lifts the cap on how many paths a collapsed line
    /// names (`status --all`).
    public static func evaluate(_ f: DirectorFacts, all: Bool = false) -> [RedLine] {
        var out: [DirectorDuty: [RedLine]] = [:]
        let now = f.now
        let shown = all ? Int.max : Limits.listShown
        func add(_ d: DirectorDuty, _ subject: String, _ what: String, _ todo: String = "") {
            out[d, default: []].append(RedLine(duty: d, subject: subject, what: what, todo: todo))
        }
        func listing(_ paths: [String], more: String = "") -> String {
            let head = paths.prefix(shown).joined(separator: ", ")
            return paths.count > shown ? head + " and \(paths.count - shown) more" + more : head
        }

        // R8: your environment.
        if f.me.permissionMode == "bypassPermissions" {
            add(.R8, "your mode", "This session runs in bypass, so messages to and from your workers are held and expire unseen.", "Switch to Auto now.")
        }
        if let s = f.me.skillNote { add(.R8, "the skill", s) }
        if f.me.cliLoggedOut {
            add(.R8, "the CLI", "Claude's CLI is logged out on this Mac, so no background worker can start.", "Ask the user to run claude auth login here.")
        }
        if let d = f.me.duo {
            if d.running && !d.reachable {
                add(.R8, "Duo", "A Duo is running, but duo2 can't reach it.", "Tell the user: it may be a second instance or an old build.")
            }
            if let cpu = d.cpu, cpu > Limits.duoCPU {
                add(.R8, "Duo", "Duo is using \(Int(cpu.rounded()))% CPU.", "Tell the user, and find out why.")
            }
            if d.running, let last = d.lastUpdateCheck, now.timeIntervalSince(last) > Limits.updateCheckAge {
                add(.R8, "Duo", "Duo last checked for updates \(span(now.timeIntervalSince(last))) ago, so it may be behind.", "Compare it with the latest release and tell the user.")
            }
        }

        // The notes: each appears under at most one per-note rule (R1, then R2, then R9).
        let live = f.notes.filter { Director.unfinished(status: $0.status, archived: false) }
        let active = live.filter { !atReview($0) }
        var taken = Set<String>()

        // R1: workers watched to a conclusion.
        for n in active where n.hasWorkerRecord && !n.userTyping {
            switch n.workerState {
            case "needs-you":
                add(.R1, n.path, "Its worker is waiting: \"\(n.question ?? "input needed")\".", "Read it (claude logs, or duo2 session show), then answer it or ask the user.")
                taken.insert(n.path)
            case "stopped", "idle":
                let report = n.workerLastActivity ?? n.workerSince
                let unchecked = n.lastChecked == nil || (report != nil && n.lastChecked.map { report! > $0 } == true)
                guard unchecked else { continue }
                add(.R1, n.path, "Its worker stopped \(span(now.timeIntervalSince(report ?? n.modified))) ago and nothing you checked is recorded since.",
                    "Read its report, compare it with the Request, then duo2 director check \(n.path) \"what you found\".")
                taken.insert(n.path)
            case "working":
                if let last = n.workerLastActivity, now.timeIntervalSince(last) > Limits.workerSilent {
                    add(.R1, n.path, "Its worker has been silent for \(span(now.timeIntervalSince(last))).", "Read its screen (claude logs) before you assume anything.")
                    taken.insert(n.path)
                }
            default: break
            }
        }

        // R3: scheduled jobs.
        if let why = f.jobsUnreadable {
            add(.R3, "scheduled runs", "Can't read scheduled runs: \(why).", "Check them by hand (the Claude app's session tools), and tell the user this check is blind.")
        }
        for job in f.jobs {
            var stuck = false
            if let run = job.latestRun, !run.archived {
                let idle = now.timeIntervalSince(run.lastActivity)
                if run.completedTurns == 0 && idle > Limits.runStuck {
                    add(.R3, job.id, "Its run started \(clock(run.startedAt, now: now)) in \(run.mode ?? "an unknown mode"), with no activity for \(span(idle)).",
                        "Unstick it. If this has happened before, find out why it starts this way (the failure protocol).")
                    stuck = true
                } else if run.completedTurns > 0 && idle > Limits.runBusy && idle <= Limits.runFinishedWindow
                            && (job.lastCheck == nil || run.lastActivity > job.lastCheck!) {
                    add(.R3, job.id, "Its run finished \(span(idle)) ago and you haven't recorded reading it.",
                        "Read it, then duo2 director check job:\(job.id) \"what it found\" (--routine if nothing new).")
                }
            }
            if !stuck, let due = job.nextDue, now.timeIntervalSince(due) > Limits.jobMissedBy {
                add(.R3, job.id, "A run due \(clock(due, now: now)) never started.", "Start it, and find out why it was missed.")
            }
        }

        // R2: follow-up by check_by (and R9's failure tasks, which are R2 with a different protocol).
        var unowned: [String] = []
        for n in active where !taken.contains(n.path) {
            if n.pendingExpired {
                add(.R2, n.path, "Its worker \(n.workerName ?? "(unnamed)") was recorded to start and never appeared.", "Start it again and find out why it didn't start.")
                taken.insert(n.path)
            } else if let by = n.checkBy, by < now {
                if n.title.trimmingCharacters(in: .whitespaces).hasPrefix("Failure:") {
                    add(.R9, n.path, "This failure's check_by passed \(span(now.timeIntervalSince(by))) ago.", "Finish the protocol: cause, duty, change, eval, ship.")
                } else {
                    add(.R2, n.path, "Its check_by passed \(span(now.timeIntervalSince(by))) ago.", "Look now, then duo2 director check \(n.path) \"what you found\" --next <when>.")
                }
                taken.insert(n.path)
            } else if n.checkBy == nil, !n.hasWorkerRecord, !n.inWorkTree, isLive(n.status),
                      now.timeIntervalSince(n.modified) > Limits.newNote, now.timeIntervalSince(n.lastProgress ?? n.modified) <= Limits.staleNote {
                unowned.append(n.path)
                taken.insert(n.path)
            }
        }
        // As one line, like the other sweeps: a line per note is the wall a director stops reading.
        if !unowned.isEmpty {
            add(.R2, "live notes", (unowned.count == 1 ? "1 note is marked live" : "\(unowned.count) notes are marked live") + " with no worker and no check_by: \(listing(unowned, more: " (--all lists them)")).",
                "Start each one's worker, or set when you'll look: duo2 director check <task> \"what you know\" --next <when>.")
        }

        // R9: a second try is a signal. A send is a `send` or a `handed` (the director's own SendMessage) event.
        let sends = f.events.filter { ($0.event == "send" || $0.event == "handed") && $0.task != nil }
        let checks = f.events.filter { $0.event == "check" && $0.task != nil }
        for n in active where !taken.contains(n.path) {
            let recent = sends.filter { $0.task == n.path }.compactMap(eventDate).filter { $0 <= now && now.timeIntervalSince($0) <= Limits.repeatWindow }
            guard recent.count >= Limits.repeatSends, let first = recent.min() else { continue }
            let checked = checks.contains { $0.task == n.path && (eventDate($0).map { $0 > first } ?? false) }
            if !checked {
                add(.R9, n.path, "You've sent to this worker \(recent.count) times in a day with no check recorded.", "A second try is a signal: find the cause (the failure protocol).")
                taken.insert(n.path)
            }
        }

        // R4: a recorded check the user hasn't heard about.
        if f.me.transcriptRead {
            let latest = checks.filter { $0.routine != true }.compactMap { e in eventDate(e).map { (e, $0) } }.max { $0.1 < $1.1 }
            if let (e, at) = latest, now.timeIntervalSince(at) <= Limits.findingWindow, f.me.lastToUser.map({ at > $0 }) ?? true {
                add(.R4, e.task ?? "your last check", "You recorded a check \(span(now.timeIntervalSince(at))) ago and haven't messaged the user since.",
                    "If it matters to them, tell them in plain words with its link. If it doesn't, mark it --routine next time.")
            }
        }

        // R7: a long turn with no word.
        if f.me.transcriptRead, let since = [f.me.lastToUser, f.me.turnStartedAt].compactMap({ $0 }).max(), now.timeIntervalSince(since) > Limits.turnSilent {
            add(.R7, "this turn", "You've gone \(span(now.timeIntervalSince(since))) without a word to the user.", "Send three lines: what's done, what's running, what's next.")
        }

        // R5: notes at review (and done ones) nobody checked, as one line.
        var unchecked: [String] = []
        for n in f.notes {
            let s = (n.status ?? "").trimmingCharacters(in: .whitespaces).lowercased()
            if s == "review", Director.unfinished(status: n.status, archived: false) {
                let report = n.workerLastActivity ?? n.workerSince
                if n.lastChecked == nil || (report != nil && n.lastChecked.map { report! > $0 } == true) || (n.checkBy.map { $0 < now } ?? false) { unchecked.append(n.path) }
            } else if s == "done", n.hasWorkerRecord, now.timeIntervalSince(n.modified) <= Limits.doneWindow, n.lastChecked == nil {
                unchecked.append(n.path)
            }
        }
        if !unchecked.isEmpty {
            let paths = listing(unchecked, more: " (--all lists them)")
            add(.R5, "review", unchecked.count == 1 ? "1 note waits at review with no recent check: \(paths)."
                                                    : "\(unchecked.count) notes wait at review with no recent check: \(paths).",
                "Check each against its Request (duo2 director check), then bring the user one sweep and one question, not a line each.")
        }

        // R6: the record. Stale live notes, and status words Duo doesn't know, each as one line.
        let stale = active.filter { n in
            !taken.contains(n.path) && n.checkBy == nil && !["working", "needs-you", "starting"].contains(n.workerState)
                && now.timeIntervalSince(n.lastProgress ?? n.modified) > Limits.staleNote
        }
        if !stale.isEmpty {
            let only = stale.filter(\.inWorkTree).count
            let paths = listing(stale.map(\.path), more: " (--all lists them)")
            add(.R6, "the record", (stale.count == 1 ? "1 note marked live has had nothing for over 7 days and no check_by: \(paths)."
                                                     : "\(stale.count) notes marked live have had nothing for over 7 days and no check_by: \(paths).")
                + (only == 0 ? "" : stale.count == 1 ? " It exists only in a work tree." : " \(only) of them exist only in work trees."),
                "Close each, or set when you'll look. Make it one sweep and one question to the user.")
        }
        let odd = f.notes.compactMap { n -> String? in
            guard let s = n.status?.trimmingCharacters(in: .whitespaces), !s.isEmpty, !knownStatuses.contains(s.lowercased()) else { return nil }
            return "\(n.path) (\(s))"
        }
        if !odd.isEmpty {
            add(.R6, "the record", (odd.count == 1 ? "1 note uses" : "\(odd.count) notes use") + " a status word Duo doesn't know: \(listing(odd)).", "Use open, in-progress, waiting, review or done.")
        }

        return order.flatMap { out[$0] ?? [] }
    }

    /// `in-progress` or `open` (no status reads as open).
    static func isLive(_ status: String?) -> Bool {
        let s = (status ?? "open").trimmingCharacters(in: .whitespaces).lowercased()
        return s == "in-progress" || s == "open" || s.isEmpty
    }

    // MARK: What status and the verbs print

    /// Status's opening lines: `Red lines: none.`, or the count, the instruction and each line indented.
    public static func block(_ lines: [RedLine]) -> [String] {
        guard !lines.isEmpty else { return ["Red lines: none."] }
        return ["Red lines (\(lines.count)): clear what you can this turn, and put anything you can't in your next message to the user, in plain words with links."]
            + lines.map { "  " + $0.line }
    }

    /// What ends status's shortened worker list.
    public static func otherTasks(_ n: Int) -> String { "  and \(n) other task\(n == 1 ? "" : "s") (--all lists them)." }

    /// The line every `duo2 director` verb ends with when something is red; nil for none.
    public static func nudge(_ n: Int) -> String? {
        n > 0 ? "\(n) red line\(n == 1 ? "" : "s"): run duo2 director status." : nil
    }
}
