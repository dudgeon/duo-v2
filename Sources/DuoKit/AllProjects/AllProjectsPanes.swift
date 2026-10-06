import SwiftUI

// All projects (handoff §3.2). Targets: screens/overview.html, flow-zoom-1.html, flow-zoom-4.html.

// MARK: - Home pane

/// The Home terminal pane: header, one tab per live Home session, then the terminal. The body is
/// Claude Code's own TUI (handoff §0.4), so it stays empty until terminals exist (Phase D).
struct HomePane: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let home = model.fixture.home
        let tabs = home.map { model.tabSessions(inProject: $0.name) } ?? []
        VStack(spacing: 0) {
            HStack(spacing: DuoSpace.gapRowItems) {
                Text("★ \(home?.name ?? "Home")")
                    .duoText(.bodyEmphasis)
                    .foregroundStyle(DuoColor.consoleText)
                    .contentShape(Rectangle())
                    // Home's heading opens Home as a project, like any tile's name (Geoff, 2026-10-04).
                    .onActivate { if let h = home?.name { model.open(project: h) } }  // action: open
                    .accessibilityLabel("Open \(home?.name ?? "home")")
                Spacer(minLength: 8)
                Text(home?.path ?? "")
                    .duoText(.mono)
                    .foregroundStyle(DuoColor.consoleText2)
                    .lineLimit(1)
            }
            .padding(.horizontal, DuoSpace.panePadding)
            .frame(height: DuoMetric.tabStripHeight)
            ConsoleRule()

            // No Home yet: no session row, the message sits under the heading (S2-3).
            let noHome = model.fixtureConsole == .noHome || (model.terminalsMode == .live && home == nil)
            if !noHome {
            HStack(spacing: 16) {
                ForEach(tabs) { s in
                    let active = s.tabKey == model.homeTab
                    HStack(spacing: DuoSpace.gapGlyphToLabel) {
                        if model.showsTabClose(s.tabKey) {   // DL-126
                            TabCloseButton(key: s.tabKey, onConsole: true, active: active) { model.closeConsoleTab(s.tabKey) }  // action: session close
                                .frame(width: DuoMetric.glyph, height: DuoMetric.glyph)
                        } else {
                            StateGlyph(s.state, on: .console(active: active))
                        }
                        Text(s.name)
                            .duoText(active ? .monoActiveTab : .mono)
                            .foregroundStyle(active ? DuoColor.consoleText : DuoColor.consoleText2)
                            .lineLimit(1)
                    }
                    .contentShape(Rectangle())
                    .onActivate { model.homeTab = s.tabKey }  // action: session open
                    .modifier(SessionOrganizeMenu(sessionKey: s.tabKey))
                    .modifier(TabHover(key: s.tabKey) { model.closeConsoleTab(s.tabKey) })
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(active ? [.isSelected, .isButton] : .isButton)
                    .background(DuoColor.console)
                    .transition(.tab)
                }
                // Home's shells (DB-4), after its sessions.
                ForEach(home.map { model.shells(inProject: $0.name) } ?? [], id: \.self) { key in
                    let active = key == model.homeTab
                    HStack(spacing: DuoSpace.gapGlyphToLabel) {
                        if model.showsTabClose(key) {
                            TabCloseButton(key: key, onConsole: true, active: active) { model.closeConsoleTab(key) }  // action: session close
                                .frame(width: 11, height: 9)
                        } else {
                            ShellPromptMark(active: active).frame(width: 11, height: 9)
                        }
                        Text(model.consoleTitle(key)).duoText(active ? .monoActiveTab : .mono)
                            .foregroundStyle(active ? DuoColor.consoleText : DuoColor.consoleText2).lineLimit(1)
                    }
                    .contentShape(Rectangle())
                    .onActivate { model.homeTab = key }  // action: session open
                    .modifier(TabHover(key: key) { model.closeConsoleTab(key) })
                    .accessibilityLabel("\(model.consoleTitle(key)), shell")
                    .background(DuoColor.console)
                    .transition(.tab)
                }
                // With no tabs, a way to start one (home-none).
                if home != nil, tabs.isEmpty && (home.map { model.shells(inProject: $0.name).isEmpty } ?? true) {
                    HStack(spacing: 5) {
                        Text("+").duoText(.mono).foregroundStyle(DuoColor.consoleText2)
                            .onActivate { if let h = home?.name { model.homeTab = model.newSession(in: h) } }  // action: session new
                            .accessibilityLabel("New Claude session")
                        Chevron(direction: .down, color: DuoColor.consoleText2).frame(width: 8, height: 6).scaleEffect(0.8)
                            .frame(height: 16).contentShape(Rectangle())
                            .onActivate {  // action: session new
                                PopUp.show([("New Claude Session", { if let h = home?.name { model.homeTab = model.newSession(in: h) } }),
                                            ("New Shell", { model.newShell() })], keys: [("t", [.command]), ("t", [.command, .shift])])
                            }
                            .accessibilityLabel("New session or shell")
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, DuoSpace.panePadding)
            .frame(height: DuoMetric.homeSessionTabsHeight)
            .duoAnimation(.tabMove, value: tabs.map(\.tabKey) + (home.map { model.shells(inProject: $0.name) } ?? []))
            ConsoleRule()
            }

            let _ = model.endedRevision
            if let home, let tab = model.homeTab, model.fixtureConsole != .homeNone,
               let t = model.terminal(project: home.name, session: tab), !t.missingClaude {
                TerminalSlot(session: t)
                if t.ended != nil { ConsoleEndedBar(session: t, name: model.consoleTitle(t.key)) }
            } else if noHome {
                // No Home folder chosen (DL-84, S2-3): sessions are listed anyway (DL-82).
                ConsoleMessage(state: .noHome, inHome: true)
            } else if model.fixtureConsole == .homeNone || (model.terminalsMode == .live && home != nil) {
                // Duo starts a Home session at launch (DL-54); this shows once the last one is closed.
                ConsoleMessage(state: ClaudeLocator.resolve() == nil && model.terminalsMode == .live ? .notFound : .homeNone, inHome: true)
            } else {
                Color.clear
            }
        }
        .background(DuoColor.console)
    }
}

