import AppKit
import DuoControl
import DuoDeck
import Foundation

// Duo Decks P3b: the deck bar's state and actions, the cards under the slides and the comment pins (P3-1, P3-3).
extension DeckPreview {
    /// The errors (notices are counted in the menu only, P3-3).
    public var errors: [SourceProblem] { rendering.problems.filter { $0.severity == .error } }
    public var notices: [SourceProblem] { rendering.problems.filter { $0.severity == .notice } }

    /// What Duo draws round the slides, as the page takes it.
    func overlayJSON() -> [String: Any] {
        var shapes: [String: [String: Int]] = [:]
        for (slide, ids) in shapesDrawn { shapes[String(slide)] = Dictionary(ids.map { ($0.value, $0.key) }, uniquingKeysWith: { a, _ in a }) }
        return [
            "cards": rendering.cards.map { c -> [String: Any] in
                ["slide": c.slide, "kind": c.kind.rawValue, "slot": c.slot as Any, "message": c.message,
                 "buttons": c.buttons.map { ["id": $0.id, "label": $0.label] }]
            },
            "pins": rendering.pins.map { ["slide": $0.slide, "slot": $0.slot as Any, "count": $0.count, "thread": $0.thread] },
            "templates": rendering.templates,
            "shapes": shapes,
        ]
    }

    func pushOverlay() { viewer.setOverlay(overlayJSON()) }

    public func toggleMenu(_ which: String) {
        menu = menu == which ? nil : which
        menuHover = nil
        viewer.onChange?()
    }

    func hover(_ id: String?, leaving: String) {
        if let id { menuHover = id } else if menuHover == leaving { menuHover = nil }
        viewer.onChange?()
    }

    /// The slide a source line is in.
    func slide(ofLine line: Int) -> Int? {
        rendering.anchors.first { $0.anchor.hasPrefix("slide ") && !$0.anchor.contains("/") && $0.contains(line: line) }
            .flatMap { DeckPreviewBuild.parse(anchor: $0.anchor)?.slide }
    }

    /// Choosing a problem reveals both sides: its slide in the preview and its lines in the source.
    public func reveal(problem p: SourceProblem) {
        if let n = slide(ofLine: p.line) ?? DeckCards.split(p.message)?.slide, n != viewer.slide { revealMoved(to: n) }
        model?.editor(.main).run("return window.duo && duo.selectLines ? duo.selectLines(a, a) : false", ["a": p.line]) { _ in }
    }

    func problemMenuItems() -> [DeckMenuItem] {
        var out: [DeckMenuItem] = []
        func title(_ p: SourceProblem) -> String {
            guard let s = DeckCards.split(p.message) else { return p.message }
            return "\(s.slide) · " + (s.slot.map { "\($0): " } ?? "") + s.text
        }
        for (i, p) in errors.enumerated() {
            out.append(DeckMenuItem(id: "e\(i)", title: title(p), trailing: "line \(p.line)") { [weak self] in self?.reveal(problem: p) })
        }
        if !notices.isEmpty {
            out.append(DeckMenuItem(id: "d", title: "", divider: true))
            for (i, p) in notices.enumerated() {
                out.append(DeckMenuItem(id: "n\(i)", title: title(p), trailing: "notice") { [weak self] in self?.reveal(problem: p) })
            }
        }
        return out
    }

    func exportMenuItems() -> [DeckMenuItem] {
        let ex = rendering.export
        return [
            DeckMenuItem(id: "as", title: "Export as PowerPoint…") { [weak self] in self?.exportDeck() },
            DeckMenuItem(id: "again", title: "Export Again", trailing: ex.stamp.map { "replaces \($0)" }, enabled: ex.newest != nil) { [weak self] in self?.exportDeck() },
            DeckMenuItem(id: "show", title: "Show Export in Finder", enabled: ex.newest != nil) { [weak self] in self?.showExport() },
            DeckMenuItem(id: "d", title: "", divider: true),
            DeckMenuItem(id: "gs", title: "Upload to Google Slides…", trailing: "later", enabled: false),
        ]
    }

    /// The newest dated export beside the deck.
    public var exportURL: URL? {
        guard let file, let n = rendering.export.newest else { return nil }
        return file.deletingLastPathComponent().appending(path: n)
    }

    public func showExport() { if let u = exportURL { FileActions.reveal(u) } }

    /// Writes the deck's dated export beside it, removing the previous one (DL-282, DL-286): the same writer
    /// as `duo2 deck export`. Says what it wrote, or why it didn't.
    public func exportDeck(completion: (@MainActor @Sendable (ExportNotice) -> Void)? = nil) {
        guard let file else { return }
        let slides = rendering.slideCount
        Task.detached(priority: .userInitiated) { [weak self] in
            let note = Self.exportNote(file: file, slides: slides)
            await MainActor.run { self?.finishExport(note); completion?(note) }
        }
    }

    /// Checks and exports `file`; the notice says what happened.
    nonisolated static func exportNote(file: URL, slides: Int) -> ExportNotice {
        let dirs = Deck.packDirs(near: file.deletingLastPathComponent())
        do {
            let c = try Deck.check(deck: file, packDirs: dirs)
            if !c.problems.isEmpty {
                let n = c.problems.count
                return ExportNotice(text: "Not exported: \(n) problem\(n == 1 ? "" : "s") to fix first.",
                                    sub: c.problems.first.map { "\(file.lastPathComponent):\($0.line): \($0.message)" }, file: nil)
            }
            let e = try Deck.writeExport(deck: file, packDirs: dirs)
            return ExportNotice(text: "Exported \(e.url.lastPathComponent) · \(slides) slides", sub: nil, file: e.url)
        } catch { return ExportNotice(text: "Not exported: \(error)", sub: nil, file: nil) }
    }

    private func finishExport(_ note: ExportNotice) {
        exportNotice = note
        if let file { rendering.export = DeckExportState.read(deck: file, text: lastText) }
        viewer.onChange?()
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            if self?.exportNotice == note { self?.exportNotice = nil; self?.viewer.onChange?() }
        }
    }

    /// Add Comment in the picked bar: asks the source's margin to open its composer on the slot's lines.
    public func addCommentForPicked() {
        guard let a = pickedAnchor else { return }
        emit?(.addComment(anchor: a))
    }

    // MARK: Cards

    func cardAction(_ index: Int, _ button: String) {
        guard let file, let model, rendering.cards.indices.contains(index) else { return }
        let card = rendering.cards[index]
        let deck = model.displayPath(file)
        switch button {
        case "goto":
            model.editor(.main).run("return window.duo && duo.selectLines ? duo.selectLines(a, a) : false", ["a": card.line]) { _ in }
        case "send":
            model.sendDraft(DeckCards.request(for: card, deck: deck))
        case "split":
            model.sendDraft(DeckCards.splitRequest(slide: card.slide, template: card.template, deck: deck))
        case "undo":
            model.editor(.main).run("return window.duo && duo.undo ? duo.undo() : false", [:]) { _ in }
        case "fix":
            guard let fix = card.fixLine else { return }
            model.reviewText(file) { [weak model] text in
                guard let model, let text, let new = DeckCards.replacing(line: card.line, with: fix, in: text) else { return }
                model.reviewWrite(file, old: text, new: new, plain: true) { _ in }
            }
        default:
            guard button.hasPrefix("move:") else { return }
            let slot = String(button.dropFirst(5))
            model.reviewText(file) { [weak model] text in
                guard let model, let text, let new = DeckCards.moveNotes(source: text, slide: card.slide, to: slot) else { return }
                model.reviewWrite(file, old: text, new: new, plain: true) { _ in }
            }
        }
    }
}
