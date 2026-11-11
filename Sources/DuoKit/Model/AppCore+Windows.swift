import AppKit
import DuoControl
import Foundation

/// Multi-window slice 1 (DL-311): the window set, a project in one window (DL-308), Home in one window
/// (Q-431), window colours (DL-312, DL-313), and which window a `duo2` request acts on (Q-430).
/// The windows themselves are AppKit's, made by the app (`windowMaker`); everything here runs without
/// them, so the checks drive two or more models on one core.
extension AppCore {
    // MARK: - Finding a window

    /// The window showing `project`, by its altitude (DL-308: there is at most one).
    public func model(showing project: String) -> AppModel? {
        models.first { $0.altitude == .project(project) }
    }

    /// Window `n` by its number (`AppModel.windowNumber`).
    public func model(number n: Int) -> AppModel? {
        models.first { $0.windowNumber == n }
    }

    /// `--window <n|project>` and `duo2 window focus|close <n|project>`: a number, else a project a window shows.
    public func model(named s: String) -> AppModel? {
        if let n = Int(s) { return model(number: n) }
        if let m = model(showing: s) { return m }
        let lower = s.lowercased()
        return models.first { $0.currentProject?.name.lowercased() == lower }
    }

    /// The lowest number no open window has (window 1 first).
    public func freeWindowNumber() -> Int {
        let taken = Set(models.map(\.windowNumber))
        return (1...).first { !taken.contains($0) }!
    }

    // MARK: - Opening, bringing forward, closing

    /// File › New Window (⌥⌘N), Project › Open in New Window, `duo2 window new [<project>]` (DL-311, board 1 A).
    /// With a project another window shows, that window comes forward instead (DL-308). The new window
    /// opens at All projects or on the project, with the next free colour while colouring is on (DL-312).
    @discardableResult
    public func openWindow(project: String? = nil) -> AppModel {
        if let project, let m = model(showing: project) { bringForward(m); return m }
        // The last window closed, so it only hid (F-538): New Window brings it back as the new window, at All
        // projects or on the project, numbered 1 again, instead of opening a second beside it (Q-460).
        if let hidden = models.first(where: \.hiddenByClose), models.allSatisfy(\.hiddenByClose) {
            hidden.hiddenByClose = false
            hidden.windowNumber = 1
            if let project { hidden.open(project: project) } else if !hidden.altitude.isAllProjects { hidden.zoomOut() }
            count("openWindow")
            bringForward(hidden)
            return hidden
        }
        let m = AppModel(core: self, number: freeWindowNumber())
        opened.append(m)   // the core owns a window it opened until the window closes
        if colourNewWindows { m.windowColourID = Self.nextColour(taken: models.filter { $0 !== m }.map(\.windowColourID)).id }
        if let project { m.open(project: project) }
        count("openWindow")
        windowMaker?(m)
        bringForward(m)
        return m
    }

    /// Brings a window forward (DL-308): the app shows it, makes it key and records which.
    public func bringForward(_ m: AppModel) {
        focusLog.append(m.windowNumber)
        m.hiddenByClose = false
        keyWindowID = m.windowID ?? keyWindowID
        windowFocuser?(m)
    }

    /// Close Window (⇧⌘W) and `duo2 window close`: a second window closes; its projects keep their tabs and
    /// sessions (they're the core's). The last window only hides, as today (v1's teardown bug, F-538).
    /// Returns false for the last window.
    @discardableResult
    public func closeWindow(_ m: AppModel) -> Bool {
        guard models.count > 1 else { m.hiddenByClose = true; windowHider?(m); return false }
        m.rememberTabs()
        windowCloser?(m)
        detach(m)
        return true
    }

    /// Forgets a window that closed; the key window moves on.
    public func detach(_ m: AppModel) {
        m.rememberTabs()
        registered.removeAll { $0.model == nil || $0.model === m }
        opened.removeAll { $0 === m }
        if keyWindowID != nil, keyWindowID == m.windowID { keyWindowID = primary?.windowID }
        count("closeWindow")
    }

    // MARK: - Colours (DL-312, DL-313)