struct ConsoleRule: View {
    var body: some View { DuoColor.consoleRule.frame(height: 1) }
}

// MARK: - Project map

struct ProjectMapPane: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let map = model.mapLayout
        VStack(spacing: 0) {
            ScrollView {
                // DL-104: the filter and sort, Home's ★ tile and columns as tiles, then the folders
                // outside Home: live ones as tiles, the rest as rows under their parent folder.
                let outsideAny = !map.active.isEmpty || !map.outside.isEmpty
                VStack(alignment: .leading, spacing: DuoSpace.gapMapColumns) {
                    MapHeader(layout: map)
                    if !map.homeColumns.isEmpty {
                        MapGrid(columns: map.homeColumns, home: map.home, tileAtEnd: !outsideAny && model.mapFilter.isEmpty)
                    }
                    if outsideAny {
                        if model.fixture.home != nil {
                            HStack(spacing: 10) {
                                SectionLabel(text: "Outside Home", count: map.outsideTotal)
                                DuoColor.rule.frame(height: DuoMetric.borderHairline)
                            }
                            .padding(.top, 6)
                        }
                        if !map.active.isEmpty {
                            SectionLabel(text: "Active outside Home", count: map.active.count)
                            TileFlow(projects: map.active)
                        }
                        if !map.outside.isEmpty { OutsideGroups(columns: map.outside) }
                        if model.mapFilter.isEmpty { NewProjectTile() }
                    }
                    if map.isEmpty && model.mapFilter.isEmpty { NewProjectTile() }
                }
                .padding(DuoSpace.panePadding)
                ArchivedRollup()
            }
            .scrollIndicators(.automatic)
            // Arrow keys move between tiles, Enter opens the focused one (handoff §6.3).
            .focusable()
            .focusEffectDisabled()
            .onMoveCommand { direction in
                switch direction {
                case .left: model.moveTileFocus(dx: -1, dy: 0)
                case .right: model.moveTileFocus(dx: 1, dy: 0)
                case .up: model.moveTileFocus(dx: 0, dy: -1)
                case .down: model.moveTileFocus(dx: 0, dy: 1)
                @unknown default: break
                }
            }
            .onKeyPress(.return) {
                guard let tile = model.focusedTile else { return .ignored }
                model.open(project: tile)
                return .handled
            }

            DuoColor.rule.frame(height: 1)
            IdleFooter()
        }
        .foregroundStyle(DuoColor.text)
        .background(DuoColor.pane)
        // The idle list (DB-1): above the footer's left end, 16 in, arrow down at it.
        .overlay(alignment: .bottomLeading) {
            if model.idleOpen {
                GeometryReader { box in
                    // The whole popover stays within the map's height less 32 (DB-1): the list part gets
                    // what the heading, key rows and padding (about 110) and the footer leave.
                    IdleListPopover(maxHeight: max(120, box.size.height - DuoMetric.overviewFooterHeight - 7 - 32 - 110))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                        .padding(.leading, 16)
                        .padding(.bottom, DuoMetric.overviewFooterHeight + DuoMetric.borderHairline + 6)
                }
            }
        }
    }
}

/// Columns side by side while each gets 220; past that they wrap into rows (DL-83, handoff §13's
/// suggested adaptive grid). `tileAtEnd`: the New project tile closes the last column.
struct MapGrid: View {
    let columns: [MapLayout.Column]
    /// Home's ★ tile, first in the first (unlabelled) column (DL-104).
    var home: Fixture.Project? = nil
    let tileAtEnd: Bool

    var body: some View {
        if columns.count == 1, columns[0].topic.isEmpty {
            loneColumn
        } else {
            // Packed (DL-129): each topic goes to the shortest column, in map order, so no hole
            // opens beside a short one.
            PackedColumns(rowSpacing: DuoSpace.gapMapColumns + 6) {
                ForEach(columns.indices, id: \.self) { i in
                    MapColumn(topic: columns[i].topic, projects: columns[i].projects, home: i == 0 ? home : nil,
                              last: tileAtEnd && i == columns.count - 1)
                }
            }
        }
    }

    /// As approved (DL-111, F-86; stand-ins-handoff `q42-one-list`): with every project directly in
    /// Home there is only the unlabelled column, which a third of the width left as one tall stack
    /// with the rest empty. Its tiles flow three across instead, as ACTIVE OUTSIDE HOME's do; the
    /// blank label row keeps Home's tile where it was. Two lists keep a third each (`q42-two-lists`).
    var loneColumn: some View {
        let projects = columns[0].projects
        let count = (home == nil ? 0 : 1) + projects.count + (tileAtEnd ? 1 : 0)
        return VStack(alignment: .leading, spacing: DuoSpace.gapTileToTile) {
            SectionLabel(text: " ")
            AdaptiveColumns(count: count, rowSpacing: DuoSpace.gapTileToTile) { i in
                let p = i - (home == nil ? 0 : 1)
                if let home, i == 0 {
                    HomeTile(home: home)
                } else if p < projects.count {
                    ProjectTile(project: projects[p])
                } else {
                    NewProjectTile()
                }
            }
        }
    }
}

/// Columns side by side while each gets 220; past that they wrap into rows, a short last row keeping
/// the others' width (DL-83's adaptive grid). Three slots across, as the map's targets draw: one
/// column or group stays a column wide.
struct AdaptiveColumns<Cell: View>: View {
    let count: Int
    var maxPerRow = 3
    var rowSpacing: CGFloat = DuoSpace.gapMapColumns
    @ViewBuilder let cell: (Int) -> Cell

