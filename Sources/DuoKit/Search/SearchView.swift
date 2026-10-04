import AppKit
import SwiftUI

/// The search modal (search-handoff §3; DL-76, DL-79, DL-80): centred 92 pt from the window's
/// top over a scrim, field row, filter row, list and preview, coverage line, footer.
/// DL-80 merged Jump in: there is no Search/Jump switch, and name matches lead the list.
struct SearchOverlay: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let s = model.search
        GeometryReader { box in
            ZStack(alignment: .top) {
                DuoColor.scrim
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onActivate { model.closeSearch() }  // action: search
                    .accessibilityLabel("Close search")
                SearchPanel()
                    .frame(width: min(DuoMetric.searchModalWidth, box.size.width - 96))
                    // 92 from the window's top; this view starts under the toolbar.
                    .padding(.top, DuoMetric.searchModalTop - FixtureHarness.designContentTop)
            }
            .frame(width: box.size.width, height: box.size.height, alignment: .top)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Search")
        .accessibilityAddTraits(.isModal)
        .opacity(s.isOpen ? 1 : 0)
    }
}

struct SearchPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let s = model.search
        VStack(spacing: 0) {
            SearchFieldRow()
            if showsFilters { SearchFilterRow() }
            SearchBody()
            if let c = s.coverage, showsCoverage { CoverageLine(text: c) }
            SearchFooter()
        }
        .clipShape(RoundedRectangle(cornerRadius: DuoMetric.searchModalRadius - DuoMetric.borderHairline))
        // The border sits outside the content (CSS border-box at 960 wide): content is inset by it.
        .padding(DuoMetric.borderHairline)
        .background(RoundedRectangle(cornerRadius: DuoMetric.searchModalRadius).fill(DuoColor.pane))
        .clipShape(RoundedRectangle(cornerRadius: DuoMetric.searchModalRadius))
        .overlay(RoundedRectangle(cornerRadius: DuoMetric.searchModalRadius).strokeBorder(DuoColor.rule, lineWidth: DuoMetric.borderHairline))
        .overlayPreferenceValue(SelectedRowAnchor.self) { anchor in
            GeometryReader { g in
                if s.menuOpen, let anchor, let item = s.selectedItem {
                    let r = g[anchor]
                    ActionMenu(actions: s.actions(for: item), chosen: s.menuIndex)
                        .offset(x: r.maxX - DuoMetric.actionMenuAnchorFromRowRight - DuoMetric.actionMenuWidth,
                                y: r.minY + DuoMetric.actionMenuAnchorFromRowTop)
                }
            }
        }
        .shadow(color: DuoColor.text.opacity(0.22), radius: 16, x: 0, y: 12)
    }

    var showsFilters: Bool {
        switch model.search.phase { case .rebuilding, .unreadable: false; default: true }
    }
    var showsCoverage: Bool {
        switch model.search.phase { case .rebuilding, .unreadable: false; default: model.search.firstRun == nil }
    }
}

// MARK: - Field row

struct SearchFieldRow: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let s = model.search
        HStack(spacing: 10) {
            SearchIcon(kind: .magnifier).frame(width: 16, height: 16)
            if let src = s.similarTo {
                Text("Similar to").duoText(.body).foregroundStyle(DuoColor.text2).fixedSize()
                HStack(spacing: 6) {
                    SearchIcon(kind: src.kind == .session ? .session : .file).frame(width: 12, height: 12)
                    Text(src.title).duoText(src.kind == .file ? .mono : .control, lineHeight: 16).foregroundStyle(DuoColor.text)
                    if !src.location.isEmpty { Text(src.location).duoText(.control).foregroundStyle(DuoColor.text2) }
                }
                .padding(.horizontal, 8 + DuoMetric.borderHairline).padding(.vertical, 2 + DuoMetric.borderHairline)
                .overlay(RoundedRectangle(cornerRadius: DuoMetric.radiusControl).strokeBorder(DuoColor.controlEdge, lineWidth: DuoMetric.borderHairline))
                .fixedSize()
            }
            SearchTextField(placeholder: s.similarTo == nil ? "Search all projects" : "Narrow these")
        }
        .padding(.horizontal, 16)
        .frame(height: DuoMetric.searchModalFieldRowHeight)
    }
}

/// The field: 17/24, no bezel. Keys go to the model (search-handoff §5, DL-79).
struct SearchTextField: NSViewRepresentable {
    @Environment(AppModel.self) private var model
    let placeholder: String

    func makeNSView(context: Context) -> KeyField {
        let f = KeyField()
        f.isBezeled = false
        f.drawsBackground = false
        f.focusRingType = .none
        f.font = DuoTextStyle.searchField.spec.nsFont
        f.textColor = DuoNSColor.text
        f.cell?.usesSingleLineMode = true
        f.cell?.lineBreakMode = .byTruncatingTail
        f.delegate = context.coordinator
        f.onKey = { [weak model] key in model?.searchKey(key) ?? false }
        f.setAccessibilityLabel("Search all projects")
        return f
    }

