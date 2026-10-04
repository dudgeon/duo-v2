import Foundation

/// The surfaces-handoff targets (slice 1: DB-1 to DB-4) as window states, from the fixture's
/// `surfaces` section. `shell-new-menu` is a native menu and `shell-narrow` is 1280×800, so
/// neither is a capture target at the design size; their logic has checks.
@MainActor
public enum SurfaceTargets {
    nonisolated public static let screens = ["idle-list", "idle-many", "console-none", "console-ended", "home-none", "shell-tab"]

    public static func apply(_ screen: String, to model: AppModel) {
        guard let url = Bundle.main.url(forResource: "fixture", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let s = root["surfaces"] as? [String: Any] else { return }
        let inProject = ["console-none", "console-ended", "shell-tab"].contains(screen)
        TargetState(rawValue: inProject ? "project" : "overview")?.apply(to: model)
        switch screen {
        case "idle-list", "idle-many":
            model.fixtureIdle = screen == "idle-list" ? idle(s) : idleMany(s)
            if screen == "idle-list" {
                let buckets = (s["idleSessions"] as? [String: Any])?["buckets"] as? [[String: Any]] ?? []
                var n = 0
                model.fixtureIdleBuckets = buckets.map { b in
                    (label: b["label"] as? String ?? "", rows: (b["sessions"] as? [[String: Any]] ?? []).map { r in defer { n += 1 }; return row(r, n) })
                }
            }
            model.fixture.counts.idle = model.fixtureIdle?.count ?? 0
            model.idleOpen = true
            model.idleSelection = 0
        case "console-none":
            let c = (s["consoleStates"] as? [String: Any])?["none"] as? [String: Any]
            let project = c?["project"] as? String ?? "api-deprecations"
            // "api-deprecations gains two files and two idle sessions" (fixture-surfaces $additions).
            if !model.fixture.sessions.contains(where: { $0.project == project }) {
                for (name, wait) in [("v1 sunset comms", "12d"), ("Customer list pull", "2w")] {
                    model.fixture.sessions.append(Fixture.Session(name: name, project: project, state: .idle, wait: wait, question: nil, options: nil,
                                                                  summary: nil, forkOf: nil, document: nil, sessionId: nil))
                }
            }
            model.fixture.projectFiles[project] = c?["files"] as? [String] ?? ["PROJECT.md", "comms/v1-sunset.md"]
            model.open(project: project)
            model.consoleTab = nil
            model.fixtureConsole = .noneOpen(project: project, last: c?["lastSession"] as? String, lastKey: c?["lastSession"] as? String)
        case "console-ended":
            let c = (s["consoleStates"] as? [String: Any])?["ended"] as? [String: Any]
            let session = c?["session"] as? String ?? "Teardown research"
            // Its tab's glyph becomes the idle dash, and it moves to Idle on the left.
            if let i = model.fixture.sessions.firstIndex(where: { $0.name == session }) { model.fixture.sessions[i].state = .idle }
            model.consoleTab = session
            model.fixtureEnded = (session, "\(session) ended at \(c?["at"] as? String ?? "10:42").")
        case "home-none":
            // Home's sessions are closed, so they count as idle and its pointer card goes.
            if let home = model.fixture.home?.name {
                for i in model.fixture.sessions.indices where model.fixture.sessions[i].project == home {
                    model.fixture.sessions[i].state = .idle; model.fixture.sessions[i].question = nil
                }
            }
            if let c = ((s["consoleStates"] as? [String: Any])?["homeNone"] as? [String: Any])?["counts"] as? [String: Int] {
                model.fixture.counts = .init(needsYou: c["needsYou"] ?? 0, readyForReview: c["readyForReview"] ?? 0,
                                             working: c["working"] ?? 0, idle: c["idle"] ?? 0)
            }
            model.homeTab = nil
            model.fixtureConsole = .homeNone
        case "shell-tab":
            let sh = s["shells"] as? [String: Any]
            let project = sh?["project"] as? String ?? "checkout-redesign"
            var keys: [String] = []
            for t in sh?["tabs"] as? [[String: Any]] ?? [] where t["kind"] as? String == "shell" {
                let key = AppModel.shellPrefix + (t["name"] as? String ?? "zsh")
                keys.append(key)
                model.shellTitles[key] = t["name"] as? String
                if t["selected"] as? Bool == true { model.consoleTab = key }
            }
            model.shellTabs[project] = keys
        default: break
        }
    }

    static func row(_ r: [String: Any], _ n: Int) -> IdleRow {
        let age = r["age"] as? String ?? ""
        return IdleRow(id: "idle-\(n)", name: r["name"] as? String ?? "", project: r["project"] as? String,
                       unfiled: r["unfiled"] as? Bool ?? false, archived: r["archived"] as? Bool ?? false,
                       group: r["group"] as? String, age: age, seconds: seconds(age), openIn: r["openIn"] as? String)
    }

    static func seconds(_ age: String) -> Int {
        guard let n = Int(age.filter(\.isNumber)) else { return 0 }
        if age.hasSuffix("mo") { return n * 30 * 86_400 }
        if age.hasSuffix("w") { return n * 7 * 86_400 }
        return WaitTime(age).seconds
    }

    /// idle-list: the fixture's fourteen, as dated relative to a Saturday so the buckets match.
    static func idle(_ s: [String: Any]) -> [IdleRow] {
        let buckets = (s["idleSessions"] as? [String: Any])?["buckets"] as? [[String: Any]] ?? []
        return buckets.flatMap { $0["sessions"] as? [[String: Any]] ?? [] }.enumerated().map { row($1, $0) }
    }

    /// idle-many: the awkward rows and the named others, then filler to the fixture's 312.
    static func idleMany(_ s: [String: Any]) -> [IdleRow] {
        let m = s["idleMany"] as? [String: Any] ?? [:]
        var rows = (m["awkwardRows"] as? [[String: Any]] ?? []).enumerated().map { row($1, $0) }
        for (i, line) in (m["otherRows"] as? [String] ?? []).enumerated() {
            let p = line.components(separatedBy: " · ")
            rows.append(IdleRow(id: "other-\(i)", name: p[0], project: p.count > 1 ? p[1] : nil, age: p.count > 2 ? p[2] : "",
                                seconds: seconds(p.count > 2 ? p[2] : "")))
        }
        let total = m["count"] as? Int ?? 312
        var n = rows.count
        while rows.count < total {
            let days = 2 + n / 3
            rows.append(IdleRow(id: "f-\(n)", name: "Session \(n)", project: ["checkout-redesign", "onboarding-v3", "refunds-api-spec"][n % 3],
                                age: days < 14 ? "\(days)d" : days < 60 ? "\(days / 7)w" : "\(days / 30)mo", seconds: days * 86_400))
            n += 1
        }
        return rows.sorted { $0.seconds < $1.seconds }
    }
}
