import DuoControl
import DuoKit
import DuoSearch
import Foundation

// The isolation guard (F-529, F-583, F-587, F-588, C-162): in a test context duo2 reaches only the
// instance it was told to, and refuses otherwise; an isolated instance reads only its own folders.
// Everything runs on decoys under /tmp: a fake "real" Application Support with a live socket, a
// test instance's folder, and a fake home whose ~/.claude holds a canary transcript.

/// Listens on `path` and answers "pong" to `token`, like `ControlServer`.
private final class Listener: @unchecked Sendable {
    let path: String
    private let fd: Int32
    init?(path: String, token: String) {
        self.path = path
        unlink(path)
        fd = socket(AF_UNIX, SOCK_STREAM, 0)
        var addr = sockaddr_un(); addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: addr.sun_path) else { return nil }
        withUnsafeMutableBytes(of: &addr.sun_path) { $0.copyBytes(from: bytes); $0[bytes.count] = 0 }
        let rc = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
        guard fd >= 0, rc == 0, listen(fd, 8) == 0 else { return nil }
        let fd = self.fd
        Thread.detachNewThread {
            while true {
                let c = accept(fd, nil, nil)
                if c < 0 { return }
                var buf = [UInt8](repeating: 0, count: 65536)
                let n = read(c, &buf, buf.count)
                let req = n > 0 ? try? JSONDecoder().decode(ControlRequest.self, from: Data(buf[0..<n])) : nil
                let ok = req?.token == token
                let reply = ControlResponse(ok: ok, output: ok ? "pong from \(path)" : "wrong token")
                var line = (try? JSONEncoder().encode(reply)) ?? Data(); line.append(UInt8(ascii: "\n"))
                _ = line.withUnsafeBytes { write(c, $0.baseAddress, $0.count) }
                close(c)
            }
        }
    }
    func stop() { close(fd); unlink(path) }
}

/// Runs with these variables set (nil: unset), then puts the process's environment back.
private func withEnv<T>(_ vars: [String: String?], _ body: () throws -> T) rethrows -> T {
    var saved: [String: String?] = [:]
    for (k, v) in vars {
        saved[k] = getenv(k).map { String(cString: $0) }
        if let v { setenv(k, v, 1) } else { unsetenv(k) }
    }
    defer { for (k, v) in saved { if let v { setenv(k, v, 1) } else { unsetenv(k) } } }
    return try body()
}

