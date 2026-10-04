import Foundation

/// Duo's copy of its sessions' transcripts (DL-44; Q-19's defaults, to revisit with Geoff).
/// Claude Code deletes transcripts after `cleanupPeriodDays` (30 by default; F-32). Duo copies
/// the transcript of every session it lists into `Application Support/Duo/archive/`, so a
/// purged session stays listed, can be put back for `--resume`, or carried into a new session.
/// Copies are refreshed only when the transcript changed; nothing in `~/.claude` is modified
/// except to put a missing transcript back on resume.
public enum SessionArchive {
    public struct Entry: Codable, Sendable, Equatable {
        public var sessionId: String
        public var cwd: String           // where Claude filed it (its folder, after any /cd)
        public var title: String?
        public var size: Int
        public var modified: Double
        public var archived: Double
        /// The sidecar folder's fingerprint when last copied (DL-48): file count, bytes, newest change.
        public var sidecar: String?
    }

    public struct Manifest: Codable, Sendable, Equatable {
        public var schema = 1
        public var sessions: [String: Entry] = [:]
    }

    public static var root: URL {
        if let r = ProcessInfo.processInfo.environment["DUO_ARCHIVE_ROOT"] { return URL(fileURLWithPath: r) }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "Duo/archive")
    }
    static var manifestURL: URL { root.appending(path: "manifest.json") }
    public static func copyURL(_ id: String) -> URL { root.appending(path: "\(id).jsonl") }
    public static func sidecarURL(_ id: String) -> URL { root.appending(path: id) }

    /// File count, total bytes and newest modification in a session's sidecar folder.
    static func fingerprint(_ dir: URL) -> String? {
        guard let walker = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]) else { return nil }
        var n = 0, bytes = 0, newest = 0.0
        for case let u as URL in walker {
            guard let v = try? u.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]), let size = v.fileSize else { continue }
            n += 1; bytes += size; newest = max(newest, v.contentModificationDate?.timeIntervalSince1970 ?? 0)
        }
        return n == 0 ? nil : "\(n)/\(bytes)/\(Int(newest))"
    }

    /// Forgets a deleted session: its copy, sidecar and manifest entry (FR-7.6.2 via Duo's delete).
    public static func forget(_ id: String) {
        try? FileManager.default.removeItem(at: copyURL(id))
        try? FileManager.default.removeItem(at: sidecarURL(id))
        var m = manifest()
        guard m.sessions.removeValue(forKey: id) != nil, let data = try? JSONEncoder().encode(m) else { return }
        try? data.write(to: manifestURL, options: .atomic)
        chmod(manifestURL.path, 0o600)
    }

    public static func manifest() -> Manifest {
        (try? Data(contentsOf: manifestURL)).flatMap { try? JSONDecoder().decode(Manifest.self, from: $0) } ?? Manifest()
    }

    /// Copies each listed session's transcript if it's new or changed. Returns how many were copied.
    @discardableResult
    public static func sync(_ sessions: [(id: String, transcript: URL)]) throws -> Int {
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var m = manifest()
        var copied = 0
        for (id, url) in sessions {
            guard let v = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
                  let size = v.fileSize, let mod = v.contentModificationDate?.timeIntervalSince1970 else { continue }
            // Sidecars (tool outputs, subagent transcripts) beside the transcript (DL-48).
            let sidecar = url.deletingPathExtension()
            let print = fingerprint(sidecar)
            if let e = m.sessions[id], e.size == size, e.modified == mod, e.sidecar == print, fm.fileExists(atPath: copyURL(id).path) { continue }
            if let print, m.sessions[id]?.sidecar != print {
                let tmpDir = root.appending(path: ".\(id).sidecar.tmp")
                try? fm.removeItem(at: tmpDir)
                try fm.copyItem(at: sidecar, to: tmpDir)
                try? fm.removeItem(at: sidecarURL(id))
                try fm.moveItem(at: tmpDir, to: sidecarURL(id))
            }
            let tmp = root.appending(path: ".\(id).tmp")
            try? fm.removeItem(at: tmp)
            try fm.copyItem(at: url, to: tmp)
            if fm.fileExists(atPath: copyURL(id).path) { _ = try fm.replaceItemAt(copyURL(id), withItemAt: tmp) }
            else { try fm.moveItem(at: tmp, to: copyURL(id)) }
            chmod(copyURL(id).path, 0o600)
            let read = ClaudeStorage.filedCwd(url)
            m.sessions[id] = Entry(sessionId: id, cwd: read ?? url.deletingLastPathComponent().path, title: SessionTitles.title(transcript: url),
                                   size: size, modified: mod, archived: Date().timeIntervalSince1970, sidecar: print)
            copied += 1
        }
        if copied > 0 {
            let data = try JSONEncoder().encode(m)
            try data.write(to: manifestURL, options: .atomic)
            chmod(manifestURL.path, 0o600)
        }
        return copied
    }

    /// Puts an archived transcript back where Claude Code looks for it, so `--resume` works again.
    /// Never overwrites a transcript that's there. Returns where it went.
    @discardableResult
    public static func restore(_ id: String) throws -> URL? {
        guard let e = manifest().sessions[id], FileManager.default.fileExists(atPath: copyURL(id).path) else { return nil }
        let dir = ClaudeStorage.projects.appending(path: ClaudeStorage.encode(URL(fileURLWithPath: e.cwd).resolvingSymlinksInPath().path))
        let dest = dir.appending(path: "\(id).jsonl")
        if FileManager.default.fileExists(atPath: dest.path) { return dest }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: copyURL(id), to: dest)
        let side = dir.appending(path: id)
        if FileManager.default.fileExists(atPath: sidecarURL(id).path), !FileManager.default.fileExists(atPath: side.path) {
            try FileManager.default.copyItem(at: sidecarURL(id), to: side)
        }
        return dest
    }

    /// Archived sessions whose transcript Claude no longer has: search indexes these copies (DL-49).
    public static func purged() -> [(id: String, copy: URL, cwd: String)] {
        manifest().sessions.values.compactMap { e in
            guard ClaudeStorage.transcript(sessionId: e.sessionId, cwd: e.cwd) == nil,
                  FileManager.default.fileExists(atPath: copyURL(e.sessionId).path) else { return nil }
            return (e.sessionId, copyURL(e.sessionId), e.cwd)
        }
    }

    // MARK: Keep-alive (DL-47)

    /// The cleanup period Claude Code will use: the smallest of the managed policy and the user's
    /// setting, else its default of 30 days. Nil when cleanup is off (0).
    public static func cleanupPeriodDays(claudeDir: URL = ClaudeStorage.root) -> Int? {
        let files = [URL(fileURLWithPath: "/Library/Application Support/ClaudeCode/managed-settings.json"), claudeDir.appending(path: "settings.json")]
        let values = files.compactMap { f -> Int? in
            guard let d = try? Data(contentsOf: f), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return nil }
            return (o["cleanupPeriodDays"] as? NSNumber)?.intValue
        }
        if values.contains(0) { return nil }
        return values.min() ?? 30
    }

    /// Claude Code deletes transcripts whose modification time is older than the cleanup period
    /// (F-41: its sweep compares `stat.mtime`). A listed session that has gone quiet for half the
    /// period gets its modification time set to *half the period ago*, not now, so it stays out
    /// of the sweep without jumping to the top of recency lists. Its sidecar folder (tool outputs,
    /// subagents) is treated the same. Returns how many items were refreshed.
    @discardableResult
    public static func keepAlive(_ transcripts: [URL], periodDays: Int, now: Date = Date()) -> Int {
        let half = Double(periodDays) * 86_400 / 2
        let stamp = now.addingTimeInterval(-half)
        let fm = FileManager.default
        var refreshed = 0
        func refresh(_ url: URL) {
            guard let mod = (try? fm.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date, mod < stamp else { return }
            if (try? fm.setAttributes([.modificationDate: stamp], ofItemAtPath: url.path)) != nil { refreshed += 1 }
        }
        for t in transcripts {
            refresh(t)
            let sidecar = t.deletingPathExtension()   // <bucket>/<session-id>/
            if let walker = fm.enumerator(at: sidecar, includingPropertiesForKeys: nil) {
                for case let u as URL in walker { refresh(u) }
                refresh(sidecar)
            }
        }
        return refreshed
    }

    /// The first prompt for a new session that carries on from an archived one (Geoff's idea in
    /// Q-19): it points Claude at the archived transcript instead of pasting it.
    public static func carryOnPrompt(_ id: String) -> String? {
        guard let e = manifest().sessions[id] else { return nil }
        return "Carry on from an earlier session" + (e.title.map { " (\"\($0)\")" } ?? "")
            + ". Its full transcript is archived at \(copyURL(id).path) (JSON lines; the conversation is in the "
            + "\"user\" and \"assistant\" records). Read the last part of it, summarise where we left off in a few lines, then wait for me."
    }
}
