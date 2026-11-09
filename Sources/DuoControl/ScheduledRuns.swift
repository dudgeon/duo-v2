import Foundation

// The Claude desktop app's scheduled tasks and their runs, read for R3 "Watch recurring jobs" (DL-321,
// F-608). The records are the app's own and undocumented, so every read is tolerant, and a read that
// fails says why: R3 then shows "can't read scheduled runs" and never stays quiet. Read-only, for this
// project's jobs only. Foundation only.

/// Where the Claude desktop app keeps its records.
public enum ClaudeDesktop {
    public static let variable = "DUO_CLAUDE_APP_DIR"

    /// `DUO_CLAUDE_APP_DIR` when it names a folder (how a check or a scripted run points at fixtures),
    /// nil in a test context or on a scratch home (it never reads the user's own records), else the app's folder.
    public static func directory(env: [String: String] = ProcessInfo.processInfo.environment) -> URL? {
        if let v = env[variable], !v.trimmingCharacters(in: .whitespaces).isEmpty { return URL(fileURLWithPath: v) }
        if Isolation.isStrict(env) || Isolation.scratchHome(env) { return nil }
        return FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support/Claude")
    }
}

public enum ScheduledRuns {
    static let folder = "claude-code-sessions"
    static let tasksFile = "scheduled-tasks.json"
    /// How many run records are looked at, newest first.
    static let runsLooked = 200

    /// This project's enabled scheduled jobs, each with its latest run and when it was next due after
    /// its last scheduled time. No folder, or no `scheduled-tasks.json`: no jobs, and nothing to say.
    /// A file that won't parse, or has no `scheduledTasks` list, or a run with no `lastActivityAt`:
    /// `unreadable` says which (by file name only).
    public static func read(appDir: URL?, project: URL, events: [DirectorEvent], now: Date) -> (jobs: [DirectorFacts.Job], unreadable: String?) {
        guard let appDir else { return ([], nil) }
        let fm = FileManager.default
        let root = appDir.appending(path: folder)
        let target = resolved(project)
        var problems: [String] = []
        var found: [(task: [String: Any], dir: URL)] = []
        for a in subfolders(root) {
            for b in subfolders(a) {
                let file = b.appending(path: tasksFile)
                guard fm.fileExists(atPath: file.path) else { continue }
                guard let data = try? Data(contentsOf: file), let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                    problems.append("\(tasksFile) isn't JSON Duo can read")
                    continue
                }
                guard let tasks = json["scheduledTasks"] as? [[String: Any]] else {
                    problems.append("\(tasksFile) has no scheduledTasks list")
                    continue
                }
                for t in tasks where (t["enabled"] as? Bool) != false {
                    guard let id = t["id"] as? String, !id.isEmpty, let cwd = t["cwd"] as? String, resolved(URL(fileURLWithPath: cwd)) == target,
                          !found.contains(where: { ($0.task["id"] as? String) == id }) else { continue }
                    found.append((t, b))
                }
            }
        }
        var jobs: [DirectorFacts.Job] = []
        var latest: [String: [String: Any]] = [:]   // job id -> its newest run's record
        for dir in Set(found.map { $0.dir }).sorted(by: { $0.path < $1.path }) {
            let wanted = found.filter { $0.dir == dir }.compactMap { $0.task["id"] as? String }
            for (id, run, why) in newestRuns(in: dir, jobs: wanted) {
                if let why { problems.append(why) }
                if let run { latest[id] = run }
            }
        }
        for (task, _) in found {
            let id = task["id"] as? String ?? ""
            var run: DirectorFacts.Run?
            if let r = latest[id], let last = ms(r["lastActivityAt"]) {
                run = DirectorFacts.Run(startedAt: ms(r["createdAt"]) ?? last, lastActivity: last, mode: r["permissionMode"] as? String,
                                        completedTurns: (r["completedTurns"] as? Int) ?? 0, archived: (r["isArchived"] as? Bool) == true)
            }
            let after = (task["lastScheduledFor"] as? String).flatMap(iso) ?? ms(task["createdAt"])
            let due = after.flatMap { a in (task["cronExpression"] as? String).flatMap { Cron.next(after: a, expression: $0) } }
            let check = events.filter { $0.event == "check" && $0.task == "job:\(id)" }.compactMap { DirectorRedLines.eventDate($0) }.max()
            jobs.append(DirectorFacts.Job(id: id, title: task["displayName"] as? String ?? id, nextDue: due, latestRun: run, lastCheck: check))
        }
        return (jobs, problems.isEmpty ? nil : problems.joined(separator: "; "))
    }

    /// The newest run record of each job in `dir`: `local_*.json`, newest file first, at most 200. Each
    /// file's bytes are searched for `scheduledTaskId` and the job's id before any JSON is parsed
    /// (they run to hundreds of KB), and the search stops once every job has its run.
    static func newestRuns(in dir: URL, jobs: [String]) -> [(id: String, run: [String: Any]?, problem: String?)] {
        let fm = FileManager.default
        let names = ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? []).filter { $0.hasPrefix("local_") && $0.hasSuffix(".json") }
        let dated = names.map { n -> (String, Date) in
            (n, ((try? dir.appending(path: n).resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate) ?? .distantPast)
        }.sorted { $0.1 > $1.1 }.prefix(runsLooked)
        let key = Data("scheduledTaskId".utf8)
        var out: [String: (run: [String: Any]?, problem: String?)] = [:]
        for (name, _) in dated {
            let open = jobs.filter { out[$0] == nil }
            if open.isEmpty { break }
            guard let data = try? Data(contentsOf: dir.appending(path: name), options: .mappedIfSafe), data.range(of: key) != nil else { continue }
            for id in open where data.range(of: Data(id.utf8)) != nil {
                guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                    out[id] = (nil, "\(name) isn't JSON Duo can read")
                    continue
                }
                guard json["scheduledTaskId"] as? String == id else { continue }
                if ms(json["lastActivityAt"]) == nil {
                    out[id] = (nil, "\(name) has no lastActivityAt")
                } else {
                    out[id] = (json, nil)
                }
            }
        }
        return jobs.compactMap { id in out[id].map { (id, $0.run, $0.problem) } }
    }

    static func subfolders(_ url: URL) -> [URL] {
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []).sorted()
        return names.compactMap { n in
            var isDir: ObjCBool = false
            let u = url.appending(path: n)
            return FileManager.default.fileExists(atPath: u.path, isDirectory: &isDir) && isDir.boolValue ? u : nil
        }
    }

    /// A folder as comparable text: standardized, symlinks resolved (`/tmp` is `/private/tmp`).
    static func resolved(_ url: URL) -> String { url.standardizedFileURL.resolvingSymlinksInPath().path }

    /// Milliseconds since 1970 (an integer or a decimal), as a date.
    static func ms(_ v: Any?) -> Date? {
        (v as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue / 1000) }
    }

    static func iso(_ s: String) -> Date? { DirectorTranscript.parseDate(s) }
}

