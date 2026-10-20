import DuoControl
import DuoKit
import Foundation

// DL-229: the "Trust this folder" notice. The write touches Claude Code's own file, so these run on scratch copies only.
@MainActor func trustChecks(_ base: Fixture) throws {
    print("trust this folder: the line, the rule, the write (DL-229)")
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appending(path: "trust-checks-\(UUID().uuidString.prefix(8))")
    try fm.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: root) }

    // The reader
    let screen = ["❯ /fork build the thing", "", "  ⎿  Workspace not trusted. Run claude in /private/tmp/checkout once and accept the trust prompt, then retry.", "", "❯ "]
    check(TrustLine.read(lines: screen, cols: 120) == .init(path: "/private/tmp/checkout", forkLine: "/fork build the thing"), "the line gives the path and the /fork above it")
    let wrapped = ["> /fork", "  ⎿  Workspace not trusted. Run claude in /private/tmp/some/very/lo", "     ng/folder once and accept the trust prompt, then retry."]
    check(TrustLine.read(lines: wrapped, cols: 65)?.path == "/private/tmp/some/very/long/folder", "a path wrapped at the row's end is joined without a space")
    check(TrustLine.read(lines: ["  ⎿  Run `claude` in a folder that could not be resolved on disk"], cols: 80) == nil, "the could-not-be-resolved variant gets no notice")
    check(TrustLine.read(lines: ["  ⎿  The home directory is trusted one session at a time."], cols: 80) == nil, "the home-directory variant gets no notice")
    check(TrustLine.read(lines: ["❯ hello", "Hi"], cols: 80) == nil, "an ordinary screen gets none")

    // The rule
    let above: [String: Bool?] = ["/private/tmp": true, "/private/tmp/checkout": false]
    check(TrustRule.offer(linePath: "/private/tmp/checkout", sessionFolder: "/private/tmp/checkout", top: nil, entries: above) == .trust(path: "/private/tmp/checkout"), "the session's folder, false entry, trusted above: offered")
    check(TrustRule.offer(linePath: "/private/tmp/checkout", sessionFolder: "/private/tmp/checkout/api", top: "/private/tmp/checkout", entries: above) == .trust(path: "/private/tmp/checkout"), "the repository's top folder is offered too")
    check(TrustRule.offer(linePath: "/private/tmp/other", sessionFolder: "/private/tmp/checkout", top: nil, entries: above) == .runClaude(path: "/private/tmp/other"), "some other folder: OK-only bar")
    check(TrustRule.offer(linePath: "/private/tmp/checkout", sessionFolder: "/private/tmp/checkout", top: nil, entries: ["/private/tmp/checkout": false]) == .runClaude(path: "/private/tmp/checkout"), "nothing trusted above: OK-only bar")
    check(TrustRule.offer(linePath: "/private/tmp/checkout", sessionFolder: "/private/tmp/checkout", top: nil, entries: ["/private/tmp/checkout": true]) == .trusted, "already trusted: no bar")

    // The write: compare the parsed JSON before and after
    func scratch(_ name: String, _ text: String) throws -> URL {
        let dir = root.appending(path: name)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let f = dir.appending(path: ".claude.json")
        try Data(text.utf8).write(to: f)
        return f
    }
    func err(_ r: Result<Void, ClaudeTrust.Failure>) -> ClaudeTrust.Failure? { if case .failure(let e) = r { return e }; return nil }
    func parsed(_ f: URL) -> NSDictionary? { (try? JSONSerialization.jsonObject(with: Data(contentsOf: f))) as? NSDictionary }
    let path = "/private/tmp/checkout"
    let original = """
    {
      "numStartups": 12,
      "projects": {
        "/private/tmp": {
          "hasTrustDialogAccepted": true,
          "allowedTools": []
        },
        "/private/tmp/checkout": {
          "allowedTools": ["Bash"],
          "hasTrustDialogAccepted": false,
          "history": []
        }
      },
      "zeta": null,
      "alpha": {"keep": 1.50}
    }
    """
    let f1 = try scratch("flip", original)
    let before = parsed(f1)!
    check(err(ClaudeTrust.trust(path, file: f1)) == nil, "false flips to true")
    let after = parsed(f1)!
    let want = before.mutableCopy() as! NSMutableDictionary
    let projects = (want["projects"] as! NSDictionary).mutableCopy() as! NSMutableDictionary
    let entry = (projects[path] as! NSDictionary).mutableCopy() as! NSMutableDictionary
    entry["hasTrustDialogAccepted"] = true
    projects[path] = entry
    want["projects"] = projects
    check(after == want, "only that one key changed (parsed before and after)")
    let text = try String(contentsOf: f1, encoding: .utf8)
    check(text == original.replacingOccurrences(of: "\"hasTrustDialogAccepted\": false", with: "\"hasTrustDialogAccepted\": true"), "every other byte is as it was: order, spacing, 1.50")
    check(!fm.fileExists(atPath: f1.deletingLastPathComponent().appending(path: ".claude.json.lock").path), "the lock Duo made is gone")
    check((try fm.contentsOfDirectory(atPath: f1.deletingLastPathComponent().path)).sorted() == [".claude.json"], "no temp file is left")
    let again = err(ClaudeTrust.trust(path, file: f1)) == nil
    try check(again && (try String(contentsOf: f1, encoding: .utf8)) == text, "already true: nothing written")

    let f2 = try scratch("missing-entry", #"{"b":1,"projects":{"/x":{"hasTrustDialogAccepted":true}},"a":2}"#)
    check(err(ClaudeTrust.trust(path, file: f2)) == nil, "a missing entry is added")
    check(try String(contentsOf: f2, encoding: .utf8) == #"{"b":1,"projects":{"/x":{"hasTrustDialogAccepted":true},"\#(path)": {"hasTrustDialogAccepted": true}},"a":2}"#, "…with that key alone, the rest untouched")

    let f3 = try scratch("no-projects", "{\n  \"a\": 1\n}")
    check(err(ClaudeTrust.trust(path, file: f3)) == nil, "no projects key: it is made")
    check((parsed(f3)?["a"] as? Int) == 1 && (((parsed(f3)?["projects"] as? NSDictionary)?[path] as? NSDictionary)?["hasTrustDialogAccepted"] as? Bool) == true, "…and a stays")

    let f4 = try scratch("empty-entry", "{\n  \"projects\": {\n    \"\(path)\": {}\n  }\n}")
    check(err(ClaudeTrust.trust(path, file: f4)) == nil && ((parsed(f4)?["projects"] as? NSDictionary)?[path] as? NSDictionary)?["hasTrustDialogAccepted"] as? Bool == true, "an empty entry gets the key")

    let junk = "{\"projects\": {oops"
    let f5 = try scratch("junk", junk)
    try check(err(ClaudeTrust.trust(path, file: f5)) == .unreadable && (try String(contentsOf: f5, encoding: .utf8)) == junk, "invalid JSON is left alone")
    let f6 = try scratch("array", "[1,2]")
    check(err(ClaudeTrust.trust(path, file: f6)) == .unreadable, "a file that isn't an object is left alone")

    // Claude's lock: waited on, and never removed
    let f7 = try scratch("locked", original)
    let lock = f7.deletingLastPathComponent().appending(path: ".claude.json.lock")
    try fm.createDirectory(at: lock, withIntermediateDirectories: false)
    check(err(ClaudeTrust.trust(path, file: f7, wait: 0.2)) == .locked, "a held lock fails as locked")
    try check(fm.fileExists(atPath: lock.path) && (try String(contentsOf: f7, encoding: .utf8)) == original, "…the lock stays and the file is untouched")
    DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) { try? FileManager.default.removeItem(at: lock) }
    check(err(ClaudeTrust.trust(path, file: f7, wait: 3)) == nil, "a lock that clears is waited for")

    // Paths
    let real = root.appending(path: "real"), link = root.appending(path: "link")
    try fm.createDirectory(at: real, withIntermediateDirectories: true)
    try fm.createSymbolicLink(at: link, withDestinationURL: real)
    check(ClaudeTrust.realPath(link.path + "/") == ClaudeTrust.realPath(real.path), "the key is the real path, symlinks resolved, no trailing slash")
    check(ClaudeTrust.realPath("/tmp") == "/private/tmp", "/tmp is /private/tmp")
    let gitRoot = root.appending(path: "repo/sub")
    try fm.createDirectory(at: gitRoot, withIntermediateDirectories: true)
    _ = GitTool.git(["init", "-q"], in: root.appending(path: "repo"))
    check(ClaudeTrust.repositoryTop(of: gitRoot.path) == ClaudeTrust.realPath(root.appending(path: "repo").path), "the repository's top folder holds the key")
    check(ClaudeTrust.configFile(configDir: "/x/y").path == "/x/y/.claude.json", "CLAUDE_CONFIG_DIR names the file's folder")

    // The model: the notice's life on a session's tab (DL-229)
    let m = AppModel(fixture: base)
    let key = "tab-1"
    let entries: [String: Bool?] = ["/private/tmp": true, "/private/tmp/checkout": false]
    let read = TrustLine.Read(path: "/private/tmp/checkout", forkLine: "/fork x")
    m.applyTrustRead(key: key, read: read, sessionFolder: "/private/tmp/checkout") { entries }
    check(m.trustNotice(key)?.phase == .offer && m.trustNotice(key)?.folder == "checkout", "the line on a session's screen raises the offer bar")
    m.dismissTrustNotice(key)
    check(m.trustNotice(key) == nil && m.trustNotices[key] != nil, "Not Now hides it for the session")
    m.applyTrustRead(key: key, read: read, sessionFolder: "/private/tmp/checkout") { entries }
    check(m.trustNotice(key) == nil, "…while the same line is still on screen it stays hidden")
    m.applyTrustRead(key: key, read: nil, sessionFolder: "/private/tmp/checkout") { entries }
    m.applyTrustRead(key: key, read: read, sessionFolder: "/private/tmp/checkout") { entries }
    check(m.trustNotice(key)?.phase == .offer, "…and the next such line, once it had left, brings it back")
    m.applyTrustRead(key: key, read: read, sessionFolder: "/private/tmp/checkout") { ["/private/tmp/checkout": true] }
    check(m.trustNotices[key] == nil, "trusted some other way: the bar goes by itself")
    m.applyTrustRead(key: key, read: TrustLine.Read(path: "/private/tmp/elsewhere", forkLine: nil), sessionFolder: "/private/tmp/checkout") { entries }
    check(m.trustNotice(key)?.phase == .runClaude, "a folder Duo doesn't offer gets the OK-only bar")

    // The write through the model, on a scratch config only
    let cfg = root.appending(path: "model-config")
    try fm.createDirectory(at: cfg, withIntermediateDirectories: true)
    let file = cfg.appending(path: ".claude.json")
    try Data(#"{"projects":{"/private/tmp/checkout":{"hasTrustDialogAccepted":false}}}"#.utf8).write(to: file)
    setenv("CLAUDE_CONFIG_DIR", cfg.path, 1)
    defer { unsetenv("CLAUDE_CONFIG_DIR") }
    m.trustNotices[key] = TrustNotice(path: "/private/tmp/checkout", forkLine: "/fork x", phase: .offer, sessionFolder: "/private/tmp/checkout")
    var answer = ""
    m.writeTrust(key, source: "duo2") { answer = $0 }
    check(m.trustNotices[key]?.phase == .trusted && answer == "trusted /private/tmp/checkout", "the write changes the bar in place and says what it trusted")
    check(((parsed(file)?["projects"] as? NSDictionary)?["/private/tmp/checkout"] as? NSDictionary)?["hasTrustDialogAccepted"] as? Bool == true, "…in the scratch file")
    let lockDir = cfg.appending(path: ".claude.json.lock")
    try fm.createDirectory(at: lockDir, withIntermediateDirectories: false)
    try Data(#"{"projects":{"/private/tmp/checkout":{"hasTrustDialogAccepted":false}}}"#.utf8).write(to: file)
    m.trustNotices[key]?.phase = .offer
    m.writeTrust(key, source: "you") { answer = $0 }
    if case .failed(let why)? = m.trustNotices[key]?.phase { check(why.hasPrefix("another Claude is saving them"), "a held lock gives the failure bar with its reason") } else { check(false, "a held lock gives the failure bar") }
    check(m.trustNotices[key]?.canAsk == true, "…with Try Again")

    // duo2 can ask but not trust for itself
    let verb = DuoAction.all.first { $0.verb == "session trust-folder" }
    check(verb?.args == "<id>" && verb?.summary.contains("no --yes") == true, "duo2 session trust-folder takes an id and no --yes")
    check(DuoAction.all.contains { $0.verb == "session fork-again" }, "Fork Again has its verb")
}