    var body: some View {
        ViewThatFits(in: .horizontal) {
            ForEach(Array(stride(from: maxPerRow, through: 1, by: -1)), id: \.self) { perRow in
                VStack(alignment: .leading, spacing: rowSpacing) {
                    ForEach(Array(stride(from: 0, to: count, by: perRow)), id: \.self) { start in
                        HStack(alignment: .top, spacing: DuoSpace.gapMapColumns) {
                            ForEach(start..<min(start + perRow, count), id: \.self) { i in
                                cell(i).frame(minWidth: perRow == 1 ? 0 : DuoMetric.mapColumnMin, idealWidth: DuoMetric.mapColumnMin, maxWidth: .infinity, alignment: .topLeading)
                            }
                            ForEach(0..<(perRow - min(perRow, count - start)), id: \.self) { _ in
                                Color.clear.frame(minWidth: DuoMetric.mapColumnMin, idealWidth: DuoMetric.mapColumnMin, maxWidth: .infinity, maxHeight: 0)
                            }
                        }
                    }
                }
            }
        }
    }
}

/// Topic columns as many across as fit at 220 (three at most, DL-83), each placed under the
/// shortest column so far, in order (DL-129). One across below 2 × 220.
struct PackedColumns: Layout {
    var maxPerRow = 3
    var minWidth: CGFloat = DuoMetric.mapColumnMin
    var spacing: CGFloat = DuoSpace.gapMapColumns
    var rowSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? CGFloat(maxPerRow) * minWidth + CGFloat(maxPerRow - 1) * spacing
        let p = pack(width: width, subviews: subviews)
        return CGSize(width: width, height: p.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let p = pack(width: bounds.width, subviews: subviews)
        for (i, origin) in p.origins.enumerated() {
            subviews[i].place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), anchor: .topLeading,
                              proposal: ProposedViewSize(width: p.columnWidth, height: nil))
        }
    }

    /// Where each subview goes: the column count, its width, every origin, the tallest column.
    func pack(width: CGFloat, subviews: Subviews) -> (columnWidth: CGFloat, origins: [CGPoint], height: CGFloat) {
        let n = MapPacking.columnCount(width: width, items: subviews.count, minWidth: minWidth, spacing: spacing, maxPerRow: maxPerRow)
        let columnWidth = max(0, (width - CGFloat(n - 1) * spacing) / CGFloat(n))
        var heights = [CGFloat](repeating: 0, count: n)
        var origins: [CGPoint] = []
        for s in subviews {
            let c = heights.indices.min { heights[$0] < heights[$1] } ?? 0   // the leftmost of the shortest
            let h = s.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil)).height
            origins.append(CGPoint(x: CGFloat(c) * (columnWidth + spacing), y: heights[c] == 0 ? 0 : heights[c] + rowSpacing))
            heights[c] = (heights[c] == 0 ? 0 : heights[c] + rowSpacing) + h
        }
        return (columnWidth, origins, heights.max() ?? 0)
    }

}

/// The map's packing rule (DL-129), apart from SwiftUI so DuoChecks can check it.
public enum MapPacking {
    /// As many columns as fit at `minWidth`, never more than the items or `maxPerRow`, at least one.
    public static func columnCount(width: CGFloat, items: Int, minWidth: CGFloat, spacing: CGFloat, maxPerRow: Int) -> Int {
        let fit = Int(((width + spacing) / (minWidth + spacing)).rounded(.down))
        return max(1, min(fit, maxPerRow, max(1, items)))
    }

    /// The column each item goes to, given its height: the leftmost of the shortest so far.
    public static func columns(heights: [CGFloat], count: Int, rowSpacing: CGFloat) -> [Int] {
        var tops = [CGFloat](repeating: 0, count: max(1, count))
        return heights.map { h in
            let c = tops.indices.min { tops[$0] < tops[$1] } ?? 0
            tops[c] += (tops[c] == 0 ? 0 : rowSpacing) + h
            return c
        }
    }
}

/// Tiles three across with no column labels: folders outside Home with something live (DL-104).
struct TileFlow: View {
    let projects: [Fixture.Project]

    var body: some View {
        AdaptiveColumns(count: projects.count, rowSpacing: DuoSpace.gapTileToTile) { i in ProjectTile(project: projects[i]) }
    }
}

/// The map's header (DL-104): `Filter folders` on the left, `Sort` and its popup on the right.
struct MapHeader: View {
    @Environment(AppModel.self) private var model
    let layout: MapLayout

    var body: some View {
        @Bindable var model = model
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 10, weight: .medium)).foregroundStyle(DuoColor.text2)
                    .accessibilityHidden(true)
                TextField("Filter folders", text: $model.mapFilter)
                    .textFieldStyle(.plain)
                    .duoText(.control)
                    .foregroundStyle(DuoColor.text)
                    .onExitCommand { model.mapFilter = "" }
                    .accessibilityLabel("Filter projects and folders")
                if !model.mapFilter.isEmpty {
                    Text("\(layout.shown) of \(layout.total)").duoText(.control).foregroundStyle(DuoColor.text2).fixedSize()
                }
            }
            .padding(.horizontal, 8)
            .frame(width: DuoMetric.mapFilterWidth, height: DuoMetric.mapHeaderControlHeight)
            .overlay(RoundedRectangle(cornerRadius: DuoMetric.radiusField)
                .strokeBorder(model.mapFilter.isEmpty ? DuoColor.rule : DuoColor.controlEdge, lineWidth: DuoMetric.borderHairline))
            Spacer(minLength: 8)
            Text("Sort").duoText(.control).foregroundStyle(DuoColor.text2)
            Menu {
                ForEach(MapSort.allCases, id: \.self) { s in
                    Button { model.setMapSort(s) } label: {
                        if s == model.mapSort { Label(s.title, systemImage: "checkmark") } else { Text(s.title) }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(model.mapSort.title).duoText(.control).foregroundStyle(DuoColor.text)
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 8, weight: .semibold)).foregroundStyle(DuoColor.text2)
                }
                .padding(.leading, 8).padding(.trailing, 6)
                .frame(height: DuoMetric.mapHeaderControlHeight)
                .overlay(RoundedRectangle(cornerRadius: DuoMetric.radiusControl).strokeBorder(DuoColor.rule, lineWidth: DuoMetric.borderHairline))
                .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("Sort projects by \(model.mapSort.title)")
        }
        .frame(height: DuoMetric.mapHeaderControlHeight)
    }
}

