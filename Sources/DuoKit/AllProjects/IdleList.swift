import AppKit
import SwiftUI

/// What `14 idle, resumable ›` opens (surfaces-handoff DB-1, Q-11): a popover from the map's
/// footer listing every idle, resumable session, newest first, grouped by when.
public struct IdleRow: Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var project: String?
    public var unfiled = false
    public var archived = false
    public var group: String?
    public var age: String
    public var seconds: Int
    /// Live in another app (LR-8): listed so it can be found, not resumable.
    public var openIn: String?

    public init(id: String, name: String, project: String?, unfiled: Bool = false, archived: Bool = false, group: String? = nil,
                age: String, seconds: Int, openIn: String? = nil) {
        self.id = id; self.name = name; self.project = project; self.unfiled = unfiled; self.archived = archived
        self.group = group; self.age = age; self.seconds = seconds; self.openIn = openIn
    }
}

extension AppModel {
    /// Idle sessions not running in Duo (DL-55: a running, quiet one isn't listed).
    public func idleRows() -> [IdleRow] {
        if let fixed = fixtureIdle { return fixed }
        let folders = Set(fixture.projects.filter(\.isFolderOnly).map(\.name))
        return fixture.sessions.compactMap { s -> IdleRow? in
            guard s.state == .idle || s.state == .resolved, terminals.existing(s.tabKey) == nil else { return nil }
            let group = fixture.groups.first { $0.project == s.project && $0.sessions.contains(s.name) }?.name
            let elsewhere = s.sessionId.map { liveElsewhere.contains($0) } ?? false
            return IdleRow(id: s.tabKey, name: s.name, project: folders.contains(s.project) ? nil : s.project,
                           unfiled: folders.contains(s.project), archived: false, group: group,
                           age: s.wait ?? "", seconds: WaitTime(s.wait).seconds, openIn: elsewhere ? "Terminal" : nil)
        }
        .sorted { $0.seconds < $1.seconds }
    }

    /// This week, last week, then one bucket per month; a short tail is just "Earlier".
    public static func idleBuckets(_ rows: [IdleRow], now: Date = Date()) -> [(label: String, rows: [IdleRow])] {
        let cal = Calendar.current
        let weekStart = cal.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        let lastWeekStart = cal.date(byAdding: .day, value: -7, to: weekStart) ?? now
        var buckets: [(String, [IdleRow])] = [("This week", []), ("Last week", [])]
        var older: [IdleRow] = []
        for r in rows {
            let d = now.addingTimeInterval(-TimeInterval(r.seconds))
            if d >= weekStart { buckets[0].1.append(r) } else if d >= lastWeekStart { buckets[1].1.append(r) } else { older.append(r) }
        }
        if older.count <= 8 { buckets.append(("Earlier", older)) }
        else {
            let f = DateFormatter(); f.dateFormat = "LLLL"
            for r in older {
                let label = f.string(from: now.addingTimeInterval(-TimeInterval(r.seconds)))
                if let i = buckets.firstIndex(where: { $0.0 == label }) { buckets[i].1.append(r) } else { buckets.append((label, [r])) }
            }
        }
        return buckets.filter { !$0.1.isEmpty }.map { (label: $0.0, rows: $0.1) }
    }

    /// The list's buckets: the fixture's own in fixture mode (its sample ages don't follow calendar
    /// weeks), else calendar weeks and months.
    public func idleGroups() -> [(label: String, rows: [IdleRow])] {
        fixtureIdleBuckets ?? Self.idleBuckets(idleRows())
    }

    public func toggleIdleList() {
        idleOpen.toggle()
        idleSelection = 0
        if idleOpen { IdleKeys.install(self) } else { IdleKeys.remove() }
    }

    /// Return resumes: the project opens with that session in the console (DB-1).
    func resumeIdle(_ r: IdleRow, openOnly: Bool = false) {
        toggleIdleList()
        guard let project = r.project ?? fixture.sessions.first(where: { $0.tabKey == r.id })?.project else { return }
        if openOnly || r.openIn != nil { open(project: project) } else {
            open(project: project, session: r.name)
            if consoleTab != r.id { consoleTab = r.id }
        }
    }
}

