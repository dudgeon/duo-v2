import SwiftUI

// All projects' List (DL-142). Targets: home-evolution-handoff/screens/list-1440.html, list-1280.html,
// rows.html (the row, compact and two-line), needs-you.html (N1).

/// The middle when List is chosen: the header, then every session by recency. No idle footer: the
/// idle sessions are the list's own Today, This week and Earlier.
struct SessionListPane: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let list = model.sessionList
        let filtering = !model.listFilter.trimmingCharacters(in: .whitespaces).isEmpty
        GeometryReader { box in
            let twoLine = box.size.width < DuoMetric.sessionListTwoLineBelow
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    MapHeader(layout: nil)
                        .padding(EdgeInsets(top: DuoSpace.panePadding, leading: DuoSpace.panePadding, bottom: 8, trailing: DuoSpace.panePadding))
                    if filtering {
                        let rows = list.filtered(model.listFilter)
                        SessionListSectionLabel(text: "Matches", count: rows.count)
                        ForEach(rows) { r in SessionListRow(row: r, twoLine: twoLine) }
                    } else {
                        if model.rightCollapsedAllProjects {
                            // N1 with the column hidden: the line opens into the rows themselves.
                            if !list.needsYou.isEmpty {
                                SessionListSectionLabel(text: "Needs you", count: list.needsYou.count, needsYou: true)
                                ForEach(list.needsYou) { r in SessionListRow(row: r, twoLine: twoLine) }
                            }
                        } else if !list.needsYou.isEmpty {
                            NeedsYouLine(count: list.needsYou.count, first: list.needsYou[0].id)
                                .padding(.top, 8)
                        }
                        ForEach(list.sections) { s in
                            SessionListSectionLabel(text: s.title, count: s.id == "open" ? s.rows.count : nil)
                            ForEach(s.rows) { r in SessionListRow(row: r, twoLine: twoLine) }
                        }
                        SessionListFold(key: SessionListKeys.earlier, title: "Earlier", rows: list.earlier, twoLine: twoLine)
                        if model.listShowsArchived {
                            SessionListFold(key: SessionListKeys.archived, title: "Archived", rows: list.archived, twoLine: twoLine)
                        }
                    }
                }
                .padding(.bottom, DuoSpace.panePadding)
                .frame(width: box.size.width, alignment: .leading)
            }
            .scrollIndicators(.automatic)
            .focusable()
            .focusEffectDisabled()
            .onMoveCommand { direction in
                switch direction {
                case .up: model.moveListSelection(-1)
                case .down: model.moveListSelection(1)
                default: break
                }
            }
            .onKeyPress(.return) {
                guard let id = model.listSelection else { return .ignored }
                model.openListRow(id)
                return .handled
            }
        }
        .foregroundStyle(DuoColor.text)
        .background(DuoColor.pane)
    }
}

/// `OPEN · 5`, `TODAY`: a section's label, 10 above and 4 below, 16 in.
struct SessionListSectionLabel: View {
    let text: String
    var count: Int?
    var needsYou = false

