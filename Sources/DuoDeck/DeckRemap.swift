import Foundation

/// Changing a slide's template (DL-281, DL-285): where each slot's content goes, and what moves to
/// the speaker notes. Duo's rules, one set for every pack, which a pack may override:
///  0. a pack's own mapping (`from: {bullets: {body: left}}` in the target's yaml) wins;
///  1. a slot whose name exists in the new template, and whose kind matches, keeps its content
///     (`title` stays `title` this way);
///  2. the default slot goes to the new default slot when the kinds match;
///  3. otherwise a slot goes to the only unused slot of its kind;
///  4. anything left goes to the speaker notes, under a line naming where it came from. Never dropped.
/// Comments travel with their slot's text (DL-284): a slot carries its `raw` lines, comments included.
extension Deck {
    public struct Remap: Sendable {
        public struct Move: Equatable, Sendable {
            public var from: String
            public var to: String
            public init(from: String, to: String) { self.from = from; self.to = to }
        }
        /// The new template's slots, in its order. Slots with nothing to put in them are there too,
        /// empty (they show as empty slots, a notice and not an error).
        public var slots: [Slot]
        /// Where content went, including slots that kept their name.
        public var moves: [Move]
        /// The old slots with no place in the new template, in slide order.
        public var unplaced: [String]
        /// What to append under the slide's `> [!note]`, without the `> ` prefix: the line
        /// `Not placed after changing to <template>: <slot>, …`, then the content. Empty when
        /// nothing was left over.
        public var notes: [String]
    }

    /// Pure: the same slide and templates give the same answer. `packOverrides` is the target's
    /// `from:` map (by old template name, then old slot to new slot); by default the target template's own.
    public static func remap(_ slide: Slide, from: Template, to: Template, packOverrides: [String: [String: String]]? = nil) -> Remap {
        let overrides = (packOverrides ?? to.overrides)[from.name] ?? [:]
        // The slide's slots by their real names: unheaded text is the old default slot, a lone image its image slot.
        let pics = from.slots.filter { $0.kind == "image" }
        var old: [Slot] = slide.slots.compactMap { s in
            var s = s
            if s.name == "_default" { guard let d = from.defaultSlot else { return s }; s.name = d.name }
            if s.name == "_image" { guard pics.count == 1 else { return s }; s.name = pics[0].name }
            return s
        }
        old.sort { $0.line < $1.line }
        func kind(_ s: Slot) -> String { from.slot(s.name)?.kind ?? (s.name == "title" ? "text" : "") }

        var used = Set<String>()
        var placed: [String: Slot] = [:]       // by new slot name
        var moves: [Remap.Move] = []
        var left: [Slot] = old
        func put(_ s: Slot, _ target: String) {
            var n = s
            n.name = target
            placed[target] = n
            used.insert(target)
            moves.append(Remap.Move(from: s.name, to: target))
            left.removeAll { $0.name == s.name }
        }
        // 0. the pack's own mapping
        for s in left { if let t = overrides[s.name], to.slot(t) != nil, !used.contains(t) { put(s, t) } }
        // 1. the same name and kind
        for s in left { if let t = to.slot(s.name), !used.contains(t.name), t.kind == kind(s) { put(s, t.name) } }
        // 2. the default slot to the default slot
        if let od = from.defaultSlot, let nd = to.defaultSlot, !used.contains(nd.name), od.kind == nd.kind,
           let s = left.first(where: { $0.name == od.name }) { put(s, nd.name) }
        // 3. the only unused slot of the same kind
        for s in left {
            let candidates = to.slots.filter { !used.contains($0.name) && $0.kind == kind(s) }
            if candidates.count == 1 { put(s, candidates[0].name) }
        }

        let newSlots = to.slots.map { spec in placed[spec.name] ?? Slot(name: spec.name, line: 0, lastLine: 0, lines: []) }
        var notes: [String] = []
        if !left.isEmpty {
            notes.append("Not placed after changing to \(to.name): " + left.map(\.name).joined(separator: ", "))
            for s in left {
                let body = s.raw.isEmpty ? s.lines : s.raw
                if left.count > 1 { notes.append("\(s.name):") }
                notes += body
            }
        }
        return Remap(slots: newSlots, moves: moves, unplaced: left.map(\.name), notes: notes)
    }