    /// The colour a new window takes: the first in DL-313's order no open window has; with all taken, the
    /// one the fewest windows have, first in the order (4b's "round again", Q-444).
    public static func nextColour(taken: [String?]) -> DuoWindowColour.Colour {
        let counts = Dictionary(taken.compactMap { $0 }.map { ($0, 1) }, uniquingKeysWith: +)
        let least = DuoWindowColour.all.map { counts[$0.id] ?? 0 }.min() ?? 0
        return DuoWindowColour.all.first { (counts[$0.id] ?? 0) == least }!
    }

    /// "Colour new windows automatically" (DL-312), on by default, saved in Duo's state.
    public var colourNewWindows: Bool {
        get { colourNewWindowsSetting }
        set { setColourNewWindows(newValue, save: true) }
    }

    /// The switch, saved unless `save` is false (the checks never write Duo's state).
    public func setColourNewWindows(_ on: Bool, save: Bool) {
        colourNewWindowsSetting = on
        if save { try? DuoState.write { $0.colourNewWindows = on } }
    }

    // MARK: - Which window a duo2 request acts on (Q-430)

    /// `--window <n|project>` if given (taken out of the arguments), else the window that shows the caller's
    /// session (its project's window; Home's session, Home's window), else the primary. Never the key window.
    public func target(for req: ControlRequest) -> (model: AppModel?, request: ControlRequest, error: String?) {
        var r = req
        var named: String?
        var args: [String] = []
        var i = 0
        while i < req.args.count {
            let a = req.args[i]
            if a == "--window", i + 1 < req.args.count { named = req.args[i + 1]; i += 2; continue }
            if a.hasPrefix("--window=") { named = String(a.dropFirst("--window=".count)); i += 1; continue }
            args.append(a); i += 1
        }
        r.args = args
        if let named {
            guard let m = model(named: named) else {
                return (nil, r, "no window '\(named)'. Open windows: " + models.map { "\($0.windowNumber) \($0.windowTitle)" }.joined(separator: ", "))
            }
            return (m, r, nil)
        }
        return (callerWindow(session: req.session) ?? primary, r, nil)
    }

    /// The window that shows the caller's session: the window on its project (Home's page, for Home's).
    func callerWindow(session: String?) -> AppModel? {
        guard let session, let s = fixture.sessions.first(where: { $0.sessionId == session || $0.tabKey == session }) else { return nil }
        return model(showing: s.project)
    }

    // MARK: - C-150: what the app-wide passes need from every window

    /// The sessions on screen in any window (notify skips these, C-150).
    public var visibleSessionIds: Set<String> {
        Set(models.compactMap(\.visibleSessionId))
    }

    /// The window a notification click, a shell that ended, or voice acts through: the project's window
    /// when one shows it, else the key window, else the primary.
    public func model(forProject project: String?) -> AppModel? {
        project.flatMap { model(showing: $0) } ?? keyModel
    }
}

extension AppModel {
    /// A window's model with its number (`AppCore.openWindow`).
    convenience init(core: AppCore, number: Int) {
        self.init(core: core)
        windowNumber = number
    }

    /// The window's title (DL-311): its project's name, or "Duo" at All projects. macOS lists windows by it.
    public var windowTitle: String { currentProject?.name ?? "Duo" }

    /// The last window, closed: it only hid (Duo keeps running, F-538). New Window or a Dock click brings it back (Q-460).
    public var hiddenByClose: Bool {
        get { core.hiddenWindows.contains(ObjectIdentifier(self)) }
        set { if newValue { core.hiddenWindows.insert(ObjectIdentifier(self)) } else { core.hiddenWindows.remove(ObjectIdentifier(self)) } }
    }

    /// The window's colour as drawn: nil (None) when it has none, and while Classic is on (DL-312, board 4c A).
    public var windowColour: DuoWindowColour.Colour? {
        guard !core.classicOn, let id = windowColourID else { return nil }
        return DuoWindowColour.all.first { $0.id == id }
    }

    /// Window › Window Colour, the toolbar swatch, `duo2 window colour` (DL-312): nil is None.
    public func setWindowColour(_ id: String?) {
        windowColourID = id
    }
}