    var body: some View {
        SectionLabel(text: text, count: count, needsYou: needsYou)
            .padding(EdgeInsets(top: 10, leading: DuoSpace.panePadding, bottom: 4, trailing: DuoSpace.panePadding))
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// N1 (`needs-you`): one 28-high line, a 1 pt `needsYou` border, radius 6: the filled glyph, `3 need
/// you` semibold in `needsYou`, `in the column` in `text2`, a chevron. It selects the column's first card.
struct NeedsYouLine: View {
    @Environment(AppModel.self) private var model
    let count: Int
    let first: String

    var body: some View {
        HStack(spacing: DuoSpace.gapRowItems) {
            StateGlyph(.needsYou)
            Text("\(count) need\(count == 1 ? "s" : "") you").duoText(.bodyEmphasis).foregroundStyle(DuoColor.needsYou)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("in the column").duoText(.body).foregroundStyle(DuoColor.text2)
            Chevron(direction: .right, color: DuoColor.needsYou).frame(width: 8, height: 10)
        }
        .padding(.horizontal, DuoMetric.sessionListRowInset)
        .frame(height: DuoMetric.sessionListNeedsLineHeight)
        .overlay(RoundedRectangle(cornerRadius: DuoMetric.radiusSelection).strokeBorder(DuoColor.needsYou, lineWidth: DuoMetric.borderHairline))
        .padding(.horizontal, DuoMetric.sessionListRowInset)
        .contentShape(Rectangle())
        .onActivate { model.selectedActionSession = first }  // action: view select
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(count) need you, in the column")
    }
}

/// One session (`rows`): compact, 26 high (glyph, title, project 150, task 150, wait 64), or under 520
/// two lines, 44 high (the wait beside the title, `project › task` under it in 12/16 `text2`; Q-101).
/// Bold while it needs you. No `activeTint` here (DL-142 (2)); the selected row has the selected fill.
struct SessionListRow: View {
    @Environment(AppModel.self) private var model
    let row: SessionList.Row
    let twoLine: Bool

    var body: some View {
        let selected = model.listSelection == row.id
        let bold = row.session.state == .needsYou
        Group {
            if twoLine {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: DuoSpace.gapRowItems) {
                        StateGlyph(row.session.state)
                        Text(row.session.name).duoText(.body, weight: bold ? .semibold : nil).lineLimit(1).truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        WaitLabel(text: row.wait)
                    }
                    HStack(spacing: 5) {
                        Text(row.project).lineLimit(1).truncationMode(.tail)
                        if let task = row.task {
                            Text("›")
                            TaskBox()
                            Text(task).lineLimit(1).truncationMode(.tail)
                        }
                    }
                    .duoText(.control)
                    .foregroundStyle(DuoColor.text2)
                    .padding(.leading, DuoMetric.glyph + DuoSpace.gapRowItems)
                }
                .frame(height: DuoMetric.sessionListTwoLineHeight)
            } else {
                HStack(spacing: DuoSpace.gapRowItems) {
                    StateGlyph(row.session.state)
                    Text(row.session.name).duoText(.body, weight: bold ? .semibold : nil).lineLimit(1).truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(row.project).duoText(.body).foregroundStyle(DuoColor.text2).lineLimit(1).truncationMode(.tail)
                        .frame(width: DuoMetric.sessionListProjectWidth, alignment: .leading)
                    HStack(spacing: 5) {
                        if let task = row.task {
                            TaskBox()
                            Text(task).duoText(.body).foregroundStyle(DuoColor.text2).lineLimit(1).truncationMode(.tail)
                        }
                    }
                    .frame(width: DuoMetric.sessionListTaskWidth, alignment: .leading)
                    Text(row.wait ?? "").duoText(.body).foregroundStyle(DuoColor.text2).lineLimit(1).fixedSize()
                        .frame(width: DuoMetric.sessionListWaitWidth, alignment: .trailing)
                }
                .frame(height: DuoMetric.rowSession)
            }
        }
        .padding(.horizontal, DuoMetric.sessionListRowInset)
        .background { if selected { RoundedRectangle(cornerRadius: DuoMetric.radiusSelection).fill(DuoColor.selected) } }
        .padding(.horizontal, DuoMetric.sessionListRowInset)
        .contentShape(Rectangle())
        .onActivate { model.openListRow(row.id) }  // action: open
        .modifier(SessionOrganizeMenu(sessionKey: row.session.tabKey))
        .help([row.session.name, model.fixture.projects.first { $0.name == row.session.project }?.path, row.task].compactMap { $0 }.joined(separator: " · "))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(row.session.name), \(row.project)\(row.task.map { ", task \($0)" } ?? ""), \(row.session.state.spokenName)\(row.wait.map { ", \($0)" } ?? "")")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

/// `› Earlier · 9`, `› Archived · 4`: 26 high, 16 in; open, its rows.
struct SessionListFold: View {
    @Environment(AppModel.self) private var model
    let key: String
    let title: String
    let rows: [SessionList.Row]
    let twoLine: Bool

    var body: some View {
        if !rows.isEmpty {
            let expanded = model.expandedGroups.contains(key)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: DuoSpace.gapRowItems) {
                    Chevron(direction: expanded ? .down : .right).frame(width: 8, height: 10)
                    Text("\(title) · \(rows.count)").duoText(.body).foregroundStyle(DuoColor.text2)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, DuoSpace.panePadding)
                .frame(height: DuoMetric.rowSession)
                .contentShape(Rectangle())
                .onActivate { withDuoAnimation(.fold) { if expanded { model.expandedGroups.remove(key) } else { model.expandedGroups.insert(key) } } }  // not an action: a fold in the list; its rows are `duo2 sessions`
                .accessibilityLabel(expanded ? "Hide \(title.lowercased()) sessions" : "Show \(rows.count) \(title.lowercased()) sessions")
                if expanded {
                    ForEach(rows) { r in SessionListRow(row: r, twoLine: twoLine) }.transition(.foldRows)
                }
            }
        }
    }
}

/// Board | List (`list-1440`): a segmented control, 22 high, `controlEdge` border, radius 6; the
/// chosen half on `selected` and semibold. Board has a two-column mark, List three lines.
struct HomeViewToggle: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 0) {
            segment(.board)
            DuoColor.rule.frame(width: DuoMetric.borderHairline)
            segment(.list)
        }
        .frame(height: DuoMetric.mapHeaderControlHeight)
        .background(DuoColor.pane)
        .clipShape(RoundedRectangle(cornerRadius: DuoMetric.radiusControl))
        .overlay(RoundedRectangle(cornerRadius: DuoMetric.radiusControl).strokeBorder(DuoColor.controlEdge, lineWidth: DuoMetric.borderHairline))
        .fixedSize()
    }

    private func segment(_ v: HomeView) -> some View {
        let on = model.homeView == v
        return HStack(spacing: DuoMetric.sessionListToggleIconGap) {
            HomeViewMark(view: v).frame(width: 12, height: 10)
            Text(v.title).duoText(.control, weight: on ? .semibold : nil)
        }
        .foregroundStyle(on ? DuoColor.text : DuoColor.text2)
        .padding(.horizontal, DuoMetric.sessionListToggleSegmentPadding)
        .frame(maxHeight: .infinity)
        .background(on ? DuoColor.selected : Color.clear)
        .contentShape(Rectangle())
        .onActivate { model.setHomeView(v) }  // action: view home
        .accessibilityLabel("Show \(v.title)")
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// The toggle's marks, as the board draws them (12×10, 1.2 strokes).
struct HomeViewMark: View {
    let view: HomeView

    var body: some View {
        Canvas { ctx, box in
            ctx.scaleBy(x: box.width / 12, y: box.height / 10)
            var p = Path()
            if view == .board {
                p.addRoundedRect(in: CGRect(x: 1, y: 1, width: 4, height: 8), cornerSize: CGSize(width: 1, height: 1))
                p.addRoundedRect(in: CGRect(x: 7, y: 1, width: 4, height: 5), cornerSize: CGSize(width: 1, height: 1))
            } else {
                for y in [2.0, 5.0, 8.0] { p.move(to: CGPoint(x: 1, y: y)); p.addLine(to: CGPoint(x: 11, y: y)) }
            }
            ctx.stroke(p, with: .foreground, style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
        }
        .accessibilityHidden(true)
    }
}
