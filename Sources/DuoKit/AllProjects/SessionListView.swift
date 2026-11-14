import SwiftUI

// All projects' List (DL-142). Targets: home-evolution-handoff/screens/list-1440.html, list-1280.html,
// rows.html (the row, compact and two-line), needs-you.html (N1).

/// The middle when List is chosen: the header, then every session by recency. No idle footer: the
/// idle sessions are the list's own Today, This week and Earlier.
struct SessionListPane: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let list = model.sessionList
        let scrolled = model.listScrolled
        let filtering = !model.listFilter.trimmingCharacters(in: .whitespaces).isEmpty
        let _ = model.noteSelectionOrder("list", Self.order(list, model: model, filtering: filtering))   // what ⇧ ranges over (DL-247)
        GeometryReader { box in
            let twoLine = box.size.width < DuoMetric.sessionListTwoLineBelow
            VStack(alignment: .leading, spacing: 0) {
            // The header and the New session row stay put while the list scrolls (DL-262); a rule shows under them once it has.
            VStack(alignment: .leading, spacing: 0) {
                MapHeader(layout: nil)
                    .padding(EdgeInsets(top: DuoSpace.panePadding, leading: DuoSpace.panePadding, bottom: 8, trailing: DuoSpace.panePadding))
                NewSessionRow()
                    .padding(.horizontal, DuoMetric.sessionListRowInset)
                    .padding(.top, 8)
            }
            .padding(.bottom, scrolled ? 7 : 8)
            .overlay(alignment: .bottom) { if scrolled { Rectangle().fill(DuoColor.rule).frame(height: DuoMetric.borderHairline) } }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if filtering {
                        // The filter (DL-142 (4), `filter`): best first, each with the passage that matched.
                        let matches = model.listMatches
                        if matches.isEmpty {
                            if !model.listSearching { NothingMatches(text: model.listFilter.trimmingCharacters(in: .whitespaces)) }
                        } else {
                            SessionListSectionLabel(text: "Matches", count: matches.count)
                            ForEach(matches) { m in
                                SessionListRow(row: m.row, twoLine: twoLine)
                                if let p = m.passage { MatchPassage(who: m.who, text: p, words: SessionList.words(model.listFilter)) }
                            }
                        }
                    } else {
                        // Home has no projects yet (DL-212): its folders, to make projects of, before the sessions.
                        if let folders = model.firstRunFolders {
                            HomeFoldersSection(folders: folders)
                                .padding(.horizontal, DuoSpace.panePadding)
                                .padding(.bottom, 8)
                        }
                        if list.needsYou.isEmpty, list.sections.isEmpty, list.earlier.isEmpty, model.firstRunFolders == nil {
                            EmptySessionList()   // DL-262: the words (not drawn: a stand-in, C-127)
                        }
                        if model.listGroup == .project {
                            // DL-341: a header per project, its sessions under it; needs-you sessions sit in their project (L1).
                            ForEach(list.projects) { g in SessionListProjectGroup(group: g, twoLine: twoLine, narrow: twoLine) }
                            SessionListQuieter(groups: list.quietProjects, twoLine: twoLine, narrow: twoLine)
                            if model.listShowsArchived {
                                SessionListFold(key: SessionListKeys.archived, title: "Archived", rows: list.archived, twoLine: twoLine)
                            }
                        } else {
                        if model.rightCollapsedAllProjects {
                            // N1 with the column hidden: the line opens into the rows themselves.
                            if !list.needsYou.isEmpty {
                                SessionListSectionLabel(text: "Needs you", count: list.needsYou.count, needsYou: true)
                                    .accessibilityIdentifier("video.needs-you-header")
                                ForEach(list.needsYou) { r in SessionListRow(row: r, twoLine: twoLine) }
                            }
                        } else if !list.needsYou.isEmpty {
                            NeedsYouLine(count: list.needsYou.count, first: list.needsYou[0].id)
                                .padding(.top, 8)
                                .accessibilityIdentifier("video.needs-you-line")
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
                }
                .padding(.bottom, DuoSpace.panePadding)
                .frame(width: box.size.width, alignment: .leading)
            }
            .onScrollGeometryChange(for: Bool.self, of: { $0.contentOffset.y > 0.5 }) { model.listScrolled = $1 }
            .background { Color.clear.contentShape(Rectangle()).onTapGesture { model.clearSessionSelection() } }   // DL-247
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
                guard model.listSelection != nil else { return .ignored }
                model.activateListSelection()
                return .handled
            }
            // ⌘F in the list focuses its filter (`filter`, A).
            .onKeyPress(keys: ["f"]) { press in
                guard press.modifiers == .command else { return .ignored }
                model.focusListFilter()
                return .handled
            }
            }
        }
        .foregroundStyle(DuoColor.text)
        .background(WindowTint.pane)
        .accessibilityIdentifier("video.s3.list")   // anchors: the video camera's target
    }
}

