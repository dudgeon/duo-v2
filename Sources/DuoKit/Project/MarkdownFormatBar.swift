import AppKit
import DuoControl
import SwiftUI

/// The Markdown formatting bar (DL-266; target markdown-toolbar-handoff `bar`): 24 high (`formatBarHeight`), laid over the top
/// of the editor while a Markdown document has the keyboard, so the text never moves. Style ⌄, Bold, Italic, Link, Insert Table
/// and ⋯ at the left; the mic at the trailing end. In a table, + Row, + Column, Align ⌄ and Delete ⌄ take Style's place (the
/// in-document table bar is gone). Listening, the controls give way to the hint row. Clicks never take the keyboard from the text.
public enum FormatBarLogic {
    /// When the bar shows (DL-266): the pane's focus rule, DL-165. It stays while one of its menus is open and while a dictation runs.
    public static func shows(editorHasKeyboard: Bool, isMarkdown: Bool, hidden: Bool, source: Bool, readOnly: Bool, templatePreview: Bool,
                      menuOpen: Bool, dictating: Bool, reviewPending: Bool = false) -> Bool {
        // DL-317: also whenever the document has suggestions or comments or is Suggesting, so pending review is never hidden.
        isMarkdown && !hidden && !source && !readOnly && !templatePreview && (editorHasKeyboard || menuOpen || dictating || reviewPending)
    }

    /// Style ⌄'s items, in order: the title and the `duo2 doc format` word.
    public static let styles: [(title: String, command: String)] = [
        ("Body", "body"), ("Heading 1", "heading1"), ("Heading 2", "heading2"), ("Heading 3", "heading3"), ("Quote", "quote"),
        ("Bulleted List", "bullet"), ("Numbered List", "numbered"), ("Task", "task"), ("Code Block", "codeblock"),
    ]

    /// The paragraph at the caret, named for Style's label.
    public static func styleTitle(_ block: String) -> String {
        if let s = styles.first(where: { $0.command == block }) { return s.title }
        if block.hasPrefix("heading"), let n = Int(block.dropFirst(7)) { return "Heading \(n)" }
        return "Body"
    }

    /// Under 420 the table's Align and Delete fold into ⋯.
    public static func foldsTableMenus(width: CGFloat) -> Bool { width < 420 }

    /// The controls left to right (DL-266, DL-317): Style, B, I, Link, Table and ⋯, then Comment behind a separator; in a table,
    /// + Row, + Column, Align and Delete take Style's place after B, I and Link (Align and Delete fold into ⋯ under 420), then
    /// Comment. The mode menu and the mic are at the trailing end and are not in this list. `tableInMore`: Insert Table goes into ⋯
    /// (DL-317: at 360, and at 460 when the bar shows for review without the keyboard).
    public static func controls(inTable: Bool, width: CGFloat, tableInMore: Bool = false) -> [String] {
        guard inTable else { return ["style", "bold", "italic", "link"] + (tableInMore ? [] : ["table"]) + ["more", "comment"] }
        // As the board draws it: at 460 the table's controls fill the bar (no ⋯, no Insert Table); under 420 ⋯ holds Align and Delete.
        return ["bold", "italic", "link", "row", "column"] + (foldsTableMenus(width: width) ? ["more"] : ["align", "delete"]) + ["comment"]
    }

    /// Insert Table moves into ⋯ at 360 (under 420), and at 460 when the bar shows only because review is pending (DL-317 §Fit).
    public static func tableInMore(width: CGFloat, hasKeyboard: Bool, reviewPending: Bool) -> Bool {
        width < 420 || (reviewPending && !hasKeyboard)
    }

    /// The mode menu's label (DL-317).
    public static func modeTitle(suggesting: Bool) -> String { suggesting ? "Suggesting" : "Editing" }