    func updateNSView(_ f: KeyField, context: Context) {
        let s = model.search
        if f.stringValue != s.query { f.stringValue = s.query }
        f.placeholderAttributedString = NSAttributedString(string: placeholder, attributes: [
            .font: DuoTextStyle.searchField.spec.nsFont, .foregroundColor: DuoNSColor.text2])
        if s.isOpen, s.wantsFocus, let w = f.window {
            s.wantsFocus = false
            DispatchQueue.main.async { w.makeFirstResponder(f); f.currentEditor()?.selectedRange = NSRange(location: (f.stringValue as NSString).length, length: 0) }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        let model: AppModel
        init(model: AppModel) { self.model = model }
        func controlTextDidChange(_ n: Notification) {
            guard let f = n.object as? NSTextField else { return }
            model.searchQueryChanged(f.stringValue)
        }
        func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
            let key: SearchKey? = switch sel {
            case #selector(NSResponder.moveUp(_:)): .up
            case #selector(NSResponder.moveDown(_:)): .down
            case #selector(NSResponder.moveUpAndModifySelection(_:)): .extendUp
            case #selector(NSResponder.moveDownAndModifySelection(_:)): .extendDown
            case #selector(NSResponder.insertNewline(_:)): .returnKey
            case #selector(NSResponder.insertTab(_:)): .tab
            case #selector(NSResponder.insertBacktab(_:)): .backTab
            case #selector(NSResponder.cancelOperation(_:)): .escape
            default: nil
            }
            guard let key else { return false }
            return model.searchKey(key)
        }
    }

    /// Takes ⌘ chords and Escape before SwiftUI's host claims them as key equivalents.
    final class KeyField: NSTextField {
        var onKey: ((SearchKey) -> Bool)?
        override func performKeyEquivalent(with e: NSEvent) -> Bool {
            guard currentEditor() != nil else { return super.performKeyEquivalent(with: e) }
            let mods = e.modifierFlags.intersection([.command, .option, .shift, .control])
            let ch = e.charactersIgnoringModifiers?.lowercased() ?? ""
            let key: SearchKey? = switch (mods, e.keyCode, ch) {
            case (_, 53, _): .escape
            case ([.command], _, "e"): .toggleExact
            case ([.command], _, "d"): .chord(.sendToClaude)
            case ([.command, .shift], _, "a"): .narrow
            case ([.command, .option], 36, _): .chord(.splitView)
            case ([.command, .shift], 36, _): .chord(.readOnly)
            case ([.command, .option], _, "c"): .chord(.copyPath)
            case ([.command, .shift], _, "c"): .chord(.copyPassage)
            case ([.command], _, "r"): .chord(.reveal)
            default: nil
            }
            if let key, onKey?(key) == true { return true }
            return super.performKeyEquivalent(with: e)
        }
    }
}

public enum SearchKey: Equatable, Sendable {
    case up, down, extendUp, extendDown, returnKey, tab, backTab, escape, toggleExact, narrow
    case chord(SearchAction.ID)
}

// MARK: - Filter row

struct SearchFilterRow: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var s = model.search
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                if s.exact {
                    FilterChip(label: "Exact", set: true, chevron: false) { model.toggleExact() }  // action: search
                }
                FilterChip(label: s.scopeProject ?? "All projects", set: s.scopeProject != nil) {  // action: search
                    PopUp.show([("All projects", { model.setSearchScope(nil) }), nil]
                               + model.searchProjectNames.map { p in (p, { model.setSearchScope(p) }) })
                }
                FilterChip(label: kindLabel(s.kind), set: s.kind != nil) {  // action: search
                    PopUp.show([("Any kind", { model.setSearchKind(nil) }), nil, ("Files", { model.setSearchKind(.file) }),
                                ("Sessions", { model.setSearchKind(.session) }), ("Memory", { model.setSearchKind(.memory) })])
                }
                FilterChip(label: s.time.rawValue, set: s.time != .any) {  // action: search
                    PopUp.show(SearchTime.allCases.map { t in (t.rawValue, { model.setSearchTime(t) }) })
                }
                Toggle(isOn: Binding(get: { s.includeArchived }, set: { model.setIncludeArchived($0) })) {
                    Text("Include archived").duoText(.control).foregroundStyle(DuoColor.text2)
                }
                .toggleStyle(.checkbox)
                .padding(.leading, 6)
                .fixedSize()
                Spacer(minLength: 8)
                if let hint { Text(hint).duoText(.control).foregroundStyle(DuoColor.text2).lineLimit(1) }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
            Rectangle().fill(DuoColor.rule).frame(height: DuoMetric.borderHairline)
        }
    }

    func kindLabel(_ k: SearchItem.Kind?) -> String {
        switch k { case .file: "Files"; case .session: "Sessions"; case .memory: "Memory"; default: "Any kind" }
    }

    /// `⇧⌘A again: only <project>` inside a project; `⇧⌘A again: all projects` once narrowed (DL-79 a).
    /// The exact-mode hint is left out (DL-79 d).
    var hint: String? {
        let s = model.search
        guard let p = s.openedIn else { return nil }
        return s.scopeProject == p ? "⇧⌘A again: all projects" : "⇧⌘A again: only \(p)"
    }
}