/// ↑↓ move, Return resumes, ⌘↩ opens the project, Esc closes, letters jump to a title (DB-1).
@MainActor
enum IdleKeys {
    nonisolated(unsafe) static var monitor: Any?
    static func install(_ model: AppModel) {
        remove()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak model] e in
            let code = e.keyCode, flags = e.modifierFlags, chars = e.charactersIgnoringModifiers
            // NSEvent isn't Sendable: decide on the main actor from plain values, return the event here.
            let used = MainActor.assumeIsolated { model.map { handle($0, code: code, flags: flags, chars: chars) } ?? false }
            return used ? nil : e
        }
    }

    static func handle(_ model: AppModel, code: UInt16, flags: NSEvent.ModifierFlags, chars: String?) -> Bool {
        guard model.idleOpen else { return false }
        let rows = model.idleGroups().flatMap(\.rows)
        switch code {
        case 125: model.idleSelection = min(rows.count - 1, model.idleSelection + 1)
        case 126: model.idleSelection = max(0, model.idleSelection - 1)
        case 36, 76:
            if rows.indices.contains(model.idleSelection) { model.resumeIdle(rows[model.idleSelection], openOnly: flags.contains(.command)) }
        case 53: model.toggleIdleList()
        default:
            guard let c = chars?.lowercased().first, c.isLetter || c.isNumber, flags.intersection([.command, .control]).isEmpty, !rows.isEmpty else { return false }
            let start = min(model.idleSelection + 1, rows.count)
            let order = Array(rows.indices[start...]) + Array(rows.indices[..<start])
            if let i = order.first(where: { rows[$0].name.lowercased().hasPrefix(String(c)) }) { model.idleSelection = i }
        }
        return true
    }
    static func remove() { if let m = monitor { NSEvent.removeMonitor(m) }; monitor = nil }
}

/// The map's footer: a button that opens the list (DB-1).
struct IdleFooter: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let n = model.fixture.counts.idle
        let open = model.idleOpen
        HStack(spacing: DuoSpace.gapRowItems) {
            StateGlyph(.idle)
            Text("\(n) idle, resumable").duoText(.body, weight: open ? .semibold : nil)
                .foregroundStyle(open ? DuoColor.text : DuoColor.text2)
            Chevron(direction: .down, color: open ? DuoColor.text : DuoColor.text2)
                .frame(width: 10, height: 8)
                .rotationEffect(.degrees(open ? 180 : -90))
        }
        .foregroundStyle(DuoColor.text2)
        .padding(.horizontal, DuoSpace.panePadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: DuoMetric.overviewFooterHeight)
        .contentShape(Rectangle())
        .onActivate { if n > 0 { model.toggleIdleList() } }  // action: idle
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(n) idle sessions")
        .accessibilityAddTraits(.isButton)
    }
}

/// The list: 460 wide, above the footer's left end, arrow down at it (DB-1).
struct IdleListPopover: View {
    @Environment(AppModel.self) private var model
    let maxHeight: CGFloat

