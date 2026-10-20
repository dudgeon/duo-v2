import Foundation
import DuoControl

/// Claude Code's own trust file (DL-229, trust-notice-handoff): `<config>/.claude.json`, key
/// `projects["<real path>"].hasTrustDialogAccepted`. Duo reads it, and (after a sheet) sets that one key.
public enum ClaudeTrust {
    /// The config folder: `CLAUDE_CONFIG_DIR`, else the user's home (where `~/.claude.json` lives).
    public static func configFile(configDir: String? = Env.value("CLAUDE_CONFIG_DIR")) -> URL {
        if let dir = configDir { return URL(fileURLWithPath: dir).appending(path: ".claude.json") }
        return FileManager.default.homeDirectoryForCurrentUser.appending(path: ".claude.json")
    }

    /// The key Claude uses: the real path, symlinks resolved, no trailing slash.
    public static func realPath(_ path: String) -> String {
        // realpath(3), not Foundation's resolvingSymlinksInPath, which turns /private/tmp back into /tmp.
        var p = path.withCString { c -> String? in
            guard let r = realpath(c, nil) else { return nil }
            defer { free(r) }
            return String(cString: r)
        } ?? URL(fileURLWithPath: path).standardized.path
        while p.count > 1, p.hasSuffix("/") { p.removeLast() }
        return p
    }

    /// The repository's top folder for a folder (real path), or nil outside one.
    public static func repositoryTop(of folder: String) -> String? {
        RepoProbe.root(of: URL(fileURLWithPath: folder)).map { realPath($0.path) }
    }

    /// `projects` of the parsed file: path → hasTrustDialogAccepted (nil: no such key).
    public static func entries(file: URL) -> [String: Bool?]? {
        guard let data = try? Data(contentsOf: file), let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        guard let projects = root["projects"] as? [String: Any] else { return [:] }
        var out: [String: Bool?] = [:]
        for (k, v) in projects { out[k] = ((v as? [String: Any])?["hasTrustDialogAccepted"] as? Bool) }
        return out
    }

    public static func isTrusted(_ path: String, in entries: [String: Bool?]) -> Bool {
        if case .some(.some(true)) = entries[path] { return true }
        return false
    }

    /// Whether a folder above `path` is trusted (Claude Code trusts it from above).
    public static func trustedAbove(_ path: String, in entries: [String: Bool?]) -> Bool {
        var p = (path as NSString).deletingLastPathComponent
        while true {
            if isTrusted(p, in: entries) { return true }
            if p == "/" || p.isEmpty { return false }
            p = (p as NSString).deletingLastPathComponent
        }
    }

    // MARK: The write

    public enum Failure: Error, Equatable {
        case locked
        case unreadable
        case cannotWrite(String)

        /// The bar's reason (trust-notice-handoff, "when Duo can't write").
        public func reason(path: String) -> String {
            switch self {
            case .locked: "another Claude is saving them; try again in a moment"
            case .unreadable: "the file isn’t readable as settings, so Duo left it alone"
            case .cannotWrite(let p): "Duo can’t write to \(p)"
            }
        }
    }

    /// Sets `projects[path].hasTrustDialogAccepted = true` and nothing else, as Claude saves its own
    /// file: take the directory lock `.claude.json.lock` beside it (retrying briefly, never removing one
    /// Duo didn't make), read and parse the whole file, edit just that value in the text (so key order,
    /// unknown keys and spacing stay), write a temp file in the folder and rename it over the file.
    /// `wait` is how long to retry the lock.
    public static func trust(_ path: String, file: URL = configFile(), wait: TimeInterval = 2) -> Result<Void, Failure> {
        let lock = file.deletingLastPathComponent().appending(path: file.lastPathComponent + ".lock")
        let fm = FileManager.default
        let deadline = Date().addingTimeInterval(wait)
        var made = false
        while !made {
            if mkdir(lock.path, 0o755) == 0 { made = true; break }
            if errno != EEXIST { return .failure(.cannotWrite(file.path)) }
            if Date() >= deadline { return .failure(.locked) }
            Thread.sleep(forTimeInterval: 0.05)
        }
        defer { if made { rmdir(lock.path) } }
        guard let data = try? Data(contentsOf: file), (try? JSONSerialization.jsonObject(with: data)) is [String: Any],
              let text = String(data: data, encoding: .utf8) else { return .failure(.unreadable) }
        guard let edited = JSONEdit.settingTrust(path, in: text) else { return .failure(.unreadable) }
        if edited == text { return .success(()) }
        // What we wrote must parse, and say what we meant.
        guard let back = edited.data(using: .utf8), let root = (try? JSONSerialization.jsonObject(with: back)) as? [String: Any],
              (((root["projects"] as? [String: Any])?[path] as? [String: Any])?["hasTrustDialogAccepted"] as? Bool) == true else { return .failure(.unreadable) }
        let tmp = file.deletingLastPathComponent().appending(path: ".claude.json.tmp.\(ProcessInfo.processInfo.processIdentifier).\(String(UInt32.random(in: 0...UInt32.max), radix: 16))")
        do {
            try back.write(to: tmp)
            if let attrs = try? fm.attributesOfItem(atPath: file.path), let perm = attrs[.posixPermissions] {
                try? fm.setAttributes([.posixPermissions: perm], ofItemAtPath: tmp.path)
            }
            if rename(tmp.path, file.path) != 0 { try? fm.removeItem(at: tmp); return .failure(.cannotWrite(file.path)) }
        } catch {
            try? fm.removeItem(at: tmp)
            return .failure(.cannotWrite(file.path))
        }
        return .success(())
    }
}

