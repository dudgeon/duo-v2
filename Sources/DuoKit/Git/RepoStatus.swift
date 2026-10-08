import Foundation

/// A GitHub (or other) repository named by a remote URL (DL-149).
public struct RemoteRepo: Equatable, Sendable {
    public var host: String
    public var owner: String
    public var name: String
    public var slug: String { "\(owner)/\(name)" }
    public var isGitHub: Bool { host == "github.com" || host.hasPrefix("github.") }
    public var webURL: URL { URL(string: "https://\(host)/\(owner)/\(name)")! }
    public var httpsCloneURL: String { "https://\(host)/\(owner)/\(name).git" }

    public init(host: String, owner: String, name: String) {
        self.host = host.lowercased(); self.owner = owner; self.name = name
    }

    /// Parses every form a person pastes: `https://github.com/o/r(.git)(/tree/b/...)`, `git@github.com:o/r.git`,
    /// `ssh://git@github.com/o/r`, `github.com/o/r`, and `o/r` (GitHub implied). Returns the branch a
    /// `/tree/<branch>` link names, if any.
    public static func parse(_ raw: String) -> (repo: RemoteRepo, branch: String?)? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty, !s.hasPrefix("-"), !s.contains(" ") else { return nil }
        var host = "github.com"
        if let r = s.range(of: #"^[A-Za-z0-9._-]+@([A-Za-z0-9.-]+):"#, options: .regularExpression) {
            host = String(s[r].split(separator: "@")[1].dropLast())
            s = String(s[r.upperBound...])
        } else if let u = URL(string: s.contains("://") ? s : "https://" + s), let h = u.host, s.contains("://") || h.contains(".") {
            host = h
            s = u.path
        }
        var parts = s.split(separator: "/").map(String.init)
        guard parts.count >= 2 else { return nil }
        let owner = parts.removeFirst()
        var name = parts.removeFirst()
        if name.hasSuffix(".git") { name.removeLast(4) }
        let ok = #"^[A-Za-z0-9._-]+$"#
        guard owner.range(of: ok, options: .regularExpression) != nil, name.range(of: ok, options: .regularExpression) != nil else { return nil }
        var branch: String?
        if parts.first == "tree", parts.count >= 2 { branch = parts.dropFirst().joined(separator: "/") }
        return (RemoteRepo(host: host, owner: owner, name: name), branch)
    }

    /// GitHub's compare page with the pull request filled in: needs no CLI and no token (board 8).
    public func compareURL(base: String, head: String, headOwner: String? = nil, title: String, body: String) -> URL {
        let h = headOwner.map { "\($0):\(head)" } ?? head
        var c = URLComponents(string: "https://\(host)/\(owner)/\(name)/compare/\(base)...\(h)")!
        c.queryItems = [.init(name: "expand", value: "1"), .init(name: "title", value: title), .init(name: "body", value: body)]
        return c.url!
    }
}

/// One file's change, from `git status --porcelain=v2`.
public struct FileChange: Equatable, Sendable {
    public enum Kind: String, Sendable { case changed, new, deleted, renamed, conflict }
    public var path: String       // relative to the repository's root
    public var kind: Kind
    public var staged: Bool
    public init(path: String, kind: Kind, staged: Bool) { self.path = path; self.kind = kind; self.staged = staged }
}

/// Where a repository stands: what `git status --porcelain=v2 --branch -z` says, plus the remote.
public struct RepoStatus: Equatable, Sendable {
    public var root: URL
    public var branch: String?          // nil when detached
    public var head: String?            // short commit
    public var upstream: String?        // e.g. origin/geoff/pricing-copy
    public var ahead = 0
    public var behind = 0
    public var changes: [FileChange] = []
    public var origin: RemoteRepo?
    public var defaultBranch: String?   // origin's HEAD, when known locally
    public var merging = false
    public var forkRemote: String?      // "fork" when Duo set one up (DL-149)

    public init(root: URL) { self.root = root }

    public var conflicts: [FileChange] { changes.filter { $0.kind == .conflict } }
    public var hasConflict: Bool { !conflicts.isEmpty }

