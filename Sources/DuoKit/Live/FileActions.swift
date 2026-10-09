import AppKit
import Foundation

/// File verbs for the file tree and document tabs (DL-61). Plain filesystem operations on the
/// project folder; nothing is ever deleted outright (the Trash only). Names never clobber: a
/// taken name gets " 2", " 3", … like Finder.
@MainActor
public enum FileActions {
    /// A name in `dir` that isn't taken: "Untitled.md", "Untitled 2.md", …
    public static func freeName(_ base: String, ext: String?, in dir: URL) -> String {
        let fm = FileManager.default
        func name(_ n: Int) -> String {
            let stem = n == 1 ? base : "\(base) \(n)"
            return ext.map { "\(stem).\($0)" } ?? stem
        }
        var n = 1
        while fm.fileExists(atPath: dir.appending(path: name(n)).path) { n += 1 }
        return name(n)
    }

    public static func newMarkdown(in dir: URL, contents: String = "") throws -> URL {
        let url = dir.appending(path: freeName("Untitled", ext: "md", in: dir))
        try Data(contents.utf8).write(to: url, options: .withoutOverwriting)
        return url
    }

    public static func newFolder(in dir: URL) throws -> URL {
        let url = dir.appending(path: freeName("untitled folder", ext: nil, in: dir))
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }

    /// Renames in place. Refuses a name that's empty, contains "/", or is taken.
    public static func rename(_ url: URL, to name: String) throws -> URL {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, !clean.contains("/"), clean != "." , clean != ".." else { throw FileActionError("“\(name)” isn't a usable name") }
        let dest = url.deletingLastPathComponent().appending(path: clean)
        guard dest.path != url.path else { return url }
        guard !FileManager.default.fileExists(atPath: dest.path) else { throw FileActionError("“\(clean)” already exists here") }
        try FileManager.default.moveItem(at: url, to: dest)
        return dest
    }

    public static func duplicate(_ url: URL) throws -> URL {
        let ext = url.pathExtension.isEmpty ? nil : url.pathExtension
        let stem = url.deletingPathExtension().lastPathComponent
        let dest = url.deletingLastPathComponent().appending(path: freeName("\(stem) copy", ext: ext, in: url.deletingLastPathComponent()))
        try FileManager.default.copyItem(at: url, to: dest)
        return dest
    }

    public static func move(_ url: URL, into dir: URL) throws -> URL {
        let dest = dir.appending(path: url.lastPathComponent)
        guard dest.path != url.path else { return url }
        guard !FileManager.default.fileExists(atPath: dest.path) else { throw FileActionError("“\(url.lastPathComponent)” already exists there") }
        try FileManager.default.moveItem(at: url, to: dest)
        return dest
    }

    /// Asks for a folder inside (or anywhere under) the project.
    public static func chooseFolder(startingAt dir: URL) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = dir
        panel.prompt = "Move Here"
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// File › Open File… (DL-106): any file on the Mac, several at once.
    public static func chooseFiles(startingAt dir: URL?) -> [URL] {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.directoryURL = dir
        panel.prompt = "Open"
        return panel.runModal() == .OK ? panel.urls : []
    }

    /// Moves to the Trash (recoverable). Never deletes.
    public static func trash(_ url: URL) throws {
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
    }

    /// Trashes the item if it is there; false when it is already gone (a dangling symlink still counts as there).
    /// Move to Trash on a file that vanished from disk just closes its tab (legacy Duo BUG-098).
    @discardableResult
    public static func trashIfPresent(_ url: URL) throws -> Bool {
        var st = stat()
        guard lstat(url.path, &st) == 0 else { return false }
        try trash(url)
        return true
    }

    // MARK: Copy, reveal, open

    public static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// `[name](relative/path.md)`: a Markdown link, Obsidian-compatible (DL-17). Spaces are
    /// percent-encoded so the link survives in any Markdown renderer.
    public static func markdownLink(name: String, relative: String) -> String {
        let target = relative.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "()"))) ?? relative
        let title = (name as NSString).deletingPathExtension
        return "[\(title)](\(target))"
    }

    public static func reveal(_ url: URL) { NSWorkspace.shared.activateFileViewerSelecting([url]) }

    public static func openInDefaultApp(_ url: URL) { NSWorkspace.shared.open(url) }

    /// Lets the user pick an application, then opens the file with it.
    public static func openWithChosenApp(_ url: URL) {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.prompt = "Open"
        guard panel.runModal() == .OK, let app = panel.url else { return }
        NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }

    /// Apps that can open the file, default first (for an "Open With" submenu).
    public static func apps(for url: URL) -> [URL] {
        let all = NSWorkspace.shared.urlsForApplications(toOpen: url)
        let def = NSWorkspace.shared.urlForApplication(toOpen: url)
        return (def.map { [$0] } ?? []) + all.filter { $0 != def }.prefix(8)
    }

    // MARK: Templates

    /// Markdown files in the project's `templates/` folder, then Home's. `new-project.md` and `new-task.md`
    /// are the templates New Project and New Task use (DL-146), so they're not listed here.
    public static func templates(project: URL, home: URL?) -> [URL] {
        let dirs = [project.appending(path: "templates")] + (home.map { [$0.appending(path: "templates")] } ?? [])
        var seen = Set<String>()
        return dirs.flatMap { dir in
            ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
                .filter { f in f.pathExtension.lowercased() == "md" && !Templates.Kind.allCases.contains { $0.fileName == f.lastPathComponent } }
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        }.filter { seen.insert($0.lastPathComponent).inserted }
    }

    /// A new file from a template: named after it, never over an existing file, with Obsidian's
    /// placeholders filled as its Templates plugin would (`{{title}}` is the new file's name; DL-146).
    public static func newFromTemplate(_ template: URL, in dir: URL, date: Date = Date()) throws -> URL {
        let stem = template.deletingPathExtension().lastPathComponent
        let dest = dir.appending(path: freeName(stem, ext: "md", in: dir))
        let text = try String(contentsOf: template, encoding: .utf8)
        let filled = Templates.fill(text, title: dest.deletingPathExtension().lastPathComponent, date: date)
        try Data(filled.utf8).write(to: dest, options: .withoutOverwriting)
        return dest
    }
}

public struct FileActionError: Error, LocalizedError {
    public var errorDescription: String?
    public init(_ m: String) { errorDescription = m }
}