/// A native menu at the pointer, for the filter buttons: SwiftUI's `Menu` replaces a custom
/// label with the system's own, which isn't the design's button.
@MainActor
enum PopUp {
    final class Item: NSMenuItem {
        var run: () -> Void = {}
        @objc func fire() { run() }
    }
    /// `keys`: the chords to show beside each entry, in order (the menu shows them; Commands owns them).
    static func show(_ entries: [(String, () -> Void)?], keys: [(String, NSEvent.ModifierFlags)] = []) {
        let menu = NSMenu()
        var n = 0
        for e in entries {
            guard let (title, run) = e else { menu.addItem(.separator()); continue }
            let i = Item(title: title, action: #selector(Item.fire), keyEquivalent: keys.indices.contains(n) ? keys[n].0 : "")
            if keys.indices.contains(n) { i.keyEquivalentModifierMask = keys[n].1 }
            i.run = run; i.target = i
            menu.addItem(i)
            n += 1
        }
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }
}

/// A filter pop-up as the design draws it: the standard button with a chevron; set ones are
/// filled with `selected` and semibold (search-handoff §3).
struct FilterChip: View {
    let label: String
    var set = false
    var chevron = true
    var action: (() -> Void)?

    var body: some View {
        HStack(spacing: 6) {
            Text(label).duoText(.control, weight: set ? .semibold : nil).foregroundStyle(DuoColor.text)
            if chevron { Chevron(direction: .down, color: DuoColor.text).frame(width: 8, height: 6).scaleEffect(0.8) }
            else {
                // The 8×8 × that removes a set chip (search-exact).
                Canvas { ctx, _ in
                    var p = Path()
                    p.move(to: .init(x: 1.5, y: 1.5)); p.addLine(to: .init(x: 6.5, y: 6.5))
                    p.move(to: .init(x: 6.5, y: 1.5)); p.addLine(to: .init(x: 1.5, y: 6.5))
                    ctx.stroke(p, with: .color(DuoColor.text), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
                }
                .frame(width: 8, height: 8)
            }
        }
        .padding(.horizontal, DuoSpace.buttonPadding.leading + DuoMetric.borderHairline)
        .padding(.vertical, DuoSpace.buttonPadding.top + DuoMetric.borderHairline)
        .background(RoundedRectangle(cornerRadius: DuoMetric.radiusControl).fill(set ? DuoColor.selected : DuoColor.pane))
        .overlay(RoundedRectangle(cornerRadius: DuoMetric.radiusControl).strokeBorder(DuoColor.controlEdge, lineWidth: DuoMetric.borderHairline))
        .contentShape(Rectangle())
        .modifier(OptionalTap(action: action))
    }
}

private struct OptionalTap: ViewModifier {
    let action: (() -> Void)?
    func body(content: Content) -> some View {
        if let action { content.onActivate(action) } else { content }  // action: search
    }
}

// MARK: - Body

struct SearchBody: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let s = model.search
        switch s.phase {
        case .empty:
            HStack(alignment: .top, spacing: 0) {
                RecentSearches().frame(width: DuoMetric.searchModalListColumnWidth, alignment: .topLeading)
                VRule()
                SearchHelp().frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(minHeight: 220, alignment: .top)
            .fixedSize(horizontal: false, vertical: true)
        case .none(let sentence, let without):
            NoResults(sentence: sentence, without: without)
        case .rebuilding(let why):
            IndexNotice(title: "Search is rebuilding its index", lines: [why, Self.goToStillWorks], buttons: [])
        case .unreadable:
            IndexNotice(title: "Search can’t read its index",
                        lines: ["The index file may be damaged. Rebuilding takes a few minutes and loses nothing: your files and sessions are untouched.",
                                Self.goToStillWorks],
                        buttons: ["Rebuild the index", "Show details"])
        case .results:
            VStack(spacing: 0) {
                if let (head, detail) = s.firstRun { FirstRunNotice(head: head, detail: detail) }
                HStack(alignment: .top, spacing: 0) {
                    ResultList().frame(width: DuoMetric.searchModalListColumnWidth, alignment: .topLeading)
                    VRule()
                    SearchPreview().frame(maxWidth: .infinity, alignment: .topLeading)
                }
                // Per-state minimums from the targets: 440, 400 on first run, 360 for exact.
                .frame(minHeight: s.firstRun != nil ? 400 : s.exact ? 360 : DuoMetric.searchModalBodyMinHeight, alignment: .top)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// DL-80: name matching doesn't use the index, so going to a project, group or session by
    /// name still works while it's rebuilding or unreadable. (Replaces the design's ⌘K line.)
    static let goToStillWorks = "Typing a project, group or session name still goes straight to it."
}

struct VRule: View {
    var body: some View { Rectangle().fill(DuoColor.rule).frame(width: DuoMetric.borderHairline).frame(maxHeight: .infinity) }
}

struct RecentSearches: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let s = model.search
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(text: "Recent searches").padding(EdgeInsets(top: 6, leading: 10, bottom: 4, trailing: 10))
                .padding(.bottom, DuoMetric.searchRowGap)
            ForEach(Array(s.recents.enumerated()), id: \.offset) { i, r in
                HStack(spacing: 8) {
                    SearchIcon(kind: .magnifier).frame(width: 12, height: 12)
                    Text(r.query).duoText(Self.looksLikeIdentifier(r.query) ? .mono : .body, lineHeight: 20).foregroundStyle(DuoColor.text).lineLimit(1)
                    Spacer(minLength: 8)
                    Text(r.when).duoText(.body).foregroundStyle(DuoColor.text2).fixedSize()
                }
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(RoundedRectangle(cornerRadius: DuoMetric.searchRowRadius).fill(s.recentSelected == i ? DuoColor.selected : .clear))
                .padding(.bottom, DuoMetric.searchRowGap)
                .contentShape(Rectangle())
                .onActivate { model.runRecent(r.query) }  // action: search
            }
        }
        .padding(EdgeInsets(top: 6, leading: 8, bottom: 8, trailing: 8))
    }

