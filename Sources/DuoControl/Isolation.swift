import Foundation

/// Keeping tests away from the user's own Duo (F-529, F-583, F-587, F-588, C-162).
///
/// Two halves:
/// - **duo2 picks only the instance it was told to.** In a test context (`DUO_ISOLATED=1`, or
///   `DUO_SUPPORT_DIR` naming another folder, or a `DUO_SOCKET` outside the real support folder, or
///   any of the three set but blank, or only one of `DUO_SOCKET`/`DUO_TOKEN`) it uses only the
///   endpoint those name, checks it against that folder's `endpoint.json`, and refuses (exit 64)
///   instead of falling back to the default Duo, the endpoint file, or the offline verbs. The
///   user's own use (no variables, or the ones the user's Duo gives its terminals) is unchanged.
/// - **An isolated Duo reads only its own folders.** `confineLaunch` (at the app's launch) and
///   `confineProcess` (in duo2) point Claude's config at the given `CLAUDE_CONFIG_DIR`, or a
///   stand-in inside the instance's support folder, and drop archive and search overrides that
///   lead into the real support folder. Every reader of `~/.claude` goes through
///   `CLAUDE_CONFIG_DIR` (`ClaudeStorage`, `ClaudeTrust`, `LegacyDuo`, the search indexer,
///   `ClientCaps`), so one variable confines them all, and the instance's terminals inherit it.
public enum Isolation {
    public static let variable = "DUO_ISOLATED"
    public static let configVariable = "CLAUDE_CONFIG_DIR"
    /// The stand-in for `~/.claude` inside an isolated instance's Duo folder.
    public static let standInConfig = "claude-config"
    static let rootOverrides = ["DUO_ARCHIVE_ROOT", "DUO_SEARCH_ROOT"]

    /// Why duo2 refused to pick an instance. Never followed by a fallback to the default Duo.
    public struct Refusal: Error, CustomStringConvertible, Equatable {
        public var description: String
        public init(_ d: String) { description = d }
    }

    /// The instance duo2 talks to, and the Application Support stand-in its local verbs read.
    public struct Target: Equatable {
        public var endpoint: ControlEndpoint
        public var source: String
        /// Set in a test context: what `DUO_SUPPORT_DIR` is (or would be) for this instance.
        public var support: URL?
    }

    /// `ControlClient.send` retries the endpoint file only for this source's opposite ("environment");
    /// an isolated target never retries anything (C-80's retry could reach the user's Duo).
    public static let isolatedSource = "isolated"

    // MARK: Paths

    static func norm(_ p: String) -> String {
        URL(fileURLWithPath: p).standardizedFileURL.resolvingSymlinksInPath().path
    }
    /// Whether `path` is `folder` or inside it, after symlinks (/tmp is /private/tmp).
    public static func inside(_ path: String, _ folder: String) -> Bool {
        let p = norm(path), f = norm(folder)
        return p == f || p.hasPrefix(f.hasSuffix("/") ? f : f + "/")
    }
    static func blank(_ v: String?) -> Bool { v.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? false }

    /// `DUO_ISOLATED` is on when set to anything but empty or "0".
    public static func flag(_ env: [String: String]) -> Bool {
        guard let v = env[variable]?.trimmingCharacters(in: .whitespaces) else { return false }
        return !v.isEmpty && v != "0"
    }

    // MARK: duo2: which instance

    /// Whether duo2 runs in a test context, where only the named instance will do.
    public static func isStrict(_ env: [String: String], real: URL = SupportFolder.real) -> Bool {
        if flag(env) { return true }
        let s = env[ControlEndpoint.socketVariable], t = env[ControlEndpoint.tokenVariable], d = env[SupportFolder.variable]
        if blank(s) || blank(t) || blank(d) || (s == nil) != (t == nil) { return true }
        if let d, norm(d) != norm(real.path) { return true }
        if let s, !inside(s, real.appending(path: "Duo").path) { return true }
        return false
    }

    /// The endpoint files in a Duo folder: `endpoint.json` first, then private ones (C-18).
    static func endpointFiles(in duo: URL) -> [(URL, ControlEndpoint)] {
        let fm = FileManager.default
        var urls = [duo.appending(path: "endpoint.json")]
        let names = ((try? fm.contentsOfDirectory(atPath: duo.path)) ?? []).filter { $0.hasPrefix("endpoint-") && $0.hasSuffix(".json") }.sorted()
        urls += names.map { duo.appending(path: $0) }
        return urls.compactMap { u in
            guard let d = try? Data(contentsOf: u), let e = try? JSONDecoder().decode(ControlEndpoint.self, from: d) else { return nil }
            return (u, e)
        }
    }

    static func alive(_ pid: Int32) -> Bool { pid > 0 && kill(pid, 0) == 0 }

