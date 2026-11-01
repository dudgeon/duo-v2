import Foundation

/// Exports carry their date and time (DL-282) and only the newest is kept (DL-286):
/// `<deck> YYYY-MM-DD HHmm.pptx` beside the deck.
extension Deck {
    /// `field-trial-review 2026-10-31 1405.pptx`. The time comes from the caller (tests pass a fixed one).
    public static func exportName(deckName: String, at date: Date, timeZone: TimeZone = .current) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return String(format: "%@ %04d-%02d-%02d %02d%02d.pptx", deckName, c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0)
    }

    /// Whether `file` is a dated export of the deck called `deckName` (and not of another deck whose name starts the same).
    public static func isExport(_ file: String, of deckName: String) -> Bool {
        guard file.hasPrefix(deckName + " "), file.hasSuffix(".pptx") else { return false }
        let rest = file.dropFirst(deckName.count + 1).dropLast(5)
        return rest.range(of: #"^\d{4}-\d{2}-\d{2} \d{4}$"#, options: .regularExpression) != nil
    }

    public struct Exported: Sendable {
        public var url: URL
        public var bytes: Int
        /// The deck's earlier dated exports that this one replaced.
        public var removed: [URL]
    }

    /// Writes the export into `dir` (default: beside the deck) and removes the deck's previous dated
    /// exports. Nothing is removed if the export fails. The bytes depend only on the source and the
    /// pack; only the name carries the time.
    public static func writeExport(deck: URL, packDirs: [URL], dir: URL? = nil, now: Date = Date(), timeZone: TimeZone = .current, measureFit: Bool = true) throws -> Exported {
        let data = try export(deck: deck, packDirs: packDirs, measureFit: measureFit)
        let out = dir ?? deck.deletingLastPathComponent()
        let name = deck.deletingPathExtension().lastPathComponent
        let fm = FileManager.default
        try fm.createDirectory(at: out, withIntermediateDirectories: true)
        let url = out.appending(path: exportName(deckName: name, at: now, timeZone: timeZone))
        try data.write(to: url, options: .atomic)
        var removed: [URL] = []
        for f in (try? fm.contentsOfDirectory(atPath: out.path)) ?? [] where isExport(f, of: name) && f != url.lastPathComponent {
            let old = out.appending(path: f)
            if (try? fm.removeItem(at: old)) != nil { removed.append(old) }
        }
        return Exported(url: url, bytes: data.count, removed: removed.sorted { $0.path < $1.path })
    }
}