/// Home on the map (DL-104): first in its column, a `text` border, its goal, `Home · n sessions`,
/// five sessions in attention order, then `n more ›`. Every part opens Home as a project; a session
/// opens on that session.
struct HomeTile: View {
    @Environment(AppModel.self) private var model
    let home: Fixture.Project

    var body: some View {
        let all = MapLayout.homeSessions(model.fixture)
        let shown = Array(all.prefix(5))
        VStack(alignment: .leading, spacing: DuoSpace.gapTileRows) {
            Text("★ \(home.name)").duoText(.bodyEmphasis).lineLimit(1)
            if !home.goal.isEmpty { Text(home.goal).duoText(.body).fixedSize(horizontal: false, vertical: true) }
            Text("Home · \(all.count) session\(all.count == 1 ? "" : "s")").duoText(.body).foregroundStyle(DuoColor.text2)
            ForEach(Array(shown.enumerated()), id: \.element.id) { i, s in
                TileSessionRow(session: s, selected: model.selectedActionSession == s.id, active: model.hasOpenTerminal(s.tabKey))
                    .padding(.top, i == 0 ? 6 : 0)
                    .contentShape(Rectangle())
                    .onActivate { model.open(project: home.name, session: s.name) }  // action: open
                    .modifier(SessionOrganizeMenu(sessionKey: s.tabKey))
            }
            if all.count > shown.count {
                HStack(spacing: DuoSpace.gapGlyphToLabel) {
                    Text("\(all.count - shown.count) more").duoText(.body)
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).accessibilityHidden(true)
                }
                .foregroundStyle(DuoColor.text2)
                .frame(height: DuoMetric.rowTileSession)
                .contentShape(Rectangle())
                .onActivate { model.open(project: home.name) }  // action: open
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .bordered(DuoSpace.cardPadding, color: DuoColor.text)
        .overlay {
            if model.focusedTile == home.name {
                RoundedRectangle(cornerRadius: DuoMetric.radiusCard + 1).strokeBorder(DuoColor.text, lineWidth: 1).padding(-1)
            }
        }
        .contentShape(Rectangle())
        .onActivate { model.open(project: home.name) }  // action: open
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Home, \(home.name), \(all.count) sessions")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { model.open(project: home.name) }
    }
}

/// Folders outside Home as rows under their parent folder, three groups across (DL-104).
struct OutsideGroups: View {
    let columns: [MapLayout.Column]

    var body: some View {
        AdaptiveColumns(count: columns.count, rowSpacing: DuoSpace.gapMapColumns + 6) { i in OutsideGroup(column: columns[i]) }
    }
}

struct OutsideGroup: View {
    @Environment(AppModel.self) private var model
    let column: MapLayout.Column

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 5) {
                Image(systemName: "folder").font(.system(size: 9, weight: .semibold)).foregroundStyle(DuoColor.text2)
                    .accessibilityHidden(true)
                SectionLabel(text: "\(MapColumn.label(column.topic)) /")
                Spacer(minLength: 6)
                Text("\(column.projects.count + column.hidden)").duoText(.pill).foregroundStyle(DuoColor.text2)
            }
            .frame(height: 20)
            .padding(.bottom, 4)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Folder \(column.topic), \(column.projects.count + column.hidden) folders")
            // A folder that's gone keeps its full tile (S3-2): it says what happened and what to do.
            ForEach(column.projects) { p in
                if p.isMissing { ProjectTile(project: p).padding(.vertical, 4) } else { OutsideRow(project: p) }
            }
            if column.hidden > 0 {
                Text("+ \(column.hidden) more")
                    .duoText(.body)
                    .foregroundStyle(DuoColor.text2)
                    .frame(height: DuoMetric.rowTileSession)
                    .contentShape(Rectangle())
                    .onActivate { model.openOutsideGroups.insert(column.topic) }  // not an action: view-only unfold, like scrolling
                    .accessibilityAddTraits(.isButton)
            }
        }
    }
}

/// One folder outside Home: its name, its session count, its last activity (DL-104).
struct OutsideRow: View {
    @Environment(AppModel.self) private var model
    let project: Fixture.Project

    var body: some View {
        let sessions = model.fixture.sessions(inProject: project.name)
        let focused = model.focusedTile == project.name
        let last = MapLayout.activity(of: project.name, in: model.fixture, now: Date().timeIntervalSince1970 * 1000)
        HStack(spacing: DuoSpace.gapGlyphToLabel) {
            Text(project.name.split(separator: "/").last.map(String.init) ?? project.name)
                .duoText(.body).lineLimit(1).truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(sessions.count)").duoText(.body).foregroundStyle(DuoColor.text2).monospacedDigit()
            Text(Self.wait(last)).duoText(.body).foregroundStyle(DuoColor.text2).monospacedDigit()
                .frame(width: DuoMetric.mapOutsideRowWaitWidth, alignment: .trailing)
        }
        .frame(height: DuoMetric.rowTileSession)
        .padding(.horizontal, 8)
        .background { if focused { RoundedRectangle(cornerRadius: DuoMetric.radiusSelection).fill(DuoColor.selected) } }
        .padding(.horizontal, -8)
        .contentShape(Rectangle())
        .onActivate { model.open(project: project.name) }  // action: open
        .modifier(ProjectOrganizeMenu(project: project))
        .help(project.path)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(project.name), \(sessions.count) sessions, last active \(Self.wait(last))")
        .accessibilityAddTraits(.isButton)
    }

    /// The wait words for a time (`4m`, `1h`, `3d`, `2w`), the same as session rows (Attention).
    static func wait(_ ms: Double) -> String {
        guard ms > 0 else { return "" }
        return Attention.waitText(since: ms, now: Date()) ?? ""
    }
}

/// One topic's column: its label (none for projects directly in Home, DL-83), then its tiles.
struct MapColumn: View {
    /// A column outside Home is labelled by its parent's path (`~/repos`).
    static func isPath(_ topic: String) -> Bool { topic.hasPrefix("~") || topic.hasPrefix("/") }

    /// A long path keeps its first and last parts: `~/Desktop/…/interviews` (DL-100).
    static func label(_ topic: String) -> String {
        guard isPath(topic) else { return topic }
        let parts = topic.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard parts.count > 3 else { return topic }
        return [parts[0], parts[1], "…", parts[parts.count - 1]].joined(separator: "/")
    }