    /// Which instance duo2 reaches. Nil only outside a test context when no Duo is running (the
    /// old behaviour: the offline verbs may run). In a test context it returns the named instance
    /// or throws a `Refusal`; it never reaches the default Duo.
    public static func resolve(_ env: [String: String] = ProcessInfo.processInfo.environment,
                               real: URL = SupportFolder.real) throws -> Target? {
        let sv = ControlEndpoint.socketVariable, tv = ControlEndpoint.tokenVariable, dv = SupportFolder.variable
        guard isStrict(env, real: real) else {
            if let s = env[sv], let t = env[tv], !s.isEmpty, !t.isEmpty {
                return Target(endpoint: ControlEndpoint(socket: s, token: t, pid: 0), source: "environment")
            }
            return ControlEndpoint.fileEndpoint(real.appending(path: "Duo/endpoint.json")).map { Target(endpoint: $0.0, source: $0.source) }
        }
        let s = env[sv], t = env[tv], d = env[dv]
        try checkNames(env)
        let realDuo = real.appending(path: "Duo")
        var duo: URL?
        if let d {
            if norm(d) == norm(real.path) || inside(d, realDuo.path) {
                throw Refusal("\(dv) is the real support folder (\(real.path)) in a test context (\(variable)=1): duo2 won't reach the user's Duo.")
            }
            duo = URL(fileURLWithPath: d).appending(path: "Duo")
        }
        if let s, let t {
            if inside(s, realDuo.path) {
                throw Refusal("\(sv) (\(s)) is the user's own Duo, in a test context: refusing. Point it at the test instance's socket.")
            }
            if let duo, !inside(s, duo.path) {
                throw Refusal("\(sv) (\(s)) is outside \(dv)'s Duo folder (\(duo.path)): the two name different instances. Take both from the test instance's endpoint.json.")
            }
            let folder = duo ?? URL(fileURLWithPath: s).deletingLastPathComponent()
            guard FileManager.default.fileExists(atPath: s) else {
                throw Refusal("\(sv) names \(s), which doesn't exist: that instance quit, or its folder was deleted. duo2 won't fall back to the default Duo.")
            }
            let files = endpointFiles(in: folder)
            guard !files.isEmpty else {
                throw Refusal("no endpoint.json in \(folder.path) (deleted mid-run?), so duo2 can't confirm \(sv) is that instance's. Refusing.")
            }
            guard let match = files.first(where: { norm($0.1.socket) == norm(s) && $0.1.token == t }) else {
                throw Refusal("\(sv)/\(tv) don't match \(folder.path)'s endpoint.json (another run reused the folder, or the instance restarted). Refusing; take both from the current endpoint.json.")
            }
            guard alive(match.1.pid) else {
                throw Refusal("the instance in \(match.0.path) (pid \(match.1.pid)) isn't running. duo2 won't fall back to the default Duo.")
            }
            return Target(endpoint: ControlEndpoint(socket: s, token: t, pid: match.1.pid), source: isolatedSource,
                          support: folder.deletingLastPathComponent())
        }
        guard let duo else {
            throw Refusal("\(variable)=1 but nothing names the test instance: set \(dv) to its support folder, or \(sv) and \(tv) from its endpoint.json. duo2 won't use the default Duo.")
        }
        let files = endpointFiles(in: duo)
        guard !files.isEmpty else {
            throw Refusal("no endpoint.json in \(duo.path): the test instance isn't running there (or the file was deleted mid-run). duo2 won't fall back to the default Duo.")
        }
        for (u, e) in files where !inside(e.socket, duo.path) {
            throw Refusal("\(u.path) names a socket outside its own folder (\(e.socket)). Refusing.")
        }
        let live = files.filter { alive($0.1.pid) && FileManager.default.fileExists(atPath: $0.1.socket) }
        guard let pick = live.first else {
            throw Refusal("the instance in \(duo.path) isn't running (its endpoint's process or socket is gone). duo2 won't fall back to the default Duo.")
        }
        return Target(endpoint: pick.1, source: isolatedSource, support: duo.deletingLastPathComponent())
    }

    /// The Application Support stand-in duo2's local verbs (search, doctor, legacy) read in a
    /// test context, without needing the instance to be running. Throws when it would be the real one.
    /// Blank variables, or only one of DUO_SOCKET/DUO_TOKEN: both would reach the default Duo.
    static func checkNames(_ env: [String: String]) throws {
        let sv = ControlEndpoint.socketVariable, tv = ControlEndpoint.tokenVariable, dv = SupportFolder.variable
        let s = env[sv], t = env[tv]
        for (name, v) in [(sv, s), (tv, t), (dv, env[dv])] where blank(v) {
            throw Refusal("\(name) is set but empty, so duo2 won't guess an instance (it would reach the default Duo). Set \(sv) and \(tv) from the test instance's endpoint.json, or \(dv) to its folder.")
        }
        if (s == nil) != (t == nil) {
            throw Refusal("only \(s == nil ? tv : sv) is set; without \(s == nil ? sv : tv) duo2 would reach the default Duo. Set both from the test instance's endpoint.json.")
        }
    }

