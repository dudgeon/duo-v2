import SwiftUI

// The Board by activity (DL-347; all-projects-board-handoff B1, B2, T). Sections of tiles and rows,
// the tile's New session row, This week's rows.

/// The Board's body when Group is Activity or None: each section's label, then its tiles across (as
/// many as fit at `mapColumnMin`, Q-545) or its rows.
struct ActivityBoard: View {
    @Environment(AppModel.self) private var model
    let layout: ActivityLayout

    var body: some View {
        VStack(alignment: .leading, spacing: DuoSpace.gapMapColumns) {
            ForEach(layout.sections) { section in
                VStack(alignment: .leading, spacing: DuoSpace.gapTileToTile) {
                    if !section.title.isEmpty { label(section) }
                    switch section.style {
                    case .tiles:
                        BoardTiles(projects: section.projects)
                    case .rows:
                        BoardRows(projects: section.projects)
                    case .fold:
                        if section.open { BoardRows(projects: section.projects) }
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("board.section.\(section.id)")
            }
        }
    }

    @ViewBuilder private func label(_ section: ActivityLayout.Section) -> some View {
        if section.style == .fold {
            HStack(spacing: DuoSpace.gapRowItems) {
                SectionLabel(text: section.title, count: section.projects.count)
                Chevron(direction: section.open ? .down : .right).frame(width: section.open ? 10 : 8, height: section.open ? 8 : 10)
            }
            .contentShape(Rectangle())
            .onActivate {  // not an action: a fold, as the List's are
                withDuoAnimation(.fold) {
                    if model.expandedGroups.contains(AppModel.boardEarlierKey) { model.expandedGroups.remove(AppModel.boardEarlierKey) }
                    else { model.expandedGroups.insert(AppModel.boardEarlierKey) }
                }
            }
            .accessibilityLabel("\(section.title), \(section.projects.count) projects, \(section.open ? "open" : "folded")")
            .accessibilityAddTraits(.isButton)
        } else {
            SectionLabel(text: section.title, count: section.projects.count)
        }
    }
}

/// Tiles across as many as fit at 220 (Q-545), each section's last row keeping the others' width.
struct BoardTiles: View {
    @Environment(AppModel.self) private var model
    let projects: [Fixture.Project]

    var body: some View {
        AdaptiveColumns(count: projects.count, maxPerRow: Int(DuoMetric.mapPerRowMax), rowSpacing: DuoSpace.gapTileToTile) { i in
            let p = projects[i]
            Group {
                if p.isHome == true { HomeTile(home: p) } else { ProjectTile(project: p) }
            }
            .transition(MotionSettings.shared.reduce ? .identity : .opacity.animation(DuoMotionToken.tileIn.animation))
        }
        .background {
            // The arrow keys' up and down step by the tiles across, as last drawn.
            GeometryReader { box in
                Color.clear.onChange(of: box.size.width, initial: true) { _, w in
                    model.boardPerRow = MapPacking.columnCount(width: w, items: projects.count, minWidth: DuoMetric.mapColumnMin,
                                                               spacing: DuoSpace.gapMapColumns, maxPerRow: Int(DuoMetric.mapPerRowMax))
                }
            }
        }
    }
}

/// This week's, and Earlier's, projects as rows (B1): name, folder, status, when, and a + that starts a session.
struct BoardRows: View {
    let projects: [Fixture.Project]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(projects) { p in BoardRow(project: p) }
        }
    }
}

struct BoardRow: View {
    @Environment(AppModel.self) private var model
    let project: Fixture.Project

    var body: some View {
        let focused = model.focusedTile == project.name
        let hover = model.boardNewSessionHover == project.name
        let last = MapLayout.activity(of: project.name, in: model.fixture, now: model.minute.timeIntervalSince1970 * 1000)
        let when = OutsideRow.wait(last, now: model.minute)
        let folder = BoardText.folder(project)
        let status = BoardText.status(project)
        ViewThatFits(in: .horizontal) {
            line(folder: folder, status: status, when: when, hover: hover, wide: true)
            line(folder: nil, status: status, when: when, hover: hover, wide: false)
            line(folder: nil, status: nil, when: when, hover: hover, wide: false)
        }
        .padding(.horizontal, 8)
        .frame(height: DuoMetric.mapWeekRowHeight)
        .background { if focused { RoundedRectangle(cornerRadius: DuoMetric.radiusSelection).fill(DuoColor.selected) } }
        .padding(.horizontal, -8)
        .overlay(alignment: .bottom) { Rectangle().fill(DuoColor.rule).frame(height: DuoMetric.borderHairline) }
        .contentShape(Rectangle())
        .onActivate { model.open(project: project.name) }  // action: open
        .modifier(ProjectOrganizeMenu(project: project))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(project.name), \(status), \(when.isEmpty ? "no recent activity" : "last active \(when)")")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("board.row.\(project.name)")
    }

