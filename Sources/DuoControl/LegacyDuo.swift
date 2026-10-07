import Foundation

/// Legacy Duo's global instructions in `~/.claude` (DL-39, DL-16): its hooks (tagged `_duo`), its
/// managed `CLAUDE.md` block, its skill, subagent and `claude` wrapper. They load into every Claude
/// session, Duo v2's included. Detection is read-only; disabling backs everything up first and is
/// undone by `restore`. Honours CLAUDE_CONFIG_DIR.
public enum LegacyDuo {
    public struct Finding: Sendable, Equatable {
        public var what: String
        public var path: String
    }

    public static var claudeDir: URL {
        if let d = Env.value("CLAUDE_CONFIG_DIR") { return URL(fileURLWithPath: d) }
        return FileManager.default.homeDirectoryForCurrentUser.appending(path: ".claude")
    }

    static let blockRE = try! NSRegularExpression(pattern: #"\n?<!--\s*duo:managed-v[^>]*-->[\s\S]*?<!--\s*duo:end\s*-->\n?"#)

    public static func detect(in dir: URL = claudeDir) -> [Finding] {
        var out: [Finding] = []
        let fm = FileManager.default
        let settings = dir.appending(path: "settings.json")
        if let n = (try? Data(contentsOf: settings)).flatMap(managedHookCount), n > 0 {
            out.append(Finding(what: "\(n) hook\(n == 1 ? "" : "s") in settings.json", path: settings.path))
        }
        let md = dir.appending(path: "CLAUDE.md")
        if let text = try? String(contentsOf: md, encoding: .utf8),
           blockRE.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil {
            out.append(Finding(what: "a managed block in CLAUDE.md", path: md.path))
        }
        for (what, rel) in [("the duo skill", "skills/duo"), ("the duo subagent", "agents/duo.md"), ("the claude wrapper on PATH", "duo/bin/claude")]
        where fm.fileExists(atPath: dir.appending(path: rel).path) {
            out.append(Finding(what: what, path: dir.appending(path: rel).path))
        }
        return out
    }

    /// Hooks whose entry carries legacy's `_duo: "managed-v…"` marker.
    static func managedHookCount(_ data: Data) -> Int? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = obj["hooks"] as? [String: Any] else { return nil }
        return hooks.values.compactMap { $0 as? [[String: Any]] }.joined().filter { isManaged($0) }.count
    }

    static func isManaged(_ entry: [String: Any]) -> Bool {
        if (entry["_duo"] as? String)?.hasPrefix("managed-v") == true { return true }
        return (entry["hooks"] as? [[String: Any]])?.contains { ($0["_duo"] as? String)?.hasPrefix("managed-v") == true } ?? false
    }

    /// Backs up, then removes legacy's hooks and block and moves its files into the backup.
    /// Returns the backup folder.
    public static func disable(in dir: URL = claudeDir, backupRoot: URL) throws -> URL {
        let fm = FileManager.default
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let backup = backupRoot.appending(path: "legacy-duo-\(stamp)")
        try fm.createDirectory(at: backup, withIntermediateDirectories: true)
        for name in ["settings.json", "CLAUDE.md"] where fm.fileExists(atPath: dir.appending(path: name).path) {
            try fm.copyItem(at: dir.appending(path: name), to: backup.appending(path: name))
        }
        // settings.json: drop managed hook entries, keep everything else as it was.
        let settings = dir.appending(path: "settings.json")
        if let data = try? Data(contentsOf: settings), var obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           var hooks = obj["hooks"] as? [String: Any] {
            for (event, value) in hooks {
                guard let list = value as? [[String: Any]] else { continue }
                let kept = list.filter { !isManaged($0) }
                if kept.isEmpty { hooks.removeValue(forKey: event) } else { hooks[event] = kept }
            }
            obj["hooks"] = hooks.isEmpty ? nil : hooks
            let out = try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            try out.write(to: settings, options: .atomic)
        }
        let md = dir.appending(path: "CLAUDE.md")
        if let text = try? String(contentsOf: md, encoding: .utf8) {
            let cleaned = blockRE.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
            try cleaned.write(to: md, atomically: true, encoding: .utf8)
        }
        for rel in ["skills/duo", "agents/duo.md", "duo/bin"] where fm.fileExists(atPath: dir.appending(path: rel).path) {
            let dest = backup.appending(path: "moved").appending(path: rel)
            try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.moveItem(at: dir.appending(path: rel), to: dest)
        }
        try Data(dir.path.utf8).write(to: backup.appending(path: "SOURCE"))
        return backup
    }

    /// Puts a backup back as it was, keeping Duo v2's own block in CLAUDE.md.
    public static func restore(from backup: URL) throws {
        let fm = FileManager.default
        guard let source = try? String(contentsOf: backup.appending(path: "SOURCE"), encoding: .utf8) else {
            throw NSError(domain: "duo2", code: 1, userInfo: [NSLocalizedDescriptionKey: "not a legacy-duo backup: \(backup.path)"])
        }
        let dir = URL(fileURLWithPath: source)
        // Duo v2's own block was added after this backup; keep it (DL-74).
        let before = (try? String(contentsOf: dir.appending(path: "CLAUDE.md"), encoding: .utf8)) ?? ""
        defer { Installer.reapplyBlock(ifPresentIn: before, to: dir.appending(path: "CLAUDE.md")) }
        for name in ["settings.json", "CLAUDE.md"] where fm.fileExists(atPath: backup.appending(path: name).path) {
            _ = try? fm.removeItem(at: dir.appending(path: name))
            try fm.copyItem(at: backup.appending(path: name), to: dir.appending(path: name))
        }
        for rel in ["skills/duo", "agents/duo.md", "duo/bin"] where fm.fileExists(atPath: backup.appending(path: "moved/\(rel)").path) {
            try fm.createDirectory(at: dir.appending(path: rel).deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.moveItem(at: backup.appending(path: "moved/\(rel)"), to: dir.appending(path: rel))
        }
    }
}
