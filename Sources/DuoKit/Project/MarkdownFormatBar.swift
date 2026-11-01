import AppKit
import DuoControl
import SwiftUI

/// The Markdown formatting bar (DL-266; target markdown-toolbar-handoff `bar`): 24 high (`formatBarHeight`), laid over the top
/// of the editor while a Markdown document has the keyboard, so the text never moves. Style ⌄, Bold, Italic, Link, Insert Table
/// and ⋯ at the left; the mic at the trailing end. In a table, + Row, + Column, Align ⌄ and Delete ⌄ take Style's place (the
/// in-document table bar is gone). Listening, the controls give way to the hint row. Clicks never take the keyboard from the text.
enum FormatBarLogic {
    /// When the bar shows (DL-266): the pane's focus rule, DL-165. It stays while one of its menus is open and while a dictation runs.
    static func shows(editorHasKeyboard: Bool, isMarkdown: Bool, hidden: Bool, source: Bool, readOnly: Bool, templatePreview: Bool,
                      menuOpen: Bool, dictating: Bool) -> Bool {
        isMarkdown && !hidden && !source && !readOnly && !templatePreview && (editorHasKeyboard || menuOpen || dictating)
    }

    /// Style ⌄'s items, in order: the title and the `duo2 doc format` word.
    static let styles: [(title: String, command: String)] = [
        ("Body", "body"), ("Heading 1", "heading1"), ("Heading 2", "heading2"), ("Heading 3", "heading3"), ("Quote", "quote"),
        ("Bulleted List", "bullet"), ("Numbered List", "numbered"), ("Task", "task"), ("Code Block", "codeblock"),
    ]

    /// The paragraph at the caret, named for Style's label.
    static func styleTitle(_ block: String) -> String {
        if let s = styles.first(where: { $0.command == block }) { return s.title }
        if block.hasPrefix("heading"), let n = Int(block.dropFirst(7)) { return "Heading \(n)" }
        return "Body"
    }

    /// Under 420 the table's Align and Delete fold into ⋯.
    static func foldsTableMenus(width: CGFloat) -> Bool { width < 420 }

    // Measures from `bar` (handoff §The bar).
    static let leading: CGFloat = 22, trailing: CGFloat = 20
    static let glyphWidth: CGFloat = 24, controlHeight: CGFloat = 20, glyphRadius: CGFloat = 5, markSize: CGFloat = 13
    static let micDiameter: CGFloat = 20, micGlyph: CGFloat = 12, separatorHeight: CGFloat = 12, gap: CGFloat = 2
}

/// Where the bar goes: over the editor of this side, on a Markdown document.
struct MarkdownFormatBarSlot: View {
    @Environment(AppModel.self) private var model
    @Environment(\.editorSide) private var side
    let file: URL

    var body: some View {
        let _ = model.editorRevision
        let e = model.editor(side)
        let isMarkdown = AppModel.markdownExtensions.contains(file.pathExtension.lowercased()) && e.url?.standardizedFileURL == file.standardizedFileURL
        let voice = model.voice
        let dictating: Bool = { if case .document(let p)? = voice.target, voice.state.isActive, p == e.url?.path { return true }; return false }()
        let shows = FormatBarLogic.shows(
            editorHasKeyboard: model.webFocus == .editor && model.editors.active == side, isMarkdown: isMarkdown, hidden: model.formatBarHidden,
            source: model.sourceDocuments.contains(file.standardizedFileURL.path), readOnly: e.readOnlyReason != nil, templatePreview: e.previewing,
            menuOpen: model.formatBarMenuOpen && model.editors.active == side, dictating: dictating)
        let _ = e.setFormatBar(shows)
        if shows { MarkdownFormatBar().transition(.identity) }
    }
}

struct MarkdownFormatBar: View {
    @Environment(AppModel.self) private var model
    @Environment(\.editorSide) private var side

    var body: some View {
        let _ = model.editorRevision
        let e = model.editor(side)
        let voice = model.voice
        let mine: Bool = { if case .document(let p)? = voice.target, p == e.url?.path { return true }; return false }()
        let state = mine ? voice.state : .idle
        GeometryReader { g in
            let folds = FormatBarLogic.foldsTableMenus(width: g.size.width)
            HStack(spacing: 0) {
                if mine, ChatVoiceLine.shows(state) { hintRow(state) }
                else { controls(e, folds: folds) }
                Spacer(minLength: 0)
                mic(state: state, mine: mine)
            }
            .padding(.leading, FormatBarLogic.leading).padding(.trailing, FormatBarLogic.trailing)
            .frame(width: g.size.width, height: DuoMetric.formatBarHeight)
        }
        .frame(height: DuoMetric.formatBarHeight)
        .background(DuoColor.pane)
        .overlay(alignment: .bottom) { DuoColor.rule.frame(height: DuoMetric.borderHairline) }
        .zIndex(2)
    }

    // MARK: Controls