    /// Parses `git status --porcelain=v2 --branch -z` output.
    public static func parse(porcelain: String, root: URL) -> RepoStatus {
        var s = RepoStatus(root: root)
        var fields = porcelain.split(separator: "\0", omittingEmptySubsequences: true).map(String.init)
        var i = 0
        while i < fields.count {
            let f = fields[i]
            if f.hasPrefix("# branch.oid ") {
                let oid = String(f.dropFirst(13)); s.head = oid == "(initial)" ? nil : String(oid.prefix(7))
            } else if f.hasPrefix("# branch.head ") {
                let h = String(f.dropFirst(14)); s.branch = h == "(detached)" ? nil : h
            } else if f.hasPrefix("# branch.upstream ") {
                s.upstream = String(f.dropFirst(18))
            } else if f.hasPrefix("# branch.ab ") {
                let ab = f.dropFirst(12).split(separator: " ")
                if ab.count == 2 { s.ahead = Int(ab[0].dropFirst()) ?? 0; s.behind = Int(ab[1].dropFirst()) ?? 0 }
            } else if f.hasPrefix("1 ") || f.hasPrefix("2 ") || f.hasPrefix("u ") {
                let cols = f.split(separator: " ", maxSplits: f.hasPrefix("1 ") ? 8 : (f.hasPrefix("2 ") ? 9 : 10), omittingEmptySubsequences: false)
                let xy = cols.count > 1 ? String(cols[1]) : ".."
                let path = cols.last.map(String.init) ?? ""
                let kind: FileChange.Kind
                if f.hasPrefix("u ") { kind = .conflict }
                else if f.hasPrefix("2 ") { kind = .renamed; i += 1 }   // -z: the original path follows as its own field
                else if xy.contains("D") { kind = .deleted }
                else if xy.first == "A" { kind = .new }
                else { kind = .changed }
                s.changes.append(FileChange(path: path, kind: kind, staged: xy.first != "."))
            } else if f.hasPrefix("? ") {
                s.changes.append(FileChange(path: String(f.dropFirst(2)), kind: .new, staged: false))
            }
            i += 1
        }
        fields.removeAll()
        return s
    }
}

public enum RepoProbe {
    /// The repository a folder is in (DL-157: any project inside a repo counts), compared by real paths (legacy BUG-204).
    public static func root(of folder: URL) -> URL? {
        let r = GitTool.git(["rev-parse", "--show-toplevel"], in: folder.resolvingSymlinksInPath(), timeout: 5)
        guard r.ok else { return nil }
        let p = r.out.trimmingCharacters(in: .whitespacesAndNewlines)
        return p.isEmpty ? nil : URL(fileURLWithPath: p)
    }

    /// Reads local state only: never touches the network.
    public static func status(of folder: URL) -> RepoStatus? {
        guard let root = root(of: folder) else { return nil }
        let r = GitTool.git(["status", "--porcelain=v2", "--branch", "-z", "--untracked-files=all"], in: root, timeout: 10)
        guard r.ok else { return nil }
        var s = RepoStatus.parse(porcelain: r.out, root: root)
        if let url = remoteURL(root, "origin") { s.origin = RemoteRepo.parse(url)?.repo }
        if remoteURL(root, "fork") != nil { s.forkRemote = "fork" }
        let d = GitTool.git(["symbolic-ref", "--quiet", "--short", "refs/remotes/origin/HEAD"], in: root, timeout: 5)
        if d.ok { s.defaultBranch = d.out.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "origin/", with: "") }
        s.merging = FileManager.default.fileExists(atPath: gitDir(root).appending(path: "MERGE_HEAD").path)
        return s
    }

    public static func remoteURL(_ root: URL, _ name: String) -> String? {
        // The configured URL, not `remote get-url`, which applies `insteadOf` rewrites.
        let r = GitTool.git(["config", "--get", "remote.\(name).url"], in: root, timeout: 5)
        let u = r.out.trimmingCharacters(in: .whitespacesAndNewlines)
        return r.ok && !u.isEmpty ? u : nil
    }

    public static func gitDir(_ root: URL) -> URL {
        let r = GitTool.git(["rev-parse", "--absolute-git-dir"], in: root, timeout: 5)
        let p = r.out.trimmingCharacters(in: .whitespacesAndNewlines)
        return r.ok && !p.isEmpty ? URL(fileURLWithPath: p) : root.appending(path: ".git")
    }
}