/// A byte-faithful edit of one JSON value: the scanner finds where members sit, so only that text changes.
enum JSONEdit {
    private struct Member { var key: String; var keyStart: Int; var value: Range<Int> }
    private struct Object { var open: Int; var close: Int; var members: [Member] }

    private static func quoted(_ s: String) -> String? {
        let e = JSONEncoder()
        e.outputFormatting = .withoutEscapingSlashes
        return (try? e.encode(s)).flatMap { String(data: $0, encoding: .utf8) }
    }

    /// `text` with `projects[path].hasTrustDialogAccepted` true, or nil if `text` isn't an object this can edit.
    static func settingTrust(_ path: String, in text: String) -> String? {
        let b = Array(text.utf8)
        var p = Scanner(b)
        guard let root = p.object(at: p.skipSpace(0)) else { return nil }
        let entryText = "{\"hasTrustDialogAccepted\": true}"
        func insert(_ obj: Object, key: String, value: String) -> String? {
            guard let ks = quoted(key) else { return nil }
            let member = ks + ": " + value
            var out = b
            if let last = obj.members.last {
                // Same separator as the member before it: the whitespace ahead of its key.
                var s = last.keyStart
                while s > 0, [0x20, 0x09, 0x0a, 0x0d].contains(b[s - 1]) { s -= 1 }
                let sep = String(decoding: b[s..<last.keyStart], as: UTF8.self)
                out.insert(contentsOf: Array(("," + sep + member).utf8), at: last.value.upperBound)
            } else {
                // `{}` or `{ }`: on one line the member goes in compact; across lines, one level deeper than the closer.
                var s = obj.close
                while s > obj.open + 1, [0x20, 0x09].contains(b[s - 1]) { s -= 1 }
                let indent = String(decoding: b[s..<obj.close], as: UTF8.self)
                let spread = b[(obj.open + 1)..<obj.close].contains(0x0a)
                let ins = spread ? "\n" + indent + "  " + member + "\n" + indent : member
                out.replaceSubrange((obj.open + 1)..<obj.close, with: Array(ins.utf8))
            }
            return String(decoding: out, as: UTF8.self)
        }
        guard let projectsMember = root.members.first(where: { $0.key == "projects" }) else {
            return insert(root, key: "projects", value: "{" + (quoted(path) ?? "\"\"") + ": " + entryText + "}")
        }
        var q = Scanner(b)
        guard let projects = q.object(at: projectsMember.value.lowerBound) else { return nil }
        guard let entryMember = projects.members.first(where: { $0.key == path }) else {
            return insert(projects, key: path, value: entryText)
        }
        var r = Scanner(b)
        guard let entry = r.object(at: entryMember.value.lowerBound) else { return nil }
        guard let flag = entry.members.first(where: { $0.key == "hasTrustDialogAccepted" }) else {
            return insert(entry, key: "hasTrustDialogAccepted", value: "true")
        }
        if String(decoding: b[flag.value], as: UTF8.self) == "true" { return text }
        var out = b
        out.replaceSubrange(flag.value, with: Array("true".utf8))
        return String(decoding: out, as: UTF8.self)
    }

    /// A small JSON walker over bytes: it only has to find members' ranges in text JSONSerialization accepted.
    private struct Scanner {
        let b: [UInt8]
        init(_ b: [UInt8]) { self.b = b }

        func skipSpace(_ i: Int) -> Int {
            var i = i
            while i < b.count, [0x20, 0x09, 0x0a, 0x0d].contains(b[i]) { i += 1 }
            return i
        }

        /// The end of the string starting at `i` (after its closing quote).
        func stringEnd(_ i: Int) -> Int? {
            var i = i + 1
            while i < b.count {
                if b[i] == 0x5c { i += 2; continue }
                if b[i] == 0x22 { return i + 1 }
                i += 1
            }
            return nil
        }

