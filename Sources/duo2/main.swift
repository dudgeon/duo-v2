import DuoControl
import DuoSearch
import Foundation

// `duo2` (DL-37): the command line for the Duo app. Coexists with legacy `duo` (DL-16).

let argv = Array(CommandLine.arguments.dropFirst())
let env = ProcessInfo.processInfo.environment

func fail(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data("duo2: \(message)\n".utf8))
    exit(code)
}

// The verbs are the action registry (DL-72): two-word verbs ("file rename") first, then one word.
guard let (action, parsed) = DuoAction.resolve(argv.isEmpty ? ["help"] : argv) else {
    fail("unknown command '\(argv.prefix(2).joined(separator: " "))'. Run `duo2 help`.", code: 64)
}
var rest = parsed
// `--stdin`: the argument is whatever is piped in (JSON for `doc edit`).
if let i = rest.firstIndex(of: "--stdin") {
    rest[i] = String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)
}
let args = [action.verb] + rest   // what the local verbs below read (args[0] is the verb)

switch action.id {
case .search, .searchStatus:
    exit(runSearch(action.verb, rest))
case .help:
    if rest.first == "--markdown" { print(DuoAction.markdown(), terminator: "") } else { print(DuoAction.help(family: rest.first), terminator: "") }
case .legacy:
    let sub = args.dropFirst().first
    let backups = ControlEndpoint.file.deletingLastPathComponent().appending(path: "backups")
    switch sub {
    case "disable":
        guard args.contains("--yes") else { fail("this changes ~/.claude (after a backup). Run `duo2 legacy disable --yes` to go ahead.", code: 64) }
        guard !LegacyDuo.detect().isEmpty else { print("Nothing of legacy Duo's to disable."); exit(0) }
        do {
            let b = try LegacyDuo.disable(backupRoot: backups)
            print("Disabled legacy Duo's instructions. Backup: \(b.path)\nUndo with: duo2 legacy restore \"\(b.path)\"")
        } catch { fail("\(error)") }
    case "restore":
        guard let path = args.dropFirst(2).first else { fail("usage: duo2 legacy restore <backup folder>", code: 64) }
        do { try LegacyDuo.restore(from: URL(fileURLWithPath: path)); print("Restored from \(path).") } catch { fail("\(error)") }
    default:
        let found = LegacyDuo.detect()
        if found.isEmpty { print("No legacy Duo instructions in \(LegacyDuo.claudeDir.path).") }
        else {
            print("Legacy Duo installed these into \(LegacyDuo.claudeDir.path); they load into every Claude session, Duo v2's too:")
            for f in found { print("  - \(f.what): \(f.path)") }
            print("To turn them off (everything is backed up first, and can be restored): duo2 legacy disable --yes")
        }
    }
case .compose:
    // Claude Code runs this as $EDITOR / $VISUAL (chat mode's composer, F-104): a hand-over from
    // Duo goes into Claude's prompt file; anything else opens the user's own editor.
    let env = ProcessInfo.processInfo.environment
    guard let file = rest.last else { fail("usage: duo2 compose <file>", code: 64) }
    let outcome = ChatCompose.take(file: URL(fileURLWithPath: file), dir: env[ChatCompose.dirVariable].map { URL(fileURLWithPath: $0) },
                                   session: env["DUO_SESSION_ID"])
    if outcome != .notOurs { exit(0) }
    let editor = ChatCompose.userEditorCommand(env)
    let argv = ["/bin/sh", "-c", editor + " \"$@\"", "sh"] + rest
    let cargs = argv.map { strdup($0) } + [nil]
    execv("/bin/sh", cargs)
    fail("couldn't open \(editor)")
case .hook where rest.first == "context":
    // SessionStart and UserPromptSubmit in Duo's sessions (DL-116): the project's brief (ENH-16)
    // and the task(s) the session is attributed to, in full at start (startup, resume, clear,
    // compact) and, on a prompt, what changed since Duo last told it. Duo works out the text; this wraps it as the hook's
    // additionalContext. Nothing to say, or Duo out of reach: no output, exit 0, so the prompt
    // always goes through (exit 2 would block it).
    guard let hook = (try? JSONSerialization.jsonObject(with: FileHandle.standardInput.readDataToEndOfFile())) as? [String: Any],
          let name = hook["hook_event_name"] as? String, ["SessionStart", "UserPromptSubmit"].contains(name),
          let sid = (hook["session_id"] as? String) ?? env["CLAUDE_CODE_SESSION_ID"],
          let (endpoint, _) = ControlEndpoint.discover() else { exit(0) }
    var a = [sid, "--hook", name == "SessionStart" ? "start" : "prompt", "--pid", String(getppid())]
    if let source = hook["source"] as? String { a += ["--source", source] }
    if let origin = env["DUO_SESSION_ID"] { a += ["--origin", origin] }
    guard let r = try? ControlClient.send(ControlRequest(token: endpoint.token, command: "session task", args: a, session: sid,
                                                         cwd: (hook["cwd"] as? String) ?? FileManager.default.currentDirectoryPath),
                                          socket: endpoint.socket, timeout: 8),
          r.ok, !r.output.isEmpty else { exit(0) }
    let out: [String: Any] = ["hookSpecificOutput": ["hookEventName": name, "additionalContext": r.output]]
    FileHandle.standardOutput.write((try? JSONSerialization.data(withJSONObject: out)) ?? Data())
    exit(0)
case .hook:
    // PreToolUse for Edit, MultiEdit and Write in Duo's sessions (DL-78). A document open in
    // Duo's editor gets the change through the editor (highlighted, merged with the user's
    // unsaved text) and the direct write is declined with a reason that says it's done. Anything
    // else, or any failure to reach Duo, lets the tool run as usual (exit 0, no output).
    guard rest.first == "pre-edit",
          let hook = (try? JSONSerialization.jsonObject(with: FileHandle.standardInput.readDataToEndOfFile())) as? [String: Any],
          let tool = hook["tool_name"] as? String, let input = hook["tool_input"] as? [String: Any],
          let path = input["file_path"] as? String, let (endpoint, _) = ControlEndpoint.discover() else { exit(0) }
    var edit: [String: Any] = ["file_path": path]
    switch tool {
    case "Edit": for k in ["old_string", "new_string", "replace_all"] { edit[k] = input[k] }
    case "MultiEdit": edit["edits"] = input["edits"]
    case "Write": edit["content"] = input["content"]
    default: exit(0)
    }
    guard let json = try? JSONSerialization.data(withJSONObject: edit),
          let r = try? ControlClient.send(ControlRequest(token: endpoint.token, command: "doc edit", args: [String(decoding: json, as: UTF8.self)],
                                                         session: env["CLAUDE_CODE_SESSION_ID"] ?? env["DUO_SESSION_ID"], cwd: FileManager.default.currentDirectoryPath),
                                          socket: endpoint.socket) else { exit(0) }
    if !r.ok, r.output.hasPrefix("not open") { exit(0) }
    let name = (path as NSString).lastPathComponent
    let reason = r.ok
        ? "Done: the user has \(name) open in Duo, so Duo made this change in its editor instead of writing the file. \(r.output) Don't repeat it. For further edits to \(name), keep using \(tool) as usual, or `duo2 doc edit`."
        : "Not applied: the user has \(name) open in Duo, and Duo couldn't make this change there: \(r.output). Read the current text with `duo2 doc read \(path)` and try again; don't write the file directly."
    let out: [String: Any] = ["hookSpecificOutput": ["hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": reason]]
    FileHandle.standardOutput.write((try? JSONSerialization.data(withJSONObject: out)) ?? Data())
    exit(0)
case .install:
    guard let cli = Bundle.main.executableURL?.resolvingSymlinksInPath().path, Installer.isDuoCLIPath(cli) else {
        fail("run the duo2 inside Duo.app (Duo.app/Contents/Helpers/duo2) so the link points at the app", code: 64)
    }
    Installer.recordConsent(true, cli: cli)
    print(Installer.install(cli: cli).lines.joined(separator: "\n"))
case .updateProbe:
    exit(probeUpdates())
case .uninstall:
    print(Installer.uninstall().lines.joined(separator: "\n"))
case .doctor:
    // Hooks can be turned off by a managed setting (DL-78): then Claude's edits to open documents
    // rely on Duo's instructions (`duo2 doc edit`) and Duo's merge, and attention on status files.
    // Only in sessions Duo started (DUO_SESSION_ID): any other Claude session has no Duo hooks.
    if env["DUO_SESSION_ID"] != nil, let sid = env["CLAUDE_CODE_SESSION_ID"] ?? env["DUO_SESSION_ID"] {
        let events = ControlEndpoint.file.deletingLastPathComponent().appending(path: "events/\(sid).jsonl")
        let seen = (try? String(contentsOf: events, encoding: .utf8))?.contains("\"hook_event_name\"") ?? false
        print(seen ? "Hooks: running in this session (Duo routes edits to open documents through its editor)."
                   : "Hooks: none have run in this session, perhaps turned off by a managed setting. Edit documents open in Duo with `duo2 doc edit --stdin`; Duo still merges direct writes into what the user sees.")
    }
    let me = Bundle.main.executableURL?.resolvingSymlinksInPath().path
    print(Installer.status(cli: me.flatMap { Installer.isDuoCLIPath($0) ? $0 : nil }).joined(separator: "\n"))
    let archive = ControlEndpoint.file.deletingLastPathComponent().appending(path: "archive")
    if let walker = FileManager.default.enumerator(at: archive, includingPropertiesForKeys: [.fileSizeKey]) {
        var bytes = 0, sessions = 0
        for case let u as URL in walker {
            bytes += (try? u.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            if u.pathExtension == "jsonl", u.deletingLastPathComponent().lastPathComponent == "archive" { sessions += 1 }
        }
        print("Session archive: \(sessions) sessions, \(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)) (\(archive.path); no limit, DL-56).")
    }
    let legacy = LegacyDuo.detect()
    if !legacy.isEmpty { print("Legacy Duo's instructions are still installed (\(legacy.map(\.what).joined(separator: ", "))). See `duo2 legacy`.") }
    guard let (endpoint, source) = ControlEndpoint.discover() else {
        print("Duo isn't running, or this terminal can't see it: no \(ControlEndpoint.socketVariable) in the environment and no live \(ControlEndpoint.file.path).")
        exit(1)
    }
    print("Found Duo through \(source): \(endpoint.socket)")
    do {
        let r = try ControlClient.send(ControlRequest(token: endpoint.token, command: "ping", args: []), socket: endpoint.socket)
        print(r.ok ? "Reachable: \(r.output)" : "Reached Duo, but it refused: \(r.output)")
        exit(r.ok ? 0 : 1)
    } catch {
        print("Not reachable: \(error).")
        print("Inside Claude's sandbox, add this socket to sandbox.network.allowUnixSockets in your settings. Duo's own terminals do this for you.")
        exit(1)
    }
default:
    guard let (endpoint, _) = ControlEndpoint.discover() else { fail("Duo isn't running. Run `duo2 doctor`.", code: 69) }
    let request = ControlRequest(token: endpoint.token, command: action.verb, args: rest,
                                 // Claude's own id is current after /clear; Duo's may be stale (F-29).
                                 session: env["CLAUDE_CODE_SESSION_ID"] ?? env["DUO_SESSION_ID"],
                                 cwd: FileManager.default.currentDirectoryPath)
    do {
        let r = try ControlClient.send(request, socket: endpoint.socket, timeout: action.timeout)
        if r.ok { print(r.output, terminator: r.output.hasSuffix("\n") ? "" : "\n") } else { fail(r.output) }
    } catch {
        fail("\(error). Run `duo2 doctor`.", code: 69)
    }
}

/// `duo2 update probe` (the work-Mac test for Sparkle): can this Mac reach the update feed and the
/// DMG it names, and is Duo installed where the updater can replace it? Prints each step and a
/// verdict; exit 0 when all pass.
func probeUpdates() -> Int32 {
    let feed = URL(string: "https://github.com/dudgeon/duo-v2/releases/latest/download/appcast.xml")!
    var ok = true
    func fetch(_ url: URL, method: String) -> (status: Int, finalHost: String, data: Data, error: String?) {
        var req = URLRequest(url: url, timeoutInterval: 20)
        req.httpMethod = method
        let done = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var out: (Int, String, Data, String?) = (0, "", Data(), nil)
        URLSession.shared.dataTask(with: req) { data, resp, err in
            let h = resp as? HTTPURLResponse
            out = (h?.statusCode ?? 0, h?.url?.host ?? "", data ?? Data(), err?.localizedDescription)
            done.signal()
        }.resume()
        done.wait()
        return out
    }
    print("Update feed: \(feed.absoluteString)")
    let f = fetch(feed, method: "GET")
    var enclosure: URL?
    if let e = f.error {
        ok = false; print("  ✗ couldn't reach it: \(e)")
    } else if f.status == 404 {
        ok = false; print("  ✗ 404: no release has published a feed yet (the first is 0.1.6), or the latest release lacks appcast.xml")
    } else if f.status != 200 {
        ok = false; print("  ✗ HTTP \(f.status) from \(f.finalHost)")
    } else {
        let xml = String(decoding: f.data, as: UTF8.self)
        let version = xml.firstMatch(of: /<sparkle:shortVersionString>([^<]+)</)?.1 ?? "?"
        enclosure = (xml.firstMatch(of: /<enclosure url="([^"]+)"/)?.1).flatMap { URL(string: String($0)) }
        print("  ✓ reached (via \(f.finalHost)); latest is \(version)")
    }
    if let enclosure {
        print("Update download: \(enclosure.lastPathComponent)")
        let d = fetch(enclosure, method: "HEAD")
        if let e = d.error { ok = false; print("  ✗ couldn't reach it: \(e)") }
        else if d.status != 200 { ok = false; print("  ✗ HTTP \(d.status) from \(d.finalHost)") }
        else { print("  ✓ reachable (served from \(d.finalHost))") }
    }
    // Where Duo is installed: the updater replaces the app in place.
    if let app = InstallLocation.app(containing: Bundle.main.executableURL) {
        print("Installed at: \(app.path)")
        print(InstallLocation.canReplace(app) ? "  ✓ you can replace it (no administrator password needed)"
              : "  ! replacing it needs an administrator password: Duo › Check for Updates… offers Open Releases Page to install by hand (DL-114)")
        if InstallLocation.isTransient(app) {
            ok = false; print("  ✗ running from a disk image or a translocated copy: drag Duo to Applications first")
        }
    } else {
        print("Installed at: not inside an app (a development duo2); run Duo.app/Contents/Helpers/duo2 update probe")
    }
    if let proxy = (CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any]),
       (proxy["HTTPSEnable"] as? Int) == 1 || proxy["ProxyAutoConfigURLString"] != nil {
        print("Network: a system proxy is set (\((proxy["HTTPSProxy"] as? String) ?? (proxy["ProxyAutoConfigURLString"] as? String) ?? "PAC")); the updater uses it too")
    }
    print(ok ? "Verdict: in-app updates should work here." : "Verdict: in-app updates are blocked here at the step marked ✗; Duo's update notice (Duo › Check for Updates…) still points to the DMG.")
    return ok ? 0 : 1
}

