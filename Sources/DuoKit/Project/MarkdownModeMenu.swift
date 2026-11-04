import AppKit
import DuoControl
import SwiftUI

/// The mode menu of the formatting bar (DL-317; target markdown-toolbar-handoff `review-in-bar`, menu open): hangs under
/// Editing ⌄ / Suggesting ⌄ at the bar's right. Editing and Suggesting (⇧⌘E) as one choice; Next and Previous Change,
/// Accept All and Reject All (and per person); Markup ▸ (All, Simple, None, Original) and Show Closed Comments with its
/// count; then the counts. It replaces the 44-high review bar (DL-237's `MarkdownReviewBar`), which is retired: every item
/// calls the function it called there, so a click and `duo2 doc review|markup`, `suggestion accept|reject` do the same.
/// `model.reviewMenu` is "mode" while it's open and "markup" while Markup's choices are open under it.
struct MarkdownModeMenu: View {
    @Environment(AppModel.self) private var model
    @Environment(\.editorSide) private var side
    private static let modes: [(id: String, title: String)] = [("all", "All Markup"), ("simple", "Simple Markup"), ("none", "No Markup"), ("original", "Original")]

    var body: some View {
        let _ = model.editorRevision
        let r = model.editor(side).review
        let markupOpen = model.reviewMenu == "markup"
        VStack(alignment: .leading, spacing: 0) {
            // Editing and Suggesting are one choice (checked).
            ReviewMenuRow(title: "Editing", checked: !r.suggestEdits, trailing: "edits change the text")
                .onActivate { model.reviewMenu = nil; if r.suggestEdits { model.onSide(side) { model.toggleSuggestEdits() } } }   // action: doc review
            ReviewMenuRow(title: "Suggesting", checked: r.suggestEdits, selected: r.suggestEdits, trailing: "⇧⌘E")
                .onActivate { model.reviewMenu = nil; if !r.suggestEdits { model.onSide(side) { model.toggleSuggestEdits() } } }   // action: doc review
            ReviewMenuDivider()
            ReviewMenuRow(title: "Next Change", checked: false).onActivate { model.reviewMenu = nil; model.editor(side).reviewStep(1) }   // action: doc review
            ReviewMenuRow(title: "Previous Change", checked: false).onActivate { model.reviewMenu = nil; model.editor(side).reviewStep(-1) }   // action: doc review
            ReviewMenuRow(title: "Accept All", checked: false).onActivate { model.reviewMenu = nil; model.editor(side).reviewResolveAll(accept: true) }   // action: suggestion accept
            ReviewMenuRow(title: "Reject All", checked: false).onActivate { model.reviewMenu = nil; model.editor(side).reviewResolveAll(accept: false) }   // action: suggestion reject
            let who = r.people.filter { $0.count > 0 }
            if who.count > 1 {
                ReviewMenuDivider()
                ForEach(who, id: \.name) { p in
                    ReviewMenuRow(title: "Accept All from \(p.name.prefix(1).uppercased() + p.name.dropFirst())", checked: false, dot: p.colour)
                        .onActivate { model.reviewMenu = nil; model.editor(side).reviewResolveAll(accept: true, person: p.name) }   // action: suggestion accept
                    ReviewMenuRow(title: "Reject All from \(p.name.prefix(1).uppercased() + p.name.dropFirst())", checked: false, dot: p.colour)
                        .onActivate { model.reviewMenu = nil; model.editor(side).reviewResolveAll(accept: false, person: p.name) }   // action: suggestion reject
                }
            }
            ReviewMenuDivider()
            // Markup ▸: its four choices open under it (a stand-in for a flyout, Q-456).
            ReviewMenuRow(title: "Markup", checked: false, trailing: "\(Self.modes.first { $0.id == r.mode }?.title.replacingOccurrences(of: " Markup", with: "").replacingOccurrences(of: "No", with: "None") ?? "All") ›")
                .onActivate { model.reviewMenu = markupOpen ? "mode" : "markup" }   // action: doc markup
            if markupOpen {
                ForEach(Self.modes, id: \.id) { mode in
                    ReviewMenuRow(title: mode.title, checked: r.mode == mode.id, selected: r.mode == mode.id, indent: true)
                        .onActivate { model.onSide(side) { model.setMarkdownMarkup(mode: mode.id) } }   // action: doc markup
                }
            }
            ReviewMenuRow(title: "Show Closed Comments", checked: r.showClosed, trailing: r.closed > 0 ? "\(r.closed)" : nil)
                .onActivate { model.onSide(side) { model.setMarkdownMarkup(showClosed: !r.showClosed) } }   // action: doc markup
            ReviewMenuDivider()
            Text("\(r.suggestions) suggestion\(r.suggestions == 1 ? "" : "s") · \(r.threads) comment\(r.threads == 1 ? "" : "s")")
                .duoText(.body).foregroundStyle(DuoColor.text2)
                .padding(.horizontal, DuoMetric.docxMenuRowPaddingX).padding(.vertical, 2)
        }
        .modifier(ReviewMenuFrame())
    }
}

private struct ReviewMenuFrame: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(5)
            .frame(width: DuoMetric.docxMenuWidth, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: DuoMetric.radiusPopover).fill(DuoColor.pane))
            .overlay(RoundedRectangle(cornerRadius: DuoMetric.radiusPopover).strokeBorder(DuoColor.rule, lineWidth: DuoMetric.borderHairline))
            .duoPopoverShadow()
    }
}

private struct ReviewMenuDivider: View {
    var body: some View { DuoColor.rule.frame(height: DuoMetric.borderHairline).padding(.horizontal, DuoMetric.docxMenuRowPaddingX).padding(.vertical, 5) }
}

private struct ReviewMenuRow: View {
    let title: String
    let checked: Bool
    var selected = false
    var trailing: String?
    var dot: Int?
    var indent = false

    var body: some View {
        HStack(spacing: 0) {
            if let dot { Circle().fill(MarkupMenu.colour(dot)).frame(width: 9, height: 9).frame(width: 16, alignment: .leading) }
            else { Text(checked ? "✓" : "").duoText(.body).frame(width: 16, alignment: .leading) }
            if indent { Spacer().frame(width: 12) }
            Text(title).duoText(.body).lineLimit(1)
            Spacer(minLength: 8)
            if let trailing { Text(trailing).duoText(.body).foregroundStyle(DuoColor.text2) }
        }
        .padding(.horizontal, DuoMetric.docxMenuRowPaddingX).padding(.vertical, 2)
        .background(RoundedRectangle(cornerRadius: DuoMetric.radiusSelection).fill(selected ? DuoColor.selected : .clear))
        .contentShape(Rectangle())
        .accessibilityLabel(title)
        .accessibilityAddTraits(checked ? .isSelected : [])
    }
}
