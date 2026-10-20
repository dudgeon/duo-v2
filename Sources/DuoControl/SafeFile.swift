import Foundation

/// Reads and writes the user's own files under `~/.claude` without hurting them (BUG-117, F-339).
/// An unreadable file isn't an empty one, a link is written through and stays a link, and a file
/// that is read-only, locked (`chflags uchg`) or in a folder Duo can't write is reported, not forced.
/// Callers skip that one step, say why in Duo's words, and carry on.
enum SafeFile {
    enum Read {
        case missing
        case text(String)
        /// Present but Duo can't use it; the sentence says why, without a path or a verb.
        case blocked(String)
    }

    struct Blocked: Error { let why: String }

    static func read(_ url: URL) -> Read {
        let fm = FileManager.default
        let real = url.resolvingSymlinksInPath()
        guard fm.fileExists(atPath: real.path) else {
            return (try? fm.destinationOfSymbolicLink(atPath: url.path)) == nil ? .missing : .blocked("it's a link to a file that isn't there")
        }
        guard fm.isReadableFile(atPath: real.path) else { return .blocked("Duo can't read it") }
        guard let data = try? Data(contentsOf: real) else { return .blocked("Duo can't read it") }
        guard let s = String(data: data, encoding: .utf8) else { return .blocked("it isn't UTF-8 text") }
        return .text(s)
    }

    /// Writes through a link, only if the target and its folder accept it. Throws `Blocked`.
    static func write(_ text: String, to url: URL) throws {
        let fm = FileManager.default
        let real = url.resolvingSymlinksInPath()
        if fm.fileExists(atPath: real.path) {
            var st = stat()
            if stat(real.path, &st) == 0, st.st_flags & (UInt32(UF_IMMUTABLE) | UInt32(SF_IMMUTABLE)) != 0 { throw Blocked(why: "it's locked") }
            guard fm.isWritableFile(atPath: real.path) else { throw Blocked(why: "it's read-only") }
        } else {
            let folder = real.deletingLastPathComponent()
            try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
            guard fm.isWritableFile(atPath: folder.path) else { throw Blocked(why: "its folder isn't writable") }
        }
        do { try Data(text.utf8).write(to: real, options: .atomic) }
        catch { throw Blocked(why: "the write failed (\(error.localizedDescription))") }
    }
}
