import DuoControl
import Foundation
import Network

/// Listens on a Unix socket for `duo2` (DL-15, DL-43, spike S8): a per-launch token, one JSON line
/// each way. Requests run on the main actor, where the model lives.
@MainActor
public final class ControlServer {
    public private(set) var endpoint: ControlEndpoint?
    private let handler: @MainActor (ControlRequest) -> ControlResponse
    private var listener: NWListener?
    private let token = ControlEndpoint.newToken()

    public init(handler: @escaping @MainActor (ControlRequest) -> ControlResponse) {
        self.handler = handler
    }

    /// Starts listening; `ready` runs once the port is known (the endpoint file is written first).
    public func start(ready: @escaping @MainActor (ControlEndpoint) -> Void = { _ in }) throws {
        let path = ControlEndpoint.defaultSocket
        try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        unlink(path)  // a stale socket from a crash, or an older instance: the newest Duo answers
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = .unix(path: path)
        let l = try NWListener(using: params)
        l.newConnectionHandler = { [weak self] c in
            MainActor.assumeIsolated { self?.accept(c) }
        }
        l.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated {
                guard let self, case .ready = state else { return }
                chmod(path, 0o600)
                let e = ControlEndpoint(socket: path, token: self.token, pid: getpid())
                self.endpoint = e
                try? e.write()
                ready(e)
            }
        }
        l.start(queue: .main)
        listener = l
    }

    public func stop() {
        listener?.cancel()
        if let e = endpoint, let current = ControlEndpoint.discover(environment: [:])?.0, current == e {
            try? FileManager.default.removeItem(at: ControlEndpoint.file)
            unlink(e.socket)
        }
    }

    private func accept(_ c: NWConnection) {
        c.start(queue: .main)
        receive(c, buffer: Data())
    }

    private func receive(_ c: NWConnection, buffer: Data) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, done, error in
            MainActor.assumeIsolated {
                guard let self else { return c.cancel() }
                var buf = buffer
                if let data { buf.append(data) }
                if let nl = buf.firstIndex(of: UInt8(ascii: "\n")) {
                    self.respond(c, to: buf[..<nl])
                } else if done || error != nil || buf.count > 1 << 20 {
                    c.cancel()
                } else {
                    self.receive(c, buffer: buf)
                }
            }
        }
    }

    private func respond(_ c: NWConnection, to line: Data) {
        let response: ControlResponse
        if let req = try? JSONDecoder().decode(ControlRequest.self, from: line) {
            response = Self.same(req.token, token) ? handler(req) : ControlResponse(ok: false, output: "wrong token")
        } else {
            response = ControlResponse(ok: false, output: "unreadable request")
        }
        var out = (try? JSONEncoder().encode(response)) ?? Data()
        out.append(UInt8(ascii: "\n"))
        c.send(content: out, completion: .contentProcessed { _ in c.cancel() })
    }

    /// Constant-time comparison, so the token can't be guessed byte by byte.
    static func same(_ a: String, _ b: String) -> Bool {
        let x = Array(a.utf8), y = Array(b.utf8)
        guard x.count == y.count else { return false }
        return zip(x, y).reduce(0) { $0 | ($1.0 ^ $1.1) } == 0
    }
}

extension AppModel {
    /// What `duo2` commands do in the app (the table is `ControlCommand.all`).
    public func handle(_ req: ControlRequest) -> ControlResponse {
        switch req.command {
        case "ping":
            let mode = terminalsMode == .live ? "live" : "fixture"
            return .init(ok: true, output: "Duo \(getpid()), \(mode), \(fixture.projects.count) projects")
        case "needs-you":
            let lines = fixture.needsYou.map { s in
                "\(s.project) / \(s.name)" + (s.wait.map { " · \($0)" } ?? "") + (s.question.map { "\n  \($0)" } ?? "")
            }
            return .init(ok: true, output: lines.isEmpty ? "Nothing needs you." : lines.joined(separator: "\n"))
        case "projects":
            let lines = fixture.projects.map { p in
                (p.isHome == true ? "★ " : "") + p.name + (p.goal.isEmpty ? "" : " — \(p.goal)")
                    + ([p.health, p.next].compactMap { $0 }.joined(separator: " · ").nonEmpty.map { " (\($0))" } ?? "")
            }
            return .init(ok: true, output: lines.joined(separator: "\n"))
        case "open":
            guard let name = req.args.first else { return .init(ok: false, output: "usage: duo2 open <project> [session]") }
            guard fixture.projects.contains(where: { $0.name == name }) else { return .init(ok: false, output: "no project '\(name)'") }
            open(project: name, session: req.args.dropFirst().first)
            return .init(ok: true, output: "Opened \(name).")
        case "doc-status":
            guard let path = req.args.first else { return .init(ok: false, output: "usage: duo2 doc-status <file>") }
            let url = URL(fileURLWithPath: path, relativeTo: req.cwd.map { URL(fileURLWithPath: $0, isDirectory: true) }).absoluteURL
            return .init(ok: true, output: editorIfLoaded?.status(of: url) ?? "not open in Duo")
        case "status":
            let view: String
            switch altitude {
            case .allProjects: view = "All projects" + (homeTab.flatMap { k in fixture.sessions.first { $0.tabKey == k } }.map { ", Home on \($0.name)" } ?? "")
            case .project(let p): view = "Project \(p)" + (consoleTab.flatMap { k in fixture.sessions.first { $0.tabKey == k } }.map { ", console on \($0.name)" } ?? "")
            }
            let c = fixture.counts
            return .init(ok: true, output: "\(view)\n\(c.needsYou) need you · \(c.readyForReview) to review · \(c.working) working · \(c.idle) idle")
        case "session":
            if req.args.first == "carry-on" {
                guard let old = req.args.dropFirst().first else { return .init(ok: false, output: "usage: duo2 session carry-on <session-id>") }
                guard let new = carryOn(old) else { return .init(ok: false, output: "no archived copy of session \(old)") }
                return .init(ok: true, output: "Started session \(new.prefix(8)), carrying on from \(old.prefix(8)).")
            }
            guard req.args.count >= 2, ["note", "next"].contains(req.args[0]) else {
                return .init(ok: false, output: "usage: duo2 session note|next <text>")
            }
            guard let id = req.session else { return .init(ok: false, output: "not run from a Claude session (no session id)") }
            let text = req.args.dropFirst().joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            guard setNarration(id, kind: req.args[0], text: text) else {
                return .init(ok: false, output: "Duo doesn't know session \(id.prefix(8)) yet")
            }
            return .init(ok: true, output: "Noted.")
        default:
            return .init(ok: false, output: "unknown command '\(req.command)'")
        }
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