/// An empty List (DL-262): where to start one. Not drawn; centred under the New session row as a stand-in (C-127).
struct EmptySessionList: View {
    var body: some View {
        VStack(spacing: 4) {
            Text("No sessions yet").duoText(.body).foregroundStyle(DuoColor.text)
            Text("Start one above, or ⌘T. Sessions show here, newest first.").duoText(.control).foregroundStyle(DuoColor.text2)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.top, 48)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("list-empty")
    }
}

/// The passage under a match (`filter`): 12/18 `text2`, 41 in, who and when first in `controlEdge`,
/// the filter's words semibold; one line, truncated.
struct MatchPassage: View {
    let who: String?
    let text: String
    let words: [String]

    var body: some View {
        Text(Self.styled(who: who, text: text, words: words))
            .duoText(.control, lineHeight: 18)
            .foregroundStyle(DuoColor.text2)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(EdgeInsets(top: -4, leading: 41, bottom: 4, trailing: DuoSpace.panePadding))
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel("\(who.map { "\($0): " } ?? "")\(text)")
    }

    /// The passage, starting near its first matched word so it shows, with each word that contains
    /// one of the filter's words semibold.
    static func styled(who: String?, text: String, words: [String]) -> AttributedString {
        var out = AttributedString()
        if let who {
            var w = AttributedString("\(who) · ")
            w.foregroundColor = DuoColor.controlEdge
            out += w
        }
        let fold: (Substring) -> String = { $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) }
        var tokens = text.split(separator: " ", omittingEmptySubsequences: false)
        // A long passage starts a few words before its first match, as search's snippets do.
        if let first = tokens.firstIndex(where: { t in words.contains { fold(t).contains($0) } }), first > 10 {
            tokens = ["…"] + tokens[(first - 4)...]
        }
        for (i, t) in tokens.enumerated() {
            var a = AttributedString((i == 0 ? "" : " ") + t)
            if words.contains(where: { fold(t).contains($0) }) {
                a = AttributedString(i == 0 ? "" : " ")
                var b = AttributedString(t)
                b.font = .system(size: DuoTextStyle.control.spec.size, weight: .semibold)
                a += b
            }
            out += a
        }
        return out
    }
}

/// Nothing found (`filter`): one sentence and a link that searches files and notes with the same words.
struct NothingMatches: View {
    @Environment(AppModel.self) private var model
    let text: String

