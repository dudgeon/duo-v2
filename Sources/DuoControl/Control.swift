import Foundation

// The app ↔ CLI protocol (DL-15, DL-43, spike S8). Foundation only, shared by the app and `duo2`,
// so the CLI starts fast and runs inside Claude's sandbox. Transport: a Unix socket in Duo's
// Application Support folder plus a per-launch token, one JSON line each way. Claude's sandbox
// blocks both loopback TCP and Unix sockets by default; `sandbox.network.allowUnixSockets` opens
// exactly this one path, where allowing loopback would open every local service (F-29).

/// Where the running app listens. Duo's terminals get it in the environment; other terminals
/// read `endpoint.json` (owner-only) from Duo's Application Support folder.
public struct ControlEndpoint: Codable, Sendable, Equatable {
    public var socket: String
    public var token: String
    public var pid: Int32

    public init(socket: String, token: String, pid: Int32) {
        self.socket = socket; self.token = token; self.pid = pid
    }

    public static let socketVariable = "DUO_SOCKET"
    public static let tokenVariable = "DUO_TOKEN"

    static var support: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "Duo")
    }
    public static var file: URL { support.appending(path: "endpoint.json") }
    /// One socket per user; a second Duo instance takes it over (the newest app answers).
    public static var defaultSocket: String { support.appending(path: "duo.sock").path }

    /// The environment first (Duo's own terminals), then the file. Nil if Duo isn't running.
    public static func discover(environment: [String: String] = ProcessInfo.processInfo.environment) -> (ControlEndpoint, source: String)? {
        if let s = environment[socketVariable], let t = environment[tokenVariable], !s.isEmpty, !t.isEmpty {
            return (ControlEndpoint(socket: s, token: t, pid: 0), "environment")
        }
        guard let data = try? Data(contentsOf: file),
              let e = try? JSONDecoder().decode(ControlEndpoint.self, from: data),
              kill(e.pid, 0) == 0 else { return nil }
        return (e, file.path)
    }

    /// Writes the endpoint file readable by the user only.
    public func write() throws {
        let url = Self.file
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    public static func newToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 24)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}

public struct ControlRequest: Codable, Sendable, Equatable {
    public var token: String
    public var command: String
    public var args: [String]
    /// The caller's session, when run from a Duo terminal (LR-20).
    public var session: String?
    public var cwd: String?

    public init(token: String, command: String, args: [String], session: String? = nil, cwd: String? = nil) {
        self.token = token; self.command = command; self.args = args; self.session = session; self.cwd = cwd
    }
}

public struct ControlResponse: Codable, Sendable, Equatable {
    public var ok: Bool
    /// Human-readable output, printed as is.
    public var output: String

    public init(ok: Bool, output: String) { self.ok = ok; self.output = output }
}

/// One table for every command: the CLI's help and the docs are generated from it (LR-52).
public struct ControlCommand: Sendable {
    public var name: String
    public var usage: String
    public var summary: String
    /// Needs the app running (otherwise the CLI answers by itself).
    public var needsApp: Bool

    public static let all: [ControlCommand] = [
        .init(name: "ping", usage: "duo2 ping", summary: "Check that Duo is running and reachable.", needsApp: true),
        .init(name: "needs-you", usage: "duo2 needs-you", summary: "List sessions waiting for you, with their questions.", needsApp: true),
        .init(name: "projects", usage: "duo2 projects", summary: "List projects with their goal, health and next step.", needsApp: true),
        .init(name: "open", usage: "duo2 open <project> [session]", summary: "Open a project in Duo, optionally on one of its sessions.", needsApp: true),
        .init(name: "status", usage: "duo2 status", summary: "What Duo is showing: the view, the open project and session, and counts.", needsApp: true),
        .init(name: "session", usage: "duo2 session note|next <text>", summary: "Tell the user, in one line, what this session is doing (note) or needs next (next).", needsApp: true),
        .init(name: "search", usage: "duo2 search <query> [-k N] [--project P] [--kind file|session|memory] [--exact] [--json]",
              summary: "Search every project by meaning and by words. Works without the app; read-only.", needsApp: false),
        .init(name: "search-status", usage: "duo2 search-status [--json]", summary: "How much of each project the search index covers.", needsApp: false),
        .init(name: "legacy", usage: "duo2 legacy [disable --yes | restore <backup>]",
              summary: "Find legacy Duo's instructions in ~/.claude; disable them (backed up first) or restore them.", needsApp: false),
        .init(name: "doctor", usage: "duo2 doctor", summary: "Explain how this terminal finds Duo, and whether it can reach it.", needsApp: false),
        .init(name: "help", usage: "duo2 help", summary: "Show this list.", needsApp: false),
    ]

    /// What Duo tells each session it starts (`--append-system-prompt`, DL-15): generated from
    /// this table, so it never drifts from the CLI.
    public static func sessionGuidance() -> String {
        "You are running inside Duo, a Mac app that organizes the user's Claude Code sessions into projects. "
            + "The `duo2` command talks to Duo; it is already on PATH and needs no approval:\n"
            + all.filter { $0.name != "help" }.map { "- `\($0.usage)`: \($0.summary)" }.joined(separator: "\n")
            + "\nFor questions across projects, or about meaning rather than exact text, run `duo2 search \"<question>\"` before grep or "
            + "reading folders: it covers every project the user has and works offline. Read only the lines it points to (path:Lstart-end). "
            + "Its scores only compare results within one search; don't treat them as percentages. Use `--exact` for identifiers and quoted strings."
            + "\nWhen you start substantial work, run `duo2 session note \"<one line>\"` so the user sees what you're doing; "
            + "when you hand back to the user, `duo2 session next \"<one line>\"`. Keep both short and plain."
    }

    public static func help() -> String {
        let width = all.map(\.usage.count).max() ?? 0
        return "duo2 talks to the Duo app.\n\n" + all.map { $0.usage.padding(toLength: width + 2, withPad: " ", startingAt: 0) + $0.summary }
            .joined(separator: "\n") + "\n"
    }
}

/// A blocking client: connect, send one line, read one line. Plain sockets keep the CLI small.
public enum ControlClient {
    public enum Failure: Error, CustomStringConvertible {
        case connect(Int32), io(String)
        public var description: String {
            switch self {
            case .connect(let e): "couldn't connect to Duo (\(String(cString: strerror(e))))"
            case .io(let m): m
            }
        }
    }

    public static func send(_ request: ControlRequest, socket path: String, timeout: Int = 10) throws -> ControlResponse {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw Failure.connect(errno) }
        defer { close(fd) }
        var tv = timeval(tv_sec: timeout, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: addr.sun_path) else { throw Failure.io("socket path too long: \(path)") }
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            raw.copyBytes(from: bytes)
            raw[bytes.count] = 0
        }
        let rc = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard rc == 0 else { throw Failure.connect(errno) }
        var line = try JSONEncoder().encode(request)
        line.append(UInt8(ascii: "\n"))
        let wrote = line.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
        guard wrote == line.count else { throw Failure.io("couldn't send the request") }
        var reply = Data()
        var buf = [UInt8](repeating: 0, count: 65536)
        while !reply.contains(UInt8(ascii: "\n")) {
            let n = read(fd, &buf, buf.count)
            if n <= 0 { break }
            reply.append(contentsOf: buf[0..<n])
        }
        guard let end = reply.firstIndex(of: UInt8(ascii: "\n")),
              let response = try? JSONDecoder().decode(ControlResponse.self, from: reply[..<end]) else {
            throw Failure.io("Duo didn't answer")
        }
        return response
    }
}