    public static func localSupport(_ env: [String: String], real: URL = SupportFolder.real) throws -> URL {
        try checkNames(env)
        if let d = env[SupportFolder.variable], !blank(d) {
            if norm(d) == norm(real.path) || inside(d, real.appending(path: "Duo").path) {
                throw Refusal("\(SupportFolder.variable) is the real support folder in a test context: refusing.")
            }
            return URL(fileURLWithPath: d)
        }
        if let s = env[ControlEndpoint.socketVariable], !blank(s), !inside(s, real.appending(path: "Duo").path) {
            let duo = URL(fileURLWithPath: s).deletingLastPathComponent()
            guard duo.lastPathComponent == "Duo" else {
                throw Refusal("\(ControlEndpoint.socketVariable) (\(s)) isn't in a Duo support folder (<folder>/Duo/), so duo2 can't tell which folder is the instance's. Set \(SupportFolder.variable) too.")
            }
            return duo.deletingLastPathComponent()
        }
        throw Refusal("a test context (\(variable)=1) with no \(SupportFolder.variable) or \(ControlEndpoint.socketVariable): duo2 won't read the user's own index, archive or settings.")
    }

    // MARK: DuoChecks

    /// The support folder a DuoChecks run uses: the given `DUO_SUPPORT_DIR` if it is isolated (not
    /// the real one), else nil: the run makes a temporary one of its own (director, 2026-11-04: its
    /// trust and drop lines had reached the real `logs/duo.log`). Never the real folder.
    public static func checksSupport(_ env: [String: String], real: URL = SupportFolder.real) -> String? {
        guard let d = env[SupportFolder.variable], !blank(d), SupportFolder.isIsolated(given: d, real: real),
              !inside(d, real.appending(path: "Duo").path) else { return nil }
        return d
    }

    // MARK: Confining an isolated process

    /// What to change in an isolated process's environment so it reads only its own folders:
    /// `CLAUDE_CONFIG_DIR` (the given one, else the stand-in in `<support>/Duo`), `DUO_ISOLATED=1`,
    /// `DUO_SUPPORT_DIR`, and archive/search overrides that lead into the real support folder
    /// removed (nil values). Pure, for DuoChecks.
    public static func confinement(_ env: [String: String], support: URL, real: URL = SupportFolder.real,
                                   home: URL = FileManager.default.homeDirectoryForCurrentUser) -> (changes: [String: String?], notes: [String]) {
        var changes: [String: String?] = [:], notes: [String] = []
        changes[variable] = "1"
        changes[SupportFolder.variable] = support.path
        let realDuo = real.appending(path: "Duo").path
        for k in rootOverrides {
            if let v = env[k], !v.isEmpty, inside(v, realDuo) {
                changes[k] = .some(nil)
                notes.append("ignoring \(k)=\(v): it is in the user's own support folder")
            }
        }
        if let c = env[configVariable], !blank(c) {
            if inside(c, home.appending(path: ".claude").path) {
                notes.append("\(configVariable)=\(c) is the account's real Claude folder: sessions here read and write the user's own transcripts (Q-425)")
            }
        } else {
            changes[configVariable] = support.appending(path: "Duo/\(standInConfig)").path
            notes.append("no \(configVariable) given; Claude's config is \(support.path)/Duo/\(standInConfig), not ~/.claude")
        }
        return (changes, notes)
    }

    /// Applies `confinement` to this process with setenv/unsetenv, and makes the stand-in folder.
    @discardableResult
    public static func apply(_ c: (changes: [String: String?], notes: [String])) -> [String] {
        for (k, v) in c.changes {
            if let v { setenv(k, v, 1) } else { unsetenv(k) }
        }
        if let dir = c.changes[configVariable] ?? nil {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        }
        return c.notes
    }

    /// At the app's launch, after `SupportFolder.prepareForLaunch`: an isolated instance (any
    /// support folder but the real one) reads only its own folders and the given Claude config,
    /// and everything it starts (terminals, Claude, duo2) inherits that and `DUO_ISOLATED=1`.
    public static func confineLaunch() {
        guard SupportFolder.isIsolated else { return }
        let notes = apply(confinement(ProcessInfo.processInfo.environment, support: SupportFolder.applicationSupport))
        for n in notes { FileHandle.standardError.write(Data("Duo: isolated: \(n) (F-583)\n".utf8)) }
    }

    /// In duo2, before any verb: in a test context, local verbs read the instance's folders only.
    /// Throws when no folder but the real one is named.
    public static func confineProcess(_ env: [String: String] = ProcessInfo.processInfo.environment) throws {
        guard isStrict(env) else { return }
        let support = try localSupport(env)
        apply(confinement(env, support: support))
    }
}
