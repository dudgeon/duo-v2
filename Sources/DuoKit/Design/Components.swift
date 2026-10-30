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
    /// Shown pressed while its mode is on (Select Shape while picking, pptx-handoff B).
    var on = false
    /// The label semibold while on (the template bar's Preview, templates-handoff A2).
    var boldWhenOn = false
    /// The repo line's smaller button: 20 high, 11 pt, padding 8 (DL-149, `repoLine` tokens).
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        DuoButtonBody(configuration: configuration, on: on, bold: on && boldWhenOn, compact: compact)
    }
}

/// A disabled button is drawn at half strength, label and border (DL-132 j, q68-drawing).
private struct DuoButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let on: Bool
    var bold = false
    var compact = false
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        Group {
            if compact {
                configuration.label.font(.system(size: DuoMetric.repoLineButtonFont))
                    .padding(.horizontal, DuoMetric.repoLineButtonPaddingX)
                    .frame(height: DuoMetric.repoLineButtonHeight)
            } else {
                configuration.label.duoText(.control, weight: bold ? .semibold : nil)
                    .padding(.horizontal, DuoSpace.buttonPadding.leading + DuoMetric.borderHairline)
                    .padding(.vertical, DuoSpace.buttonPadding.top + DuoMetric.borderHairline)
            }
        }
            .foregroundStyle(enabled ? DuoColor.text : DuoColor.text2.opacity(0.5))
            .lineLimit(1)
            .background(
                RoundedRectangle(cornerRadius: DuoMetric.radiusControl)
                    .fill(configuration.isPressed || on ? DuoColor.selected : DuoColor.pane)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DuoMetric.radiusControl)
                    .strokeBorder(DuoColor.controlEdge.opacity(enabled ? 1 : 0.5), lineWidth: DuoMetric.borderHairline)
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
struct Chevron: View, @preconcurrency Animatable {
    enum Direction { case right, down }
    var color: Color = DuoColor.text2
    /// 0 points right, 1 points down. A fold turns it over `motion.fold` (DL-130): the down
    /// chevron is the right one turned 90° about its centre, so the turn ends exactly on it.
    var turn: Double

    init(direction: Direction = .right, color: Color = DuoColor.text2) {
        self.turn = direction == .down ? 1 : 0
        self.color = color
    }

    var animatableData: Double {
        get { turn }
        set { turn = newValue }
    }

    var body: some View {
        let t = min(max(turn, 0), 1)
        let w = 8 + 2 * t, h = 10 - 2 * t
        Canvas { ctx, box in
            var p = Path()
            if t == 0 {
                ctx.scaleBy(x: box.width / 8, y: box.height / 10)
                p.move(to: CGPoint(x: 2, y: 1.5)); p.addLine(to: CGPoint(x: 6, y: 5)); p.addLine(to: CGPoint(x: 2, y: 8.5))
            } else if t == 1 {
                ctx.scaleBy(x: box.width / 10, y: box.height / 8)
                p.move(to: CGPoint(x: 1.5, y: 2)); p.addLine(to: CGPoint(x: 5, y: 6)); p.addLine(to: CGPoint(x: 8.5, y: 2))
            } else {
                // Mid-turn: the right chevron about the box's centre, rotated by t × 90°.
                let a = t * .pi / 2, c = CGPoint(x: box.width / 2, y: box.height / 2)
                let pts = [CGPoint(x: -2, y: -3.5), CGPoint(x: 2, y: 0), CGPoint(x: -2, y: 3.5)].map {
                    CGPoint(x: c.x + $0.x * cos(a) - $0.y * sin(a), y: c.y + $0.x * sin(a) + $0.y * cos(a))
                }
                p.move(to: pts[0]); p.addLine(to: pts[1]); p.addLine(to: pts[2])
            }
            ctx.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
        .frame(width: w, height: h)
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

// MARK: - The segmented pill (DL-253)

/// The robot beside "new session": a filled 12 × 8 pixel mark with its eyes cut out and an antenna
/// (tokens.json `icon.newSessionRobot`), the design system's one filled icon.
struct RobotMark: Shape {
    func path(in r: CGRect) -> Path {
        let sx = r.width / 12, sy = r.height / 8
        var p = Path()
        // x, y, w, h in the 12 × 8 grid (each a pixel run).
        for (x, y, w, h) in [(5, 0, 1, 1), (2, 1, 8, 1), (2, 2, 1, 1), (4, 2, 4, 1), (9, 2, 1, 1), (2, 3, 8, 2),
                             (1, 5, 10, 1), (3, 6, 2, 1), (7, 6, 2, 1), (3, 7, 2, 1), (7, 7, 2, 1)] {
            p.addRect(CGRect(x: CGFloat(x) * sx, y: CGFloat(y) * sy, width: CGFloat(w) * sx, height: CGFloat(h) * sy))
        }
        return p
    }
}

/// `>_` in a 12 × 10 box (tokens.json `icon.shellPrompt`), as a shape.
struct ShellPromptShape: Shape {
    func path(in r: CGRect) -> Path {
        let sx = r.width / 12, sy = r.height / 10
        var p = Path()
        p.move(to: .init(x: 1.5 * sx, y: 2 * sy)); p.addLine(to: .init(x: 5 * sx, y: 5 * sy)); p.addLine(to: .init(x: 1.5 * sx, y: 8 * sy))
        p.move(to: .init(x: 6.5 * sx, y: 8.5 * sy)); p.addLine(to: .init(x: 10.5 * sx, y: 8.5 * sy))
        return p
    }
}

/// `+` in a 10 × 10 box, stroke 1.5.
struct PlusShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: .init(x: r.midX, y: r.minY + r.height * 0.15)); p.addLine(to: .init(x: r.midX, y: r.maxY - r.height * 0.15))
        p.move(to: .init(x: r.minX + r.width * 0.15, y: r.midY)); p.addLine(to: .init(x: r.maxX - r.width * 0.15, y: r.midY))
        return p
    }
}

