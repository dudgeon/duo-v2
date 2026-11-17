import SwiftUI

// The Explainers' pictures for Chat and Terminal, Director and Home (first-run-welcome-handoff X2, B3; DL-348 (5),
// closing Q-523): each is made of Duo's own parts, on `ground`, decorative, 268 wide, with numbered marks tied
// to the card's points. The Tasks picture is in Explainer.swift.

/// The text sizes inside the pictures (board X2's, measured): a drawing's own scale, not UI text.
private enum PictureType {
    static let tiny: CGFloat = 8.5
    static let mark: CGFloat = 7
    static let mono: CGFloat = 9.5
}

/// The picture's ground: `ground`, radius 6, padding 10 (the boards' `.ill`).
private struct PictureGround<Content: View>: View {
    var height: CGFloat = 96
    @ViewBuilder let content: () -> Content
    var body: some View {
        content()
            .padding(10)
            .frame(width: DuoMetric.explainerWidth - 2 * DuoSpace.popoverPadding.leading, height: height)
            .background(RoundedRectangle(cornerRadius: 6).fill(DuoColor.ground))
    }
}

/// 8.5 pt text in the pictures' small bubbles and boxes.
private extension Text {
    func tiny() -> Text { self.font(.system(size: PictureType.tiny)) }
}

private struct SmallMark: View {
    let number: Int
    var onConsole = false
    var body: some View {
        Text("\(number)").font(.system(size: PictureType.mark, weight: .semibold)).foregroundStyle(onConsole ? DuoColor.console : DuoColor.pane)
            .frame(width: 11, height: 11).background(Circle().fill(onConsole ? DuoColor.consoleText : DuoColor.text))
    }
}

private struct YouBubble: View {
    let text: String
    var body: some View {
        Text(text).tiny().foregroundStyle(DuoColor.text).lineLimit(1)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(UnevenRoundedRectangle(topLeadingRadius: 7, bottomLeadingRadius: 7, bottomTrailingRadius: 2, topTrailingRadius: 7).fill(DuoColor.chatYou))
    }
}

private struct ClaudeBubble: View {
    let text: String
    var underlined: String?
    var fill: Color = DuoColor.pane
    var body: some View {
        Group {
            if let underlined, let r = text.range(of: underlined) {
                Text(String(text[..<r.lowerBound])).tiny() + Text(underlined).tiny().underline() + Text(String(text[r.upperBound...])).tiny()
            } else { Text(text).tiny() }
        }
        .foregroundStyle(DuoColor.text)
        .padding(.horizontal, 6).padding(.vertical, 3)
        .background(UnevenRoundedRectangle(topLeadingRadius: 7, bottomLeadingRadius: 2, bottomTrailingRadius: 7, topTrailingRadius: 7).fill(fill))
    }
}

/// Chat and Terminal: Claude Code's own screen beside the same turn as chat bubbles (marks 2 and 1).
struct ModesExplainerPicture: View {
    var body: some View {
        PictureGround {
            HStack(spacing: 8) {
                Text("> Outline the Q4…\n⏺ Saved an outline\n  to plan-outline.md")
                    .font(.system(size: PictureType.tiny, design: .monospaced)).lineSpacing(1.5).foregroundStyle(DuoColor.consoleText2)
                    .padding(.horizontal, 8).padding(.vertical, 7)
                    .frame(maxWidth: .infinity, maxHeight: 72, alignment: .topLeading)
                    .background(RoundedRectangle(cornerRadius: 5).fill(DuoColor.console))
                    .overlay(alignment: .topTrailing) { ExplainerMark(number: 2).scaleEffect(0.875).padding(4) }
                Text("⇄").font(.system(size: DuoTextStyle.control.spec.size)).foregroundStyle(DuoColor.text2)
                VStack(alignment: .leading, spacing: 4) {
                    YouBubble(text: "Outline the Q4…").frame(maxWidth: .infinity, alignment: .trailing)
                    ClaudeBubble(text: "Saved to plan-outline.md.", underlined: "plan-outline.md", fill: DuoColor.ground)
                }
                .padding(6)
                .frame(maxWidth: .infinity, maxHeight: 72, alignment: .topLeading)
                .background(RoundedRectangle(cornerRadius: 5).fill(DuoColor.pane))
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(DuoColor.rule, lineWidth: DuoMetric.borderHairline))
                .overlay(alignment: .bottomLeading) { ExplainerMark(number: 1).scaleEffect(0.875).padding(4) }
            }
        }
    }
}

/// Director: "be the director", the director's row (1), and the workers it starts (2) and checks (3).
struct DirectorExplainerPicture: View {
    var body: some View {
        PictureGround {
            HStack(spacing: 10) {
                VStack(alignment: .trailing, spacing: 4) {
                    YouBubble(text: "be the director")
                    HStack(spacing: 4) {
                        SmallMark(number: 1, onConsole: true)
                        Text("director").tiny().foregroundStyle(DuoColor.consoleText)
                    }
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 4).fill(DuoColor.console))
                }
                .frame(width: 92)
                Path { p in
                    p.move(to: CGPoint(x: 1, y: 20)); p.addLine(to: CGPoint(x: 7, y: 20))
                    p.move(to: CGPoint(x: 7, y: 20)); p.addLine(to: CGPoint(x: 15, y: 5))
                    p.move(to: CGPoint(x: 7, y: 20)); p.addLine(to: CGPoint(x: 15, y: 20))
                    p.move(to: CGPoint(x: 7, y: 20)); p.addLine(to: CGPoint(x: 15, y: 35))
                }
                .stroke(DuoColor.text2, style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
                .frame(width: 16, height: 40)
                VStack(spacing: 4) {
                    worker("☐ Budget table · worker", mark: 2)
                    worker("☐ Hiring section · worker", mark: nil)
                    worker("✓ Outline · checked", mark: 3)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func worker(_ text: String, mark: Int?) -> some View {
        HStack(spacing: 4) {
            if let mark { SmallMark(number: mark) }
            Text(text).tiny().foregroundStyle(DuoColor.text).lineLimit(1)
        }
        .padding(.horizontal, 5).padding(.vertical, 1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 4).fill(DuoColor.pane))
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(DuoColor.rule, lineWidth: DuoMetric.borderHairline))
    }
}

/// Home: the folder with _HOME.md and its projects, and a question across them.
struct HomeExplainerPicture: View {
    var body: some View {
        PictureGround {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("~/work")
                    Text("├ _HOME.md")
                    HStack(spacing: 0) {
                        Text("├ q4-plan/  ")
                        Text("_PROJECT.md").background(RoundedRectangle(cornerRadius: 3).fill(DuoColor.selected))
                    }
                    Text("└ hiring/   _PROJECT.md")
                }
                .font(.system(size: PictureType.mono, design: .monospaced)).foregroundStyle(DuoColor.text).lineLimit(1).fixedSize()
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 5).fill(DuoColor.pane))
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(DuoColor.rule, lineWidth: DuoMetric.borderHairline))
                VStack(alignment: .trailing, spacing: 4) {
                    YouBubble(text: "What's open across projects?")
                    ClaudeBubble(text: "Two in q4-plan, one in hiring.").frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}