    var body: some View {
        let buckets = model.idleGroups()
        let rows = buckets.flatMap(\.rows)
        let flat = buckets.flatMap(\.rows)
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(text: "Idle, resumable", count: rows.count).padding(EdgeInsets(top: 0, leading: 8, bottom: 2, trailing: 8))
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(buckets, id: \.label) { b in
                            SectionLabel(text: b.label, count: b.rows.count).padding(EdgeInsets(top: 8, leading: 8, bottom: 2, trailing: 8))
                            ForEach(b.rows) { r in
                                let i = flat.firstIndex(of: r) ?? 0
                                IdleRowView(row: r, selected: i == model.idleSelection)
                                    .id(r.id)
                                    .onActivate { model.idleSelection = i; model.resumeIdle(r) }  // action: session open
                                    .modifier(SessionOrganizeMenu(sessionKey: r.id))
                            }
                        }
                    }
                }
                .onChange(of: model.idleSelection) { _, i in if flat.indices.contains(i) { proxy.scrollTo(flat[i].id) } }
            }
            .frame(maxHeight: maxHeight)
            .fixedSize(horizontal: false, vertical: true)
            // The keys, then the way to older sessions on its own line (the target's flex-wrap at 460).
            VStack(alignment: .trailing, spacing: 14) {   // flex-wrap's gap applies between the lines too
                HStack(spacing: 14) {
                    Text("↑↓ Select"); Text("↩ Resume"); Text("⌘↩ Open project"); Text("esc Close")
                    Spacer(minLength: 0)
                }
                Text("Older? Search ⇧⌘A").onActivate { model.toggleIdleList(); model.openSearch() }  // action: search
            }
            .duoText(.control)
            .foregroundStyle(DuoColor.text2)
            .padding(.top, 10)
            .overlay(alignment: .top) { Rectangle().fill(DuoColor.rule).frame(height: DuoMetric.borderHairline) }
            .padding(EdgeInsets(top: 10, leading: 8, bottom: 0, trailing: 8))
        }
        .padding(DuoMetric.idlePopoverPadding)
        .frame(width: DuoMetric.idlePopoverWidth)
        .background(RoundedRectangle(cornerRadius: DuoMetric.radiusPopover).fill(DuoColor.pane))
        .overlay(RoundedRectangle(cornerRadius: DuoMetric.radiusPopover).strokeBorder(DuoColor.rule, lineWidth: DuoMetric.borderHairline))
        .overlay(alignment: .bottomLeading) { PopoverArrow().frame(width: 12, height: 12).offset(x: 44, y: 7) }
        .duoPopoverShadow()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Idle sessions")
    }
}

struct IdleRowView: View {
    let row: IdleRow
    let selected: Bool

    var body: some View {
        HStack(spacing: 8) {
            StateGlyph(.idle)
            Text(row.name).duoText(.body).foregroundStyle(row.openIn == nil ? DuoColor.text : DuoColor.text2)
                .lineLimit(1).truncationMode(.tail).layoutPriority(1)
            if let g = row.group {
                Text(g).duoText(.pill).foregroundStyle(DuoColor.text)
                    .padding(.horizontal, 7 + DuoMetric.borderHairline).padding(.vertical, DuoMetric.borderHairline)
                    .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(DuoColor.rule, lineWidth: DuoMetric.borderHairline))
                    .fixedSize()
            }
            if row.archived { Pill(text: "archived") }
            Spacer(minLength: 8)
            Group {
                if row.unfiled { Pill(text: "Unfiled") }
                else if let p = row.project { Text(p).duoText(.body).foregroundStyle(DuoColor.text2).lineLimit(1).truncationMode(.tail) }
            }
            .frame(maxWidth: DuoMetric.idleProjectColumnMax, alignment: .trailing)
            .fixedSize(horizontal: row.project.map { ($0 as NSString).size(withAttributes: [.font: DuoTextStyle.body.spec.nsFont]).width <= DuoMetric.idleProjectColumnMax } ?? true, vertical: false)
            Text(row.openIn.map { "open in \($0)" } ?? row.age).duoText(.body).foregroundStyle(DuoColor.text2)
                .frame(minWidth: DuoMetric.idleAgeColumn, alignment: .trailing)
                .fixedSize()
        }
        .padding(.horizontal, 8)
        .frame(height: DuoMetric.idleRowHeight)
        .background(RoundedRectangle(cornerRadius: DuoMetric.idleRowRadius).fill(selected ? DuoColor.selected : .clear))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel([row.name, row.group.map { "in \($0)" }, row.unfiled ? "Unfiled" : row.project, row.openIn.map { "open in \($0)" } ?? "idle \(row.age)"]
            .compactMap { $0 }.joined(separator: ", "))
    }
}

/// A popover's arrow: a 12 pt square turned 45°, `pane` with the border on its two outer sides.
struct PopoverArrow: View {
    var body: some View {
        ZStack {
            Rectangle().fill(DuoColor.pane)
            Path { p in p.move(to: .init(x: 12, y: 0)); p.addLine(to: .init(x: 12, y: 12)); p.addLine(to: .init(x: 0, y: 12)) }
                .stroke(DuoColor.rule, lineWidth: DuoMetric.borderHairline)
        }
        .rotationEffect(.degrees(45))
        .accessibilityHidden(true)
    }
}
