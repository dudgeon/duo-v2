import DuoControl
import Foundation

// The duo2 control plane (C-80, F-108): the pre-edit hook fails open, env endpoints fall back to
// the endpoint file, and every flag the code reads with `inv.has` is declared as a switch.

/// A one-shot-per-connection stand-in for Duo's socket: answers "pong" to the right token and
/// "wrong token" to any other, like `ControlServer`.
private final class StandInDuo: @unchecked Sendable {
    let path: String, token: String
    private let fd: Int32
    init?(token: String) {
        self.token = token
        path = "/tmp/duo-cp-\(UUID().uuidString.prefix(8)).sock"
        fd = socket(AF_UNIX, SOCK_STREAM, 0)
        var addr = sockaddr_un(); addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        withUnsafeMutableBytes(of: &addr.sun_path) { $0.copyBytes(from: bytes); $0[bytes.count] = 0 }
        let rc = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
        guard fd >= 0, rc == 0, listen(fd, 4) == 0 else { return nil }
        let (fd, token) = (self.fd, token)
        Thread.detachNewThread {
            while true {
                let c = accept(fd, nil, nil)
                if c < 0 { return }
                var buf = [UInt8](repeating: 0, count: 65536)
                let n = read(c, &buf, buf.count)
                let req = n > 0 ? try? JSONDecoder().decode(ControlRequest.self, from: Data(buf[0..<n])) : nil
                let reply = ControlResponse(ok: req?.token == token, output: req?.token == token ? "pong" : "wrong token")
                var line = (try? JSONEncoder().encode(reply)) ?? Data(); line.append(UInt8(ascii: "\n"))
                _ = line.withUnsafeBytes { write(c, $0.baseAddress, $0.count) }
                close(c)
            }
        }
    }
    func stop() { close(fd); unlink(path) }
}

func controlPlaneChecks() throws {
    print("duo2 control plane: hook fails open, env endpoints fall back, flags declared (C-80)")

    // 1. The hook denies Claude's write only on a clear yes (F-108's case: any other answer used to deny).
    check(PreEditDecision.decide(ControlResponse(ok: true, output: "Edited.")) == .deny(done: "Edited."), "hook: a successful edit denies Claude's direct write")
    check(PreEditDecision.decide(ControlResponse(ok: false, output: "not open")) == .allow, "hook: not open lets Claude write")
    check(PreEditDecision.decide(ControlResponse(ok: false, output: "wrong token")) == .allow, "hook: a stale token lets Claude write")
    check(PreEditDecision.decide(ControlResponse(ok: false, output: "bad request: unreadable")) == .allow, "hook: an unreadable request lets Claude write")
    check(PreEditDecision.decide(ControlResponse(ok: false, output: "the text changed")) == .allow, "hook: a failed edit lets Claude write")
    check(PreEditDecision.decide(nil) == .allow, "hook: no answer lets Claude write")

    // 2. Env endpoints retry the endpoint file on a dead socket or a wrong token.
    let live = StandInDuo(token: "new-token")
    check(live != nil, "stand-in Duo listens")
    guard let live else { return }
    defer { live.stop() }
    let file = URL(fileURLWithPath: "/tmp/duo-cp-\(UUID().uuidString.prefix(8)).json")
    defer { try? FileManager.default.removeItem(at: file) }
    try ControlEndpoint(socket: live.path, token: "new-token", pid: getpid()).write(to: file)
    let req = ControlRequest(token: "", command: "ping", args: [])
    let dead = ControlEndpoint(socket: "/tmp/duo-cp-none.sock", token: "old-token", pid: 0)
    let stale = ControlEndpoint(socket: live.path, token: "old-token", pid: 0)
    check((try? ControlClient.send(req, via: dead, source: "environment", file: file))?.output == "pong", "env endpoint: a dead socket falls back to the endpoint file")
    check((try? ControlClient.send(req, via: stale, source: "environment", file: file))?.output == "pong", "env endpoint: a wrong token falls back to the endpoint file")
    check((try? ControlClient.send(req, via: ControlEndpoint(socket: live.path, token: "new-token", pid: 0), source: "environment", file: file))?.output == "pong", "env endpoint: a good one is used as is")
    check((try? ControlClient.send(req, via: stale, source: file.path, file: file))?.output == "wrong token", "a file endpoint doesn't retry itself")
    let none = URL(fileURLWithPath: "/tmp/duo-cp-missing.json")
    check((try? ControlClient.send(req, via: dead, source: "environment", file: none)) == nil, "env endpoint: no endpoint file, the connect error stands")

    // 3. Every flag read with `inv.has` is a declared switch (or takes its value), so it can't swallow the next word.
    let fm = FileManager.default
    let root = repoRoot().appending(path: "Sources")
    var read = Set<String>()
    let re = try NSRegularExpression(pattern: #"\.has\("([a-z][a-z-]*)"\)"#)
    if let walker = fm.enumerator(at: root, includingPropertiesForKeys: nil) {
        for case let u as URL in walker where u.pathExtension == "swift" && !u.path.contains("/DuoChecks/") {
            let text = (try? String(contentsOf: u, encoding: .utf8)) ?? ""
            for m in re.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                if let r = Range(m.range(at: 1), in: text) { read.insert(String(text[r])) }
            }
        }
    }
    let undeclared = read.filter { !Invocation.switches.contains($0) && !Invocation.optionalValues.contains($0) }.sorted()
    check(read.count > 20 && undeclared.isEmpty, "every inv.has flag is declared a switch (\(read.count) read; undeclared: \(undeclared))")
    check(Invocation(["--hidden", "docs"]).positional == ["docs"] && Invocation(["--anyway", "a.docx"]).positional == ["a.docx"]
          && Invocation(["--not-now", "x"]).positional == ["x"] && Invocation(["--cancel", "x"]).positional == ["x"] && Invocation(["--fetch", "x"]).positional == ["x"],
          "--hidden, --anyway, --not-now, --cancel and --fetch don't swallow the next word")
}