    static func looksLikeIdentifier(_ q: String) -> Bool {
        !q.contains(" ") && q.rangeOfCharacter(from: CharacterSet(charactersIn: "_./:#")) != nil
    }
}

struct SearchHelp: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Search every project by meaning or by exact words.")
            Text("Put a phrase in quotes, or paste an identifier, to match it exactly.")
            // DL-80: Jump merged into search; names come first instead of a ⌘K switch.
            Text("Names of projects, groups and sessions come first: Return goes straight there.")
        }
        .duoText(.body)
        .foregroundStyle(DuoColor.text2)
        .padding(SearchMetric.previewPadding)
    }
}

enum SearchMetric {
    static let previewPadding = DuoMetric.searchPreviewPadding
}

struct FirstRunNotice: View {
    let head: String, detail: String
    var body: some View {
        HStack(spacing: 8) {
            StateGlyph(.working)
            (Text(head).foregroundStyle(DuoColor.text).fontWeight(.semibold) + Text(" " + detail).foregroundStyle(DuoColor.text2))
                .duoText(.body)
            Spacer(minLength: 0)
        }
        .padding(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
        .background(RoundedRectangle(cornerRadius: DuoMetric.radiusControl).fill(DuoColor.ground))
        .padding(EdgeInsets(top: 10, leading: 16, bottom: 2, trailing: 16))
    }
}

struct NoResults: View {
    @Environment(AppModel.self) private var model
    let sentence: String, without: Int

    var body: some View {
        StateNotice(title: "No results", minHeight: 260,
                    lines: [sentence] + (without > 0 ? ["\(without) result\(without == 1 ? "" : "s") without these filters."] : [])) {
            Button("Clear filters") { model.clearSearchFilters() }.buttonStyle(.duo)
            if !model.search.includeArchived {
                Button("Include archived") { model.setIncludeArchived(true) }.buttonStyle(.duo)
            }
        }
    }
}

struct IndexNotice: View {
    @Environment(AppModel.self) private var model
    let title: String, lines: [String], buttons: [String]

    var body: some View {
        StateNotice(title: title, minHeight: 220, lines: lines) {
            if buttons.contains("Rebuild the index") { Button("Rebuild the index") { model.rebuildSearchIndex() }.buttonStyle(.duo) }
            if buttons.contains("Show details") { Button("Show details") { model.showSearchIndexDetails() }.buttonStyle(.duo) }
        }
    }
}

/// The body for a state without results: 14 semibold title, lines in `text2`, buttons (search-none, -error).
struct StateNotice<Buttons: View>: View {
    let title: String
    let minHeight: CGFloat
    let lines: [String]
    @ViewBuilder let buttons: () -> Buttons

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).duoText(.title).foregroundStyle(DuoColor.text)
            ForEach(lines, id: \.self) { Text($0).duoText(.body).foregroundStyle(DuoColor.text2).frame(maxWidth: 560, alignment: .leading) }
            HStack(spacing: 6) { buttons() }.padding(.top, 6)
        }
        .padding(EdgeInsets(top: 28, leading: 28, bottom: 24, trailing: 28))
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
    }
}

