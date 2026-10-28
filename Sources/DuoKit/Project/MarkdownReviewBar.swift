import AppKit
import DuoControl
import SwiftUI

/// The review bar on a Markdown document (DL-237; target markdown-review-handoff `track-a`, `margin-suggest`):
/// 44 high under the tabs with a `rule` below, Duo's one button. Markup ⌄ and Suggest Edits at the
/// left; ‹ › and Review All ⌄ at the right. It shows on a document that has marks or comments, or has
/// Suggest Edits on (a stand-in until Q-265 is answered). Under 420 it drops ‹ › and says Review ⌄,
/// which gains Next and Previous at its top.
struct MarkdownReviewBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let _ = model.editorRevision
        let r = model.editor.review
        GeometryReader { g in
            let compact = g.size.width < 420
            row(r, compact: compact)
                .padding(.leading, DuoMetric.noticePaddingX).padding(.trailing, DuoMetric.docxBarTrailing)
                .frame(width: g.size.width, height: DuoMetric.deckBarHeight)
                .overlay(alignment: .bottom) { DuoColor.rule.frame(height: DuoMetric.borderHairline) }
                // The menus hang under their buttons; the bar is above the editor so they draw over it.
                .overlay(alignment: .topLeading) {
                    if model.reviewMenu == "markup" { MarkdownMarkupMenu().padding(.leading, DuoMetric.noticePaddingX).padding(.top, DuoMetric.docxMenuTop) }
                }
                .overlay(alignment: .topTrailing) {
                    if model.reviewMenu == "all" { MarkdownReviewAllMenu(compact: compact).padding(.trailing, DuoMetric.docxBarTrailing).padding(.top, DuoMetric.docxMenuTop) }
                }
        }
        .frame(height: DuoMetric.deckBarHeight)
        .zIndex(1)
    }

    private func chevron(_ title: String) -> some View {
        HStack(spacing: 1) { Text(title); Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold)) }
    }

    private func row(_ r: ReviewSummary, compact: Bool) -> some View {
        HStack(spacing: DuoSpace.gapButtonToButton) {
            Button { model.reviewMenu = model.reviewMenu == "markup" ? nil : "markup" } label: { chevron("Markup") }   // action: doc markup
                .buttonStyle(DuoButtonStyle(on: model.reviewMenu == "markup")).fixedSize()
            Button { model.toggleSuggestEdits() } label: {   // action: doc review
                HStack(spacing: 6) {
                    // A hollow 8 dot (1.5 controlEdge) when off; filled `text` when on (track-a).
                    if r.suggestEdits { Circle().fill(DuoColor.text).frame(width: 8, height: 8) }
                    else { Circle().strokeBorder(DuoColor.controlEdge, lineWidth: 1.5).frame(width: 8, height: 8) }
                    Text("Suggest Edits")
                }
            }
            .buttonStyle(DuoButtonStyle(on: r.suggestEdits)).fixedSize()
            .accessibilityAddTraits(r.suggestEdits ? .isSelected : [])
            Spacer(minLength: 0)
            if !compact {
                Button { model.editor.reviewStep(-1) } label: { Text("‹") }   // action: doc review
                    .buttonStyle(DuoButtonStyle(on: false)).fixedSize().accessibilityLabel("Previous Change")
                Button { model.editor.reviewStep(1) } label: { Text("›") }   // action: doc review
                    .buttonStyle(DuoButtonStyle(on: false)).fixedSize().accessibilityLabel("Next Change")
            }
            Button { model.reviewMenu = model.reviewMenu == "all" ? nil : "all" } label: { chevron(compact ? "Review" : "Review All") }   // action: suggestion accept
                .buttonStyle(DuoButtonStyle(on: model.reviewMenu == "all")).fixedSize()
        }
    }
}

/// Where the bar goes in the pane: on a Markdown document that has marks or comments, or Suggest Edits on.
struct MarkdownReviewSlot: View {
    @Environment(AppModel.self) private var model
    let file: URL