    @ViewBuilder private func controls(_ e: EditorController, folds: Bool) -> some View {
        let inTable = e.inTable
        HStack(spacing: FormatBarLogic.gap) {
            if !inTable { styleMenu(e) ; separator }
            glyph("bold", help: "Bold ⌘B", on: e.caretMarks.contains("bold")) { Text("B").font(.system(size: FormatBarLogic.markSize, weight: .bold)) } run: { format("bold") }
            glyph("italic", help: "Italic ⌘I", on: e.caretMarks.contains("italic")) { Text("I").font(.system(size: FormatBarLogic.markSize, weight: .regular).italic()) } run: { format("italic") }
            glyph("link", help: "Link ⌘K", on: e.caretMarks.contains("link")) { Image(systemName: "link").font(.system(size: FormatBarLogic.markSize)) } run: { format("link") }
            if inTable {
                separator
                wordButton("+ Row", help: "Add Row Below") { format("tableRowBelow") }
                wordButton("+ Column", help: "Add Column After") { format("tableColumnAfter") }
                if !folds {
                    menuButton("Align", help: "Align Column") { alignMenu() }
                    menuButton("Delete", help: "Delete Row or Column") { deleteMenu() }
                }
            } else {
                glyph("table", help: "Insert Table", on: false) { Image(systemName: "tablecells").font(.system(size: FormatBarLogic.markSize)) } run: { format("tableInsert") }
            }
            glyph("more", help: "More", on: model.formatBarMenuOpen) { Image(systemName: "ellipsis").font(.system(size: FormatBarLogic.markSize)) } run: { popUp("more", moreMenu(e, folds: folds && inTable)) }
        }
    }

    private var separator: some View {
        DuoColor.rule.frame(width: DuoMetric.borderHairline, height: FormatBarLogic.separatorHeight).padding(.horizontal, 4)
    }

    private func styleMenu(_ e: EditorController) -> some View {
        let title = FormatBarLogic.styleTitle(e.caretBlock)
        return wordLabel(title, chevron: true, on: model.formatBarHover == "style")
            .onHover { hover("style", $0) }
            .onActivate { popUp("style", styleItems(e)) }  // action: doc format
            .help("Paragraph Style")
            .accessibilityLabel("Style: \(title)")
            .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { model.formatBarFrames["style"] = $0 }
    }

    private func wordLabel(_ title: String, chevron: Bool, on: Bool) -> some View {
        HStack(spacing: 1) {
            Text(title).duoText(.control)
            if chevron { Image(systemName: "chevron.down").font(.system(size: DuoSymbolSize.chevronSmall, weight: .semibold)) }
        }
        .foregroundStyle(on ? DuoColor.text : DuoColor.text2)
        .padding(.horizontal, 6)
        .frame(height: FormatBarLogic.controlHeight)
        .background(RoundedRectangle(cornerRadius: FormatBarLogic.glyphRadius).fill(on ? DuoColor.selected : .clear))
        .contentShape(Rectangle())
    }

    private func wordButton(_ title: String, help: String, run: @escaping () -> Void) -> some View {
        wordLabel(title, chevron: false, on: model.formatBarHover == title)
            .onHover { hover(title, $0) }
            .onActivate(run)  // action: doc table
            .help(help)
            .accessibilityLabel(help)
    }

    private func menuButton(_ title: String, help: String, items: @escaping () -> [NSMenuItem]) -> some View {
        wordLabel(title, chevron: true, on: model.formatBarHover == title || (model.formatBarMenuOpen && model.formatBarHover == title))
            .onHover { hover(title, $0) }
            .onActivate { popUp(title, items()) }  // action: doc table
            .help(help)
            .accessibilityLabel(help)
            .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { model.formatBarFrames[title] = $0 }
    }

    /// A 24 × 20 glyph control: `text2` mark; `selected` fill with a `text` mark when on or under the pointer, never the accent.
    private func glyph<M: View>(_ id: String, help: String, on: Bool, @ViewBuilder mark: () -> M, run: @escaping () -> Void) -> some View {
        let lit = on || model.formatBarHover == id
        return mark()
            .foregroundStyle(lit ? DuoColor.text : DuoColor.text2)
            .frame(width: FormatBarLogic.glyphWidth, height: FormatBarLogic.controlHeight)
            .background(RoundedRectangle(cornerRadius: FormatBarLogic.glyphRadius).fill(lit ? DuoColor.selected : .clear))
            .contentShape(Rectangle())
            .onHover { hover(id, $0) }
            .onActivate(run)  // action: doc format
            .help(help)
            .accessibilityLabel(help)
            .accessibilityAddTraits(on ? .isSelected : [])
            .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { model.formatBarFrames[id] = $0 }
    }

    private func hover(_ id: String, _ inside: Bool) {
        if inside { model.formatBarHover = id } else if model.formatBarHover == id { model.formatBarHover = nil }
    }

