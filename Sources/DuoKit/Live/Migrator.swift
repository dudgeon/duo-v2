import CryptoKit
import Foundation

/// The deterministic, journaled migrator (CONS §6.3, §7.4, §7.5, §7.8.4; DL-41 R2). Moves only
/// what Claude's own `/cd` moves (a session's transcript, its sidecar folder and siblings) and
/// appends one `relocated` record; nothing historical is rewritten (R1). Every plan is journaled
/// before the first change, verified after the last, and undone by replaying it in reverse.
///
/// Not here (logged in F-59): delete (DL-47's copy archive already preserves), re-keying
/// `~/.claude.json` and `history.jsonl` on a folder move (the first resume asks for trust again),
/// and `git worktree repair`.
public struct Migrator: Sendable {
    public let claudeDir: URL
    public let journalDir: URL

    public init(claudeDir: URL = ClaudeStorage.root, journalDir: URL = Migrator.defaultJournalDir) {
        self.claudeDir = claudeDir
        self.journalDir = journalDir
    }

    public static var defaultJournalDir: URL {
        (ProcessInfo.processInfo.environment["DUO_SUPPORT_DIR"].map { URL(fileURLWithPath: $0) } ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]).appending(path: "Duo/migrations")
    }

    var projects: URL { claudeDir.appending(path: "projects") }

    // MARK: Journal

    public enum Kind: String, Codable, Sendable { case relocate, folderMove = "folder-move", delete }
    public enum State: String, Codable, Sendable { case planned, applying, committed, reverting, reverted, failed }

    public struct Step: Codable, Sendable, Equatable {
        public enum Op: String, Codable, Sendable { case renameDir = "rename-dir", move, appendRelocated = "append-relocated", delete }
        public var n: Int
        public var op: Op
        public var from: String
        public var to: String
        public var sessionId: String?
        public var relocatedCwd: String?
        public var bytesBefore: Int?
        public var sha256Before: String?
        public var sha256After: String?
        public var mtime: Double?
        public var done = false
    }

    public struct Journal: Codable, Sendable, Equatable {
        public var id: String
        public var kind: Kind
        public var state: State
        public var created: Date
        public var summary: String
        public var mapping: [String: String]
        public var steps: [Step]
        public var warnings: [String] = []
        public var error: String?
    }

    public struct Refusal: Error, CustomStringConvertible, Equatable {
        public let description: String
        init(_ s: String) { description = s }
    }

    func url(_ j: Journal) -> URL { journalDir.appending(path: "\(j.id).json") }

    public func save(_ j: Journal) throws {
        try FileManager.default.createDirectory(at: journalDir, withIntermediateDirectories: true)
        let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]; e.dateEncodingStrategy = .iso8601
        let tmp = journalDir.appending(path: ".\(j.id).tmp")
        try e.encode(j).write(to: tmp)
        _ = try FileManager.default.replaceItemAt(url(j), withItemAt: tmp)
    }

    public func journals() -> [Journal] {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        return ((try? FileManager.default.contentsOfDirectory(at: journalDir, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "json" }
            .compactMap { try? d.decode(Journal.self, from: Data(contentsOf: $0)) }
            .sorted { $0.created > $1.created }
    }

    /// Journals a crash left between states (FR-7.8.4): physical operations wait until each is completed or reverted.
    public func interrupted() -> [Journal] { journals().filter { $0.state == .applying || $0.state == .reverting } }

    // MARK: Gates (§6.3: 4, 5, 6)

    /// A project folder whose name Duo's encoder can't reproduce from the sessions in it, or nil
    /// (encoder self-calibration, `ClaudeStorage.calibrate`).
    public func calibrationProblem() -> String? {
        guard let m = ClaudeStorage.calibrate(in: projects).mismatches.first else { return nil }
        return "\(m.folder) holds sessions from \(m.cwd), which encodes to \(m.encoded)"
    }

    /// Physical operations wait for a calibrated encoder (§6.3 5); planning checks too, so the
    /// refusal comes before the user confirms.
    func requireCalibrated() throws {
        if let problem = calibrationProblem() { throw Refusal("Duo's folder naming doesn't match Claude's here: \(problem). Nothing was moved (§6.3 5).") }
    }

    /// FR-7.4.8: the installed CLI must understand the `relocated` record.
    public static func cliUnderstandsRelocation(_ binary: String?) -> Bool {
        guard let binary, let fh = FileHandle(forReadingAtPath: URL(fileURLWithPath: binary).resolvingSymlinksInPath().path) else { return false }
        defer { try? fh.close() }
        let needle = Data("relocatedCwd".utf8)
        var carry = Data()
        while let chunk = try? fh.read(upToCount: 4 << 20), !chunk.isEmpty {
            let hay = carry + chunk
            if hay.range(of: needle) != nil { return true }
            carry = hay.suffix(needle.count)
        }
        return false
    }

    // MARK: Planning

    /// The files `/cd` moves for one session: the transcript, its sidecar folder, and its siblings (FR-7.4.2).
    func files(of id: String, in bucket: URL) -> [URL] {
        let all = (try? FileManager.default.contentsOfDirectory(at: bucket, includingPropertiesForKeys: nil)) ?? []
        return all.filter { u in
            let n = u.lastPathComponent
            return n == "\(id).jsonl" || n == id || n.hasPrefix("\(id).jsonl.superseded-") || n.hasPrefix("\(id).orphaned-")
                || n == "\(id).ccr-tip.json" || n == "\(id).precompact.json"
        }
        .sorted { a, _ in a.pathExtension != "jsonl" }   // the transcript last, so its record is appended after everything moved
    }

    func bucket(holding id: String) -> URL? {
        ((try? FileManager.default.contentsOfDirectory(at: projects, includingPropertiesForKeys: nil)) ?? [])
            .first { FileManager.default.fileExists(atPath: $0.appending(path: "\(id).jsonl").path) }
    }

    /// Relocate one session to `target` (FR-7.4.1): it shows up in that folder's picker and leaves its old one.
    public func planRelocate(_ id: String, to target: String, live: Set<String> = []) throws -> Journal {
        if live.contains(id) { throw Refusal("\(id.prefix(8)) is running; relocation waits until it isn't (§6.3 liveness)") }
        guard let from = bucket(holding: id) else { throw Refusal("no transcript for \(id.prefix(8))") }
        try requireCalibrated()
        let dest = projects.appending(path: ClaudeStorage.encode(target))
        if from.standardizedFileURL == dest.standardizedFileURL { throw Refusal("\(id.prefix(8)) already lives in \(target)'s folder") }
        if FileManager.default.fileExists(atPath: dest.appending(path: "\(id).jsonl").path) {
            throw Refusal("\(target)'s folder already has a transcript \(id.prefix(8)); choose which to keep first (FR-7.4.4)")
        }
        var steps = files(of: id, in: from).enumerated().map { i, f in
            Step(n: i + 1, op: .move, from: f.path, to: dest.appending(path: f.lastPathComponent).path, sessionId: id)
        }
        steps.append(Step(n: steps.count + 1, op: .appendRelocated, from: dest.appending(path: "\(id).jsonl").path,
                          to: dest.appending(path: "\(id).jsonl").path, sessionId: id, relocatedCwd: target))
        return Journal(id: Self.newID(), kind: .relocate, state: .planned, created: Date(),
                       summary: "Relocate \(id.prefix(8)) to \(target)", mapping: ["session": id, "to": target], steps: steps)
    }

    /// Move a folder and, in the same transaction, every session filed under it (FR-7.5).
    public func planFolderMove(_ folder: String, to dest: String, live: Set<String> = [], openFolders: [String] = []) throws -> Journal {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: folder, isDirectory: &isDir), isDir.boolValue else { throw Refusal("\(folder) isn't a folder") }
        if fm.fileExists(atPath: dest), ((try? fm.contentsOfDirectory(atPath: dest)) ?? []).isEmpty == false {
            throw Refusal("\(dest) exists and isn't empty (FR-7.5.2)")
        }
        if let open = openFolders.first(where: { $0 == folder || $0.hasPrefix(folder + "/") }) {
            throw Refusal("a Duo tab is open in \(open); close it first (FR-7.5.3)")
        }
        try requireCalibrated()
        var steps = [Step(n: 1, op: .renameDir, from: folder, to: dest)]
        var warnings: [String] = []
        for b in (try? fm.contentsOfDirectory(at: projects, includingPropertiesForKeys: nil)) ?? [] {
            for t in ((try? fm.contentsOfDirectory(at: b, includingPropertiesForKeys: nil)) ?? []) where t.pathExtension == "jsonl" {
                guard let cwd = Self.currentCwd(t), cwd == folder || cwd.hasPrefix(folder + "/") else { continue }
                let id = t.deletingPathExtension().lastPathComponent
                if live.contains(id) { throw Refusal("\(id.prefix(8)) is running in \(cwd); end it first (FR-7.5.3)") }
                let mapped = dest + cwd.dropFirst(folder.count)
                let target = projects.appending(path: ClaudeStorage.encode(String(mapped)))
                if fm.fileExists(atPath: target.appending(path: "\(id).jsonl").path) { throw Refusal("\(String(mapped))'s folder already holds \(id.prefix(8)) (FR-7.4.4)") }
                for f in files(of: id, in: b) {
                    steps.append(Step(n: steps.count + 1, op: .move, from: f.path, to: target.appending(path: f.lastPathComponent).path, sessionId: id))
                }
                steps.append(Step(n: steps.count + 1, op: .appendRelocated, from: target.appending(path: "\(id).jsonl").path,
                                  to: target.appending(path: "\(id).jsonl").path, sessionId: id, relocatedCwd: String(mapped)))
                if let first = Self.firstCwd(t), first != cwd { warnings.append("\(id.prefix(8)) started in \(first)") }
            }
        }
        warnings.append("Claude will ask to trust \(dest) on the first resume there (its trust entry stays under the old path).")
        return Journal(id: Self.newID(), kind: .folderMove, state: .planned, created: Date(),
                       summary: "Move \(folder) to \(dest) with its sessions", mapping: ["from": folder, "to": dest], steps: steps, warnings: warnings)
    }

    /// Delete a session completely (FR-7.6.2; Geoff, 2026-10-04): its transcript, sidecar folder and
    /// siblings, and Claude's per-session folders (file history, environment, tasks, debug, todos).
    /// Never `~/.claude.json`, `history.jsonl` or memory. The journal keeps the list, not the content.
    /// `extra`: paths outside Claude's folder that also go (Duo's archive copy).
    public func planDelete(_ id: String, live: Set<String> = [], extra: [URL] = []) throws -> Journal {
        if live.contains(id) { throw Refusal("\(id.prefix(8)) is running; end it before deleting it") }
        let fm = FileManager.default
        var paths: [URL] = bucket(holding: id).map { files(of: id, in: $0) } ?? []
        for dir in ["file-history", "session-env", "tasks", "debug", "todos"] {
            let d = claudeDir.appending(path: dir)
            for u in (try? fm.contentsOfDirectory(at: d, includingPropertiesForKeys: nil)) ?? [] where u.lastPathComponent.hasPrefix(id) { paths.append(u) }
        }
        paths += extra.filter { fm.fileExists(atPath: $0.path) }
        guard !paths.isEmpty else { throw Refusal("nothing of \(id.prefix(8)) is on disk") }
        let steps = paths.enumerated().map { i, u in
            Step(n: i + 1, op: .delete, from: u.path, to: "", sessionId: id, bytesBefore: Int(Self.size(u)))
        }
        return Journal(id: Self.newID(), kind: .delete, state: .planned, created: Date(),
                       summary: "Delete \(id.prefix(8)) and its local logs", mapping: ["session": id], steps: steps)
    }

    /// Bytes under a file or folder.
    static func size(_ u: URL) -> Int64 {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: u.path, isDirectory: &isDir) else { return 0 }
        if !isDir.boolValue { return Int64((try? fm.attributesOfItem(atPath: u.path)[.size] as? NSNumber)??.int64Value ?? 0) }
        return (fm.enumerator(at: u, includingPropertiesForKeys: [.fileSizeKey])?.allObjects as? [URL] ?? [])
            .reduce(0) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    }

    // MARK: Applying

    /// Writes the journal, applies each step, verifies, commits. On failure, reverses what was done.
    @discardableResult
    public func apply(_ plan: Journal, live: Set<String> = []) throws -> Journal {
        if let open = interrupted().first { throw Refusal("an earlier migration (\(open.summary)) was interrupted; complete or undo it first (FR-7.8.4)") }
        try requireCalibrated()
        if let s = plan.steps.compactMap(\.sessionId).first(where: live.contains) { throw Refusal("\(s.prefix(8)) is running now; nothing was moved") }
        var j = plan
        j.state = .applying
        try save(j)   // write-ahead (§6.3 3)
        do {
            for i in j.steps.indices {
                try run(&j.steps[i])
                j.steps[i].done = true
                try save(j)
            }
            try verify(j)
            j.state = .committed
            try save(j)
            sweepEmptyBuckets(j.steps.filter { $0.op == .move }.map(\.from))
            return j
        } catch {
            j.error = "\(error)"
            j.state = .failed
            try? save(j)
            if j.kind != .delete { try? undo(j) }
            throw error
        }
    }

    func run(_ s: inout Step) throws {
        let fm = FileManager.default
        switch s.op {
        case .renameDir:
            try fm.createDirectory(at: URL(fileURLWithPath: s.to).deletingLastPathComponent(), withIntermediateDirectories: true)
            if fm.fileExists(atPath: s.to) { try fm.removeItem(atPath: s.to) }   // an empty destination (checked in the plan)
            try fm.moveItem(atPath: s.from, toPath: s.to)
        case .move:
            let attrs = try fm.attributesOfItem(atPath: s.from)
            s.mtime = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970
            if s.from.hasSuffix(".jsonl") { let d = try Data(contentsOf: URL(fileURLWithPath: s.from)); s.bytesBefore = d.count; s.sha256Before = Self.sha(d) }
            try fm.createDirectory(at: URL(fileURLWithPath: s.to).deletingLastPathComponent(), withIntermediateDirectories: true)
            guard !fm.fileExists(atPath: s.to) else { throw Refusal("\(s.to) appeared during the move; stopped") }
            try fm.moveItem(atPath: s.from, toPath: s.to)   // same volume: a rename, atomic per file (§6.3 2)
        case .delete:
            // Permanent, by the user's explicit choice; the journal keeps what went.
            if fm.fileExists(atPath: s.from) { try fm.removeItem(atPath: s.from) }
        case .appendRelocated:
            let u = URL(fileURLWithPath: s.from)
            let before = try Data(contentsOf: u)
            let mtime = (try fm.attributesOfItem(atPath: s.from)[.modificationDate] as? Date)
            s.bytesBefore = before.count
            s.sha256Before = Self.sha(before)
            var line = try JSONSerialization.data(withJSONObject: ["type": "relocated", "sessionId": s.sessionId ?? "", "relocatedCwd": s.relocatedCwd ?? ""],
                                                  options: [.sortedKeys, .withoutEscapingSlashes])
            line.append(UInt8(ascii: "\n"))
            let after = (before.last == UInt8(ascii: "\n") || before.isEmpty ? before : before + Data("\n".utf8)) + line
            let tmp = u.deletingLastPathComponent().appending(path: ".\(u.lastPathComponent).duo-tmp")
            try after.write(to: tmp)
            _ = try fm.replaceItemAt(u, withItemAt: tmp)
            if let mtime { try? fm.setAttributes([.modificationDate: mtime], ofItemAtPath: s.from) }   // the sweep's clock is unchanged (§6.3 7)
            s.sha256After = Self.sha(after)
        }
    }

    /// §6.3 8: every moved transcript parses, its old bytes are intact, the record is last, ids are unique.
    func verify(_ j: Journal) throws {
        if j.kind == .delete {
            if let left = j.steps.first(where: { FileManager.default.fileExists(atPath: $0.from) }) { throw Refusal("\(left.from) is still there") }
            return
        }
        for s in j.steps where s.op == .appendRelocated {
            let d = try Data(contentsOf: URL(fileURLWithPath: s.to))
            let lines = d.split(separator: UInt8(ascii: "\n"))
            for l in lines where (try? JSONSerialization.jsonObject(with: Data(l))) == nil { throw Refusal("a record in \(s.to) doesn't parse after the move") }
            guard let last = lines.last, let rec = try? JSONSerialization.jsonObject(with: Data(last)) as? [String: Any],
                  rec["type"] as? String == "relocated", rec["relocatedCwd"] as? String == s.relocatedCwd else { throw Refusal("the relocated record isn't last in \(s.to)") }
            let prefix = d.prefix(s.bytesBefore ?? 0)
            if let want = s.sha256Before, Self.sha(prefix) != want { throw Refusal("\(s.to)'s history changed during the move") }
            if let id = s.sessionId {
                let holders = ((try? FileManager.default.contentsOfDirectory(at: projects, includingPropertiesForKeys: nil)) ?? [])
                    .filter { FileManager.default.fileExists(atPath: $0.appending(path: "\(id).jsonl").path) }
                if holders.count != 1 { throw Refusal("\(id.prefix(8)) is in \(holders.count) folders after the move (§6.3 1)") }
            }
        }
    }

    // MARK: Undo

    /// Replays a journal in reverse (§6.3 9): removes the appended record, moves files back, renames the folder back.
    public func undo(_ plan: Journal) throws {
        let fm = FileManager.default
        var j = plan
        j.state = .reverting
        try save(j)
        if j.kind == .delete { throw Refusal("a delete can't be undone: its files are gone (the journal lists them)") }
        for i in j.steps.indices.reversed() where j.steps[i].done {
            let s = j.steps[i]
            switch s.op {
            case .delete: continue
            case .appendRelocated:
                let u = URL(fileURLWithPath: s.to)
                let d = try Data(contentsOf: u)
                guard let n = s.bytesBefore, d.count >= n, Self.sha(d.prefix(n)) == s.sha256Before else {
                    throw Refusal("\(s.to) changed since the move; undo stopped here so nothing is lost")
                }
                let mtime = try? fm.attributesOfItem(atPath: s.to)[.modificationDate] as? Date
                try Data(d.prefix(n)).write(to: u, options: .atomic)
                if let mtime { try? fm.setAttributes([.modificationDate: mtime], ofItemAtPath: s.to) }
            case .move:
                guard fm.fileExists(atPath: s.to), !fm.fileExists(atPath: s.from) else { continue }
                // The bucket may have been swept when the move left it empty.
                try fm.createDirectory(at: URL(fileURLWithPath: s.from).deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.moveItem(atPath: s.to, toPath: s.from)
                if let m = s.mtime { try? fm.setAttributes([.modificationDate: Date(timeIntervalSince1970: m)], ofItemAtPath: s.from) }
            case .renameDir:
                guard fm.fileExists(atPath: s.to), !fm.fileExists(atPath: s.from) else { continue }
                try fm.moveItem(atPath: s.to, toPath: s.from)
            }
            j.steps[i].done = false
            try save(j)
        }
        j.state = .reverted
        try save(j)
        sweepEmptyBuckets(j.steps.filter { $0.op == .move }.map(\.to))
    }

    /// Claude's per-folder buckets a move or an undo left empty (F-64 noted them). Only a folder
    /// directly in Claude's projects folder, and only when nothing is left in it (`.DS_Store` aside).
    func sweepEmptyBuckets(_ paths: [String]) {
        let fm = FileManager.default
        let root = projects.standardizedFileURL.path
        for dir in Set(paths.map { URL(fileURLWithPath: $0).deletingLastPathComponent().standardizedFileURL }) {
            guard dir.deletingLastPathComponent().path == root,
                  let left = try? fm.contentsOfDirectory(atPath: dir.path), left.allSatisfy({ $0 == ".DS_Store" }) else { continue }
            try? fm.removeItem(at: dir)
        }
    }

    // MARK: Helpers

    static func newID() -> String {
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd-HHmmss"
        return "mig-\(f.string(from: Date()))-\(UUID().uuidString.prefix(6).lowercased())"
    }

    static func sha(_ d: Data) -> String { SHA256.hash(data: d).map { String(format: "%02x", $0) }.joined() }

    /// A transcript's first recorded cwd.
    static func firstCwd(_ u: URL) -> String? {
        guard let fh = try? FileHandle(forReadingFrom: u) else { return nil }
        defer { try? fh.close() }
        let head = (try? fh.read(upToCount: 1 << 20)) ?? Data()
        for line in head.split(separator: UInt8(ascii: "\n")) {
            if let r = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any], let c = r["cwd"] as? String { return c }
        }
        return nil
    }

    /// Where a session lives now: its last `relocated` record, else its first cwd (§5.2).
    static func currentCwd(_ u: URL) -> String? {
        guard let d = try? Data(contentsOf: u) else { return nil }
        for line in d.split(separator: UInt8(ascii: "\n")).reversed() {
            if let r = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any], r["type"] as? String == "relocated", let c = r["relocatedCwd"] as? String { return c }
        }
        return firstCwd(u)
    }
}