    var body: some View {
        VStack(spacing: 0) {
            Text("Nothing in your sessions is about “\(text)”.").foregroundStyle(DuoColor.text2)
            Text("Search files and notes too ⇧⌘A")
                .foregroundStyle(DuoColor.text)
                .underline(color: DuoColor.controlEdge)
                .contentShape(Rectangle())
                .onActivate { model.searchFromListFilter() }  // action: search
        }
        .duoText(.body)
        .multilineTextAlignment(.center)
        .padding(EdgeInsets(top: 28, leading: DuoSpace.panePadding, bottom: 28, trailing: DuoSpace.panePadding))
        .frame(maxWidth: .infinity)
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
    /// False under a project's header (DL-341): the project is the header's, so the column shows only the task.
    var showProject = true

    var body: some View {
        let selected = model.listSelection == row.id
        let bold = row.session.state == .needsYou
        Group {
            if twoLine {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: DuoSpace.gapRowItems) {
                        SessionGlyph(kind: model.sessionKind(row.session), state: row.session.state)
                        Text(row.session.name).duoText(.body, weight: bold ? .semibold : nil).lineLimit(1).truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        WaitLabel(text: row.wait)
                    }
                    HStack(spacing: 5) {
                        if showProject { Text(row.project).lineLimit(1).truncationMode(.tail) }
                        if let task = row.task {
                            if showProject { Text("›") }
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
                    SessionGlyph(kind: model.sessionKind(row.session), state: row.session.state)
                    Text(row.session.name).duoText(.body, weight: bold ? .semibold : nil).lineLimit(1).truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(showProject ? row.project : "").duoText(.body).foregroundStyle(DuoColor.text2).lineLimit(1).truncationMode(.tail)
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
        .background {
            let run = model.selectionRun(row.session.tabKey, list: "list")
            if run != .none { SelectionRunFill(run: run) }   // several selected (DL-247)
            else if selected { RoundedRectangle(cornerRadius: DuoMetric.radiusSelection).fill(DuoColor.selected) }
        }
        .padding(.horizontal, DuoMetric.sessionListRowInset)
        .contentShape(Rectangle())
        // A plain click opens it; ⇧ and ⌘ select and never open or resume (DL-247).
        .onActivate { model.sessionRowClicked(row.session.tabKey, list: "list") { model.openListRow(row.id) } }  // action: open, view select
        .modifier(SessionOrganizeMenu(sessionKey: row.session.tabKey))
        .help([row.session.name, model.fixture.projects.first { $0.name == row.session.project }?.path, row.task].compactMap { $0 }.joined(separator: " · "))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(row.session.name), \(row.project)\(row.task.map { ", task \($0)" } ?? ""), \(SessionGlyph.spokenKind(model.sessionKind(row.session))), \(row.session.state.spokenName)\(row.wait.map { ", \($0)" } ?? "")")
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
        .accessibilityIdentifier("video.allprojects.\(v.rawValue)")   // anchors: the video cursor's target
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

extension SessionListPane {
    /// The List's rows as drawn: session keys, a breaker for each label and fold row (DL-247).
    @MainActor static func order(_ list: SessionList, model: AppModel, filtering: Bool) -> [String] {
        let b = SessionSelection.breaker
        if filtering { return model.listMatches.map(\.row.session.tabKey) }
        var out: [String] = []
        if model.listGroup == .project {
            // A breaker before each project's rows, so ⇧ doesn't range across projects (DL-341).
            for e in model.listProjectEntries(list) { if let r = e.row { out.append(r.session.tabKey) } else { out.append(b) } }
            return out
        }
        if model.rightCollapsedAllProjects, !list.needsYou.isEmpty { out.append(b); out += list.needsYou.map(\.session.tabKey) }
        for s in list.sections { out.append(b); out += s.rows.map(\.session.tabKey) }
        out.append(b)
        if model.expandedGroups.contains(SessionListKeys.earlier) { out += list.earlier.map(\.session.tabKey) }
        out.append(b)
        if model.listShowsArchived, model.expandedGroups.contains(SessionListKeys.archived) { out += list.archived.map(\.session.tabKey) }
        return out
    }
}

/// One project in the grouped List (DL-341): its header, then five sessions and "n more ›", unless folded.
struct SessionListProjectGroup: View {
    @Environment(AppModel.self) private var model
    let group: SessionList.ProjectGroup
    let twoLine: Bool
    let narrow: Bool

    var body: some View {
        let folded = model.expandedGroups.contains(SessionListKeys.folded(group.id))
        let all = model.expandedGroups.contains(SessionListKeys.more(group.id))
        VStack(alignment: .leading, spacing: 0) {
            SessionListProjectHeader(group: group, folded: folded, narrow: narrow)
            if !folded {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(all ? group.rows : group.firstRows) { r in SessionListRow(row: r, twoLine: twoLine, showProject: false) }
                    if group.hiddenCount > 0 {
                        Text(all ? "Show fewer ‹" : "\(group.hiddenCount) more ›")
                            .duoText(.body).foregroundStyle(DuoColor.text2)
                            .padding(.leading, DuoSpace.panePadding + DuoMetric.glyph + DuoSpace.gapRowItems)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(height: DuoMetric.rowSession)
                            .contentShape(Rectangle())
                            .onActivate { withDuoAnimation(.fold) { let k = SessionListKeys.more(group.id); if all { model.expandedGroups.remove(k) } else { model.expandedGroups.insert(k) } } }  // not an action: a fold in the list
                            .accessibilityLabel(all ? "Show fewer \(group.title) sessions" : "Show \(group.hiddenCount) more \(group.title) sessions")
                    }
                }
                .transition(.foldRows)
            }
        }
    }
}

/// `Quieter projects · 6`: the projects with nothing this week, closed (DL-341, Q-547); open, the same headers.
struct SessionListQuieter: View {
    @Environment(AppModel.self) private var model
    let groups: [SessionList.ProjectGroup]
    let twoLine: Bool
    let narrow: Bool

    var body: some View {
        if !groups.isEmpty {
            let key = SessionListKeys.quieter
            let expanded = model.expandedGroups.contains(key)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: DuoSpace.gapRowItems) {
                    Chevron(direction: expanded ? .down : .right).frame(width: 8, height: 10)
                    Text("Quieter projects · \(groups.count)").duoText(.body).foregroundStyle(DuoColor.text2)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, DuoSpace.panePadding)
                .frame(height: DuoMetric.rowSession)
                .contentShape(Rectangle())
                .onActivate { withDuoAnimation(.fold) { if expanded { model.expandedGroups.remove(key) } else { model.expandedGroups.insert(key) } } }  // not an action: a fold in the list
                .accessibilityLabel(expanded ? "Hide quieter projects" : "Show \(groups.count) quieter projects")
                if expanded {
                    ForEach(groups) { g in SessionListProjectGroup(group: g, twoLine: twoLine, narrow: narrow) }.transition(.foldRows)
                }
            }
        }
    }
}

/// A project's header in the grouped List (DL-341, L1/L2): 30 high with a `rule` hairline above; the fold
/// chevron, the name in 13 semibold, its folder in `monoPath` text2 (middle-truncated), the count; at the right
/// end a + in text2 (22×22) that widens leftward to "+ New session" on a `selected` pill while the pointer is on it.
struct SessionListProjectHeader: View {
    @Environment(AppModel.self) private var model
    let group: SessionList.ProjectGroup
    let folded: Bool
    /// Under 520 the folder hides first, then the count; the + always stays.
    let narrow: Bool

    var body: some View {
        let selected = model.listSelection == SessionListKeys.header(group.id)
        let hover = model.listPlusHover == group.id
        // ⌘T targets this project while its header or one of its rows is selected: the + says so.
        let cmdT = model.listSelectedProject == group.id
        HStack(spacing: DuoSpace.gapRowItems) {
            Chevron(direction: folded ? .right : .down).frame(width: 8, height: 10)
            Text(group.title).duoText(.body, weight: .semibold).lineLimit(1).fixedSize()
            if !narrow {
                Text(group.folder).duoText(.monoPath).foregroundStyle(DuoColor.text2).lineLimit(1).truncationMode(.middle)
                Text("\(group.count)").duoText(.control).foregroundStyle(DuoColor.text2).fixedSize()
            }
            Spacer(minLength: 0)
            if cmdT && !hover { Text("⌘T").duoText(.control).foregroundStyle(DuoColor.text2).fixedSize() }
            plus(hover: hover)
        }
        .padding(.horizontal, DuoSpace.panePadding)
        .frame(height: DuoMetric.sessionListProjectHeaderHeight)
        .background { if selected { RoundedRectangle(cornerRadius: DuoMetric.radiusSelection).fill(DuoColor.selected).padding(.horizontal, DuoMetric.sessionListRowInset) } }
        .overlay(alignment: .top) { Rectangle().fill(DuoColor.rule).frame(height: DuoMetric.borderHairline) }
        .contentShape(Rectangle())
        .onActivate { model.listSelection = SessionListKeys.header(group.id); model.toggleProjectFold(group.id) }  // not an action: a fold in the list
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(group.title), \(group.count) session\(group.count == 1 ? "" : "s"), \(folded ? "folded" : "open")")
        .accessibilityIdentifier("list-project-header.\(group.id)")
    }

    private func plus(hover: Bool) -> some View {
        let size = DuoMetric.sessionListProjectPlusSize
        return HStack(spacing: 4) {
            Text("+").duoText(.body).foregroundStyle(hover ? DuoColor.text : DuoColor.text2)
            if hover { Text("New session").duoText(.control).foregroundStyle(DuoColor.text).fixedSize() }
        }
        .padding(.horizontal, hover ? 7 : 0)
        .frame(minWidth: size, minHeight: size, maxHeight: size)
        .background(RoundedRectangle(cornerRadius: DuoMetric.sessionListProjectPlusRadius).fill(hover ? DuoColor.selected : Color.clear))
        .contentShape(Rectangle())
        .duoAnimation(.chipIn, value: hover)
        .onHover { inside in
            if inside { model.listPlusHover = group.id } else if model.listPlusHover == group.id { model.listPlusHover = nil }
        }
        .onActivate { model.newSessionFromHeader(group.id) }  // action: session new
        .help("New session in \(group.title)\n\(group.folder)")
        .accessibilityLabel("New session in \(group.title)")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("list-project-plus.\(group.id)")
    }
}