    public struct Change: Sendable {
        /// The whole deck after the change.
        public var text: String
        public var remap: Remap
    }

    /// Changes slide `n` (1-based) to template `name`: rewrites that slide's section of `source`
    /// and returns the new text. The marker changes, the title stays, the new template's slots follow
    /// in its order (empty ones as bare headings), and anything unplaced goes under the slide's
    /// `> [!note]` callout (made if the slide has none). The slide's other lines (a slide comment, the
    /// trailing `---`) stay.
    public static func changeTemplate(source: String, slide n: Int, to name: String, pack: Pack) throws -> Change {
        let parsed = parse(source)
        guard n >= 1, n <= parsed.slides.count else { throw Failure(description: "the deck has \(parsed.slides.count) slides; no slide \(n)") }
        let slide = parsed.slides[n - 1]
        guard let from = pack.template(slide.template) else {
            throw Failure(description: "slide \(n) is on \"\(slide.template)\", which \(pack.md.lastPathComponent) doesn't have; fix that first (duo2 deck check)")
        }
        guard let to = pack.template(name) else {
            throw Failure(description: "no template \"\(name)\" in \(pack.md.lastPathComponent); use one of \(pack.templates.map(\.name).joined(separator: ", "))")
        }
        let r = remap(slide, from: from, to: to)
        let lines = source.components(separatedBy: "\n")
        let first = slide.line                                            // 1-based, the marker
        let end = n < parsed.slides.count ? parsed.slides[n].line - 1 : lines.count   // inclusive
        func plain(_ i: Int) -> Bool { let t = lines[i - 1].trimmingCharacters(in: .whitespaces); return t.isEmpty || t == "---" }
        var contentEnd = end
        while contentEnd > first, plain(contentEnd) { contentEnd -= 1 }
        let tail = contentEnd < end ? Array(lines[contentEnd...(end - 1)]) : []   // the lines after the content, kept as they were

        // Lines no slot, title or note owns stay with the slide, right after its marker.
        var owned = Set<Int>([first])
        for s in slide.slots { owned.formUnion(s.line...max(s.blockEnd, s.line)) }
        var oldNotes: [String] = []
        if let nl = slide.notesLine {
            var i = nl
            while i <= contentEnd, lines[i - 1].hasPrefix(">") { owned.insert(i); if i > nl { oldNotes.append(String(lines[i - 1].dropFirst()).trimmingCharacters(in: .init(charactersIn: " "))) }; i += 1 }
        }
        let stray = (first + 1...max(first + 1, contentEnd)).filter { $0 <= contentEnd && !owned.contains($0) && !plain($0) }.map { lines[$0 - 1] }

        var out: [String] = ["<!-- slide: \(name) -->"] + stray
        if let t = r.slots.first(where: { $0.name == "title" }), let text = t.raw.first ?? t.lines.first, !text.isEmpty { out.append("# \(text)") }
        for s in r.slots where s.name != "title" {
            out.append("")
            out.append("## \(s.name)")
            out += s.raw.isEmpty ? s.lines : s.raw
        }
        if !oldNotes.isEmpty || !r.notes.isEmpty {
            out.append("")
            out.append("> [!note]")
            out += oldNotes.map { $0.isEmpty ? ">" : "> \($0)" }
            out += r.notes.map { $0.isEmpty ? ">" : "> \($0)" }
        }
        out += tail
        var all = Array(lines[0..<(first - 1)])
        all += out
        if end < lines.count { all += lines[end...] }
        return Change(text: all.joined(separator: "\n"), remap: r)
    }
}
