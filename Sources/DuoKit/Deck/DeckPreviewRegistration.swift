import Foundation

/// Registers the deck preview with split view (Duo Decks P3). Called once at app start, from
/// `DuoApp.init` (Sources/Duo/DuoApp.swift), outside `Split/`.
///
/// Split view's `PreviewProviders.kind(forFile:frontmatter:)` asks each registered test, first match
/// wins. The deck registers with `PreviewProviders.register(.deck, test:make:)`, so split view hosts a
/// `DeckPreview` and calls its `bind(path:file:model:)` before the first render.
public enum DeckPreviewRegistration {
    /// A deck's frontmatter, read from a project-relative path by someone who knows the project's folder
    /// (the app model sets this); used when the caller passed no frontmatter (`previewKind(forTab:)` today).
    /// Called on the main thread.
    nonisolated(unsafe) public static var frontmatterOf: (@Sendable (String) -> [String: String])?

    @Sendable public static func test(_ file: String, _ frontmatter: [String: String]) -> Bool {
        let md = ["md", "markdown"].contains((file as NSString).pathExtension.lowercased())
        guard md else { return false }
        if !frontmatter.isEmpty { return frontmatter["type"] == "deck" }
        guard let read = frontmatterOf else { return false }
        return (Thread.isMainThread ? read(file) : DispatchQueue.main.sync { read(file) })["type"] == "deck"
    }

    nonisolated(unsafe) private static var installed = false

    /// Idempotent.
    public static func install() {
        guard !installed else { return }
        installed = true
        PreviewProviders.register(.deck, test: { file, front in test(file, front) }, make: { DeckPreview() })
    }

    /// Registers, and lets the test read a tab's frontmatter from the model's files (the model passes none).
    @MainActor public static func install(model: AppModel) {
        install()
        frontmatterOf = { [weak model] rel in
            MainActor.assumeIsolated {
                guard let url = model?.liveFile(rel), let h = try? FileHandle(forReadingFrom: url) else { return [:] }
                defer { try? h.close() }
                return frontmatter(of: String(decoding: (try? h.read(upToCount: 4096)) ?? Data(), as: UTF8.self))
            }
        }
    }

    /// The first lines of a Markdown file as frontmatter: `type: deck`, `template: northwind`.
    public static func frontmatter(of text: String) -> [String: String] {
        guard text.hasPrefix("---") else { return [:] }
        var out: [String: String] = [:]
        for l in text.split(separator: "\n", omittingEmptySubsequences: false).dropFirst().prefix(60) {
            if l.hasPrefix("---") { break }
            if let c = l.firstIndex(of: ":") {
                out[String(l[..<c]).trimmingCharacters(in: .whitespaces)] = String(l[l.index(after: c)...]).trimmingCharacters(in: .whitespaces)
            }
        }
        return out
    }
}