// MARK: - Rows

struct SelectedRowAnchor: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) { value = value ?? nextValue() }
}

struct ResultList: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let s = model.search
        let lastGoTo = s.items.lastIndex(where: { $0.goTo })
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: DuoMetric.searchRowGap) {
                    ForEach(Array(s.items.enumerated()), id: \.element.id) { i, item in
                        let on = i == s.selected || s.multi.contains(i)
                        ResultRow(item: item, on: on, inSimilar: s.similarTo != nil)
                            .id(item.id)
                            .anchorPreference(key: SelectedRowAnchor.self, value: .bounds) { i == s.selected ? $0 : nil }
                            .onActivate { model.selectSearchRow(i) }  // action: search
                        if i == lastGoTo, i < s.items.count - 1 {
                            Rectangle().fill(DuoColor.rule).frame(height: DuoMetric.borderHairline)
                                .padding(.horizontal, 10).padding(.vertical, 6)
                        }
                    }
                    if let more = s.stillSearching {
                        HStack(spacing: 6) {
                            StateGlyph(.working)
                            Text(more).duoText(.control).foregroundStyle(DuoColor.text2)
                        }
                        .padding(EdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10))
                    }
                    if s.moreElsewhere > 0 {
                        HStack(spacing: 6) {
                            Chevron(direction: .right)
                            Text("\(s.moreElsewhere) more in other projects").duoText(.body).foregroundStyle(DuoColor.text2)
                        }
                        .padding(EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8))
                        .padding(EdgeInsets(top: 4 - DuoMetric.searchRowGap, leading: 2, bottom: 0, trailing: 0))
                        .onActivate { model.setSearchScope(nil) }  // action: search
                    }
                    if let q = s.newProjectName {
                        HStack(spacing: 8) {
                            Text("+").duoText(.body).foregroundStyle(DuoColor.text2).frame(width: 12)
                            Text("New project “\(q)”").duoText(.body).foregroundStyle(DuoColor.text)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .onActivate { model.newProjectFromSearch(q) }  // action: projects
                    }
                }
                .padding(EdgeInsets(top: 6, leading: 8, bottom: 8, trailing: 8))
            }
            .scrollIndicators(.automatic)
            .onChange(of: s.selected) { _, i in if s.items.indices.contains(i) { proxy.scrollTo(s.items[i].id) } }
        }
    }
}

struct ResultRow: View {
    let item: SearchItem
    let on: Bool
    /// Find similar lists everything by meaning, so no row says so (search-similar).
    var inSimilar = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                leading
                Text(item.title)
                    .modifier(TitleStyle(item: item))
                    .foregroundStyle(DuoColor.text)
                    .lineLimit(1)
                if item.kind == .group, let n = item.groupSessions { Pill(text: "group · \(n)") }
                if item.isExact { Pill(text: "exact") }
                if item.archived { Pill(text: "archived") }
                Spacer(minLength: 8)
                if let d = item.date ?? item.wait { Text(d).duoText(.body).foregroundStyle(DuoColor.text2).fixedSize() }
            }
            meta.padding(.leading, DuoMetric.searchRowMetaIndent)
            if let snip = item.snippet, !item.goTo {
                Text(Highlight.attributed(snip, words: item.matchedWords))
                    .duoText(.body)
                    .foregroundStyle(DuoColor.text2)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .padding(.top, 2)
                    .padding(.leading, DuoMetric.searchRowMetaIndent)
            }
        }
        .padding(DuoMetric.searchRowPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: DuoMetric.searchRowRadius).fill(on ? DuoColor.selected : .clear))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    @ViewBuilder var leading: some View {
        if item.goTo, let st = item.state { StateGlyph(st).frame(width: 12, height: 12) }
        else { SearchIcon(kind: item.kind == .file || item.kind == .memory ? .file : .session).frame(width: 12, height: 12) }
    }

    @ViewBuilder var meta: some View {
        HStack(spacing: 6) {
            if item.unfiled { Pill(text: "Unfiled") }
            else if let p = item.project { Text(p).foregroundStyle(DuoColor.text) }
            ForEach(metaParts, id: \.self) { part in
                Text("·")
                Text(part)
            }
        }
        .duoText(.control, lineHeight: 20)
        .foregroundStyle(DuoColor.text2)
        .lineLimit(1)
    }

    var metaParts: [String] {
        if item.goTo {
            switch item.kind {
            case .group: return ["group"]
            case .project: return [item.detail ?? "project"].filter { !$0.isEmpty }
            default: return ["session"] + (item.state.map { [$0 == .needsYou ? "needs you" : $0.spokenName] } ?? [])
            }
        }
        var parts = [item.kind.rawValue]
        if !item.location.isEmpty { parts.append(item.location) }
        if item.byMeaningOnly && !item.similarResult && !inSimilar { parts.append("by meaning") }
        return parts
    }
}

