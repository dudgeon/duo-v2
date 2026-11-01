import AppKit
import DuoDeck
import SwiftUI

// Duo Decks P3b: the deck bar's parts (P3-3, P3-4, make-templates). The target draws Problems ⌄ and Export ⌄
// as menus under their buttons; they are drawn in the window here (not NSMenu) so a capture sees them.

struct DeckMenuItem: Identifiable {
    let id: String
    var title: String
    var trailing: String? = nil
    var enabled = true
    var divider = false
    var action: () -> Void = {}
}

/// A dropdown on `pane` with a `rule` edge, radius 6: 12 pt rows 21 high, the first (or the hovered) on `selected`.
struct DeckDropdown: View {
    @Environment(AppModel.self) private var model
    let preview: DeckPreview
    let items: [DeckMenuItem]
    var width: CGFloat = 270
    let dismiss: () -> Void

    var body: some View {
        let _ = model.pickerRevision
        let hovered = preview.menuHover
        VStack(alignment: .leading, spacing: 0) {
            ForEach(items) { it in
                if it.divider {
                    DuoColor.rule.frame(height: DuoMetric.borderHairline).padding(.vertical, 4)
                } else {
                    HStack(spacing: 8) {
                        Text(it.title).duoText(.control).lineLimit(1).truncationMode(.tail)
                        Spacer(minLength: 8)
                        if let t = it.trailing { Text(t).duoText(.pill).foregroundStyle(DuoColor.text2).lineLimit(1) }
                    }
                    .foregroundStyle(it.enabled ? DuoColor.text : DuoColor.text2)
                    .padding(.horizontal, 8)
                    .frame(height: 21)
                    .background(RoundedRectangle(cornerRadius: 4).fill(it.enabled && hovered == it.id ? DuoColor.selected : Color.clear))
                    .contentShape(Rectangle())
                    .onHover { h in if it.enabled { preview.hover(h ? it.id : nil, leaving: it.id) } }
                    .onActivate { if it.enabled { dismiss(); it.action() } }   // not an action: runs the item's own verb
                    .accessibilityLabel(it.title)
                }
            }
        }
        .padding(4)
        .frame(width: width, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: DuoMetric.radiusControl).fill(DuoColor.pane))
        .overlay(RoundedRectangle(cornerRadius: DuoMetric.radiusControl).strokeBorder(DuoColor.rule, lineWidth: DuoMetric.borderHairline))
        .compositingGroup()
        .duoPopoverShadow()
    }
}

/// Problems ⌄ (P3-3 1): only when there are errors. A warning triangle in `text` and "n problem(s)" semibold.
struct DeckProblemsButton: View {
    @Environment(AppModel.self) private var model
    let preview: DeckPreview

    var body: some View {
        let _ = model.pickerRevision
        let n = preview.errors.count
        Button { preview.toggleMenu("problems") } label: {   // action: deck problems
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle").font(.system(size: 10, weight: .regular))
                Text("\(n) problem\(n == 1 ? "" : "s")").fontWeight(.semibold)
                Image(systemName: "chevron.down").font(.system(size: DuoSymbolSize.chevron, weight: .semibold))
            }
            .duoText(.control).foregroundStyle(DuoColor.text).lineLimit(1).fixedSize()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(n) problems")
        .accessibilityIdentifier("deck.problems")
    }
}

/// Export ⌄ (P3-3 3): a bordered button with its chevron.
struct DeckExportButton: View {
    @Environment(AppModel.self) private var model
    let preview: DeckPreview

    var body: some View {
        let _ = model.pickerRevision
        Button { preview.toggleMenu("export") } label: {   // action: deck export
            HStack(spacing: 4) { Text("Export"); Image(systemName: "chevron.down").font(.system(size: DuoSymbolSize.chevron, weight: .semibold)) }
        }
        .buttonStyle(DuoButtonStyle(on: preview.menu == "export"))
        .accessibilityIdentifier("deck.export")
    }
}

/// The pptx viewer's extra buttons (P3-4): Make Templates… and Convert to Duo Deck…, or both in a ⋯ menu under 460.
struct DeckPptxButtons: View {
    @Environment(AppModel.self) private var model
    let viewer: DeckViewer
    let path: String
    var folded = false

    var body: some View {
        if folded {
            Menu {
                Button("Make Templates…") { toggleMake() }   // action: deck template pick
                    .disabled(viewer.state != .ready)
                Button("Convert to Duo Deck…") { model.showConvertDeck(path) }   // action: deck import
            } label: { Text("⋯") }
            .menuStyle(.button).buttonStyle(.duo).fixedSize().menuIndicator(.hidden)
            .accessibilityLabel("More")
        } else {
            Button("Make Templates…") { toggleMake() }   // action: deck template pick
                .buttonStyle(DuoButtonStyle(on: viewer.slidePicking)).disabled(viewer.state != .ready).fixedSize()
                .accessibilityIdentifier("deck.make-templates")
            Button("Convert to Duo Deck…") { model.showConvertDeck(path) }   // action: deck import
                .buttonStyle(.duo).disabled(viewer.state != .ready).fixedSize()
        }
    }

