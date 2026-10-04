import Foundation

/// Fork lineage for the live workspace (DL-24, S11, F-31), read cheaply enough for the 2 s refresh:
/// - a transcript's head (its first user message's uuid, its start) is read once;
/// - only sessions that share a head (one thread) are read in full, and then incrementally:
///   a growing transcript is read from where the last read stopped.
public final class ThreadCache: @unchecked Sendable {
    public static let shared = ThreadCache()

    private struct Head { var size: UInt64; var root: String?; var started: String? }
    private struct Full {
        var offset: UInt64 = 0
        var uuids: Set<String> = []
        var records: [[String: String]] = []   // uuid, parentUuid, timestamp: what ForkLineage reads
    }

    private let lock = NSLock()
    private var heads: [String: Head] = [:]
    private var fulls: [String: Full] = [:]

    public init() {}

    /// Parent session id for each fork among `sessions` (one project's), by session id.
    public func parents(_ sessions: [(id: String, transcript: URL)]) -> [String: String] {
        lock.lock(); defer { lock.unlock() }
        var byRoot: [String: [(id: String, transcript: URL, started: String?)]] = [:]
        for s in sessions {
            let h = head(s.transcript)
            if let r = h.root { byRoot[r, default: []].append((s.id, s.transcript, h.started)) }
        }
        var out: [String: String] = [:]
        for (root, family) in byRoot where family.count > 1 {
            var infos: [ForkLineage.Info] = []
            var records: [String: [[String: Any]]] = [:]
            for s in family {
                let f = full(s.transcript)
                infos.append(.init(sessionId: s.id, root: root, forkPoint: nil, started: s.started, uuids: f.uuids))
                records[s.id] = f.records
            }
            out.merge(ForkLineage.parents(infos, records: records)) { a, _ in a }
        }
        return out
    }

    private func size(_ url: URL) -> UInt64 {
        ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.uint64Value ?? 0
    }

    /// The first user message's uuid and the first timestamp, from the start of the file.
    private func head(_ url: URL) -> Head {
        let now = size(url)
        if let h = heads[url.path], h.root != nil || h.size == now { return h }
        var h = Head(size: now, root: nil, started: nil)
        guard let fh = try? FileHandle(forReadingFrom: url) else { return h }
        defer { try? fh.close() }
        var buffer = Data()
        // Heads are near the top; give up after 4 MB (a transcript with no user message yet).
        while h.root == nil, buffer.count < 4 << 20, let chunk = try? fh.read(upToCount: 64 << 10), !chunk.isEmpty {
            buffer.append(chunk)
            for line in buffer.split(separator: UInt8(ascii: "\n")) {
                guard let r = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] else { continue }
                if h.started == nil { h.started = r["timestamp"] as? String }
                if r["type"] as? String == "user", let u = r["uuid"] as? String { h.root = u; break }
            }
        }
        heads[url.path] = h
        return h
    }

    /// Every message uuid and its parent, read from where the last read stopped.
    private func full(_ url: URL) -> Full {
        var f = fulls[url.path] ?? Full()
        let now = size(url)
        if now < f.offset { f = Full() }   // rewritten or truncated: start over
        guard now > f.offset, let fh = try? FileHandle(forReadingFrom: url) else { return f }
        defer { try? fh.close() }
        try? fh.seek(toOffset: f.offset)
        guard let data = try? fh.readToEnd(), let lastNewline = data.lastIndex(of: UInt8(ascii: "\n")) else { return f }
        let complete = data[data.startIndex...lastNewline]
        for line in complete.split(separator: UInt8(ascii: "\n")) {
            guard let r = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any], let u = r["uuid"] as? String else { continue }
            f.uuids.insert(u)
            var rec = ["uuid": u]
            if let p = r["parentUuid"] as? String { rec["parentUuid"] = p }
            if let t = r["timestamp"] as? String { rec["timestamp"] = t }
            f.records.append(rec)
        }
        f.offset += UInt64(complete.count)
        fulls[url.path] = f
        return f
    }
}