extension SearchItem {
    /// Find similar lists everything by meaning, so its rows drop `by meaning` (search-similar).
    var similarResult: Bool { matchedBy == ["similar"] }
}

struct TitleStyle: ViewModifier {
    let item: SearchItem
    func body(content: Content) -> some View {
        if item.kind == .file && !item.goTo { content.duoText(.mono, lineHeight: 20, weight: .medium) }
        else { content.duoText(.bodyEmphasis) }
    }
}

/// Pill: 1 `controlEdge`, radius 9, 11/16 (search-handoff reuse table).
struct Pill: View {
    let text: String
    var body: some View {
        Text(text)
            .duoText(.pill)
            .foregroundStyle(DuoColor.text)
            .padding(.horizontal, 7 + DuoMetric.borderHairline)
            .padding(.vertical, DuoMetric.borderHairline)
            .background(RoundedRectangle(cornerRadius: 9).fill(DuoColor.pane))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(DuoColor.controlEdge, lineWidth: DuoMetric.borderHairline))
            .fixedSize()
    }
}

/// Matched words semibold in `text`, the rest as the caller colours it (Q6).
enum Highlight {
    static func attributed(_ s: String, words: [String]) -> AttributedString {
        var a = AttributedString(s)
        for w in words where !w.isEmpty {
            var from = a.startIndex
            while from < a.endIndex, let r = a[from...].range(of: w, options: .caseInsensitive) {
                a[r].font = .system(size: DuoTextStyle.body.spec.size, weight: .semibold)
                a[r].foregroundColor = DuoColor.text
                from = r.upperBound
            }
        }
        return a
    }
}

// MARK: - Preview

struct SearchPreview: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let s = model.search
        VStack(alignment: .leading, spacing: 10) {
            if s.multi.count > 1 { MultiPreview(items: s.selectedItems, target: s.sendTargetName) }
            else if let item = s.selectedItem {
                PreviewHeader(item: item)
                switch item.kind {
                case .file, .memory: FilePreview(item: item)
                case .session: if item.goTo { GoToPreview(item: item) } else { SessionPreview(item: item) }
                case .project, .group: GoToPreview(item: item)
                }
            }
        }
        .padding(SearchMetric.previewPadding)
    }
}

struct PreviewHeader: View {
    let item: SearchItem
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                if item.goTo, let st = item.state { StateGlyph(st).frame(width: 12, height: 12) }
                else { SearchIcon(kind: item.kind == .session ? .session : .file).frame(width: 12, height: 12) }
                Text(item.title).modifier(TitleStyle(item: item)).foregroundStyle(DuoColor.text).lineLimit(1)
                if item.kind == .group, let n = item.groupSessions { Pill(text: "group · \(n)") }
                if item.isExact { Pill(text: "exact") }
                Spacer(minLength: 8)
                if let d = item.date ?? item.wait { Text(d).duoText(.body).foregroundStyle(DuoColor.text2).fixedSize() }
            }
            Text(subtitle).duoText(.body).foregroundStyle(DuoColor.text2).lineLimit(1).padding(.leading, 20)
        }
    }

    var subtitle: String {
        let place = item.unfiled ? "Unfiled" : (item.project ?? "")
        if item.goTo { return [place, item.detail].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ") }
        let loc: String
        if item.kind == .file, item.location.hasPrefix("L") {
            let n = item.location.dropFirst()
            loc = n.contains("–") ? "lines \(n.replacingOccurrences(of: "–", with: "–"))" : "line \(n)"
        } else { loc = item.location }
        return [place, loc].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

struct FilePreview: View {
    let item: SearchItem
    var body: some View {
        let main = item.passages.first
        if let h = main?.heading {
            Text(h).duoText(.title).foregroundStyle(DuoColor.text).padding(.top, 4)
        }
        Text(Highlight.attributed(main?.snippet ?? item.snippet ?? "", words: item.matchedWords))
            .duoText(.body)
            .foregroundStyle(DuoColor.text)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DuoMetric.searchPreviewBlockPadding)
            .background(RoundedRectangle(cornerRadius: DuoMetric.searchPreviewBlockRadius).fill(DuoColor.selected))
            .padding(.horizontal, -12)
        let more = item.passages.dropFirst()
        if !more.isEmpty {
            SectionLabel(text: "More in this file", count: more.count).padding(.top, 8)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(more.enumerated()), id: \.offset) { _, p in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(p.location).duoText(.mono, lineHeight: 20).frame(width: 56, alignment: .leading)
                        Text(Highlight.attributed((p.heading.map { "\($0): " } ?? "") + p.snippet, words: item.matchedWords))
                            .duoText(.body).lineLimit(2)
                    }
                    .foregroundStyle(DuoColor.text2)
                }
            }
        }
        if !item.alsoIn.isEmpty {
            SectionLabel(text: "Also in", count: item.alsoIn.count).padding(.top, 8)
            ForEach(item.alsoIn, id: \.self) { path in
                HStack(spacing: 8) {
                    SearchIcon(kind: .file).frame(width: 12, height: 12)
                    Text(path).duoText(.mono, lineHeight: 20).foregroundStyle(DuoColor.text).lineLimit(1)
                }
            }
        }
    }
}