    let topic: String
    let projects: [Fixture.Project]
    var home: Fixture.Project? = nil
    let last: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: DuoSpace.gapTileToTile) {
            // Columns read as folders (DL-92): a folder mark and a trailing slash.
            HStack(spacing: 5) {
                if !topic.isEmpty {
                    Image(systemName: "folder").font(.system(size: 9, weight: .semibold)).foregroundStyle(DuoColor.text2)
                        .accessibilityHidden(true)
                }
                SectionLabel(text: topic.isEmpty ? " " : "\(Self.label(topic)) /")
            }
            .accessibilityLabel(topic.isEmpty ? "" : "Folder \(topic)")
            if let home { HomeTile(home: home) }
            ForEach(projects) { p in
                ProjectTile(project: p)
                    // A new tile fades in where it lands, 150 ms; the others just move (DL-129).
                    .transition(MotionSettings.shared.reduce ? .identity : .opacity.animation(DuoMotionToken.tileIn.animation))
            }
            if last { NewProjectTile() }
        }
    }
}

/// A project tile (handoff §5 `ProjectTile`): name, goal, health · next, then its live sessions.
struct ProjectTile: View {
    @Environment(AppModel.self) private var model
    let project: Fixture.Project

    @ViewBuilder var missingButtons: some View {
        if project.movedTo != nil {
            Button("Use New Place") { model.useNewPlace(project.name) }.buttonStyle(DefaultSheetButtonStyle()).fixedSize()
            Button("Locate Folder…") { model.locateFolder(project.name) }.buttonStyle(.duo).fixedSize()
        } else {
            Button("Locate Folder…") { model.locateFolder(project.name) }.buttonStyle(.duo).fixedSize()
            Button("Remove from Duo") { model.forgetFolder(project.name) }.buttonStyle(.duo).fixedSize()
        }
    }