// MARK: - Cron

/// Five-field cron (minute hour day-of-month month day-of-week) in local time: lists, ranges, steps and
/// `*`; day-of-week 0 or 7 is Sunday; when both day fields are restricted either one matches (Vixie
/// cron). Names (`MON`) and the extensions (`L`, `W`, `#`, `?`) aren't supported: `next` is nil, which
/// means no "missed run" line rather than a wrong one.
public enum Cron {
    struct Spec {
        var minutes: [Int], hours: [Int]
        var days: Set<Int>, months: Set<Int>, weekdays: Set<Int>
        var dayStar: Bool, weekdayStar: Bool
    }

    static func parse(_ expression: String) -> Spec? {
        let f = expression.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        guard f.count == 5,
              let mi = field(f[0], 0, 59), let h = field(f[1], 0, 23), let d = field(f[2], 1, 31), let mo = field(f[3], 1, 12), let w = field(f[4], 0, 7) else { return nil }
        return Spec(minutes: mi.sorted(), hours: h.sorted(), days: d, months: mo, weekdays: Set(w.map { $0 == 7 ? 0 : $0 }),
                    dayStar: f[2].hasPrefix("*"), weekdayStar: f[4].hasPrefix("*"))
    }

    /// The values a field names, or nil if any part isn't plain numbers.
    static func field(_ text: String, _ lo: Int, _ hi: Int) -> Set<Int>? {
        var out = Set<Int>()
        for part in text.split(separator: ",", omittingEmptySubsequences: false) {
            let halves = part.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
            guard halves.count <= 2 else { return nil }
            var step = 1
            if halves.count == 2 {
                guard let s = Int(halves[1]), s >= 1 else { return nil }
                step = s
            }
            let range = halves[0]
            let from: Int, to: Int
            if range == "*" { from = lo; to = hi }
            else if let dash = range.firstIndex(of: "-") {
                guard let a = Int(range[..<dash]), let b = Int(range[range.index(after: dash)...]), a <= b else { return nil }
                from = a; to = b
            } else {
                guard let a = Int(range) else { return nil }
                from = a; to = halves.count == 2 ? hi : a
            }
            guard from >= lo, to <= hi else { return nil }
            var v = from
            while v <= to { out.insert(v); v += step }
        }
        return out.isEmpty ? nil : out
    }

    /// The first time strictly after `after` that `expression` names, searching day by day (about nine
    /// years, enough for a February 29), or nil for an expression this doesn't support.
    public static func next(after: Date, expression: String, calendar: Calendar = .current) -> Date? {
        guard let s = parse(expression) else { return nil }
        var day = calendar.startOfDay(for: after)
        for _ in 0..<(366 * 9) {
            let c = calendar.dateComponents([.year, .month, .day, .weekday], from: day)
            if let y = c.year, let mo = c.month, let d = c.day, let wd = c.weekday, s.months.contains(mo) {
                let dayOK = s.days.contains(d), weekdayOK = s.weekdays.contains(wd - 1)
                if (s.dayStar || s.weekdayStar) ? (dayOK && weekdayOK) : (dayOK || weekdayOK) {
                    for h in s.hours {
                        for m in s.minutes {
                            if let t = calendar.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: m)), t > after { return t }
                        }
                    }
                }
            }
            guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: day) else { return nil }
            day = tomorrow
        }
        return nil
    }
}