    private func line(folder: String?, status: String?, when: String, hover: Bool, wide: Bool) -> some View {
        HStack(spacing: DuoSpace.gapRowItems) {
            Text(project.name).duoText(.body).lineLimit(1).truncationMode(.tail)
                .frame(width: wide ? DuoMetric.mapWeekRowNameWidth : nil, alignment: .leading)
                .frame(maxWidth: wide ? nil : .infinity, alignment: .leading)
            if let folder {
                Text(folder).duoText(.monoPath).foregroundStyle(DuoColor.text2).lineLimit(1).truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let status {
                Text(status).duoText(.body).foregroundStyle(DuoColor.text2).lineLimit(1).truncationMode(.tail)
                    .frame(width: wide ? DuoMetric.mapWeekRowStatusWidth : nil, alignment: .leading)
            }
            Text(when).duoText(.body).foregroundStyle(DuoColor.text2).monospacedDigit()
                .frame(width: DuoMetric.mapWeekRowWhenWidth, alignment: .trailing)
            BoardPlus(project: project, hover: hover)
        }
    }
}

/// The row's + (as DL-341's header +): a + at rest, "+ New session" under the pointer.
struct BoardPlus: View {
    @Environment(AppModel.self) private var model
    let project: Fixture.Project
    let hover: Bool

    var body: some View {
        let size = DuoMetric.sessionListProjectPlusSize
        HStack(spacing: 4) {
            Text("+").duoText(.body).foregroundStyle(hover ? DuoColor.text : DuoColor.text2)
            if hover { Text("New session").duoText(.control).foregroundStyle(DuoColor.text).fixedSize() }
        }
        .padding(.horizontal, hover ? 7 : 0)
        .frame(minWidth: size, minHeight: size, maxHeight: size)
        .background(RoundedRectangle(cornerRadius: DuoMetric.sessionListProjectPlusRadius).fill(hover ? DuoColor.selected : Color.clear))
        .contentShape(Rectangle())
        .duoAnimation(.chipIn, value: hover)
        .onHover { inside in
            if inside { model.boardNewSessionHover = project.name } else if model.boardNewSessionHover == project.name { model.boardNewSessionHover = nil }
        }
        .onActivate { model.newSessionFromHeader(project.name) }  // action: session new
        .help("New session in \(project.name)\n\(BoardText.folder(project))")
        .accessibilityLabel("New session in \(project.name)")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("board.plus.\(project.name)")
    }
}

/// A tile's last row (T1): a quiet "+ New session" under a hairline; ⌘T beside it while the tile is focused;
/// Make a Project at its right for a folder with no project file. Starts a session in the tile's folder
/// and opens the project's page on it.
struct TileNewSessionRow: View {
    @Environment(AppModel.self) private var model
    let project: Fixture.Project

    var body: some View {
        let hover = model.boardNewSessionHover == project.name
        let focused = model.focusedTile == project.name
        VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(DuoColor.rule).frame(height: DuoMetric.borderHairline)
                .padding(.top, DuoMetric.mapNewSessionRowGap)
            HStack(spacing: DuoSpace.gapRowItems) {
                HStack(spacing: DuoSpace.gapRowItems) {
                    Text("+").duoText(.body).frame(width: 14)
                    Text("New session").duoText(.body).lineLimit(1)
                    Spacer(minLength: 4)
                    if focused && !hover { Text("⌘T").duoText(.control).fixedSize() }
                }
                .foregroundStyle(hover ? DuoColor.text : DuoColor.text2)
                .frame(maxHeight: .infinity)
                .padding(.horizontal, hover ? 6 : 0)
                .background { if hover { RoundedRectangle(cornerRadius: DuoMetric.radiusSelection).fill(DuoColor.selected) } }
                .padding(.horizontal, hover ? -6 : 0)
                .contentShape(Rectangle())
                .onHover { inside in
                    if inside { model.boardNewSessionHover = project.name } else if model.boardNewSessionHover == project.name { model.boardNewSessionHover = nil }
                }
                .onActivate { model.newSessionFromHeader(project.name) }  // action: session new
                .help("New session in \(project.name)\n\(BoardText.folder(project))")
                .accessibilityLabel("New session in \(project.name)")
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("board.new-session.\(project.name)")
                if project.isFolderOnly && !project.isMissing {
                    Text("Make a Project").duoText(.body).underline().foregroundStyle(DuoColor.text).fixedSize()
                        .contentShape(Rectangle())
                        .onActivate { model.makeProject(project.name) }  // action: project make
                        .accessibilityAddTraits(.isButton)
                }
            }
            .frame(height: DuoMetric.mapNewSessionRowHeight)
        }
    }
}

/// The words the Board's tiles and rows share.
enum BoardText {
    /// A project's folder with the home folder as `~`.
    static func folder(_ p: Fixture.Project) -> String { (p.path as NSString).abbreviatingWithTildeInPath }

    /// A row's status: the health and next step, or what a folder with no project file has.
    static func status(_ p: Fixture.Project) -> String {
        if p.isMissing { return p.missing ?? "Folder not found" }
        if p.isFolderOnly { return p.hasClaudeMD == true ? "Has CLAUDE.md · no project file" : "No project file" }
        return [p.health, p.next].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}
