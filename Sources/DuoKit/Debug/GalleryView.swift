import SwiftUI

/// Every token and component in its states, from the fixture (handoff §0.2 `look`, §5).
/// Open with `Duo --gallery on`; capture with `--capture`. Not a design target: a review sheet.
public struct GalleryView: View {
    @Environment(AppModel.self) private var model

    public init() {}

    private let swatches: [(String, Color)] = [
        ("ground", DuoColor.ground), ("pane", DuoColor.pane), ("selected", DuoColor.selected),
        ("rule", DuoColor.rule), ("controlEdge", DuoColor.controlEdge), ("text", DuoColor.text),
        ("text2", DuoColor.text2), ("needsYou", DuoColor.needsYou), ("console", DuoColor.console),
        ("consoleRule", DuoColor.consoleRule), ("consoleText", DuoColor.consoleText),
        ("consoleText2", DuoColor.consoleText2), ("needsYouOnConsole", DuoColor.needsYouOnConsole),
    ]

    public var body: some View {
        let f = model.fixture
        let copyReview = f.sessions.first { $0.name == "Copy review pass 2" }!
        let prd = f.sessions.first { $0.name == "PRD v2 edits" }!
        let triage = f.sessions.first { $0.name == "Morning triage" }!
        let readout = f.sessions.first { $0.name == "Results readout" }!
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Duo · component gallery").duoText(.title)

                SectionLabel(text: "Colour")
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(100), spacing: 12), count: 7), alignment: .leading, spacing: 12) {
                    ForEach(swatches, id: \.0) { name, color in
                        VStack(alignment: .leading, spacing: 4) {
                            RoundedRectangle(cornerRadius: 6).fill(color).frame(height: 36)
                                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(DuoColor.rule))
                            Text(name).duoText(.control).foregroundStyle(DuoColor.text2)
                        }
                    }
                }

                SectionLabel(text: "Type")
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(DuoTextStyle.allCases, id: \.self) { style in
                        let s = style.spec
                        Text("\(style) · \(Int(s.size))/\(Int(s.lineHeight))\(s.mono ? " mono" : "")")
                            .duoText(style)
                    }
                }

                SectionLabel(text: "Session state")
                HStack(spacing: 24) {
                    ForEach(SessionState.allCases, id: \.self) { state in
                        HStack(spacing: 6) { StateGlyph(state); Text(state.sectionTitle).duoText(.body) }
                    }
                }
                HStack(spacing: 24) {
                    ForEach(SessionState.allCases, id: \.self) { state in
                        HStack(spacing: 6) {
                            StateGlyph(state, on: .console(active: true))
                            StateGlyph(state, on: .console(active: false))
                            Text(state.sectionTitle).duoText(.mono).foregroundStyle(DuoColor.consoleText)
                        }
                    }
                }
                .padding(12)
                .background(DuoColor.console)

                SectionLabel(text: "Pieces")
                HStack(alignment: .center, spacing: 12) {
                    Button("Resume a session") {}.buttonStyle(.duo)
                    Button("+ New session") {}.buttonStyle(.duo)
                    CountPill(text: "group · 3", emphasised: true)
                    CountPill(text: "thread · 2", emphasised: false)
                    ChipSample(open: false)
                    ChipSample(open: true)
                }
                HStack(alignment: .top, spacing: 16) {
                    VStack(spacing: 10) {
                        NeedsYouCard(session: copyReview, selected: true)
                        NeedsYouCard(session: prd, selected: false)
                    }.frame(width: 307)
                    VStack(spacing: 10) {
                        HomePointerCard(session: triage)
                        ReviewCard(session: readout)
                        NewProjectTile()
                    }.frame(width: 307)
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(SidebarRow.rows(for: "checkout-redesign", in: f)) { SidebarRowView(row: $0) }
                    }.frame(width: 299)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(DuoColor.text)
        .background(DuoColor.pane)
    }
}

/// The needs-you chip in a given state, without its popover.
private struct ChipSample: View {
    let open: Bool

    var body: some View {
        HStack(spacing: DuoSpace.gapGlyphToLabel) {
            Circle().fill(open ? DuoColor.onNeedsYou : DuoColor.needsYou).frame(width: DuoMetric.glyph, height: DuoMetric.glyph)
            Text("2 need you").duoText(.chip)
        }
        .foregroundStyle(open ? DuoColor.onNeedsYou : DuoColor.needsYou)
        .padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: DuoMetric.radiusControl).fill(open ? DuoColor.needsYou : Color.clear))
        .overlay(RoundedRectangle(cornerRadius: DuoMetric.radiusControl).strokeBorder(DuoColor.needsYou, lineWidth: DuoMetric.borderEmphasis))
    }
}
