import CryptoKit
import Foundation

/// Snapshots of documents (LR-38, DL-77's safety net): whenever Duo is about to replace one
/// version of a document with another (a conflict resolved either way, a document opened as it
/// was on disk), the version that would be lost is kept here first. Content-addressed per file,
/// newest last; identical content is stored once; at most 200 snapshots per file.
public enum FileHistory {
    nonisolated(unsafe) public static var root: URL = DuoPaths.support.appending(path: "history")
    static let limit = 200

    public struct Snapshot: Codable, Sendable {
        public var at: Double
        public var source: String      // open | conflict-mine | conflict-theirs | resolve-mine | resolve-theirs | removed
        public var hash: String
        public var bytes: Int
    }

    static func folder(for file: URL) -> URL {
        let key = SHA256.hash(data: Data(file.resolvingSymlinksInPath().standardizedFileURL.path.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
        return root.appending(path: key)
    }

    /// Keeps `data` as a version of `file`. Returns where it's stored.
    @discardableResult
    public static func snapshot(_ file: URL, _ data: Data, source: String) -> URL? {
        let dir = folder(for: file)
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let blob = dir.appending(path: "\(hash).txt")
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: blob.path) { try data.write(to: blob, options: .atomic) }
            var list = index(file)
            if list.last?.hash == hash, list.last?.source == source { return blob }
            list.append(Snapshot(at: Date().timeIntervalSince1970, source: source, hash: hash, bytes: data.count))
            if list.count > limit {
                let dropped = list.prefix(list.count - limit)
                list.removeFirst(list.count - limit)
                for d in dropped where !list.contains(where: { $0.hash == d.hash }) { try? FileManager.default.removeItem(at: dir.appending(path: "\(d.hash).txt")) }
            }
            try JSONEncoder().encode(SnapshotIndex(file: file.path, snapshots: list)).write(to: dir.appending(path: "index.json"), options: .atomic)
            return blob
        } catch { return nil }
    }

    public static func index(_ file: URL) -> [Snapshot] {
        guard let d = try? Data(contentsOf: folder(for: file).appending(path: "index.json")),
              let i = try? JSONDecoder().decode(SnapshotIndex.self, from: d) else { return [] }
        return i.snapshots
    }

    public static func blob(_ file: URL, hash: String) -> URL { folder(for: file).appending(path: "\(hash).txt") }

    struct SnapshotIndex: Codable {
        var file: String
        var snapshots: [Snapshot]
    }
}
