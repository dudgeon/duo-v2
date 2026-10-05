import Foundation

/// A folder Claude sessions ran in that isn't there any more (DB-8, LR-23): what happened to it,
/// as far as Duo can tell without asking for anything (no Trash listing: macOS guards it, F-54).
/// Found again when another folder carries its `.duo` session list, or is a folder of the same
/// name holding the same project file. Looked up at most once a minute per path.
public enum MissingFolders {
    public enum Status: Sendable, Equatable {
        case notFound
        case unmounted(volume: String)
        case movedTo(String)

        /// The tile's line, in words (stand-in until S3-2 is approved).
        public var text: String {
            switch self {
            case .notFound: "Folder not found"
            case .unmounted(let v): "On “\(v)”, not connected"
            case .movedTo(let p): "Moved to \(p.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~"))"
            }
        }
    }

    private final class Cache: @unchecked Sendable {
        let lock = NSLock()
        var entries: [String: (at: Date, status: Status)] = [:]
    }
    private static let cache = Cache()

    public static func status(of path: String, sessionIds: [String], searchIn roots: [URL]) -> Status {
        cache.lock.lock()
        if let hit = cache.entries[path], hit.at.timeIntervalSinceNow > -60 { cache.lock.unlock(); return hit.status }
        cache.lock.unlock()
        let s = look(path, ids: Set(sessionIds), roots: roots)
        cache.lock.lock(); cache.entries[path] = (Date(), s); cache.lock.unlock()
        return s
    }

    /// Only whether it's on a disk that isn't connected: no searching.
    public static func volumeStatus(of path: String) -> Status {
        let parts = URL(fileURLWithPath: path).pathComponents
        if parts.count > 2, parts[1] == "Volumes", !FileManager.default.fileExists(atPath: "/Volumes/\(parts[2])") { return .unmounted(volume: parts[2]) }
        return .notFound
    }

    static func look(_ path: String, ids: Set<String>, roots: [URL]) -> Status {
        let fm = FileManager.default
        if case .unmounted = volumeStatus(of: path) { return volumeStatus(of: path) }
        let name = URL(fileURLWithPath: path).lastPathComponent
        // Where to look: the given roots (Home), and the nearest folder above the old place that's still there.
        var places = roots
        var up = URL(fileURLWithPath: path).deletingLastPathComponent()
        while up.path.count > 1, !fm.fileExists(atPath: up.path) { up.deleteLastPathComponent() }
        if up.path != fm.homeDirectoryForCurrentUser.path, up.path.count > 1 { places.append(up) }
        var byName: URL?
        for root in places {
            for dir in folders(under: root, depth: 4) {
                let index = SessionIndex.load(project: dir)
                if !ids.isEmpty, index.sessions.contains(where: { ids.contains($0.sessionId) }) { return .movedTo(dir.path) }
                if byName == nil, dir.lastPathComponent == name, dir.path != path { byName = dir }
            }
        }
        return byName.map { .movedTo($0.path) } ?? .notFound
    }

    private final class WalkCache: @unchecked Sendable {
        let lock = NSLock()
        var entries: [String: (at: Date, dirs: [URL])] = [:]
    }
    private static let walks = WalkCache()

    /// Folders under a root, four deep, remembered for a minute (several missing folders share one walk).
    static func folders(under root: URL, depth: Int) -> [URL] {
        walks.lock.lock()
        if let hit = walks.entries[root.path], hit.at.timeIntervalSinceNow > -60 { walks.lock.unlock(); return hit.dirs }
        walks.lock.unlock()
        let dirs = walk(root, depth: depth)
        walks.lock.lock(); walks.entries[root.path] = (Date(), dirs); walks.lock.unlock()
        return dirs
    }

    static func walk(_ root: URL, depth: Int) -> [URL] {
        var out: [URL] = []
        func walk(_ d: URL, _ n: Int) {
            guard out.count < 4000, let items = try? FileManager.default.contentsOfDirectory(at: d, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return }
            for u in items where (try? u.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                if ["node_modules", "build", "dist", "Pods", "vendor", "Library"].contains(u.lastPathComponent) { continue }
                out.append(u)
                if n < depth { walk(u, n + 1) }
            }
        }
        walk(root, 1)
        return out
    }
}
