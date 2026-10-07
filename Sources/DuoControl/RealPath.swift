import Foundation

/// A path the way Claude Code spells it when it files a session (LR-24): `realpath(3)`, so
/// `/tmp/x` is `/private/tmp/x`. Foundation's `resolvingSymlinksInPath()` is not that: it strips a
/// leading `/private`, so a folder under `/private/tmp` or `/private/var` maps to a bucket Claude
/// never wrote (F-200). A path that doesn't exist yet (a move's destination, a folder that was
/// moved away) resolves its deepest existing ancestor and keeps the rest.
public extension URL {
    var realPath: String { Self.realPath(path) }
    var realURL: URL { URL(fileURLWithPath: realPath) }

    static func realPath(_ path: String) -> String {
        let p = URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL.path
        var head = p, tail: [String] = []
        while true {
            if let r = realpath(head, nil) {
                defer { free(r) }
                let base = String(cString: r)
                return tail.isEmpty ? base : (base == "/" ? "" : base) + "/" + tail.reversed().joined(separator: "/")
            }
            guard head != "/", !head.isEmpty else { return p }
            tail.append((head as NSString).lastPathComponent)
            head = (head as NSString).deletingLastPathComponent
        }
    }
}
