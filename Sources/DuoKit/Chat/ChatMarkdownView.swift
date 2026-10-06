import AppKit
import SwiftUI

/// Claude's Markdown, drawn (chat-mode-handoff `text`): headings, paragraphs, plain bullets (Geoff
/// rejected pills), numbered lists, code with a copy icon, lightly ruled tables, quotes.
struct ChatMarkdownView: View {
    let blocks: [ChatBlock]
    let streaming: Bool
    var faded = false
    /// The plan card's smaller scale: 13/20 text, 15/22 headings.
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { i, b in
                // An interrupted reply's last paragraph is drawn faded; headings keep their weight.
                ChatBlockView(block: b, caret: streaming && i == blocks.count - 1, faded: faded && i == blocks.count - 1, compact: compact)
            }
            if streaming, blocks.isEmpty { ChatCaret() }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// The streaming caret: 2 × 15, in `text`.
struct ChatCaret: View {
    var body: some View { DuoColor.text.frame(width: 2, height: 15) }
}

struct ChatBlockView: View {
    let block: ChatBlock
    var caret = false
    var faded = false
    var compact = false

    var body: some View {
        switch block {
        case .heading(let level, let text):
            ChatInlineText(text: text, style: compact ? .chatPlanHeading : level <= 1 ? .chatHeading1 : level == 2 ? .chatHeading : .chatHeading3, caret: caret)
                .accessibilityAddTraits(.isHeader)
        case .paragraph(let text):
            ChatInlineText(text: text, style: compact ? .body : .chatBody, caret: caret, color: faded ? DuoColor.text2 : DuoColor.text)
        case .list(let ordered, let start, let items):
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Text(ordered ? "\(start + i)." : "•").duoText(compact ? .body : .chatBody).foregroundStyle(DuoColor.text)
                            .frame(width: 22, alignment: ordered ? .trailing : .center)
                            .padding(.trailing, ordered ? 6 : 2)
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(item.enumerated()), id: \.offset) { j, b in
                                ChatBlockView(block: b, caret: caret && i == items.count - 1 && j == item.count - 1, compact: compact)
                            }
                        }
                    }
                }
            }
        case .code(_, let text):
            HStack(alignment: .top, spacing: 10) {
                Text(text).duoText(.mono).foregroundStyle(DuoColor.text)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ChatCopyButton(text: text)
            }
            .padding(EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 8))
            .background(RoundedRectangle(cornerRadius: DuoMetric.radiusChatCodeBlock).fill(DuoColor.chatGround))
        case .table(let header, let rows):
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 0) {
                GridRow {
                    ForEach(Array(header.enumerated()), id: \.offset) { _, h in
                        Text(ChatMarkdown.inline(h)).duoText(.chip).foregroundStyle(DuoColor.text2).padding(.vertical, 5)
                    }
                }
                DuoColor.selected.frame(height: DuoMetric.borderHairline).gridCellColumns(max(1, header.count))
                ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                    GridRow {
                        ForEach(0..<header.count, id: \.self) { c in
                            Text(ChatMarkdown.inline(c < r.count ? r[c] : "")).duoText(.body).foregroundStyle(DuoColor.text).padding(.vertical, 5)
                        }
                    }
                    DuoColor.selected.frame(height: DuoMetric.borderHairline).gridCellColumns(max(1, header.count))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .quote(let inner):
            HStack(alignment: .top, spacing: 10) {
                DuoColor.rule.frame(width: 2)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(inner.enumerated()), id: \.offset) { _, b in ChatBlockView(block: b).foregroundStyle(DuoColor.text2) }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        case .rule:
            DuoColor.rule.frame(height: DuoMetric.borderHairline)
        }
    }
}

/// A paragraph or heading: inline Markdown with inline code and file links in mono, links underlined.
struct ChatInlineText: View {
    let text: String
    let style: DuoTextStyle
    var caret = false
    var color = DuoColor.text

    var body: some View {
        let t = Text(Self.styled(text, style: style))
        Group {
            if caret { Text("\(t)\(Text(Image(systemName: "poweron")).font(.system(size: 13, weight: .regular)).foregroundStyle(DuoColor.text))") } else { t }
        }
        .duoText(style)
        .foregroundStyle(color)
        .textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
    }

    static func styled(_ text: String, style: DuoTextStyle) -> AttributedString {
        var a = ChatMarkdown.inline(text)
        let mono = Font(NSFont.monospacedSystemFont(ofSize: DuoTextStyle.chatInlineCode.spec.size, weight: .regular))
        for run in a.runs {
            let r = run.range
            if run.inlinePresentationIntent?.contains(.code) == true {
                a[r].font = mono
                if run.link == nil { a[r].backgroundColor = DuoColor.chatGround }
            }
            if run.inlinePresentationIntent?.contains(.stronglyEmphasized) == true {
                a[r].font = .system(size: style.spec.size, weight: .semibold)
            }
            if run.inlinePresentationIntent?.contains(.emphasized) == true {
                a[r].font = .system(size: style.spec.size, weight: style.spec.weight).italic()
            }
            if let link = run.link {
                a[r].foregroundColor = DuoColor.text
                a[r].underlineStyle = Text.LineStyle(pattern: .solid, color: DuoColor.controlEdge)
                if link.scheme == "duo-file", run.inlinePresentationIntent?.contains(.code) != true { a[r].font = mono }
            }
        }
        return a
    }
}

/// The copy icon on a code block (labelled Copy).
struct ChatCopyButton: View {
    let text: String
    var body: some View {
        CopyMark().stroke(DuoColor.text2, style: StrokeStyle(lineWidth: 1.2, lineCap: .round)).frame(width: 12, height: 12)
            .frame(width: 26, height: 24)
            .background(RoundedRectangle(cornerRadius: DuoMetric.radiusChatStepBody).fill(DuoColor.pane))
            .overlay(RoundedRectangle(cornerRadius: DuoMetric.radiusChatStepBody).strokeBorder(DuoColor.rule, lineWidth: DuoMetric.borderHairline))
            .contentShape(Rectangle())
            .onActivate { FileActions.copy(text) }  // not an action: copies text already on screen
            .help("Copy")
            .accessibilityLabel("Copy")
    }
}

/// Two overlapping rounded squares, 12 × 12 (handoff `text`).
struct CopyMark: Shape {
    func path(in r: CGRect) -> Path {
        let s = r.width / 12
        var p = Path(roundedRect: CGRect(x: 3.5 * s, y: 3.5 * s, width: 7 * s, height: 7 * s), cornerRadius: 1.5 * s)
        p.move(to: .init(x: 8.5 * s, y: 3.5 * s)); p.addLine(to: .init(x: 8.5 * s, y: 2 * s))
        p.addQuadCurve(to: .init(x: 7 * s, y: 0.5 * s), control: .init(x: 8.5 * s, y: 0.5 * s))
        p.addLine(to: .init(x: 2 * s, y: 0.5 * s))
        p.addQuadCurve(to: .init(x: 0.5 * s, y: 2 * s), control: .init(x: 0.5 * s, y: 0.5 * s))
        p.addLine(to: .init(x: 0.5 * s, y: 7 * s))
        p.addQuadCurve(to: .init(x: 2 * s, y: 8.5 * s), control: .init(x: 0.5 * s, y: 8.5 * s))
        p.addLine(to: .init(x: 3.5 * s, y: 8.5 * s))
        return p
    }
}