    var body: some View {
        let focused = model.focusedTile == project.name
        // Live sessions, plus ones open in a Duo terminal at their prompt (ENH-7: easy to jump back into).
        let live = model.fixture.liveSessions(inProject: project.name)
        let sessions = live + model.fixture.sessions(inProject: project.name).filter { s in
            !live.contains(s) && model.hasOpenTerminal(s.tabKey)
        }
        VStack(alignment: .leading, spacing: DuoSpace.gapTileRows) {
            // flow-zoom-1 wraps both the name and the hint when the hint is shown, as CSS flex
            // shrinks them (the target wins over handoff §8's truncation proposal).
            FlexShrinkRow {
                Text(project.name).duoText(.bodyEmphasis)
                if focused {
                    // Non-breaking space: SwiftUI avoids a one-word last line ("Enter" / "to open");
                    // the target breaks "Enter to" / "open" (findings F-13).
                    Text("Enter\u{00A0}to open").duoText(.body).foregroundStyle(DuoColor.text2)
                }
            }
            if project.isMissing {
                // Its folder is gone (S3-2, DB-8): what happened, where it was, and what to do.
                let n = model.fixture.sessions(inProject: project.name).count
                let away = project.missing?.hasPrefix("On “") == true
                Text(project.missing ?? "Folder not found").duoText(.body).fixedSize(horizontal: false, vertical: true)
                if project.movedTo == nil {
                    Text("Was at \(project.path)").duoText(.body).foregroundStyle(DuoColor.text2).lineLimit(1).truncationMode(.middle)
                }
                Text("\(n) session\(n == 1 ? "" : "s") · \(away ? "they open when the disk is back" : "they open again once it’s found")")
                    .duoText(.body).foregroundStyle(DuoColor.text2)
                if !away {
                    // Side by side when they fit, else one under the other: never truncated.
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: DuoSpace.gapButtonToButton) { missingButtons }
                        VStack(alignment: .leading, spacing: DuoSpace.gapButtonToButton) { missingButtons }
                    }
                    .padding(.top, 8)
                }
            } else if project.isFolderOnly {
                // A folder with Claude sessions but no PROJECT.md (DL-63).
                Text(project.path).duoText(.body).foregroundStyle(DuoColor.text2).lineLimit(1).truncationMode(.middle)
                Text(project.hasClaudeMD == true ? "Has CLAUDE.md · no project file" : "No project file")
                    .duoText(.body).foregroundStyle(DuoColor.text2)
            } else {
                Text(project.goal).duoText(.body).fixedSize(horizontal: false, vertical: true)
                Text([project.health, project.next].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                    .duoText(.body)
                    .foregroundStyle(DuoColor.text2)
                    .fixedSize(horizontal: false, vertical: true)
                if let from = project.movedFrom, let n = project.staleSessions {
                    // Moved outside Duo; its sessions follow when resumed, or all at once (DB-8, stand-in).
                    Text("\(n) session\(n == 1 ? "" : "s") still filed under \(from)").duoText(.body).foregroundStyle(DuoColor.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if project.isMissing {
                EmptyView()
            } else if sessions.isEmpty, project.isFolderOnly {
                let n = model.fixture.sessions(inProject: project.name).count
                Text("\(n) past session\(n == 1 ? "" : "s")")
                    .duoText(.body)
                    .foregroundStyle(DuoColor.text2)
                    .frame(height: DuoMetric.rowTileSession)
                    .padding(.top, 6)
            } else if sessions.isEmpty {
                Text("Nothing running")
                    .duoText(.body)
                    .foregroundStyle(DuoColor.text2)
                    .frame(height: DuoMetric.rowTileSession)
                    .padding(.top, 6)
            } else {
                ForEach(Array(sessions.enumerated()), id: \.element.id) { i, s in
                    TileSessionRow(session: s, selected: model.selectedActionSession == s.id, active: model.hasOpenTerminal(s.tabKey))
                        .padding(.top, i == 0 ? 6 : 0)
                        .contentShape(Rectangle())
                        .onActivate { model.open(project: project.name, session: s.name) }  // action: open
                        .modifier(SessionOrganizeMenu(sessionKey: s.tabKey))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .bordered(DuoSpace.cardPadding, color: focused ? DuoColor.text : DuoColor.rule)
        .overlay {
            if focused {
                // The target's `box-shadow: 0 0 0 1px` ring outside the border: a 2 pt outline.
                RoundedRectangle(cornerRadius: DuoMetric.radiusCard + 1)
                    .strokeBorder(DuoColor.text, lineWidth: 1)
                    .padding(-1)
            }
        }
        .contentShape(Rectangle())
        .onActivate { model.open(project: project.name) }  // action: open
        .modifier(ProjectOrganizeMenu(project: project))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(tileLabel(sessions))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { model.open(project: project.name) }
    }

    private func tileLabel(_ sessions: [Fixture.Session]) -> String {
        var parts = [project.name]
        if let h = project.health { parts.append(h.lowercased()) }
        for state in [SessionState.needsYou, .readyForReview, .working] {
            let n = sessions.filter { $0.state == state }.count
            if n > 0 { parts.append("\(n) \(state.spokenName)") }
        }
        return parts.joined(separator: ", ")
    }
}

/// A 24-high session row inside a tile: glyph, name, wait time (no time for ready for review).
struct TileSessionRow: View {
    let session: Fixture.Session
    var selected = false
    /// A terminal is open for it in Duo (ENH-7): a tint, so it's easy to jump back in.
    var active = false

    var body: some View {
        HStack(spacing: DuoSpace.gapRowItems) {
            StateGlyph(session.state)
            Text(session.name)
                .duoText(.body, weight: selected ? .semibold : nil)
                .lineLimit(1)
            Spacer(minLength: 8)
            if session.state != .readyForReview { WaitLabel(text: session.wait) }
        }
        .frame(height: DuoMetric.rowTileSession)
        .padding(.horizontal, selected || active ? 6 : 0)
        .background {
            if selected { RoundedRectangle(cornerRadius: DuoMetric.radiusSelection).fill(DuoColor.selected) }
            else if active { RoundedRectangle(cornerRadius: DuoMetric.radiusSelection).fill(DuoColor.activeTint) }
        }
        .padding(.horizontal, selected || active ? -6 : 0)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(session.name), \(session.state.spokenName)\(session.wait.map { ", waiting \($0)" } ?? "")")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// `+ New project`: dashed, 38 high. Opens the New project sheet (S2-6, DL-100).
struct NewProjectTile: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Text("+ New project")
            .duoText(.body)
            .foregroundStyle(DuoColor.text2)
            .frame(maxWidth: .infinity)
            // 38 pt plus its 1 pt border on each side: CSS content-box (findings F-10).
            .frame(height: DuoMetric.newProjectTileHeight + 2 * DuoMetric.borderHairline)
            .overlay(
                RoundedRectangle(cornerRadius: DuoMetric.radiusCard)
                    .strokeBorder(DuoColor.controlEdge, style: StrokeStyle(lineWidth: 1, dash: DuoShadow.dashPattern))
            )
            .contentShape(Rectangle())
            .onActivate { model.showNewProject() }  // action: project new
            .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Action column

struct ActionColumnPane: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let f = model.fixture
        let needsYou = f.needsYou
        let reviews = f.sessions.filter { $0.state == .readyForReview }
        ScrollView {
            VStack(alignment: .leading, spacing: DuoSpace.gapCardToCard) {
                if needsYou.isEmpty && model.terminalsMode == .live {
                    // Nothing waiting (DL-100): one quiet line instead of an empty section.
                    HStack(spacing: DuoSpace.gapGlyphToLabel) {
                        StateGlyph(.resolved)
                        Text("Nothing needs you.").duoText(.body).foregroundStyle(DuoColor.text2)
                    }
                }
                if !needsYou.isEmpty {
                    SectionLabel(text: "Needs you", count: needsYou.count, needsYou: true)
                    ForEach(needsYou) { s in
                        if s.project == f.home?.name {
                            HomePointerCard(session: s)
                        } else {
                            NeedsYouCard(session: s, selected: model.selectedActionSession == s.id)
                        }
                    }
                }
                if !reviews.isEmpty {
                    SectionLabel(text: "Ready for review", count: reviews.count)
                        .padding(.top, needsYou.isEmpty ? 0 : 6)
                    ForEach(reviews) { s in ReviewCard(session: s) }
                }
                // Open tasks across projects (DL-93): what you're working on. Stand-in look (S2-5).
                let tasks = (f.tasks ?? []).filter(model.listedTask)
                if !tasks.isEmpty {
                    SectionLabel(text: "Open tasks", count: tasks.count)
                        .padding(.top, needsYou.isEmpty && reviews.isEmpty ? 0 : 6)
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(tasks) { t in TaskLine(task: t, showsProject: true).transition(.listRow) }
                    }
                    .duoAnimation(.rowMove, value: tasks.map(\.id))
                    .padding(.horizontal, -(8 + DuoSpace.selectionInset))
                }
            }
            .padding(DuoSpace.panePadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(DuoColor.text)
        .background(DuoColor.pane)
    }
}

/// Glyph, name (semibold), optional suffix, wait time right-aligned.
struct CardHeader: View {
    let session: Fixture.Session
    var suffix: String?
    var showsWait = true

    var body: some View {
        HStack(spacing: DuoSpace.gapRowItems) {
            StateGlyph(session.state)
            Text(session.name).duoText(.bodyEmphasis).lineLimit(1)
            if let suffix { Text(suffix).duoText(.body).foregroundStyle(DuoColor.text2).fixedSize() }
            Spacer(minLength: 8)
            if showsWait { WaitLabel(text: session.wait) }
        }
    }
}

/// A session needing you (handoff §5 `ActionCard`). The question is shown verbatim. No reply
/// buttons: DL-29.
struct NeedsYouCard: View {
    @Environment(AppModel.self) private var model
    let session: Fixture.Session
    var selected = false

    var body: some View {
        VStack(alignment: .leading, spacing: DuoSpace.gapCardContent) {
            VStack(alignment: .leading, spacing: 0) {
                CardHeader(session: session)
                // The reason follows the project (DL-100): "checkout · permission".
                Text(session.project + (session.reason.map { " · \($0)" } ?? "")).duoText(.body).foregroundStyle(DuoColor.text2).lineLimit(1)
                    .onActivate { model.open(project: session.project) }  // action: open
            }
            if let q = session.question {
                let full = model.expandedQuestions.contains(session.id)
                VStack(alignment: .leading, spacing: 2) {
                    Text(q)
                        .duoText(.body)
                        .lineLimit(full ? nil : 6)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    // A question past 6 lines folds, "… more" under it (DL-100).
                    if q.count > 280 {
                        Text(full ? "less" : "… more").duoText(.body).foregroundStyle(DuoColor.text2)
                            .onActivate { if full { model.expandedQuestions.remove(session.id) } else { model.expandedQuestions.insert(session.id) } }  // not an action: shows the rest of the text
                    }
                }
                .modifier(QuestionBox(boxed: selected))
            }
            HStack(spacing: DuoSpace.gapButtonToButton) {
                Button("Open project") { model.open(project: session.project, session: session.name) }.buttonStyle(.duo)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .bordered(DuoSpace.cardPadding,
                  color: selected ? DuoColor.text : DuoColor.rule,
                  width: selected ? DuoMetric.borderEmphasis : DuoMetric.borderHairline)
        .contentShape(Rectangle())
        // Clicking a session resumes it (Geoff, 2026-10-04): its project opens with it in the console.
        // Arrow keys still move the selection without opening.
        .onActivate { model.selectedActionSession = session.id; model.open(project: session.project, session: session.name) }  // action: open
        .modifier(SessionOrganizeMenu(sessionKey: session.tabKey))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(session.name), needs you, waiting \(session.wait ?? ""), \(session.project)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// On the selected card the question sits in a 1.5 pt `needsYou` box (handoff §3.2).
struct QuestionBox: ViewModifier {
    let boxed: Bool

    func body(content: Content) -> some View {
        if boxed {
            content.bordered(DuoSpace.questionBoxPadding, color: DuoColor.needsYou, width: DuoMetric.borderEmphasis)
        } else {
            content
        }
    }
}

/// A Home session needing you is a pointer, not a card: the Home terminal is already on screen.
struct HomePointerCard: View {
    @Environment(AppModel.self) private var model
    let session: Fixture.Session

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CardHeader(session: session, suffix: session.project)
            Text("← Waiting in the Home terminal").duoText(.body).foregroundStyle(DuoColor.text2).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .bordered(DuoSpace.pointerCardPadding, color: DuoColor.controlEdge, dashed: true)
        .contentShape(Rectangle())
        .onActivate { model.homeTab = session.tabKey; model.focusHomeRequest += 1 }  // action: session open
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(session.name), needs you, waiting in the Home terminal")
    }
}

/// A session with a deliverable to review (handoff §3.2).
struct ReviewCard: View {
    @Environment(AppModel.self) private var model
    let session: Fixture.Session

    var body: some View {
        VStack(alignment: .leading, spacing: DuoSpace.gapTileRows) {
            CardHeader(session: session, showsWait: false)
            Text(session.project).duoText(.body).foregroundStyle(DuoColor.text2).lineLimit(1)
                    .onActivate { model.open(project: session.project) }  // action: open
            if let summary = session.summary {
                Text(summary).duoText(.body).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: DuoSpace.gapButtonToButton) {
                Button("Review") { model.open(project: session.project, session: session.name, document: session.document) }
                    .buttonStyle(.duo)
            }
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .bordered(DuoSpace.cardPadding)
        .contentShape(Rectangle())
        // Clicking the card resumes the session, as Review does (Geoff, 2026-10-04).
        .onActivate { model.open(project: session.project, session: session.name, document: session.document) }  // action: open
        .modifier(SessionOrganizeMenu(sessionKey: session.tabKey))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(session.name), ready for review, \(session.project)")
    }
}


// MARK: - Organising (DL-63–DL-66), live mode only

/// Right-click a session: move it to a project. It can be dragged onto a project tile too.
struct SessionOrganizeMenu: ViewModifier {
    @Environment(AppModel.self) private var model
    let sessionKey: String

    func body(content: Content) -> some View {
        if model.terminalsMode == .live, let s = (model.fixture.sessions + (model.fixture.archivedSessions ?? [])).first(where: { $0.tabKey == sessionKey }),
           let id = s.sessionId {
            let payload = AppModel.dragPayload(session: id)
            content
                .contextMenu {
                    SendMenu { _ in model.sessionPayload(sessionKey) }
                    Button("Find Similar") { model.findSimilar(session: sessionKey) }
                    // A link for a task note (DL-87): [title](duo2://session/<id>).
                    Button("Copy Link") { model.copySessionLink(sessionKey) }
                    Divider()
                    // Tasks (DL-93): a note in tasks/ whose `sessions:` links this session.
                    Button("Make a Task") { model.makeTask(fromSession: sessionKey) }
                    if !model.taskNotes(in: s.project).isEmpty { AddToTaskMenu(model: model, session: s, id: id) }
                    Divider()
                    MoveToProjectMenu(model: model, session: s, id: id)
                    Divider()
                    // Filing (Geoff, 2026-10-04): out of the lists, kept, searchable; Unarchive from the Archived fold.
                    if model.isSessionArchived(id) {
                        Button("Unarchive Session") { _ = model.setSessionArchived(sessionKey, false) }
                    } else {
                        Button("Archive Session") { if let why = model.setSessionArchived(sessionKey, true) { model.info(why) } }
                    }
                    Button("Delete Session…") { model.deleteSession(sessionKey) }
                }
                .modifier(Lifted(active: model.dragging == payload))
                .onDrag({  // action: session move
                    model.beginDrag(payload)
                    return NSItemProvider(object: payload as NSString)
                }, preview: { DragCard(title: s.name, detail: s.project) })
        } else {
            content
        }
    }
}

/// Right-click a project or folder: merge it into another, or make a folder a project. Tiles
/// can be dragged onto each other, and take dropped sessions and projects (with a confirmation).
struct ProjectOrganizeMenu: ViewModifier {
    @Environment(AppModel.self) private var model
    let project: Fixture.Project

    func body(content: Content) -> some View {
        if model.terminalsMode == .live, project.isHome != true {
            let payload = AppModel.dragPayload(project: project.name)
            content
                .contextMenu {
                    SendMenu { _ in model.projectPayload(project.name) }
                    Divider()
                    if project.isMissing {
                        if project.movedTo != nil { Button("Use New Place") { model.useNewPlace(project.name) } }
                        Button("Locate Folder…") { model.locateFolder(project.name) }
                        Button("Remove from Duo") { model.forgetFolder(project.name) }
                        Divider()
                    } else if project.isFolderOnly {
                        Button("Make a Project") { model.makeProject(project.name) }
                    }
                    if project.staleSessions != nil {
                        Button("Reconnect Sessions…") { model.reconnectStale(project.name) }
                    }
                    // Into Home with its sessions (DL-85); only for what isn't in Home already.
                    if model.liveRoot != nil, !model.isInHome(project.name), !project.isMissing {
                        Button("Move into Home…") { model.moveIntoHome(project.name) }
                    }
                    MergeIntoMenu(model: model, project: project)
                    Divider()
                    // Filing (ENH-6): the tile moves to the Archived rollup; nothing else changes.
                    Button("Archive Project") { model.setArchived(project.name, true) }
                }
                .modifier(Lifted(active: model.dragging == payload))
                .modifier(DropTarget(name: project.name))
                .onDrag({  // action: project merge
                    model.beginDrag(payload)
                    return NSItemProvider(object: payload as NSString)
                }, preview: { DragCard(title: project.name, detail: project.isFolderOnly ? project.path : project.goal) })
                .modifier(TakesDrops(name: project.name))
        } else if model.terminalsMode == .live {
            // Home takes drops (sessions move into Home) but isn't merged away.
            content.contextMenu { SendMenu { _ in model.projectPayload(project.name) } }
                .modifier(DropTarget(name: project.name))
                .modifier(TakesDrops(name: project.name))
        } else {
            content
        }
    }
}

// MARK: Drag and drop feel (Geoff, 2026-10-04: an opaque card with a shadow, motion when picked
// up and when it moves in, and a clear result; F-51)

/// What follows the pointer: the item as a white card with the popover shadow, so it reads
/// clearly over other tiles.
struct DragCard: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).duoText(.bodyEmphasis).foregroundStyle(DuoColor.text).lineLimit(1)
            if !detail.isEmpty { Text(detail).duoText(.body).foregroundStyle(DuoColor.text2).lineLimit(2) }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(width: 190, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: DuoMetric.radiusCard).fill(DuoColor.pane))
        .overlay(RoundedRectangle(cornerRadius: DuoMetric.radiusCard).strokeBorder(DuoColor.rule, lineWidth: DuoMetric.borderHairline))
        // The popover shadow token (0 12 32, the text colour at 22%).
        .duoPopoverShadow()
        .padding(24)  // room for the shadow inside the drag image
    }
}

/// The item left behind while it's being dragged: it sinks back, so the pick-up registers.
/// `lift`, ease-out; with Reduce Motion it dims at once and doesn't shrink (DL-130).
struct Lifted: ViewModifier {
    let active: Bool
    func body(content: Content) -> some View {
        content
            .opacity(active ? 0.35 : 1)
            .scaleEffect(active && !MotionSettings.shared.reduce ? 0.96 : 1)
            .duoAnimation(.lift, value: active)
    }
}

/// A tile under a dragged item rises to meet it; a tile that just took a drop pulses.
struct DropTarget: ViewModifier {
    @Environment(AppModel.self) private var model
    let name: String

    func body(content: Content) -> some View {
        let hot = model.dropTarget == name && model.dragging != AppModel.dragPayload(project: name)
        let landed = model.landed == name
        content
            .overlay {
                RoundedRectangle(cornerRadius: DuoMetric.radiusCard + 1)
                    .strokeBorder(DuoColor.text, lineWidth: 2)
                    .padding(-1)
                    .opacity(hot ? 1 : 0)
            }
            .overlay {
                RoundedRectangle(cornerRadius: DuoMetric.radiusCard)
                    .fill(DuoColor.selected)
                    .opacity(landed ? 0.5 : 0)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .bottomTrailing) {
                if landed {
                    Text(model.landedNote)
                        .duoText(.bodyEmphasis)
                        .foregroundStyle(DuoColor.text)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(DuoColor.pane))
                        .overlay(Capsule().strokeBorder(DuoColor.rule, lineWidth: DuoMetric.borderHairline))
                        .padding(8)
                        .transition(.opacity)
                }
            }
            // DL-130: `lift` and `landed`, ease-out, no spring; nothing scales with Reduce Motion.
            .scaleEffect(hot && !MotionSettings.shared.reduce ? 1.03 : 1)
            .shadow(color: DuoColor.text.opacity(hot ? 0.18 : 0), radius: 12, x: 0, y: 6)
            .duoAnimation(.lift, value: hot)
            .duoAnimation(.landed, value: landed)
    }
}

/// Takes a dropped session or project (the confirmation follows; DL-66).
struct TakesDrops: ViewModifier {
    @Environment(AppModel.self) private var model
    let name: String

    func body(content: Content) -> some View {
        content.onDrop(of: [.plainText, .utf8PlainText], isTargeted: Binding(  // action: project merge
            get: { model.dropTarget == name },
            set: { on in
                if on { model.dropTarget = name } else if model.dropTarget == name { model.dropTarget = nil }
            })) { providers in
            DuoLog.write("drop on \(name): \(providers.count) item(s)")
            guard let item = providers.first else { return false }
            _ = item.loadObject(ofClass: NSString.self) { obj, err in
                if let err { DuoLog.write("drop on \(name): couldn't read it: \(err)") }
                guard let payload = obj as? String else { return }
                DispatchQueue.main.async { MainActor.assumeIsolated { model.handleDrop(payload, onto: name) } }
            }
            return true
        }
    }
}
