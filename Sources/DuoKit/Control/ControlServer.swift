import DuoControl
import Foundation
import Network

/// Listens on a Unix socket for `duo2` (DL-15, DL-43, spike S8): a per-launch token, one JSON line
/// each way. Requests run on the main actor, where the model lives.
@MainActor
public final class ControlServer {
    public private(set) var endpoint: ControlEndpoint?
    private let handler: @MainActor (ControlRequest, @escaping @MainActor (ControlResponse) -> Void) -> Void
    private var listener: NWListener?
    private let token = ControlEndpoint.newToken()

    public init(handler: @escaping @MainActor (ControlRequest, @escaping @MainActor (ControlResponse) -> Void) -> Void) {
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
        let reply: @MainActor (ControlResponse) -> Void = { response in
            var out = (try? JSONEncoder().encode(response)) ?? Data()
            out.append(UInt8(ascii: "\n"))
            c.send(content: out, completion: .contentProcessed { _ in c.cancel() })
        }
        guard let req = try? JSONDecoder().decode(ControlRequest.self, from: line) else { return reply(ControlResponse(ok: false, output: "unreadable request")) }
        guard Self.same(req.token, token) else { return reply(ControlResponse(ok: false, output: "wrong token")) }
        handler(req, reply)
    }

    /// Constant-time comparison, so the token can't be guessed byte by byte.
    static func same(_ a: String, _ b: String) -> Bool {
        let x = Array(a.utf8), y = Array(b.utf8)
        guard x.count == y.count else { return false }
        return zip(x, y).reduce(0) { $0 | ($1.0 ^ $1.1) } == 0
    }
}