struct SessionPreview: View {
    let item: SearchItem
    var body: some View {
        ForEach(item.turns, id: \.number) { t in
            VStack(alignment: .leading, spacing: 6) {
                SectionLabel(text: "Turn \(t.number)")
                if let y = t.you { TurnLine(who: "You", text: y, words: item.matchedWords, context: !t.matched) }
                if let c = t.claude { TurnLine(who: "Claude", text: c, words: item.matchedWords, context: !t.matched) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(t.matched ? DuoMetric.searchPreviewBlockPadding : EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12))
            .background(RoundedRectangle(cornerRadius: DuoMetric.searchPreviewBlockRadius).fill(t.matched ? DuoColor.selected : .clear))
            .padding(.horizontal, -12)
        }
    }
}

struct TurnLine: View {
    let who: String, text: String, words: [String]
    /// A neighbouring turn: shown as context, two lines at most, in `text2`.
    var context = false
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(who).duoText(.body).foregroundStyle(DuoColor.text2).frame(width: 54, alignment: .leading)
            Text(context ? AttributedString(text) : Highlight.attributed(text, words: words)).duoText(.body)
                .foregroundStyle(context ? DuoColor.text2 : DuoColor.text)
                .lineLimit(context ? 2 : 12)
        }
    }
}

struct MultiPreview: View {
    let items: [SearchItem], target: String?
    var body: some View {
        Text("\(items.count) selected").duoText(.title).foregroundStyle(DuoColor.text)
        ForEach(items) { i in
            HStack(spacing: 8) {
                SearchIcon(kind: i.kind == .session ? .session : .file).frame(width: 12, height: 12)
                Text(i.title).duoText(i.kind == .file ? .mono : .body, lineHeight: 20).foregroundStyle(DuoColor.text).lineLimit(1)
                Text([i.unfiled ? "Unfiled" : i.project, i.location].compactMap { $0 }.joined(separator: " · "))
                    .duoText(.body).foregroundStyle(DuoColor.text2).lineLimit(1)
            }
        }
        Text("Return sends \(items.count == 2 ? "both" : "all \(items.count)") to Claude\(target.map { " in \($0)" } ?? "") as references: the path with its lines, the session with its turn. The text itself is not pasted, and nothing is submitted.")
            .duoText(.body).foregroundStyle(DuoColor.text2).padding(.top, 6)
    }
}

struct GoToPreview: View {
    @Environment(AppModel.self) private var model
    let item: SearchItem
    var body: some View {
        let rows = model.searchGoToSessions(item)
        if !rows.isEmpty {
            SectionLabel(text: "Sessions, oldest first").padding(.top, 4)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(rows, id: \.id) { s in
                    HStack(spacing: 8) {
                        StateGlyph(s.state).frame(width: 12, height: 12)
                        Text(s.name).duoText(.body).foregroundStyle(DuoColor.text).lineLimit(1)
                        Spacer(minLength: 8)
                        Text([s.state == .needsYou ? "needs you" : s.state.spokenName, s.wait].compactMap { $0 }.joined(separator: " "))
                            .duoText(.body).foregroundStyle(DuoColor.text2).fixedSize()
                    }
                    .padding(.leading, s.forkOf == nil ? 0 : 18)
                }
            }
        }
    }
}

// MARK: - Coverage and footer

struct CoverageLine: View {
    let text: String
    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(DuoColor.rule).frame(height: DuoMetric.borderHairline)
            HStack(spacing: 6) {
                StateGlyph(.working)
                Text(text).duoText(.control).foregroundStyle(DuoColor.text2).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(EdgeInsets(top: 8, leading: 18, bottom: 10, trailing: 18))
        }
    }
}

