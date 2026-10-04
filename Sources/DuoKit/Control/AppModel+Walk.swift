import AppKit
import DuoControl
import Foundation

/// Acceptance-walk test setup (the walk page's "Set up test", `duo2://walk-setup?id=…`, or
/// `duo2 walk setup <id>`): puts Duo in the state a test starts from, so Geoff never arranges
/// fixtures by hand. The steps come only from `~/DuoAcceptance/walk-setups.json`, written by
/// `scripts/acceptance/build-page.py`; a link can name a test, never supply steps.
extension AppModel {
    public static var walkSetupsFile: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: "DuoAcceptance/walk-setups.json")
    }

    struct WalkSetups: Decodable {
        var workspace: String
        var repo: String
        var setups: [String: [String]]
    }

    public func walkSetup(_ id: String, done: @escaping @MainActor (Reply) -> Void) {
        guard let data = try? Data(contentsOf: Self.walkSetupsFile),
              let file = try? JSONDecoder().decode(WalkSetups.self, from: data) else {
            return done(.fail("no walk setups at \(Self.walkSetupsFile.path); build the walk page first"))
        }
        guard let steps = file.setups[id] else { return done(.fail("no setup for test '\(id)'")) }
        let ws = URL(fileURLWithPath: (file.workspace as NSString).expandingTildeInPath)
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first { $0.title == "Duo" }?.makeKeyAndOrderFront(nil)
        var log: [String] = []
        let start: @MainActor () -> Void = { [weak self] in
            self?.runSteps(steps[...], repo: file.repo, log: log) { lines in
                log = lines
                let failed = lines.filter { $0.hasPrefix("✘") }
                done(failed.isEmpty ? .ok("Ready for \(id).\n" + lines.joined(separator: "\n")) : .fail("Setup for \(id) stopped:\n" + lines.joined(separator: "\n")))
            }
        }
        if terminalsMode != .live || liveRoot?.standardizedFileURL.path != ws.standardizedFileURL.path {
            startLive(root: ws)
            log.append("· opened the acceptance workspace")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { MainActor.assumeIsolated { start() } }
        } else {
            start()
        }
    }

    private func runSteps(_ steps: ArraySlice<String>, repo: String, log: [String], done: @escaping @MainActor ([String]) -> Void) {
        guard let step = steps.first else { return done(log) }
        let rest = steps.dropFirst()
        let next: @MainActor (String) -> Void = { [weak self] line in
            let log = log + [line]
            if line.hasPrefix("✘") { return done(log) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { MainActor.assumeIsolated { self?.runSteps(rest, repo: repo, log: log, done: done) } }
        }
        let words = Self.shellWords(step)
        switch words.first {
        case "wait":
            let s = Double(words.dropFirst().first ?? "1") ?? 1
            DispatchQueue.main.asyncAfter(deadline: .now() + s) { MainActor.assumeIsolated { next("· waited \(s)s") } }
        case "session-running":
            // A Claude session showing in the project's console: a running one, else a new one,
            // once its prompt is ready.
            guard let project = words.dropFirst().first, fixture.projects.contains(where: { $0.name == project }) else { return next("✘ no project for \(step)") }
            open(project: project)
            if let t = terminals.all.first(where: { t in t.isLiveClaude && fixture.sessions.first { $0.tabKey == t.key }?.project == project }) {
                openConsoleTab(t.key)
                return next("· showing a running session in \(project)")
            }
            // Resume the newest session the project already has (restarts don't pile up new
            // ones); a project with none gets a new session.
            let existing = fixture.sessions(inProject: project).filter { $0.sessionId != nil }
            let t: TerminalSession
            if let s = existing.first(where: { $0.name == "New session" }) ?? existing.first, let resumed = terminal(project: project, session: s.tabKey) {
                t = resumed
                consoleTab = s.tabKey
            } else {
                guard let id = newSession(in: project), let made = terminals.existing(id) else { return next("✘ couldn't start a session in \(project)") }
                t = made
                consoleTab = id
            }
            var waited = false
            whenPromptReady(t) { waited = true; next("· a session is ready in \(project)") }
            DispatchQueue.main.asyncAfter(deadline: .now() + 21) { MainActor.assumeIsolated { if !waited { next("· a session in \(project) is starting (its prompt isn't ready yet)") } } }
        case "fixture":
            // A named recipe in the repo's fixtures script (never a command from the caller).
            let recipe = words.dropFirst().joined(separator: " ")
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            p.arguments = [repo + "/scripts/acceptance/fixtures.py", "--recipe"] + Array(words.dropFirst())
            p.terminationHandler = { proc in
                let ok = proc.terminationStatus == 0
                DispatchQueue.main.async { MainActor.assumeIsolated { next(ok ? "· fixture \(recipe)" : "✘ fixture \(recipe) failed (\(proc.terminationStatus))") } }
            }
            do { try p.run() } catch { next("✘ fixture \(recipe): \(error.localizedDescription)") }
        default:
            guard let (action, args) = DuoAction.resolve(words), !action.local, action.id != .walkSetup else { return next("✘ not a Duo action: \(step)") }
            let req = ControlRequest(token: "", command: action.verb, args: args)
            perform(action.id, Invocation(args), req) { r in next((r.ok ? "· " : "✘ ") + "\(step): \(r.text.split(separator: "\n").first ?? "")") }
        }
    }

    /// Splits a step like a shell would: spaces separate words; quotes group them.
    static func shellWords(_ s: String) -> [String] {
        var out: [String] = [], cur = "", quote: Character?, any = false
        for c in s {
            if let q = quote { if c == q { quote = nil } else { cur.append(c) } }
            else if c == "\"" || c == "'" { quote = c; any = true }
            else if c == " " { if !cur.isEmpty || any { out.append(cur) }; cur = ""; any = false }
            else { cur.append(c) }
        }
        if !cur.isEmpty || any { out.append(cur) }
        return out
    }
}
