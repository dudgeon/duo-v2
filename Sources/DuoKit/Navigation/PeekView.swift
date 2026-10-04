import SwiftUI

/// The peek (handoff §3.4, DL-28): what needs you in other projects, from the toolbar chip.
/// Target: screens/flow-zoom-3.html. A native popover draws the frame and arrow (§0.4).
struct PeekView: View {
    @Environment(AppModel.self) private var model
    @FocusState private var focused: Bool

    var body: some View {
        let sessions = model.needsYouElsewhere
        VStack(alignment: .leading, spacing: DuoSpace.gapCardToCard) {
            SectionLabel(text: "Needs you elsewhere", count: sessions.count, needsYou: true)
            ForEach(sessions) { s in
                PeekCard(session: s, selected: model.peekSelection == s.id)
            }
            FlowRow(spacing: 14) {
                Text("↑↓ Select")
                Text("⌘↩ Jump into the selected project")
                Text("⇧⌘H Home")
                Text("esc Close")
            }
            .duoText(.control)
            .foregroundStyle(DuoColor.text2)
            .padding(.top, 2)
        }
        .padding(DuoSpace.popoverPadding)
        .frame(width: DuoMetric.peekPopoverWidth, alignment: .leading)
        .foregroundStyle(DuoColor.text)
        .background(DuoColor.pane)
        // Opening the peek moves focus into it; closing returns it (handoff §10).
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onAppear { focused = true }
        .onKeyPress(.upArrow) { model.movePeekSelection(by: -1); return .handled }
        .onKeyPress(.downArrow) { model.movePeekSelection(by: 1); return .handled }
        // ⌘↩ is a menu command (DuoCommand.jumpToPeekSelection), so it isn't handled here too.
        .onKeyPress(.escape) { model.peekOpen = false; return .handled }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Needs you elsewhere, \(sessions.count) sessions")
    }
}

/// A card in the peek: like the action column's, with a way out: `Home ⇧⌘H` for Home
/// sessions, `Open project` otherwise (concerns Q-9). No reply buttons (DL-29).
struct PeekCard: View {
    @Environment(AppModel.self) private var model
    let session: Fixture.Session
    let selected: Bool

    var body: some View {
        let isHome = session.project == model.fixture.home?.name
        VStack(alignment: .leading, spacing: DuoSpace.gapCardContent) {
            VStack(alignment: .leading, spacing: 0) {
                CardHeader(session: session)
                Text(session.project).duoText(.body).foregroundStyle(DuoColor.text2).lineLimit(1)
            }
            if let q = session.question {
                Text(q)
                    .duoText(.body)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .modifier(QuestionBox(boxed: selected))
            }
            HStack(spacing: DuoSpace.gapButtonToButton) {
                if isHome {
                    Button { model.goHome() } label: {
                        HStack(spacing: 8) {
                            Text("Home")
                            Text("⇧⌘H").foregroundStyle(DuoColor.text2)
                        }
                    }
                    .buttonStyle(.duo)
                } else {
                    Button("Open project") { model.open(project: session.project, session: session.name) }
                        .buttonStyle(.duo)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .bordered(DuoSpace.cardPadding,
                  color: selected ? DuoColor.text : DuoColor.rule,
                  width: selected ? DuoMetric.borderEmphasis : DuoMetric.borderHairline)
        .contentShape(Rectangle())
        .onActivate { model.peekSelection = session.id }  // action: view select
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(session.name), needs you, waiting \(session.wait ?? ""), \(session.project)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Lays children out left to right and wraps, like a CSS `flex-wrap: wrap` row with `gap`.
struct FlowRow: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let lines = arrange(subviews, width: width)
        let height = lines.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, lines.count - 1))
        return CGSize(width: proposal.width ?? lines.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for line in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for i in line.indices {
                let size = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += line.height + spacing
        }
    }

    private struct Line { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Line] {
        var lines = [Line()]
        for i in subviews.indices {
            let size = subviews[i].sizeThatFits(.unspecified)
            let needed = lines[lines.count - 1].indices.isEmpty ? size.width : lines[lines.count - 1].width + spacing + size.width
            if needed > width, !lines[lines.count - 1].indices.isEmpty {
                lines.append(Line())
            }
            var line = lines.removeLast()
            line.width = line.indices.isEmpty ? size.width : line.width + spacing + size.width
            line.height = max(line.height, size.height)
            line.indices.append(i)
            lines.append(line)
        }
        return lines
    }
}
