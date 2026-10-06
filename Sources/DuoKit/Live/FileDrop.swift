import Foundation

/// Files dragged onto Duo (DL-117): into a terminal as paths, and from Finder onto the file tree
/// as a move. Plain functions on paths and the disk, so DuoChecks can run them.
public enum FileDrop {
    // MARK: Paths into a terminal

    /// What a drop types at the cursor, as Terminal.app does: each path shell-escaped, separated by
    /// spaces, with a trailing space, and never a Return.
    public static func terminalText(_ urls: [URL]) -> String {
        urls.map { shellEscaped($0.standardizedFileURL.path) }.joined(separator: " ") + " "
    }

    /// Characters a shell takes as themselves. Everything else in ASCII gets a backslash, as
    /// Terminal.app writes a dropped path; letters beyond ASCII (é, 日本, emoji) stay as they are.
    private static let plain = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789/._-+:@%,".unicodeScalars)

    /// One path for a shell. A control character (a newline in a file name) can't be backslashed
    /// (backslash-newline continues the line, and a bare newline would be a Return), so such a path
    /// is written whole in `$'…'` with the character as an escape.
    public static func shellEscaped(_ path: String) -> String {
        if path.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F }) {
            var out = "$'"
            for s in path.unicodeScalars {
                switch s {
                case "\\": out += "\\\\"
                case "'": out += "\\'"
                case "\n": out += "\\n"
                case "\r": out += "\\r"
                case "\t": out += "\\t"
                default: out += s.value < 0x20 || s.value == 0x7F ? String(format: "\\x%02x", s.value) : String(s)
                }
            }
            return out + "'"
        }
        var out = ""
        for s in path.unicodeScalars {
            if s.value < 0x80 && !plain.contains(s) { out += "\\" }
            out.unicodeScalars.append(s)
        }
        return out
    }

    // MARK: Moving into a folder

    /// What a drop does with one item. Finder moves on the same volume and copies across volumes;
    /// Duo does the same (Q-51).
    public enum Mode: String, Sendable { case move, copy }

    /// A taken name, answered once for the whole drop.
    public enum Clash: Sendable { case replace, keepBoth }

    /// One item's plan.
    public struct Plan: Equatable, Sendable {
        public var source: URL
        public var dest: URL
        public var mode: Mode
        /// Something is already at `dest`.
        public var clashes: Bool
    }

    /// One item done, with what undo needs.
    public struct Done: Sendable {
        public var source: URL
        public var dest: URL
        public var mode: Mode
        /// Where Replace put the item that was there (in the Trash).
        public var replaced: URL?
    }

    /// Why an item can't go into `dir`, or nil. A folder can't go into itself or anything inside
    /// it; nothing can replace a folder holding it.
    public static func refusal(_ source: URL, into dir: URL) -> String? {
        let s = canonical(source), d = canonical(dir)
        if d == s || d.hasPrefix(s + "/") { return "“\(source.lastPathComponent)” can't go into itself" }
        return nil
    }

    /// The plan for each item: skipped when it's already in `dir`; refused (with why) when it
    /// would go into itself.
    public static func plan(_ sources: [URL], into dir: URL) -> (plans: [Plan], refused: [String]) {
        var plans: [Plan] = [], refused: [String] = []
        var seen = Set<String>()
        for src in sources {
            let s = canonical(src)
            guard seen.insert(s).inserted else { continue }
            if let why = refusal(src, into: dir) { refused.append(why); continue }
            if (s as NSString).deletingLastPathComponent == canonical(dir) { continue }  // already here
            let dest = dir.appending(path: src.lastPathComponent)
            // The thing there holds the source (dragging docs/a/docs onto docs/a's parent): replacing it would trash the source.
            if s.hasPrefix(canonical(dest) + "/") { refused.append("“\(src.lastPathComponent)” is inside the folder it would replace"); continue }
            plans.append(Plan(source: src, dest: dest, mode: sameVolume(src, dir) ? .move : .copy,
                              clashes: FileManager.default.fileExists(atPath: dest.path)))
        }
        return (plans, refused)
    }

    /// Carries out a plan. A clash without an answer throws; Replace puts what was there in the
    /// Trash first, never deletes it; Keep Both picks "name 2", like Finder.
    public static func perform(_ plan: Plan, clash: Clash?) throws -> Done {
        let fm = FileManager.default
        var dest = plan.dest, replaced: URL?
        if fm.fileExists(atPath: dest.path) {
            switch clash {
            case nil: throw FileActionError("“\(dest.lastPathComponent)” already exists there")
            case .keepBoth:
                let ext = dest.pathExtension.isEmpty || isFolder(plan.source) ? nil : dest.pathExtension
                let stem = ext == nil ? dest.lastPathComponent : dest.deletingPathExtension().lastPathComponent
                dest = dest.deletingLastPathComponent().appending(path: freeName(stem, ext: ext, in: dest.deletingLastPathComponent()))
            case .replace:
                replaced = try trash(dest)
            }
        }
        do {
            switch plan.mode {
            case .move: try fm.moveItem(at: plan.source, to: dest)
            case .copy: try fm.copyItem(at: plan.source, to: dest)
            }
        } catch {
            // Put back what Replace took, so a failed move loses nothing.
            if let r = replaced { try? fm.moveItem(at: r, to: dest) }
            throw error
        }
        return Done(source: plan.source, dest: dest, mode: plan.mode, replaced: replaced)
    }

    /// Puts a drop back: moved items return, copies go to the Trash, replaced items come back out
    /// of the Trash. Stops short of overwriting anything that has appeared since; returns what it
    /// couldn't put back.
    @discardableResult
    public static func undo(_ done: [Done]) -> [String] {
        let fm = FileManager.default
        var left: [String] = []
        for d in done.reversed() {
            switch d.mode {
            case .move:
                if fm.fileExists(atPath: d.source.path) { left.append("“\(d.source.lastPathComponent)” is back in its old folder already") }
                else if (try? fm.moveItem(at: d.dest, to: d.source)) == nil { left.append("couldn't move “\(d.dest.lastPathComponent)” back") }
            case .copy:
                if (try? trash(d.dest)) == nil { left.append("couldn't put the copy of “\(d.dest.lastPathComponent)” in the Trash") }
            }
            if let r = d.replaced {
                if fm.fileExists(atPath: d.dest.path) { left.append("“\(d.dest.lastPathComponent)” is taken again; the replaced one is still in the Trash") }
                else if (try? fm.moveItem(at: r, to: d.dest)) == nil { left.append("couldn't bring “\(d.dest.lastPathComponent)” back from the Trash") }
            }
        }
        return left
    }

    // MARK: Helpers

    /// Puts an item in the Trash, returning where it went. DuoChecks swaps in a scratch folder so
    /// its runs leave nothing in the user's Trash.
    nonisolated(unsafe) public static var trash: (URL) throws -> URL? = { url in
        var out: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &out)
        return out as URL?
    }

    static func canonical(_ url: URL) -> String { url.resolvingSymlinksInPath().standardizedFileURL.path }

    static func isFolder(_ url: URL) -> Bool {
        var d: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &d) && d.boolValue
    }

    /// Whether two places are on one volume (a move), or not (a copy, as Finder does).
    public static func sameVolume(_ a: URL, _ b: URL) -> Bool {
        let ka = try? a.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier
        let kb = try? b.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier
        guard let ka = ka ?? nil, let kb = kb ?? nil else { return true }
        return ka.isEqual(kb)
    }

    /// FileActions.freeName without the main actor.
    static func freeName(_ base: String, ext: String?, in dir: URL) -> String {
        func name(_ n: Int) -> String {
            let stem = n == 1 ? base : "\(base) \(n)"
            return ext.map { "\(stem).\($0)" } ?? stem
        }
        var n = 2  // the plain name is the one that's taken
        while FileManager.default.fileExists(atPath: dir.appending(path: name(n)).path) { n += 1 }
        return name(n)
    }
}