struct SearchFooter: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let s = model.search
        VStack(spacing: 0) {
            Rectangle().fill(DuoColor.rule).frame(height: DuoMetric.borderHairline)
            HStack(spacing: 14) {
                if !s.returnLabel.isEmpty, !s.menuOpen { Text("↩ " + s.returnLabel).foregroundStyle(DuoColor.text).lineLimit(1) }
                Spacer(minLength: 8)
                HStack(spacing: 14) { ForEach(hints, id: \.self) { Text($0) } }
                    .foregroundStyle(DuoColor.text2)
                    .fixedSize()
            }
            .duoText(.control)
            .padding(.horizontal, 16)
            .frame(height: DuoMetric.searchModalFooterHeight - DuoMetric.borderHairline)
            .background(DuoColor.ground)
        }
    }

    var hints: [String] {
        let s = model.search
        if s.menuOpen { return ["↑↓ Choose", "↩ Run", "type to filter", "esc Back to results"] }
        let esc = s.similarReturnsTo.map { "esc Back to “\($0)”" } ?? "esc Close"
        switch s.phase {
        case .empty: return ["↑↓ Recent searches", esc]
        case .none: return ["⇧tab Filters", esc]
        case .rebuilding, .unreadable: return [esc]
        case .results:
            if s.multi.count > 1 { return ["⇧↑↓ Select more", "tab Actions", esc] }
            return ["tab Actions", "⇧tab Filters", esc]
        }
    }
}

// MARK: - Action menu

struct ActionMenu: View {
    @Environment(AppModel.self) private var model
    let actions: [SearchAction]
    let chosen: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Actions").duoText(.sectionLabel).foregroundStyle(DuoColor.text2)
                .padding(EdgeInsets(top: 2, leading: 8, bottom: 4, trailing: 8))
            ForEach(Array(actions.enumerated()), id: \.element.id) { i, a in
                if i > 0, actions[i - 1].group != a.group {
                    Rectangle().fill(DuoColor.rule).frame(height: DuoMetric.borderHairline).padding(.horizontal, 8).padding(.vertical, 4)
                }
                HStack(spacing: 8) {
                    Text(a.title).duoText(.body).foregroundStyle(a.enabled ? DuoColor.text : DuoColor.text2).lineLimit(1)
                    Spacer(minLength: 8)
                    if let c = a.chord { Text(c).duoText(.body).foregroundStyle(DuoColor.text2) }
                }
                .padding(.horizontal, 8)
                .frame(height: DuoMetric.actionMenuRowHeight)
                .background(RoundedRectangle(cornerRadius: DuoMetric.radiusControl).fill(i == chosen ? DuoColor.selected : .clear))
                .contentShape(Rectangle())
                .onActivate { model.runSearchAction(a.id) }  // action: search
            }
        }
        .padding(DuoMetric.actionMenuPadding)
        .frame(width: DuoMetric.actionMenuWidth)
        .background(RoundedRectangle(cornerRadius: DuoMetric.actionMenuRadius).fill(DuoColor.pane))
        .overlay(RoundedRectangle(cornerRadius: DuoMetric.actionMenuRadius).strokeBorder(DuoColor.rule, lineWidth: DuoMetric.borderHairline))
        .shadow(color: DuoColor.text.opacity(0.22), radius: 16, x: 0, y: 12)
    }
}

// MARK: - Icons

/// tokens.json `icon.searchFile`, `icon.searchSession` and the search glyph, in a 12×12 box.
struct SearchIcon: View {
    enum Kind { case file, session, magnifier }
    let kind: Kind
    var body: some View {
        Canvas { ctx, box in
            ctx.scaleBy(x: box.width / 12, y: box.height / 12)
            var p = Path()
            let width: CGFloat
            switch kind {
            case .file:
                p.move(to: .init(x: 2.5, y: 1)); p.addLine(to: .init(x: 7, y: 1)); p.addLine(to: .init(x: 9.5, y: 3.5))
                p.addLine(to: .init(x: 9.5, y: 11)); p.addLine(to: .init(x: 2.5, y: 11)); p.closeSubpath()
                p.move(to: .init(x: 7, y: 1)); p.addLine(to: .init(x: 7, y: 3.5)); p.addLine(to: .init(x: 9.5, y: 3.5))
                width = 1.2
            case .session:
                p.move(to: .init(x: 1.5, y: 2)); p.addLine(to: .init(x: 10.5, y: 2)); p.addLine(to: .init(x: 10.5, y: 8.5))
                p.addLine(to: .init(x: 6, y: 8.5)); p.addLine(to: .init(x: 3.5, y: 10.5)); p.addLine(to: .init(x: 3.5, y: 8.5))
                p.addLine(to: .init(x: 1.5, y: 8.5)); p.closeSubpath()
                width = 1.2
            case .magnifier:
                p.addEllipse(in: CGRect(x: 1.4, y: 1.4, width: 7.2, height: 7.2))
                p.move(to: .init(x: 7.8, y: 7.8)); p.addLine(to: .init(x: 11, y: 11))
                width = 1.1
            }
            ctx.stroke(p, with: .color(DuoColor.text2), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }
}
