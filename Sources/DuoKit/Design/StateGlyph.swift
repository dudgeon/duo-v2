import SwiftUI

/// The state glyph (handoff §4.4): 9 pt, drawn in a 10×10 box. Shape carries the meaning.
public struct StateGlyph: View {
    public enum Surface: Sendable {
        /// Light chrome: state colours from §4.4.
        case light
        /// On the console. `active` tabs draw needs-you in `needsYouOnConsole` and the rest in
        /// `consoleText`; inactive tabs draw everything except needs-you in `consoleText2`.
        case console(active: Bool)
    }

    let state: SessionState
    let surface: Surface
    let size: CGFloat

    public init(_ state: SessionState, on surface: Surface = .light, size: CGFloat = DuoMetric.glyph) {
        self.state = state
        self.surface = surface
        self.size = size
    }

    var color: Color {
        switch surface {
        case .light:
            switch state {
            case .needsYou: DuoColor.needsYou
            case .readyForReview, .working: DuoColor.text
            case .idle, .resolved: DuoColor.text2
            }
        case .console(let active):
            if state == .needsYou { DuoColor.needsYouOnConsole }
            else { active ? DuoColor.consoleText : DuoColor.consoleText2 }
        }
    }

    public var body: some View {
        Canvas { ctx, box in
            ctx.scaleBy(x: box.width / 10, y: box.height / 10)
            let shading = GraphicsContext.Shading.color(color)
            switch state {
            case .needsYou:
                ctx.fill(Path(ellipseIn: CGRect(x: 0, y: 0, width: 10, height: 10)), with: shading)
            case .readyForReview:
                var p = Path()
                p.move(to: CGPoint(x: 5, y: 0))
                p.addLine(to: CGPoint(x: 10, y: 5))
                p.addLine(to: CGPoint(x: 5, y: 10))
                p.addLine(to: CGPoint(x: 0, y: 5))
                p.closeSubpath()
                ctx.fill(p, with: shading)
            case .working:
                ctx.stroke(Path(ellipseIn: CGRect(x: 0.8, y: 0.8, width: 8.4, height: 8.4)), with: shading, lineWidth: 1.5)
            case .idle:
                var p = Path()
                p.move(to: CGPoint(x: 1, y: 5))
                p.addLine(to: CGPoint(x: 9, y: 5))
                ctx.stroke(p, with: shading, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
            case .resolved:
                var p = Path()
                p.move(to: CGPoint(x: 1.5, y: 5.4))
                p.addLine(to: CGPoint(x: 4, y: 7.8))
                p.addLine(to: CGPoint(x: 8.5, y: 2.4))
                ctx.stroke(p, with: shading, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
