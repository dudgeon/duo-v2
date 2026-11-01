import DuoDeck
import Foundation

/// The deck's editor pieces (DL-295, DL-296, DL-303): the page draws the slide chip, the template picker and the
/// anchor mark; Swift owns what touches the deck. A pick comes back as a message with the buffer's text, DuoDeck's
/// insert or change runs on it (the same code as `duo2 deck insert` and `duo2 deck change`), and the whole new text goes
/// back to the page, which applies it as one undo step.
extension EditorController {
    /// The pack a deck's text names, found from the file's folder (project, then Home, then built in).
    public static func deckPack(for text: String, file: URL?) -> Deck.Pack? {
        guard let file else { return nil }
        let name = Deck.parse(text).front["template"] ?? Deck.builtInPackName
        return try? Deck.loadPack(name, in: Deck.packDirs(near: file.deletingLastPathComponent()))
    }

    /// What the picker lists: `{ pack, templates: [{ name, purpose, slots: [{ name, kind }] }] }`.
    public static func deckTemplatesJSON(_ pack: Deck.Pack) -> String {
        let ts: [[String: Any]] = pack.templates.map { t in
            ["name": t.name,
             "purpose": t.purpose.split(separator: "\n").first.map(String.init) ?? "",
             "slots": t.slots.map { ["name": $0.name, "kind": $0.kind] }]
        }
        let obj: [String: Any] = ["pack": pack.name, "templates": ts]
        let data = (try? JSONSerialization.data(withJSONObject: obj)) ?? Data("{}".utf8)
        return String(decoding: data, as: UTF8.self)
    }

    /// The first and last line (1-based) of the slide holding `line`, nil above the first slide.
    public static func deckAnchor(text: String, line: Int) -> (first: Int, last: Int)? {
        let slides = Deck.parse(text).slides
        guard let s = slides.last(where: { $0.line <= line }) else { return nil }
        return (s.line, max(s.lastLine, s.line))
    }

    /// The result of a pick: the deck's new text and the line the caret goes to (the new slide's title, or the changed slide's marker).
    public static func deckPicked(op: String, slide: Int, template: String, text: String, pack: Deck.Pack) throws -> (text: String, line: Int) {
        guard let t = pack.template(template) else { throw Deck.Failure(description: "no template \"\(template)\" in \(pack.md.lastPathComponent)") }
        if op == "insert" {
            let new = try Deck.insertSlide(source: text, template: t, after: slide)
            let s = Deck.parse(new).slides
            let at = slide < s.count ? s[slide].line : 1
            return (new, at + (t.slot("title") != nil ? 1 : 0))
        }
        let c = try Deck.changeTemplate(source: text, slide: slide, to: template, pack: pack)
        let s = Deck.parse(c.text).slides
        return (c.text, slide >= 1 && slide <= s.count ? s[slide - 1].line : 1)
    }

    func handleDeck(_ kind: EditorMessage, _ body: [String: Any]) {
        switch kind {
        case .deckDoc:
            isDeck = body["deck"] as? Bool == true
            onStateChange?()
            guard isDeck else { return }
            currentText { [weak self] text in
                guard let self, let text, let pack = Self.deckPack(for: text, file: self.url) else { return }
                self.run("return duo.setDeckTemplates(j)", ["j": Self.deckTemplatesJSON(pack)]) { _ in }
            }
        case .deckCaret:
            guard isDeck, let line = body["line"] as? Int, let text = body["text"] as? String else { return }
            let a = Self.deckAnchor(text: text, line: line)
            run("return duo.setDeckAnchor(f, l)", ["f": a?.first ?? 0, "l": a?.last ?? 0]) { _ in }
        case .deckPick:
            guard let op = body["op"] as? String, let slide = body["slide"] as? Int, let name = body["template"] as? String,
                  let text = body["text"] as? String, let pack = Self.deckPack(for: text, file: url) else { return }
            do {
                let r = try Self.deckPicked(op: op, slide: slide, template: name, text: text, pack: pack)
                run("return duo.deckApply(t, l)", ["t": r.text, "l": r.line]) { _ in }
            } catch {
                lastEvent = "deck: \(error)"
            }
        default: break
        }
    }

    /// ⌃⌘N, New Slide (DL-295): a new chip under the caret's slide, with the picker open.
    public func newSlide() { run("return duo.deckNewSlide()") { _ in } }

    /// Reveals a slide's lines in the source (the slides side's click).
    public func revealDeckSlot(first: Int, last: Int) { run("return duo.revealDeckSlot(f, l)", ["f": first, "l": last]) { _ in } }
}