    private func toggleMake() { viewer.setSlidePicking(!viewer.slidePicking) }
}

/// The foot of the pptx viewer while slides are being picked (make-templates board A): "n slides picked",
/// Cancel, Add to Pack ⌄, and Make Templates with Claude, which pastes the inventory line without Return.
struct DeckSlidePickBar: View {
    @Environment(AppModel.self) private var model
    let viewer: DeckViewer
    let path: String
    let file: URL

    var body: some View {
        let _ = model.pickerRevision
        let n = viewer.pickedSlides.count
        HStack(spacing: DuoSpace.gapButtonToButton) {
            if n == 0 {
                Text("Click slides to pick them; Esc to stop").duoText(.body).foregroundStyle(DuoColor.text2).lineLimit(1)
            } else {
                (Text("\(n) slide\(n == 1 ? "" : "s") picked").fontWeight(.semibold) + Text(" · click slides to pick them; Esc to stop").foregroundColor(DuoColor.text2))
                    .duoText(.body).lineLimit(1)
            }
            Spacer(minLength: 8)
            Button("Cancel") { viewer.setSlidePicking(false) }.buttonStyle(.duo).fixedSize()   // action: deck template pick
            Menu {
                let packs = model.deckPackNames(near: file)
                if packs.isEmpty { Text("No packs yet").disabled(true) }
                ForEach(packs, id: \.self) { p in
                    Button(p) { model.sendTemplatesRequest(file: file, path: path, slides: viewer.pickedSlides, pack: p); viewer.setSlidePicking(false) }   // action: deck template inventory
                }
            } label: {
                HStack(spacing: 4) { Text("Add to Pack"); Image(systemName: "chevron.down").font(.system(size: DuoSymbolSize.chevron, weight: .semibold)) }
            }
            .menuStyle(.button).buttonStyle(.duo).fixedSize().menuIndicator(.hidden).disabled(n == 0)
            Button("Make Templates with Claude") {   // action: deck template inventory
                model.sendTemplatesRequest(file: file, path: path, slides: viewer.pickedSlides, pack: nil)
                viewer.setSlidePicking(false)
            }
            .buttonStyle(DefaultSheetButtonStyle()).disabled(n == 0).fixedSize()
            .accessibilityIdentifier("deck.make-with-claude")
        }
        .padding(.vertical, DuoMetric.noticePaddingY)
        .padding(.horizontal, DuoMetric.noticePaddingX)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DuoColor.ground)
        .overlay(alignment: .top) { DuoColor.rule.frame(height: DuoMetric.borderHairline) }
    }
}

/// The DL-132-style notice after an export: what was written, and Show in Finder and Open With.
struct DeckExportNoticeBar: View {
    @Environment(AppModel.self) private var model
    let preview: DeckPreview

    var body: some View {
        let _ = model.pickerRevision
        if let n = preview.exportNotice {
            NoticeBar(text: n.text, sub: n.sub) {
                if let url = n.file {
                    Button("Show in Finder") { FileActions.reveal(url) }.buttonStyle(.duo)
                    OpenWithMenu(path: model.displayPath(url), file: url, bordered: true)
                }
                Button("OK") { preview.exportNotice = nil; preview.viewer.onChange?() }.buttonStyle(.duo)
            }
        }
    }
}

/// The menus of the markdown deck's bar, drawn over the slides.
struct DeckMenuLayer: View {
    @Environment(AppModel.self) private var model
    let preview: DeckPreview

    var body: some View {
        let _ = model.pickerRevision
        if let which = preview.menu {
            ZStack(alignment: .topLeading) {
                Color.clear.contentShape(Rectangle()).onActivate { preview.menu = nil; preview.viewer.onChange?() }   // not an action: dismisses the menu
                if which == "problems" {
                    DeckDropdown(preview: preview, items: preview.problemMenuItems(), width: 340) { preview.menu = nil; preview.viewer.onChange?() }
                        .padding(.leading, 96).padding(.top, 4)
                } else {
                    HStack {
                        Spacer(minLength: 0)
                        DeckDropdown(preview: preview, items: preview.exportMenuItems(), width: 270) { preview.menu = nil; preview.viewer.onChange?() }
                            .padding(.trailing, 10)
                    }
                    .padding(.top, 4)
                }
            }
        }
    }
}
