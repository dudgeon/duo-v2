import SwiftUI

// What a slash command printed (chat-slash-handoff `output`, `context`; DL-143): right-aligned
// under your bubble, led by Claude Code's own ⎿ drawn as an elbow. One line is a quiet line; a few
// lines are an output block; `/context` is a bar and its legend.

/// Claude Code's ⎿, 10 × 10: stroke 1.4, round caps, `text2`.
struct ChatElbow: View {
    var body: some View {
        Path { p in p.move(to: .init(x: 2, y: 1)); p.addLine(to: .init(x: 2, y: 6.5)); p.addLine(to: .init(x: 8, y: 6.5)) }
            .stroke(DuoColor.text2, style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
            .frame(width: 10, height: 10)
    }
}

struct ChatResultView: View {
    let result: ChatResult
    let chat: ChatSession
    /// Up to 8 lines show whole; longer shows 6 and Show n more lines (DL-135's rule for output).
    static let whole = 8, shown = 6

    var body: some View {
        switch result.body {
        case .line(let text):
            HStack(spacing: 8) {
                ChatElbow()
                Text(text).duoText(.chatMeta).foregroundStyle(DuoColor.text2).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.trailing, 4)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .accessibilityElement(children: .combine)
        case .block(let lines):
            ChatResultBox { block(lines) }
        case .context(let c):
            ChatResultBox { ChatContextBox(usage: c) }
        }
    }

    func block(_ lines: [String]) -> some View {
        let all = lines.count <= Self.whole || chat.ui.fullOutput.contains(result.id)
        let visible = all ? lines : Array(lines.prefix(Self.shown))
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(visible.enumerated()), id: \.offset) { _, l in
                Text(l.isEmpty ? " " : l).duoText(.mono).foregroundStyle(DuoColor.text).lineLimit(1).truncationMode(.tail)
            }
            if !all {
                let n = lines.count - Self.shown
                Text("Show \(n) more line\(n == 1 ? "" : "s")").duoText(.chatMeta, lineHeight: DuoTextStyle.mono.spec.lineHeight).foregroundStyle(DuoColor.text)
                    .underline(color: DuoColor.controlEdge)
                    .padding(.top, 4)
                    .onActivate { chat.ui.fullOutput.insert(result.id) }  // not an action: shows more of what's drawn
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(EdgeInsets(top: 8 + 1, leading: 12 + 1, bottom: 8 + 1, trailing: 12 + 1))   // 8/12 inside a 1 pt border
        .background(RoundedRectangle(cornerRadius: DuoMetric.radiusCard).fill(DuoColor.toolOutputFill))
        .overlay(RoundedRectangle(cornerRadius: DuoMetric.radiusCard).strokeBorder(DuoColor.rule, lineWidth: DuoMetric.borderHairline))
    }
}

/// The elbow and a box, right-aligned under your bubble: 440 wide with the elbow, less in a
/// narrow console (the board's 480 console gives 356: the pane less the column's insets and 76).
struct ChatResultBox<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            ChatElbow().padding(.top, 4)
            content
        }
        .containerRelativeFrame(.horizontal, alignment: .leading) { pane, _ in Self.width(pane) }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    static func width(_ pane: CGFloat) -> CGFloat { max(200, min(DuoSpace.chatBubbleMax, pane - 2 * DuoSpace.chatColumnInset - 76)) }
}

/// `/context`: a `pane` box, its total, a bar of the used categories in greys stepped by
/// lightness (never the accent), the legend and the skills line. Narrow (the 480 console), the
/// model and the word "tokens" go and the legend is one column.
struct ChatContextBox: View {
    let usage: ChatContextUsage

    var body: some View {
        ViewThatFits(in: .horizontal) {
            box(narrow: false).frame(minWidth: 380)
            box(narrow: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Context usage: \(usage.used) of \(usage.total) tokens, \(usage.percent)%")
    }

    func box(narrow: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Context usage").duoText(.bodyEmphasis).foregroundStyle(DuoColor.text)
                if !narrow, let m = usage.model {
                    Text(m).duoText(.body).foregroundStyle(DuoColor.text2).help(usage.modelId ?? m).lineLimit(1)
                }
                Spacer(minLength: 8)
                Text("\(usage.used) / \(usage.total)\(narrow ? "" : " tokens") · \(usage.percent)%").duoText(.body).monospacedDigit()
                    .foregroundStyle(DuoColor.text).lineLimit(1)
            }
            ChatContextBar(usage: usage)
            ChatContextLegend(usage: usage, columns: narrow ? 1 : 2)
            if !narrow, let s = usage.skills { Text(s).duoText(.chatMeta).foregroundStyle(DuoColor.text2) }
        }
        .padding(EdgeInsets(top: 10 + 1, leading: 12 + 1, bottom: 12 + 1, trailing: 12 + 1))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: DuoMetric.radiusCard).fill(DuoColor.pane))
        .overlay(RoundedRectangle(cornerRadius: DuoMetric.radiusCard).strokeBorder(DuoColor.rule, lineWidth: DuoMetric.borderHairline))
    }

    /// The nth used category's grey: `text`, `text2`, then `controlEdge`.
    static func shade(_ i: Int) -> Color { i == 0 ? DuoColor.text : i == 1 ? DuoColor.text2 : DuoColor.controlEdge }
}

/// 8 high, radius 4, on `selected`; a category under 1% is still 2 wide.
struct ChatContextBar: View {
    let usage: ChatContextUsage
    var body: some View {
        GeometryReader { g in
            HStack(spacing: 0) {
                ForEach(Array(usage.categories.filter { !$0.free }.enumerated()), id: \.offset) { i, c in
                    ChatContextBox.shade(i).frame(width: max(2, g.size.width * c.share / 100))
                }
                Spacer(minLength: 0)
            }
        }
        .frame(height: 8)
        .background(DuoColor.selected)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

/// Two columns (one at the narrowest console), filled down then across; a 9 × 9 swatch.
struct ChatContextLegend: View {
    let usage: ChatContextUsage
    let columns: Int

    var body: some View {
        let entries = Self.entries(usage)
        let per = Int((Double(entries.count) / Double(columns)).rounded(.up))
        HStack(alignment: .top, spacing: 16) {
            ForEach(0..<columns, id: \.self) { col in
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(entries.dropFirst(col * per).prefix(per).enumerated()), id: \.offset) { _, e in
                        HStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 2).fill(e.free ? DuoColor.selected : e.shade)
                                .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(e.free ? DuoColor.rule : .clear, lineWidth: DuoMetric.borderHairline))
                                .frame(width: 9, height: 9)
                            Text("\(e.name) · \(e.amount)").duoText(.chatMeta, lineHeight: 18).monospacedDigit().foregroundStyle(DuoColor.text2).lineLimit(1)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    struct Entry { let name: String; let amount: String; let free: Bool; let shade: Color }

    static func entries(_ u: ChatContextUsage) -> [Entry] {
        var used = 0
        return u.categories.map { c in
            if c.free { return Entry(name: c.name, amount: c.amount, free: true, shade: DuoColor.selected) }
            defer { used += 1 }
            return Entry(name: c.name, amount: c.amount, free: false, shade: ChatContextBox.shade(used))
        }
    }
}