    // Measures from `bar` (handoff §The bar).
    static let leading: CGFloat = 22, trailing: CGFloat = 12
    static let glyphWidth: CGFloat = 24, controlHeight: CGFloat = 20, glyphRadius: CGFloat = 5, markSize: CGFloat = 13, symbolSize: CGFloat = 10.5
    static let micDiameter: CGFloat = 20, micGlyph: CGFloat = 12, micSymbol: CGFloat = 9.5, separatorHeight: CGFloat = 12, gap: CGFloat = 2
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
            menuOpen: (model.formatBarMenuOpen || model.reviewMenu != nil) && model.editors.active == side, dictating: dictating,
            reviewPending: e.review.showsBar)
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
            HStack(spacing: 0) {
                if mine, ChatVoiceLine.shows(state) { hintRow(state) }
                else { controls(e, width: g.size.width) }
                Spacer(minLength: 0)
                modeMenu(e)
                Spacer().frame(width: 3)
                mic(state: state, mine: mine)
            }
            .padding(.leading, FormatBarLogic.leading).padding(.trailing, FormatBarLogic.trailing)
            .frame(width: g.size.width, height: DuoMetric.formatBarHeight)
        }
        .frame(height: DuoMetric.formatBarHeight)
        .background(DuoColor.pane)
        .overlay(alignment: .bottom) { DuoColor.rule.frame(height: DuoMetric.borderHairline) }
        // The mode menu hangs under its button (the bar is over the editor, so it draws over the text).
        .overlay(alignment: .topTrailing) {
            if model.reviewMenu != nil, model.editors.active == side {
                MarkdownModeMenu().padding(.trailing, FormatBarLogic.trailing + FormatBarLogic.micDiameter + 6).padding(.top, FormatBarLogic.controlHeight + 6)
            }
        }
        .zIndex(2)
    }

    // MARK: Controls

    @ViewBuilder private func controls(_ e: EditorController, width: CGFloat) -> some View {
        let keys = model.webFocus == .editor && model.editors.active == side
        let tableMore = FormatBarLogic.tableInMore(width: width, hasKeyboard: keys, reviewPending: e.review.showsBar)
        let ids = FormatBarLogic.controls(inTable: e.inTable, width: width, tableInMore: tableMore)
        HStack(spacing: FormatBarLogic.gap) {
            ForEach(ids, id: \.self) { id in
                if id == "comment" { separator }   // Comment sits behind its own separator (DL-317)
                control(id, e, folds: FormatBarLogic.foldsTableMenus(width: width) && e.inTable, tableInMore: tableMore && !e.inTable)
                // A separator: after Style, or before the table's own controls.
                if id == "style" || (e.inTable && id == "link") { separator }
            }
        }
    }

    @ViewBuilder private func control(_ id: String, _ e: EditorController, folds: Bool, tableInMore: Bool) -> some View {
        switch id {
        case "style": styleMenu(e)
        case "bold": glyph("bold", help: "Bold ⌘B", on: e.caretMarks.contains("bold")) { Text("B").font(.system(size: FormatBarLogic.markSize, weight: .bold)) } run: { format("bold") }
        case "italic": glyph("italic", help: "Italic ⌘I", on: e.caretMarks.contains("italic")) { Text("I").font(.system(size: FormatBarLogic.markSize, weight: .regular).italic()) } run: { format("italic") }
        case "link": glyph("link", help: "Link ⌘K", on: e.caretMarks.contains("link")) { Image(systemName: "link").font(.system(size: FormatBarLogic.symbolSize)) } run: { format("link") }
        case "table": glyph("table", help: "Insert Table", on: false) { Image(systemName: "tablecells").font(.system(size: FormatBarLogic.symbolSize)) } run: { format("tableInsert") }
        case "comment": glyph("comment", help: "Add Comment ⌥⌘M", on: false) { Image(systemName: "plus.bubble").font(.system(size: FormatBarLogic.symbolSize)) } run: { model.onSide(side) { model.editor(side).reviewAddComment() } }  // action: comment add
        case "row": wordButton("+ Row", help: "Add Row Below") { format("tableRowBelow") }
        case "column": wordButton("+ Column", help: "Add Column After") { format("tableColumnAfter") }
        case "align": menuButton("Align", help: "Align Column") { alignMenu() }
        case "delete": menuButton("Delete", help: "Delete Row or Column") { deleteMenu() }
        default: glyph("more", help: "More", on: model.formatBarMenuOpen) { Image(systemName: "ellipsis").font(.system(size: FormatBarLogic.symbolSize)) } run: { popUp("more", moreMenu(e, folds: folds, tableInMore: tableInMore)) }
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
            Text(title).duoText(.control).foregroundStyle(DuoColor.text).fixedSize()
            if chevron { Image(systemName: "chevron.down").font(.system(size: DuoSymbolSize.chevronSmall, weight: .semibold)).foregroundStyle(DuoColor.text2) }
        }
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

    private func moreMenu(_ e: EditorController, folds: Bool, tableInMore: Bool = false) -> [NSMenuItem] {
        var items: [NSMenuItem] = []
        let strike = ActionMenuItem("Strikethrough") { format("strikethrough") }  // action: doc format
        strike.state = e.caretMarks.contains("strike") ? .on : .off
        strike.keyEquivalent = "x"; strike.keyEquivalentModifierMask = [.command, .shift]
        let code = ActionMenuItem("Code") { format("code") }  // action: doc format
        code.state = e.caretMarks.contains("code") ? .on : .off
        items += [strike, code]
        if tableInMore { items.append(ActionMenuItem("Insert Table") { format("tableInsert") }) }  // action: doc table
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

    // MARK: Mode menu (DL-317)

    /// Editing ⌄ or Suggesting ⌄, right-justified before the mic: a pen in `text2` and the word in `text`; Suggesting is on
    /// `selected` with a `text` pen and a dotted line under it, never the accent. In a table only the pen and ⌄.
    private func modeMenu(_ e: EditorController) -> some View {
        let suggesting = e.review.suggestEdits
        let title = FormatBarLogic.modeTitle(suggesting: suggesting)
        let open = model.reviewMenu != nil
        let lit = suggesting || open || model.formatBarHover == "mode"
        return HStack(spacing: 3) {
            VStack(spacing: 0) {
                Image(systemName: "pencil").font(.system(size: FormatBarLogic.symbolSize - 1)).foregroundStyle(suggesting ? DuoColor.text : DuoColor.text2)
                if suggesting {
                    HStack(spacing: 1) { ForEach(0..<5, id: \.self) { _ in DuoColor.text.frame(width: 1.4, height: 1) } }.padding(.top, -1)
                }
            }
            if !e.inTable { Text(title).duoText(.control).foregroundStyle(DuoColor.text).fixedSize() }
            Image(systemName: "chevron.down").font(.system(size: DuoSymbolSize.chevronSmall, weight: .semibold)).foregroundStyle(DuoColor.text2)
        }
        .padding(.horizontal, 6)
        .frame(height: FormatBarLogic.controlHeight)
        .background(RoundedRectangle(cornerRadius: FormatBarLogic.glyphRadius).fill(lit ? DuoColor.selected : .clear))
        .contentShape(Rectangle())
        .onHover { hover("mode", $0) }
        .onActivate { model.onSide(side) { model.reviewMenu = model.reviewMenu == nil ? "mode" : nil } }  // action: doc review
        .help("\(title): Editing or Suggesting ⇧⌘E, and the review commands")
        .accessibilityLabel("Mode: \(title)")
        .accessibilityIdentifier("review.mode")
        .accessibilityAddTraits(suggesting ? .isSelected : [])
    }

    // MARK: Voice

    /// While listening or finishing the controls give way to chat's hint row: the meter, "Listening", and the keys.
    @ViewBuilder private func hintRow(_ state: VoiceState) -> some View {
        let voice = model.voice
        HStack(spacing: 6) {
            switch state {
            case .listening:
                VoiceBars(levels: voice.levels, color: DuoColor.text).frame(width: 12)
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
                .font(.system(size: FormatBarLogic.micSymbol, weight: .regular))
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
