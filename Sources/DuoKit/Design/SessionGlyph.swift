import SwiftUI

/// The session row glyph (DL-174, session-glyphs-handoff 01): the session's kind, with attention
/// replacing it. 9 pt, drawn in a 10×10 box from `glyphs/*.svg`. Shape carries every state; nothing
/// animates. Console tabs, cards, the peek and the Dock menu keep `StateGlyph`.
///
/// | state | terminal | chat |
/// |---|---|---|
/// | idle | `>_` outline, `text2` | bubble outline, `text2` |
/// | working | caret and a block cursor, `text` | bubble and three dots, `text` |
/// | ready for review | solid square, `>_` knocked out | solid bubble |
/// | needs you | the raised hand, `needsYou` (replaces the kind) | same |
/// | resolved | today's tick (replaces the kind) | same |
public struct SessionGlyph: View {
    let kind: ChatViewMode
    let state: SessionState
    let size: CGFloat

    public init(kind: ChatViewMode, state: SessionState, size: CGFloat = DuoMetric.glyph) {
        self.kind = kind
        self.state = state
        self.size = size
    }

    /// A task or group row's glyph slot (DL-174): the hand while one of its sessions needs you,
    /// empty otherwise. A task has no kind, and its sessions show their own state.
    public static func taskMark(_ state: SessionState) -> Bool { state == .needsYou }

    /// The words an accessibility label puts after the name: "chat session", "terminal session".
    public static func spokenKind(_ kind: ChatViewMode) -> String { kind == .chat ? "chat session" : "terminal session" }

    var color: Color {
        switch state {
        case .needsYou: DuoColor.needsYou
        case .readyForReview, .working: DuoColor.text
        case .idle, .resolved: DuoColor.text2
        }
    }

    public var body: some View {
        if state == .resolved {
            StateGlyph(.resolved, size: size)
        } else {
            Canvas { ctx, box in
                ctx.scaleBy(x: box.width / 10, y: box.height / 10)
                let shading = GraphicsContext.Shading.color(color)
                let round = { (w: CGFloat) in StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round) }
                switch (state, kind) {
                case (.needsYou, _):
                    Self.drawHand(&ctx, shading)
                case (.idle, .terminal):
                    ctx.stroke(Self.caret, with: shading, style: round(1.5))
                    ctx.stroke(Self.underscore, with: shading, style: round(1.5))
                case (.working, .terminal):
                    ctx.stroke(Self.caret, with: shading, style: round(1.5))
                    ctx.fill(Path(roundedRect: CGRect(x: 5.6, y: 5, width: 3.2, height: 3.6), cornerRadius: 0.5), with: shading)
                case (.readyForReview, .terminal):
                    // `>_` is a cut-out, so the row's own fill (pane, selected, activeTint) shows through.
                    ctx.drawLayer { layer in
                        layer.fill(Path(roundedRect: CGRect(x: 0.5, y: 0.5, width: 9, height: 9), cornerRadius: 2.2), with: shading)
                        layer.blendMode = .clear
                        var knock = Path()
                        knock.move(to: CGPoint(x: 2.7, y: 3)); knock.addLine(to: CGPoint(x: 4.9, y: 5)); knock.addLine(to: CGPoint(x: 2.7, y: 7))
                        knock.move(to: CGPoint(x: 5.7, y: 7.1)); knock.addLine(to: CGPoint(x: 7.5, y: 7.1))
                        layer.stroke(knock, with: .color(.black), style: round(1.3))
                    }
                case (.idle, .chat):
                    ctx.stroke(Self.bubble, with: shading, style: round(1.2))
                case (.working, .chat):
                    ctx.stroke(Self.bubble, with: shading, style: round(1.2))
                    for x in [3.1, 5.0, 6.9] as [CGFloat] {
                        ctx.fill(Path(ellipseIn: CGRect(x: x - 0.75, y: 4.4 - 0.75, width: 1.5, height: 1.5)), with: shading)
                    }
                case (.readyForReview, .chat):
                    ctx.fill(Self.bubble, with: shading)
                    ctx.stroke(Self.bubble, with: shading, style: round(1.2))
                default:
                    break
                }
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
        }
    }

    static var caret: Path {
        var p = Path()
        p.move(to: CGPoint(x: 1.6, y: 2.2)); p.addLine(to: CGPoint(x: 4.6, y: 5)); p.addLine(to: CGPoint(x: 1.6, y: 7.8))
        return p
    }

    static var underscore: Path {
        var p = Path()
        p.move(to: CGPoint(x: 5.9, y: 8.1)); p.addLine(to: CGPoint(x: 8.7, y: 8.1))
        return p
    }

    /// chatIdle.svg: r 1.5, the tail at the bottom left.
    static var bubble: Path {
        var p = Path()
        p.move(to: CGPoint(x: 2.1, y: 1.2))
        p.addLine(to: CGPoint(x: 7.9, y: 1.2))
        p.addArc(tangent1End: CGPoint(x: 9.4, y: 1.2), tangent2End: CGPoint(x: 9.4, y: 2.7), radius: 1.5)
        p.addLine(to: CGPoint(x: 9.4, y: 6.1))
        p.addArc(tangent1End: CGPoint(x: 9.4, y: 7.6), tangent2End: CGPoint(x: 7.9, y: 7.6), radius: 1.5)
        p.addLine(to: CGPoint(x: 4.7, y: 7.6))
        p.addLine(to: CGPoint(x: 2.3, y: 9.3))
        p.addLine(to: CGPoint(x: 2.3, y: 7.6))
        p.addLine(to: CGPoint(x: 2.1, y: 7.6))
        p.addArc(tangent1End: CGPoint(x: 0.6, y: 7.6), tangent2End: CGPoint(x: 0.6, y: 6.1), radius: 1.5)
        p.addLine(to: CGPoint(x: 0.6, y: 2.7))
        p.addArc(tangent1End: CGPoint(x: 0.6, y: 1.2), tangent2End: CGPoint(x: 2.1, y: 1.2), radius: 1.5)
        p.closeSubpath()
        return p
    }

    /// needsYouHand.svg: four fingers, a palm and a thumb.
    static func drawHand(_ ctx: inout GraphicsContext, _ shading: GraphicsContext.Shading) {
        func bar(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> Path {
            Path(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerRadius: r)
        }
        ctx.fill(bar(2.1, 1.7, 1.45, 5, 0.72), with: shading)
        ctx.fill(bar(3.8, 0.5, 1.45, 5.6, 0.72), with: shading)
        ctx.fill(bar(5.5, 0.9, 1.45, 5.3, 0.72), with: shading)
        ctx.fill(bar(7.2, 2, 1.45, 4.6, 0.72), with: shading)
        ctx.fill(bar(2.1, 4.6, 6.55, 5, 2.3), with: shading)
        let spin = CGAffineTransform(translationX: 1.4, y: 7.9).rotated(by: -.pi / 6).translatedBy(x: -1.4, y: -7.9)
        ctx.fill(bar(0.7, 4.3, 1.45, 3.6, 0.72).applying(spin), with: shading)
    }
}