    private func format(_ name: String) {
        model.onSide(side) { model.editor(side).run("duo.exec(f); return 1", ["f": name]) { _ in } }
    }

    // MARK: Menus (the system's, popped under their buttons)

    private func styleItems(_ e: EditorController) -> [NSMenuItem] {
        FormatBarLogic.styles.map { s in
            let item = ActionMenuItem(s.title) { format(s.command) }  // action: doc format
            item.state = e.caretBlock == s.command ? .on : .off
            return item
        }
    }

    private func alignMenu() -> [NSMenuItem] {
        [ActionMenuItem("Left") { format("tableAlignLeft") }, ActionMenuItem("Center") { format("tableAlignCenter") }, ActionMenuItem("Right") { format("tableAlignRight") }]  // action: doc table
    }

    private func deleteMenu() -> [NSMenuItem] {
        [ActionMenuItem("Delete Row") { format("tableDeleteRow") }, ActionMenuItem("Delete Column") { format("tableDeleteColumn") }]  // action: doc table
    }

    private func moreMenu(_ e: EditorController, folds: Bool) -> [NSMenuItem] {
        var items: [NSMenuItem] = []
        let strike = ActionMenuItem("Strikethrough") { format("strikethrough") }  // action: doc format
        strike.state = e.caretMarks.contains("strike") ? .on : .off
        strike.keyEquivalent = "x"; strike.keyEquivalentModifierMask = [.command, .shift]
        let code = ActionMenuItem("Code") { format("code") }  // action: doc format
        code.state = e.caretMarks.contains("code") ? .on : .off
        items += [strike, code]
        if folds {
            items.append(.separator())
            let align = NSMenuItem(title: "Align", action: nil, keyEquivalent: ""); align.submenu = NSMenu(); alignMenu().forEach { align.submenu?.addItem($0) }
            let del = NSMenuItem(title: "Delete", action: nil, keyEquivalent: ""); del.submenu = NSMenu(); deleteMenu().forEach { del.submenu?.addItem($0) }
            items += [align, del]
        }
        return items
    }

    /// Pops the menu under the control. The bar stays while it's open; the text keeps the keyboard.
    private func popUp(_ id: String, _ items: [NSMenuItem]) {
        let editor = model.editor(side)
        guard let host = editor.webView.window?.contentView, let frame = model.formatBarFrames[id] else { return }
        let menu = NSMenu()
        items.forEach { menu.addItem($0) }
        model.onSide(side) { }
        model.formatBarMenuOpen = true
        menu.popUp(positioning: nil, at: NSPoint(x: frame.minX, y: frame.maxY + 2), in: host)
        model.formatBarMenuOpen = false
    }

    // MARK: Voice

    /// While listening or finishing the controls give way to chat's hint row: the meter, "Listening", and the keys.
    @ViewBuilder private func hintRow(_ state: VoiceState) -> some View {
        let voice = model.voice
        HStack(spacing: 6) {
            switch state {
            case .listening:
                VoiceBars(levels: voice.levels, color: DuoColor.text2).frame(width: 12)
                Text("Listening").duoText(.chatMeta).foregroundStyle(DuoColor.text)
                Text(voice.holding ? "· Let go of ⇧⌘D to finish" : "· ⇧⌘D or the mic finishes · esc ends").duoText(.chatMeta).foregroundStyle(DuoColor.text2)
                    .lineLimit(1).truncationMode(.tail)
            default:
                ChatVoiceLine(voice: voice)
            }
        }
        .lineLimit(1)
        .accessibilityElement(children: .combine)
    }

    private func mic(state: VoiceState, mine: Bool) -> some View {
        let voice = model.voice
        let e = model.editor(side)
        let listening = state == .listening
        let none = !voice.microphoneAvailable && !(mine && state.isActive)
        let slashed = none && VoiceNoMicStyle.current != .hidden
        let lit = model.formatBarHover == "mic" && !listening && !slashed
        return ZStack {
            Circle().fill(listening ? DuoColor.text : lit ? DuoColor.selected : Color.clear)
            Image(systemName: slashed ? "mic.slash" : "mic")
                .font(.system(size: FormatBarLogic.micGlyph, weight: .regular))
                .foregroundStyle(listening ? DuoColor.pane : slashed ? DuoColor.controlEdge : lit ? DuoColor.text : DuoColor.text2)
        }
        .frame(width: FormatBarLogic.micDiameter, height: FormatBarLogic.micDiameter)
        .contentShape(Circle())
        .onHover { hover("mic", $0) }
        .onActivate { if let u = e.url, e.canDictate { model.onSide(side) { model.toggleVoice(.document(u.path)) } } }  // action: voice start
        .help(slashed ? VoiceNoMicStyle.tooltip : "Start Voice Input ⇧⌘D")
        .accessibilityLabel(slashed ? VoiceNoMicStyle.tooltip : listening ? "Stop voice input" : "Voice input")
        .accessibilityIdentifier("voice.mic.document")
    }
}
