import SwiftUI

// Shared pieces from handoff §5. Borders in the targets sit outside their padding (CSS
// content-box), so content is inset by border width plus padding.

/// Uppercase section label with a count: `NEEDS YOU · 3` (handoff §5 `SectionLabel`).
struct SectionLabel: View {
    let text: String
    var count: Int?
    var needsYou = false

    var body: some View {
        Text(count.map { "\(text) · \($0)" } ?? text)
            .duoText(.sectionLabel)
            .foregroundStyle(needsYou ? DuoColor.needsYou : DuoColor.text2)
            .lineLimit(1)
    }
}

/// The target's button: 12/16 label, padding 4 10, 1 pt `controlEdge` border, radius 6, `pane`
/// fill, 26 high (handoff §5 `Button`).
struct DuoButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .duoText(.control)
            .foregroundStyle(DuoColor.text)
            .lineLimit(1)
            .padding(.horizontal, DuoSpace.buttonPadding.leading + DuoMetric.borderHairline)
            .padding(.vertical, DuoSpace.buttonPadding.top + DuoMetric.borderHairline)
            .background(
                RoundedRectangle(cornerRadius: DuoMetric.radiusControl)
                    .fill(configuration.isPressed ? DuoColor.selected : DuoColor.pane)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DuoMetric.radiusControl)
                    .strokeBorder(DuoColor.controlEdge, lineWidth: DuoMetric.borderHairline)
            )
            .contentShape(Rectangle())
    }
}

extension ButtonStyle where Self == DuoButtonStyle {
    static var duo: DuoButtonStyle { DuoButtonStyle() }
}

/// A bordered box: padding inside a border, as the targets draw cards and tiles.
struct Bordered: ViewModifier {
    var padding: EdgeInsets
    var color: Color = DuoColor.rule
    var width: CGFloat = DuoMetric.borderHairline
    var dashed = false
    var radius: CGFloat = DuoMetric.radiusCard

    func body(content: Content) -> some View {
        content
            .padding(EdgeInsets(top: padding.top + width, leading: padding.leading + width,
                                bottom: padding.bottom + width, trailing: padding.trailing + width))
            .overlay(
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(color, style: StrokeStyle(lineWidth: width, dash: dashed ? DuoShadow.dashPattern : []))
            )
    }
}

extension View {
    func bordered(_ padding: EdgeInsets, color: Color = DuoColor.rule, width: CGFloat = DuoMetric.borderHairline,
                  dashed: Bool = false) -> some View {
        modifier(Bordered(padding: padding, color: color, width: width, dashed: dashed))
    }
}

/// A wait time that never truncates (handoff §8).
struct WaitLabel: View {
    let text: String?

    var body: some View {
        if let text {
            Text(text).duoText(.body).foregroundStyle(DuoColor.text2).fixedSize()
        }
    }
}

/// The 8×10 chevron from tokens.json, drawn so it matches the targets' stroke.
struct Chevron: View {
    enum Direction { case right, down }
    var direction: Direction = .right
    var color: Color = DuoColor.text2

    var body: some View {
        Canvas { ctx, box in
            var p = Path()
            switch direction {
            case .right:
                ctx.scaleBy(x: box.width / 8, y: box.height / 10)
                p.move(to: CGPoint(x: 2, y: 1.5)); p.addLine(to: CGPoint(x: 6, y: 5)); p.addLine(to: CGPoint(x: 2, y: 8.5))
            case .down:
                ctx.scaleBy(x: box.width / 10, y: box.height / 8)
                p.move(to: CGPoint(x: 1.5, y: 2)); p.addLine(to: CGPoint(x: 5, y: 6)); p.addLine(to: CGPoint(x: 8.5, y: 2))
            }
            ctx.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
        .frame(width: direction == .right ? 8 : 10, height: direction == .right ? 10 : 8)
        .accessibilityHidden(true)
    }
}

/// A row laid out the way a CSS flex row with `flex-shrink: 1` lays it out: items get their
/// natural widths; if they overflow, every item shrinks in proportion to its natural width.
/// With room to spare, the last item is pushed to the trailing edge (`margin-left: auto`).
/// SwiftUI's HStack instead gives the overflow to whichever child is most flexible, which
/// wraps text differently from the targets (flow-zoom-1's focused tile).
struct FlexShrinkRow: Layout {
    var spacing: CGFloat = DuoSpace.gapRowItems

    private func widths(_ subviews: Subviews, available: CGFloat) -> [CGFloat] {
        let natural = subviews.map { $0.sizeThatFits(.unspecified).width }
        let gaps = spacing * CGFloat(max(0, subviews.count - 1))
        let total = natural.reduce(0, +)
        let overflow = total + gaps - available
        guard overflow > 0, total > 0 else { return natural }
        return natural.map { $0 - overflow * $0 / total }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let available = proposal.width ?? .infinity
        let w = widths(subviews, available: available)
        let h = zip(subviews, w).map { $0.sizeThatFits(ProposedViewSize(width: $1, height: nil)).height }.max() ?? 0
        let used = w.reduce(0, +) + spacing * CGFloat(max(0, subviews.count - 1))
        return CGSize(width: proposal.width ?? used, height: h)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let w = widths(subviews, available: bounds.width)
        var x = bounds.minX
        for (i, (view, width)) in zip(subviews, w).enumerated() {
            if i == subviews.count - 1, i > 0 { x = max(x, bounds.maxX - width) }
            view.place(at: CGPoint(x: x, y: bounds.minY), anchor: .topLeading,
                       proposal: ProposedViewSize(width: width, height: nil))
            x += width + spacing
        }
    }
}

extension View {
    /// A tap that VoiceOver, Full Keyboard Access and automation can also trigger: `onTapGesture`
    /// alone isn't reachable through accessibility (findings F-21; handoff §10).
    func onActivate(_ action: @escaping () -> Void) -> some View {
        self
            .onTapGesture(perform: action)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(.default, action)
    }
}
