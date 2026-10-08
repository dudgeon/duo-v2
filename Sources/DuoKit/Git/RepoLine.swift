import Foundation

/// What Duo knows about a project's repository right now (DL-149, DL-157): local state, plus what
/// GitHub said when Duo last asked.
public struct RepoView: Equatable, Sendable {
    public var status: RepoStatus
    /// The project's folder relative to the repo's root ("" when the project is the repo).
    public var projectPrefix: String
    public var access: GitHubAccess?
    public var lastFetch: Date?
    public var lastReach: Date?            // the last time GitHub answered
    public var unreachable = false         // the last fetch couldn't reach GitHub
    public var lastFailure: GitFailure.Kind?
    public var pr: Int?
    public var prURL: URL?
    public var duoFilesIgnored = false     // `_PROJECT.md` is excluded or ignored
    public var busy: String?               // "Pushing…", "Getting the latest…"

    public init(status: RepoStatus, projectPrefix: String) { self.status = status; self.projectPrefix = projectPrefix }

    /// Untracked files that are Duo's own never count as the user's changes (DL-157).
    public static func isDuoFile(_ path: String) -> Bool {
        let name = (path as NSString).lastPathComponent
        return name == "_PROJECT.md" || name == "PROJECT.md" || name == "_HOME.md" || name == "HOME.md"
            || path.hasPrefix(".duo/") || path.contains("/.duo/") || path == ".duo"
    }
    public var userChanges: [FileChange] { status.changes.filter { !($0.kind == .new && Self.isDuoFile($0.path)) } }
    public var duoChanges: [FileChange] { status.changes.filter { $0.kind == .new && Self.isDuoFile($0.path) } }

    /// The base a pull request goes into: what GitHub says is default, else origin's HEAD, else main.
    public var base: String { access?.defaultBranch ?? status.defaultBranch ?? "main" }
    public var onDefault: Bool { status.branch != nil && status.branch == base }

    /// Marks for the file tree, by path relative to the project's folder.
    public var marks: [String: String] {
        var m: [String: String] = [:]
        for c in status.changes {
            guard c.path.hasPrefix(projectPrefix) else { continue }
            let rel = String(c.path.dropFirst(projectPrefix.count))
            if c.kind == .new && Self.isDuoFile(c.path) { continue }
            m[rel] = c.kind == .conflict ? "conflict" : (c.kind == .new ? "new" : (c.kind == .deleted ? "deleted" : "changed"))
        }
        if duoFilesIgnored {
            for f in ["_PROJECT.md", "PROJECT.md"] where m[f] == nil { m[f] = "kept out of git" }
        }
        return m
    }
}

/// One fact and at most one button, the most pressing first (board 5): conflict › signed out ›
/// protected › behind › to push › changed › PR › clean.
public struct RepoLine: Equatable, Sendable {
    public enum Action: String, Sendable { case push = "Push…", pushNow = "Push", latest = "Get Latest", resolve = "Resolve…", moveToBranch = "Move to a Branch…", signIn = "Sign In…" }
    public enum Glyph: Sendable { case none, up, down, lock }
    public var fact: String
    public var glyph: Glyph = .none
    public var strong = false               // `text` semibold (a conflict), never `needsYou`
    public var prLink: Int?                 // "PR #n" is a link
    public var action: Action?
    /// Every fact that holds, for the popover.
    public var all: [String] = []

    public init(fact: String, glyph: Glyph = .none, strong: Bool = false, prLink: Int? = nil, action: Action? = nil, all: [String] = []) {
        self.fact = fact; self.glyph = glyph; self.strong = strong; self.prLink = prLink; self.action = action; self.all = all
    }

    public static func of(_ v: RepoView, now: Date = Date()) -> RepoLine {
        let s = v.status
        let changed = v.userChanges.filter { $0.kind != .conflict }.count
        let n = { (k: Int, one: String, many: String) in k == 1 ? "1 \(one)" : "\(k) \(many)" }
        var facts: [String] = []
        if s.hasConflict || s.merging { facts.append(n(max(1, s.conflicts.count), "file in conflict", "files in conflict")) }
        if s.behind > 0 { facts.append("\(s.behind) new on GitHub") }
        if s.ahead > 0 { facts.append("\(s.ahead) to push") }
        if changed > 0 { facts.append(n(changed, "file changed", "files changed")) }
        if let pr = v.pr { facts.append("PR #\(pr) open") }
        if s.origin == nil { facts.append("no GitHub remote") }
        var line: RepoLine
        let readOnly = v.access?.readOnly == true
        if s.hasConflict || s.merging {
            line = RepoLine(fact: n(max(1, s.conflicts.count), "file in conflict", "files in conflict"), strong: true, action: .resolve)
        } else if v.lastFailure == .signedOut {
            line = RepoLine(fact: "signed out of GitHub", action: .signIn)
        } else if s.origin == nil {
            line = RepoLine(fact: changed > 0 ? n(changed, "file changed", "files changed") + " · no GitHub remote" : "no GitHub remote")
        } else if v.onDefault, v.access?.protectedDefault == true, s.ahead > 0 || changed > 0 {
            line = RepoLine(fact: "protected · " + (s.ahead > 0 ? "\(s.ahead) to push" : n(changed, "file changed", "files changed")), glyph: .lock, action: .moveToBranch)
        } else if s.behind > 0 {
            line = RepoLine(fact: "\(s.behind) new on GitHub", glyph: .down, action: .latest)
        } else if readOnly, s.ahead > 0 || changed > 0 || s.upstream == nil {
            let k = s.ahead > 0 ? s.ahead : max(changed, 1)
            line = RepoLine(fact: "read only · \(k) to push to your fork", glyph: .lock, action: .push)
        } else if s.ahead > 0 {
            line = v.pr != nil
                ? RepoLine(fact: "PR #\(v.pr!) · \(s.ahead) to push", glyph: .up, prLink: v.pr, action: changed > 0 ? .push : .pushNow)
                : RepoLine(fact: "\(s.ahead) to push", glyph: .up, action: .push)
        } else if changed > 0 {
            line = RepoLine(fact: n(changed, "file changed", "files changed"), action: .push)
        } else if s.upstream == nil, s.branch != nil {
            line = RepoLine(fact: "not on GitHub yet", action: .push)
        } else if v.unreachable {
            line = RepoLine(fact: "can’t reach GitHub" + (v.lastReach.map { " · checked \(Self.ago($0, now))" } ?? ""))
        } else if let pr = v.pr {
            line = RepoLine(fact: "PR #\(pr) open · up to date", prLink: pr)
        } else {
            line = RepoLine(fact: "up to date with GitHub")
        }
        line.all = facts
        return line
    }

    static func ago(_ d: Date, _ now: Date) -> String {
        let s = Int(now.timeIntervalSince(d))
        if s < 90 { return "just now" }
        if s < 3600 { return "\(s / 60) min ago" }
        if s < 86400 { return "\(s / 3600) h ago" }
        return "\(s / 86400) d ago"
    }
}
