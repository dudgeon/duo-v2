import DuoControl
import Foundation

// The logic behind the browser basics (DL-124): where downloads go and what they're called, the
// zoom remembered per site, and where a popup's tab sits. Pure, so DuoChecks can test it.

/// Downloads go to ~/Downloads, named as Finder names a clash: "report.pdf", then "report 2.pdf".
public enum DownloadNaming {
    /// ~/Downloads; an isolated Duo (F-113) keeps them in its own support folder, and
    /// `DUO_DOWNLOADS_DIR` points them anywhere (scripted checks).
    public static var folder: URL {
        if let d = ProcessInfo.processInfo.environment["DUO_DOWNLOADS_DIR"], !d.isEmpty { return URL(fileURLWithPath: d) }
        if SupportFolder.isIsolated { return DuoPaths.support.appending(path: "Downloads") }
        return FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: "Downloads")
    }

    /// A name safe to save: no folders, no leading dot, never empty.
    public static func clean(_ suggested: String) -> String {
        var n = suggested.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        while n.hasPrefix(".") { n.removeFirst() }
        return n.isEmpty ? "download" : n
    }

    /// The first free name in `folder`: the name itself, then "name 2.ext", "name 3.ext", …
    /// A double extension that belongs together (`.tar.gz`) stays together.
    public static func unique(_ suggested: String, in folder: URL, exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }) -> URL {
        let name = clean(suggested)
        let first = folder.appending(path: name)
        guard exists(first) else { return first }
        let (base, ext) = split(name)
        var n = 2
        while true {
            let u = folder.appending(path: "\(base) \(n)\(ext)")
            if !exists(u) { return u }
            n += 1
        }
    }

    /// "report.pdf" → ("report", ".pdf"); "a.tar.gz" → ("a", ".tar.gz"); "README" → ("README", "").
    static func split(_ name: String) -> (String, String) {
        for double in [".tar.gz", ".tar.bz2", ".tar.xz"] where name.lowercased().hasSuffix(double) && name.count > double.count {
            return (String(name.dropLast(double.count)), String(name.suffix(double.count)))
        }
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return (name, "") }
        return (String(name[..<dot]), String(name[dot...]))
    }
}

/// Page zoom for browser tabs: Safari's steps, and the level remembered per site (by host).
public struct ZoomStore {
    public static let steps: [Double] = [0.5, 0.67, 0.75, 0.8, 0.9, 1.0, 1.1, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0]
    public static let range: ClosedRange<Double> = 0.25...5.0
    public static var defaultFile: URL { DuoPaths.support.appending(path: "browser-zoom.json") }

    public let file: URL
    public private(set) var levels: [String: Double]

    public init(file: URL = ZoomStore.defaultFile) {
        self.file = file
        levels = (try? JSONDecoder().decode([String: Double].self, from: Data(contentsOf: file))) ?? [:]
    }

    /// The key a page's zoom is kept under: its host without `www.`, or "file" for local files.
    public static func site(_ url: URL?) -> String? {
        guard let url else { return nil }
        if url.isFileURL { return "file" }
        guard var h = url.host?.lowercased(), !h.isEmpty else { return nil }
        if h.hasPrefix("www.") { h.removeFirst(4) }
        return url.port.map { "\(h):\($0)" } ?? h
    }

    public func level(for url: URL?) -> Double { Self.site(url).flatMap { levels[$0] } ?? 1.0 }

    /// Remembers a site's level; 100% is forgotten rather than stored.
    public mutating func set(_ level: Double, for url: URL?) {
        guard let site = Self.site(url) else { return }
        levels[site] = abs(level - 1.0) < 0.001 ? nil : level
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(levels).write(to: file, options: .atomic)
    }

    public static func zoomIn(_ z: Double) -> Double { steps.first { $0 > z + 0.001 } ?? steps.last! }
    public static func zoomOut(_ z: Double) -> Double { steps.last { $0 < z - 0.001 } ?? steps.first! }

    /// What `duo2 browser zoom` takes: "in", "out", "reset", or a percent ("125", "125%").
    public static func parse(_ arg: String, current: Double) -> Double? {
        switch arg.lowercased() {
        case "in", "+": return zoomIn(current)
        case "out", "-": return zoomOut(current)
        case "reset", "0", "100", "100%", "actual": return 1.0
        default:
            guard let p = Double(arg.trimmingCharacters(in: CharacterSet(charactersIn: "% "))) else { return nil }
            let z = p / 100
            return range.contains(z) ? z : nil
        }
    }

    public static func percent(_ z: Double) -> String { "\(Int((z * 100).rounded()))%" }
}

/// Where a popup's tab goes (DL-124): right after its opener and the opener's other popups, so a
/// sign-in or dialog window sits beside the page that opened it.
public enum PopupPlacement {
    public static func index(in docs: [String], opener: String, openers: [String: String]) -> Int {
        guard var i = docs.firstIndex(of: opener) else { return docs.count }
        while i + 1 < docs.count, openers[docs[i + 1]] == opener { i += 1 }
        return i + 1
    }

    /// The tab to show when `closing` goes: its opener if it's still open, else the left neighbour
    /// (the new first tab if the first one closes; ENH-144).
    public static func after(closing: String, in docs: [String], openers: [String: String]) -> String? {
        if let o = openers[closing], docs.contains(o) { return o }
        guard let i = docs.firstIndex(of: closing) else { return docs.last }
        let rest = docs.filter { $0 != closing }
        return rest.isEmpty ? nil : rest[max(0, i - 1)]
    }
}