func isolationChecks() throws {
    print("isolation guard: duo2 reaches only the named instance; an isolated Duo reads only its own folders (F-529, F-583)")
    let fm = FileManager.default
    let root = "/tmp/duo-iso-\(UUID().uuidString.prefix(6))"
    defer { try? fm.removeItem(atPath: root) }
    let real = URL(fileURLWithPath: root + "/real"), inst = URL(fileURLWithPath: root + "/inst"), home = URL(fileURLWithPath: root + "/home")
    for d in [real.appending(path: "Duo"), inst.appending(path: "Duo"), home.appending(path: ".claude/projects/-canary")] {
        try fm.createDirectory(at: d, withIntermediateDirectories: true)
    }
    // The canary: a transcript in the fake account's own ~/.claude, which an isolated instance must never see.
    let canary = "duo-isolation-canary-\(UUID().uuidString.prefix(8))"
    try Data("{\"type\":\"user\",\"message\":{\"content\":\"\(canary)\"}}\n".utf8).write(to: home.appending(path: ".claude/projects/-canary/canary-session.jsonl"))

    guard let realDuo = Listener(path: real.path + "/Duo/duo.sock", token: "real-token"),
          let testDuo = Listener(path: inst.path + "/Duo/duo.sock", token: "inst-token") else {
        check(false, "decoy sockets listen"); return
    }
    defer { realDuo.stop(); testDuo.stop() }
    try ControlEndpoint(socket: realDuo.path, token: "real-token", pid: getpid()).write(to: real.appending(path: "Duo/endpoint.json"))
    let instFile = inst.appending(path: "Duo/endpoint.json")
    try ControlEndpoint(socket: testDuo.path, token: "inst-token", pid: getpid()).write(to: instFile)

    func outcome(_ env: [String: String]) -> String {
        do {
            guard let t = try Isolation.resolve(env, real: real) else { return "none" }
            if Isolation.inside(t.endpoint.socket, real.path) { return "REAL" }
            if Isolation.inside(t.endpoint.socket, inst.path) { return "inst" }
            return "other"
        } catch let r as Isolation.Refusal { return "refused: " + r.description } catch { return "error: \(error)" }
    }
    func refused(_ env: [String: String]) -> Bool { outcome(env).hasPrefix("refused") }
    let sv = "DUO_SOCKET", tv = "DUO_TOKEN", dv = "DUO_SUPPORT_DIR", iv = "DUO_ISOLATED"

    // 1. The user's own use is unchanged.
    check(!Isolation.isStrict([:], real: real) && outcome([:]) == "REAL", "no variables: the default Duo, as before")
    check(!Isolation.isStrict([sv: realDuo.path, tv: "real-token"], real: real) && outcome([sv: realDuo.path, tv: "real-token"]) == "REAL",
          "a terminal of the user's Duo (its own DUO_SOCKET/DUO_TOKEN): that Duo, as before")
    check(!Isolation.isStrict([dv: real.path], real: real), "DUO_SUPPORT_DIR naming the real folder (open-duo.sh) isn't a test context")

    // 2. A test context reaches the named instance only.
    check(outcome([iv: "1", dv: inst.path]) == "inst", "DUO_ISOLATED=1 + DUO_SUPPORT_DIR: that instance")
    check(outcome([dv: inst.path]) == "inst", "DUO_SUPPORT_DIR alone: that instance, not the default Duo")
    check(outcome([sv: testDuo.path, tv: "inst-token"]) == "inst", "the instance's DUO_SOCKET/DUO_TOKEN: that instance")
    check(outcome([iv: "1", dv: inst.path, sv: testDuo.path, tv: "inst-token"]) == "inst", "all four, consistent: that instance")
    check((try? Isolation.resolve([dv: inst.path], real: real))??.source == Isolation.isolatedSource, "an isolated target is marked so it never retries elsewhere")
    check((try? Isolation.resolve([sv: testDuo.path, tv: "inst-token"], real: real))??.support?.path == inst.path, "the target names the instance's support folder")

    // 3. Every mistake refuses, never the default Duo.
    check(refused([iv: "1"]), "DUO_ISOLATED=1 naming no instance: refused")
    check(refused([sv: "", tv: ""]), "DUO_SOCKET and DUO_TOKEN empty (the 2026-11-03 sweep): refused")
    check(refused([sv: testDuo.path]), "only DUO_SOCKET: refused")
    check(refused([tv: "inst-token"]), "only DUO_TOKEN: refused")
    check(refused([dv: ""]), "DUO_SUPPORT_DIR empty: refused")
    check(refused([iv: "1", sv: realDuo.path, tv: "real-token"]), "DUO_ISOLATED=1 with the real Duo's socket: refused")
    check(refused([iv: "1", dv: real.path]), "DUO_ISOLATED=1 with the real support folder: refused")
    check(refused([dv: inst.path, sv: realDuo.path, tv: "real-token"]), "a socket outside DUO_SUPPORT_DIR (inherited from the user's terminal): refused")
    check(refused([sv: testDuo.path, tv: "wrong"]), "a token that doesn't match the instance's endpoint.json: refused")
    check(refused([sv: root + "/gone/Duo/duo.sock", tv: "x"]), "a socket that doesn't exist: refused")
    check(refused([dv: root + "/nothing"]), "a support folder with no endpoint.json: refused")
    check(refused([iv: "yes", dv: real.path]) && !Isolation.flag([iv: "0"]), "DUO_ISOLATED is on for any value but empty or 0")

    // 4. An endpoint deleted (or replaced) mid-run.
    check(outcome([dv: inst.path]) == "inst", "mid-run: reachable before")
    try fm.removeItem(at: instFile)
    check(refused([dv: inst.path]), "mid-run: endpoint.json deleted, DUO_SUPPORT_DIR: refused")
    check(refused([sv: testDuo.path, tv: "inst-token"]), "mid-run: endpoint.json deleted, DUO_SOCKET: refused")
    try ControlEndpoint(socket: testDuo.path, token: "inst-token", pid: 999_999).write(to: instFile)
    check(refused([dv: inst.path]) && refused([sv: testDuo.path, tv: "inst-token"]), "an endpoint whose process is gone: refused")
    try ControlEndpoint(socket: realDuo.path, token: "real-token", pid: getpid()).write(to: instFile)
    check(refused([dv: inst.path]), "an endpoint.json naming a socket outside its folder: refused")
    try ControlEndpoint(socket: testDuo.path, token: "inst-token", pid: getpid()).write(to: instFile)

    // 5. Sending never crosses to another Duo.
    let req = ControlRequest(token: "", command: "ping", args: [])
    let realFile = real.appending(path: "Duo/endpoint.json")
    let deadInst = ControlEndpoint(socket: inst.path + "/Duo/dead.sock", token: "inst-token", pid: 0)
    check((try? ControlClient.send(req, via: deadInst, source: Isolation.isolatedSource, file: realFile)) == nil, "an isolated target's dead socket: the error stands, no retry")
    check((try? ControlClient.send(req, via: deadInst, source: "environment", file: realFile)) == nil, "an env endpoint never retries another folder's endpoint file")
    check((try? ControlClient.send(req, via: ControlEndpoint(socket: real.path + "/Duo/old.sock", token: "old", pid: 0), source: "environment", file: realFile))?.output.contains(real.path) == true,
          "the user's own terminals still retry their own Duo's endpoint file (C-80)")

    // 6. Confinement: an isolated instance's Claude config, archive and index are its own.
    let none = Isolation.confinement([:], support: inst, real: real, home: home)
    let standIn = inst.path + "/Duo/" + Isolation.standInConfig
    check((none.changes["CLAUDE_CONFIG_DIR"] ?? nil) == standIn, "no CLAUDE_CONFIG_DIR given: the stand-in inside the instance's folder")
    check((none.changes["DUO_ISOLATED"] ?? nil) == "1", "children inherit DUO_ISOLATED=1")
    let given = Isolation.confinement(["CLAUDE_CONFIG_DIR": root + "/cfg"], support: inst, real: real, home: home)
    check(given.changes["CLAUDE_CONFIG_DIR"] == nil, "a given CLAUDE_CONFIG_DIR is kept")
    let realGiven = Isolation.confinement(["CLAUDE_CONFIG_DIR": home.path + "/.claude"], support: inst, real: real, home: home)
    check(realGiven.notes.contains { $0.contains("Q-425") }, "a given CLAUDE_CONFIG_DIR that is the real ~/.claude is called out")
    let roots = Isolation.confinement(["DUO_SEARCH_ROOT": real.path + "/Duo/search", "DUO_ARCHIVE_ROOT": real.path + "/Duo/archive"], support: inst, real: real, home: home)
    check(roots.changes.keys.contains("DUO_SEARCH_ROOT") && roots.changes["DUO_SEARCH_ROOT"]! == nil
          && roots.changes["DUO_ARCHIVE_ROOT"]! == nil, "archive and search overrides into the real folder are dropped")
    check((try? Isolation.localSupport([iv: "1"], real: real)) == nil, "local verbs in a test context with no folder: refused")
    check((try? Isolation.localSupport([sv: testDuo.path, tv: "inst-token"], real: real))?.path == inst.path, "local verbs follow the instance's socket to its folder")
    check((try? Isolation.localSupport([iv: "1", dv: real.path], real: real)) == nil, "local verbs never take the real folder")

    // 7. The canary: with the account's ~/.claude as config, Duo's readers find it; confined, they can't.
    let sanity = withEnv(["CLAUDE_CONFIG_DIR": home.path + "/.claude"]) { ClaudeStorage.transcript(sessionId: "canary-session", cwd: "/canary") }
    check(sanity != nil, "canary: visible through the account's ~/.claude (sanity)")
    try withEnv(["CLAUDE_CONFIG_DIR": standIn, "DUO_SUPPORT_DIR": inst.path, "DUO_ARCHIVE_ROOT": nil, "DUO_SEARCH_ROOT": nil]) {
        try fm.createDirectory(atPath: standIn, withIntermediateDirectories: true)
        check(ClaudeStorage.transcript(sessionId: "canary-session", cwd: "/canary") == nil, "canary: an isolated instance's transcript lookup can't see it")
        check(!Isolation.inside(ClaudeStorage.root.path, home.path) && Isolation.inside(ClaudeStorage.projects.path, inst.path), "Claude's projects folder is the instance's")
        check(Inventory.build(now: Date()).buckets.isEmpty, "canary: the inventory of Claude's buckets is empty, not the account's")
        check(Isolation.inside(SessionArchive.root.path, inst.path), "the session archive is the instance's")
        check(Isolation.inside(SearchPaths.index.path, inst.path), "the search index is the instance's")
        check(Isolation.inside(ClaudeTrust.configFile().path, inst.path), "Claude's trust file (.claude.json, its project list) is the instance's")
        check(Isolation.inside(LegacyDuo.claudeDir.path, inst.path), "legacy Duo's ~/.claude is the instance's")
        var leaked = false
        for case let u as URL in fm.enumerator(at: inst, includingPropertiesForKeys: nil) ?? FileManager.DirectoryEnumerator() {
            if let t = try? String(contentsOf: u, encoding: .utf8), t.contains(canary) { leaked = true }
        }
        check(!leaked, "canary: nothing under the instance's folders holds it")
        // What `confineLaunch` setenv's reaches the terminals it starts (Claude, duo2 in them).
        let child = withEnv(["DUO_ISOLATED": "1"]) { ChildEnvironment.make(sessionID: nil) }
        check(child.contains("CLAUDE_CONFIG_DIR=\(standIn)") && child.contains("DUO_ISOLATED=1") && child.contains("DUO_SUPPORT_DIR=\(inst.path)"),
              "a terminal of the isolated instance inherits its Claude config, DUO_ISOLATED=1 and its support folder")
    }

    // 8. Every script that launches Duo or drives duo2 sets DUO_ISOLATED=1 (open-duo.sh is Geoff's own Duo).
    var bare: [String] = []
    let launches = try NSRegularExpression(pattern: #"MacOS/Duo\b|Duo\.app"? --args|Duo\.app" --args|\bduo2\b.*\b(ping|status|search|doctor|director)\b|DUO_SOCKET="#)
    for dir in ["scripts", "scripts/acceptance"] {
        for name in (try? fm.contentsOfDirectory(atPath: repoRoot().appending(path: dir).path)) ?? [] where name.hasSuffix(".sh") && name != "open-duo.sh" && name != "bundle.sh" {
            let text = (try? String(contentsOf: repoRoot().appending(path: "\(dir)/\(name)"), encoding: .utf8)) ?? ""
            let code = text.split(separator: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("#") }.joined(separator: "\n")
            if launches.firstMatch(in: code, range: NSRange(code.startIndex..., in: code)) != nil, !code.contains("DUO_ISOLATED=1") { bare.append("\(dir)/\(name)") }
        }
    }
    check(bare.isEmpty, "every script that launches Duo or runs duo2 sets DUO_ISOLATED=1\(bare.isEmpty ? "" : ": " + bare.joined(separator: ", "))")

    // 9. DuoChecks itself runs on a support folder of its own (F-588).
    check(Isolation.checksSupport([:], real: real) == nil && Isolation.checksSupport(["DUO_SUPPORT_DIR": real.path], real: real) == nil
          && Isolation.checksSupport(["DUO_SUPPORT_DIR": real.path + "/Duo"], real: real) == nil, "DuoChecks never takes the real support folder (unset, or named)")
    check(Isolation.checksSupport(["DUO_SUPPORT_DIR": inst.path], real: real) == inst.path, "…and keeps a given isolated one")
    check(Isolation.inside(SupportFolder.duo.path, checksSupportDir) && SupportFolder.isIsolated, "this run's support folder is its own (\(checksSupportDir))")
    DuoLog.write(checksCanary)
    let realLog = SupportFolder.real.appending(path: "Duo/logs/duo.log")
    let mine = (try? String(contentsOf: SupportFolder.duo.appending(path: "logs/duo.log"), encoding: .utf8)) ?? ""
    let theirs = (try? String(contentsOf: realLog, encoding: .utf8)) ?? ""
    check(mine.contains(checksCanary) && !theirs.contains("duochecks canary \(getpid()) "), "canary: Duo's log line from this run is in its folder, not the real duo.log")

    // 10. The real duo2, as a subprocess: refusals exit 64 and say why; the named instance answers.
    let duo2 = repoRoot().appending(path: ".build/debug/duo2")
    guard fm.isExecutableFile(atPath: duo2.path) else { print("  – duo2 not built (.build/debug/duo2): subprocess cases skipped"); return }
    func run(_ vars: [String: String], _ args: [String]) -> (Int32, String) {
        let p = Process(); p.executableURL = duo2; p.arguments = args
        var e = ProcessInfo.processInfo.environment
        for k in [sv, tv, dv, iv, "DUO_SESSION_ID", "CLAUDE_CODE_SESSION_ID", "DUO_ARCHIVE_ROOT", "DUO_SEARCH_ROOT"] { e.removeValue(forKey: k) }
        e.merge(vars) { $1 }
        p.environment = e
        let out = Pipe(); p.standardOutput = out; p.standardError = out
        guard (try? p.run()) != nil else { return (-1, "") }
        let data = out.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
        return (p.terminationStatus, String(decoding: data, as: UTF8.self))
    }
    let a = run([iv: "1"], ["status"])
    check(a.0 == 64 && a.1.contains("refused"), "duo2 with DUO_ISOLATED=1 and no instance: exit 64, refused")
    let b = run([sv: "", tv: ""], ["status"])
    check(b.0 == 64 && b.1.contains("empty"), "duo2 with DUO_SOCKET/DUO_TOKEN empty: exit 64, refused")
    let c = run([iv: "1", sv: root + "/gone/Duo/duo.sock", tv: "x"], ["director", "status"])
    check(c.0 == 64, "duo2 director status (an offline verb) with a dead test socket: refused, not run offline")
    let d = run([iv: "1"], ["search", canary])
    check(d.0 == 64 && !d.1.contains(canary), "duo2 search in a test context with no folder: refused before reading any index")
    let h = run([iv: "1"], ["help"])
    check(h.0 == 0, "duo2 help needs no instance")
}
