import SwiftUI

/// tokens.json `icon.keepRunningPin` (park-handoff, keep-running-pin A): a 9 pt pin after a Keep
/// Running tab's name, stroke 1.3, round caps and joins. The state glyph stays where it is.
struct KeepRunningPin: View {
    let color: Color

    var body: some View {
        Canvas { ctx, box in
            ctx.scaleBy(x: box.width / 10, y: box.height / 10)   // viewBox 10
            var p = Path()
            p.move(to: .init(x: 3.5, y: 1.2)); p.addLine(to: .init(x: 6.5, y: 1.2))
            p.move(to: .init(x: 4.2, y: 1.2)); p.addLine(to: .init(x: 4.2, y: 4.3)); p.addLine(to: .init(x: 2.6, y: 6))
            p.addLine(to: .init(x: 7.4, y: 6)); p.addLine(to: .init(x: 5.8, y: 4.3)); p.addLine(to: .init(x: 5.8, y: 1.2))
            p.move(to: .init(x: 5, y: 6)); p.addLine(to: .init(x: 5, y: 9))
            ctx.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: DuoMetric.keepRunningPinStroke, lineCap: .round, lineJoin: .round))
        }
        .frame(width: DuoMetric.keepRunningPinSize, height: DuoMetric.keepRunningPinSize)
        .help("Keeps running: never parked")
        .accessibilityHidden(true)   // the tab's label says it
    }
}

/// The tab's name, state and the pin, for VoiceOver: “‹name›, ‹state›, keeps running”.
struct KeepRunningLabel: ViewModifier {
    let pinned: Bool
    let name: String
    let state: SessionState

    @ViewBuilder func body(content: Content) -> some View {
        if pinned { content.accessibilityLabel("\(name), \(state.spokenName), keeps running") } else { content }
    }
}