    var body: some View {
        let _ = model.editorRevision
        if AppModel.markdownExtensions.contains(file.pathExtension.lowercased()), model.editor.url?.standardizedFileURL == file.standardizedFileURL,
           model.editor.review.showsBar {
            MarkdownReviewBar()
        }
    }
}

/// Markup ⌄: the Word viewer's menu (DL-162 W4) with Show Closed Comments where Word says Show Resolved.
struct MarkdownMarkupMenu: View {
    @Environment(AppModel.self) private var model
    private static let modes: [(id: String, title: String)] = [("all", "All Markup"), ("simple", "Simple Markup"), ("none", "No Markup"), ("original", "Original")]

    var body: some View {
        let _ = model.editorRevision
        let r = model.editor.review
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Self.modes, id: \.id) { mode in
                ReviewMenuRow(title: mode.title, checked: r.mode == mode.id, selected: r.mode == mode.id)
                    .onActivate { model.setMarkdownMarkup(mode: mode.id) }   // action: doc markup
            }
            ReviewMenuDivider()
            ReviewMenuRow(title: "Show Closed Comments", checked: r.showClosed, trailing: r.closed > 0 ? "\(r.closed)" : nil)
                .onActivate { model.setMarkdownMarkup(showClosed: !r.showClosed) }   // action: doc markup
        }
        .modifier(ReviewMenuFrame())
    }
}

/// Review All ⌄ (or Review ⌄ when narrow): Accept All, Reject All, then the same per person, then the counts.
struct MarkdownReviewAllMenu: View {
    @Environment(AppModel.self) private var model
    let compact: Bool

    var body: some View {
        let _ = model.editorRevision
        let r = model.editor.review
        VStack(alignment: .leading, spacing: 0) {
            if compact {
                ReviewMenuRow(title: "Next Change", checked: false).onActivate { model.reviewMenu = nil; model.editor.reviewStep(1) }   // action: doc review
                ReviewMenuRow(title: "Previous Change", checked: false).onActivate { model.reviewMenu = nil; model.editor.reviewStep(-1) }   // action: doc review
                ReviewMenuDivider()
            }
            ReviewMenuRow(title: "Accept All", checked: false).onActivate { model.reviewMenu = nil; model.editor.reviewResolveAll(accept: true) }   // action: suggestion accept
            ReviewMenuRow(title: "Reject All", checked: false).onActivate { model.reviewMenu = nil; model.editor.reviewResolveAll(accept: false) }   // action: suggestion reject
            let who = r.people.filter { $0.count > 0 }
            if who.count > 1 {
                ReviewMenuDivider()
                ForEach(who, id: \.name) { p in
                    ReviewMenuRow(title: "Accept All from \(p.name.prefix(1).uppercased() + p.name.dropFirst())", checked: false, dot: p.colour)
                        .onActivate { model.reviewMenu = nil; model.editor.reviewResolveAll(accept: true, person: p.name) }   // action: suggestion accept
                    ReviewMenuRow(title: "Reject All from \(p.name.prefix(1).uppercased() + p.name.dropFirst())", checked: false, dot: p.colour)
                        .onActivate { model.reviewMenu = nil; model.editor.reviewResolveAll(accept: false, person: p.name) }   // action: suggestion reject
                }
            }
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
            .overlay(RoundedRectangle(cornerRadius: DuoMetric.radiusPopover).strokeBorder(DuoColor.text.opacity(0.08), lineWidth: DuoMetric.borderHairline))
            .shadow(color: DuoColor.text.opacity(0.18), radius: 12, x: 0, y: 8)
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

    var body: some View {
        HStack(spacing: 0) {
            if let dot { Circle().fill(MarkupMenu.colour(dot)).frame(width: 9, height: 9).frame(width: 16, alignment: .leading) }
            else { Text(checked ? "✓" : "").duoText(.body).frame(width: 16, alignment: .leading) }
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