        /// The end of any value starting at `i`.
        func valueEnd(_ i: Int) -> Int? {
            guard i < b.count else { return nil }
            switch b[i] {
            case 0x22: return stringEnd(i)
            case 0x7b, 0x5b:
                let close: UInt8 = b[i] == 0x7b ? 0x7d : 0x5d
                var j = skipSpace(i + 1)
                if j < b.count, b[j] == close { return j + 1 }
                while j < b.count {
                    if b[i] == 0x7b {
                        guard let ke = stringEnd(j) else { return nil }
                        j = skipSpace(ke)
                        guard j < b.count, b[j] == 0x3a else { return nil }
                        j = skipSpace(j + 1)
                    }
                    guard let ve = valueEnd(j) else { return nil }
                    j = skipSpace(ve)
                    guard j < b.count else { return nil }
                    if b[j] == close { return j + 1 }
                    guard b[j] == 0x2c else { return nil }
                    j = skipSpace(j + 1)
                }
                return nil
            default:
                var j = i
                while j < b.count, ![0x2c, 0x7d, 0x5d, 0x20, 0x09, 0x0a, 0x0d].contains(b[j]) { j += 1 }
                return j > i ? j : nil
            }
        }

        mutating func object(at start: Int) -> Object? {
            guard start < b.count, b[start] == 0x7b else { return nil }
            var members: [Member] = []
            var j = skipSpace(start + 1)
            if j < b.count, b[j] == 0x7d { return Object(open: start, close: j, members: []) }
            while j < b.count {
                guard b[j] == 0x22, let ke = stringEnd(j) else { return nil }
                let raw = Data(b[j..<ke])
                guard let key = try? JSONDecoder().decode(String.self, from: raw) else { return nil }
                var v = skipSpace(ke)
                guard v < b.count, b[v] == 0x3a else { return nil }
                v = skipSpace(v + 1)
                guard let ve = valueEnd(v) else { return nil }
                members.append(Member(key: key, keyStart: j, value: v..<ve))
                j = skipSpace(ve)
                guard j < b.count else { return nil }
                if b[j] == 0x7d { return Object(open: start, close: j, members: members) }
                guard b[j] == 0x2c else { return nil }
                j = skipSpace(j + 1)
            }
            return nil
        }
    }
}

// MARK: - The line, and the rule

/// The "Workspace not trusted" notice (DL-229): Claude Code's result line after a `/fork`.
public enum TrustLine {
    public struct Read: Equatable {
        /// The path in the line.
        public var path: String
        /// The `/fork` line typed above it, with anything after it.
        public var forkLine: String?
        public init(path: String, forkLine: String?) { self.path = path; self.forkLine = forkLine }
    }

    /// Reads the screen. Only the "Workspace not trusted. Run claude in ‹path› once and accept the trust prompt" line
    /// counts: the two other variants ("could not be resolved on disk", "home directory is trusted one session at a
    /// time") get no notice. A path that wraps across rows is joined where the row was full.
    public static func read(lines: [String], cols: Int) -> Read? {
        guard let i = lines.lastIndex(where: { $0.contains("Workspace not trusted") }) else { return nil }
        var text = lines[i].trimmingCharacters(in: .whitespaces)
        var prev = lines[i]
        var j = i + 1
        while !text.contains("trust prompt"), j < lines.count, j <= i + 4 {
            let next = lines[j].trimmingCharacters(in: .whitespaces)
            if next.isEmpty { break }
            let full = prev.count >= cols - 1
            text += (full ? "" : " ") + next
            prev = lines[j]
            j += 1
        }
        guard let m = text.range(of: #"Workspace not trusted\. Run `?claude`? in (/\S.*?) once and accept the trust prompt"#, options: .regularExpression) else { return nil }
        let hit = String(text[m])
        guard let from = hit.range(of: " in /"), let to = hit.range(of: " once and accept", options: .backwards) else { return nil }
        let path = String(hit[hit.index(from.upperBound, offsetBy: -1)..<to.lowerBound])
        var fork: String?
        for k in stride(from: i - 1, through: max(0, i - 12), by: -1) {
            let t = lines[k].trimmingCharacters(in: .whitespaces)
            for mark in ["> ", "❯ "] where t.hasPrefix(mark + "/fork") {
                fork = String(t.dropFirst(mark.count))
            }
            if fork != nil { break }
        }
        return Read(path: path, forkLine: fork)
    }
}

public enum TrustRule {
    public enum Offer: Equatable {
        /// Trust This Folder… is offered, for this real path.
        case trust(path: String)
        /// The OK-only bar: Claude Code doesn't trust this folder, and Duo doesn't offer to (Q-232 wording).
        case runClaude(path: String)
        /// It is trusted now: no bar.
        case trusted
    }

    /// Trust This Folder… only when the path is the session's folder or its repository's top, has no `true` entry,
    /// and a folder above it has one. `top` is the repository's top folder (real path) when the session is in one.
    public static func offer(linePath: String, sessionFolder: String, top: String?, entries: [String: Bool?]) -> Offer {
        let path = ClaudeTrust.realPath(linePath)
        if ClaudeTrust.isTrusted(path, in: entries) { return .trusted }
        let folder = ClaudeTrust.realPath(sessionFolder)
        if (path == folder || path == top) && ClaudeTrust.trustedAbove(path, in: entries) { return .trust(path: path) }
        return .runClaude(path: path)
    }
}