/// Two or more icon segments in one bordered box, shared by the chat mode toggle (a mode pill shows its
/// chosen segment) and the new-session pill (an action pill shows hover only). Marks are `consoleText2` /
/// `text2`; a chosen or hovered segment fills `consoleRule` / `selected` and its mark takes `consoleText` / `text`.
/// `light` is the thin strip over chat: 1 pt `controlEdge`, white inside.
struct SegmentedPill<Content: View>: View {
    var light = false
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: 0) { content() }
            .background(light ? DuoColor.pane : .clear)
            .clipShape(RoundedRectangle(cornerRadius: DuoMetric.radiusControl))
            // The border sits outside the segments (the target's 22 × 16 inside a 1 pt border).
            .padding(DuoMetric.borderHairline)
            .overlay(RoundedRectangle(cornerRadius: DuoMetric.radiusControl).strokeBorder(light ? DuoColor.controlEdge : DuoColor.tuiInputBorder, lineWidth: DuoMetric.borderHairline))
    }
}

/// The hairline between an action pill's segments (the mode pill has none).
struct PillDivider: View {
    var light = false
    var body: some View {
        (light ? DuoColor.rule : DuoColor.tuiInputBorder).frame(width: DuoMetric.borderHairline, height: light ? 10 : 12)
    }
}

/// One segment of a `SegmentedPill`. `id` names it for hover (`AppModel.hoveredPill`).
struct PillSegment<Mark: View>: View {
    @Environment(AppModel.self) private var model
    let id: String
    var light = false
    let size: CGSize
    /// The chosen segment of a mode pill.
    var on = false
    /// An action pill's segments fill under the pointer; a mode pill's show only the chosen one.
    var hovers = true
    /// The pointer is on this segment (`AppModel.hoveredPill == id`, read by the caller so its body redraws with it).
    var hovered = false
    let label: String
    var help: String? = nil
    let action: () -> Void
    @ViewBuilder let mark: () -> Mark

    var body: some View {
        let lit = on || (hovers && hovered)
        mark()
            .foregroundStyle(light ? (lit ? DuoColor.text : DuoColor.text2) : lit ? DuoColor.consoleText : DuoColor.consoleText2)
            .frame(width: size.width, height: size.height)
            .background(lit ? (light ? DuoColor.selected : DuoColor.consoleRule) : .clear)
            .contentShape(Rectangle())
            .onActivate(action)
            .onHover { inside in
                if inside { model.hoveredPill = id } else if model.hoveredPill == id { model.hoveredPill = nil }
            }
            .help(help ?? label)
            .accessibilityLabel(label)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
