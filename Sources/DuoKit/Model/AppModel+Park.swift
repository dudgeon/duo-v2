import Foundation

// Parking sessions on demand (DL-192, park-handoff): the Session menu, a tab's right-click menu,
// `duo2 session park`, and the question under memory pressure.

extension AppModel {
    // MARK: Keep Running

    /// The session id a tab key stands for: the key itself when it is one.
    func sessionID(forTab key: String) -> String? {
        fixture.sessions.first { $0.tabKey == key }?.sessionId ?? (isShell(key) ? nil : key)
    }

    public func isKeepRunning(_ key: String) -> Bool {
        sessionID(forTab: key).map(keepRunningIDs.contains) ?? false
    }

    /// Reads the pins from Duo's state (launch, and the checks' second "launch").
    public func loadKeepRunning() { keepRunningIDs = Set(DuoState.load().keepRunning) }

    /// Keep Running on or off. On wakes a tab that is parked, so the pin means it is running.
    public func setKeepRunning(_ key: String, _ on: Bool) {
        guard !isShell(key), let id = sessionID(forTab: key) else { return }
        if on { keepRunningIDs.insert(id) } else { keepRunningIDs.remove(id) }
        let all = keepRunningIDs.sorted()
        DuoState.update { $0.keepRunning = all }
        if on, parkedTabs.contains(key) { wakeParked(key) }
    }

    // MARK: Eligibility

    func parkInputs(_ key: String) -> ParkInputs {
        var i = ParkInputs()
        i.isShell = isShell(key)
        guard !i.isShell else { return i }
        let t = terminals.existing(key)
        i.hasTerminal = t.map { !$0.exited } ?? false
        i.parked = parkedTabs.contains(key)
        i.keepRunning = isKeepRunning(key)
        i.state = fixture.sessions.first { $0.tabKey == key }?.state
        i.onScreen = visibleSessionId == key
        if i.hasTerminal, let t {
            if let pid = t.view.process?.shellPid, pid > 0 { i.children = parkChildren(pid) }
            if let id = sessionID(forTab: key) { i.events = parkEvents(id) }
        }
        return i
    }

    /// Nil when the tab can park. `bulk` also keeps the tab on screen.
    public func parkBlock(_ key: String, bulk: Bool = false) -> ParkBlock? {
        ParkCheck.why(parkInputs(key), bulk: bulk)
    }

    /// Every tab that could park now without being asked: running, not on screen, not busy, not pinned.
    public func parkCandidates() -> [Fixture.Session] {
        fixture.sessions.filter { s in
            terminals.existing(s.tabKey) != nil && parkBlock(s.tabKey, bulk: true) == nil
        }
    }

    // MARK: Park

    /// Parks one tab: ends its Claude, keeps the tab, resumes it when shown. The tab on screen first
    /// gives its pane to the next tab, and a pane with no other tab refuses. Nil when parked.
    @discardableResult
    public func park(_ key: String) -> ParkBlock? {
        if let why = parkBlock(key) { return why }
        let s = fixture.sessions.first { $0.tabKey == key }
        if visibleSessionId == key {
            guard let s, let next = consoleTabKeys(inProject: s.project).first(where: { $0 != key }) else { return .onScreen }
            if homeTab == key { homeTab = next }
            if consoleTab == key { consoleTab = next }
        }
        terminals.close(key)
        chats.forget(key)
        parkedTabs.insert(key)
        fixture = fixture   // the strips redraw
        return nil
    }

    public struct ParkReport {
        public var parked: [Fixture.Session] = []
        public var kept: [(session: Fixture.Session, block: ParkBlock)] = []
        public var text: String { ParkCheck.notice(parked: parked.count, kept: kept.map { ($0.session.name, $0.block) }) }
    }

    /// Park Background Sessions: every running tab that isn't on screen and can park. What stays
    /// because of what it's doing (or a pin) is reported with its reason; shells, parked tabs and
    /// the tab on screen are not.
    @discardableResult
    public func parkBackground(notify: Bool = true) -> ParkReport {
        var report = ParkReport()
        for s in fixture.sessions where terminals.existing(s.tabKey) != nil && !isShell(s.tabKey) {
            switch parkBlock(s.tabKey, bulk: true) {
            case nil:
                if park(s.tabKey) == nil { report.parked.append(s) }
            case .some(.shell), .some(.notRunning), .some(.alreadyParked), .some(.onScreen):
                break
            case .some(let why):
                report.kept.append((s, why))
            }
        }
        if notify { info(report.text) }
        return report
    }

    // MARK: Memory pressure

    /// How long a session has sat at its prompt: `45m`, `2h`, `1d`.
    func idleFor(_ s: Fixture.Session) -> String? { Attention.waitText(since: s.lastActive) }

    /// The question under critical memory pressure (park-handoff, memory-question A).
    public func parkQuestion(_ sessions: [Fixture.Session]) -> DuoQuestion {
        let n = sessions.count
        let count = n == 1 ? "1 idle session" : "\(n) idle sessions"
        var q = DuoQuestion(title: "Your Mac is low on memory. Park \(count)?", choices: [])
        q.paragraphs = ["Parking ends Claude in tabs you aren’t looking at. Each tab stays, and its session picks up where it left off when you show it."]
        let shown = n > 6 ? Array(sessions.prefix(5)) : sessions
        q.items = shown.map { s in .init(what: s.name, path: "", detail: [s.project, idleFor(s)].compactMap { $0 }.joined(separator: " · ")) }
        if n > 6 { q.items.append(.init(what: "and \(n - 5) more", path: "")) }
        q.note = "Tabs that are working, waiting on you, running something in the background, or set to Keep Running stay as they are."
        q.choices = [
            .init(label: "Not Now", isCancel: true) {},
            // Eligibility is read again when the answer comes: a tab may have started working since.
            .init(label: n == 1 ? "Park 1 Session" : "Park \(n) Sessions", isDefault: true) { [weak self] in self?.parkBackground(notify: false) },
        ]
        return q
    }

    /// Asks (or, in a scripted run, takes the default and logs) once the episode calls for it.
    public func askPark() {
        let sessions = parkCandidates().sorted { ($0.lastActive ?? 0) < ($1.lastActive ?? 0) }
        guard !sessions.isEmpty else { return }
        ask(parkQuestion(sessions))
    }

    /// The episode's state machine, wired to this model (also driven by the harness's `memory-pressure:`).
    public func makeParkPressure() -> ParkPressure {
        let p = ParkPressure()
        p.eligible = { [weak self] in self?.parkCandidates().count ?? 0 }
        p.sheetUp = { SheetCenter.shared.current != nil }
        p.ask = { [weak self] in self?.askPark() }
        parkPressure = p
        return p
    }

    /// macOS's memory-pressure signal, live mode only (a capture or fixture run never calls this).
    func startMemoryPressureWatch() {
        guard pressureSource == nil else { return }
        let p = makeParkPressure()
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.normal, .warning, .critical], queue: .main)
        source.setEventHandler { [weak self, weak source] in
            guard let event = source?.data else { return }
            MainActor.assumeIsolated {
                self?.parkPressure?.changed(to: event.contains(.critical) ? .critical : event.contains(.warning) ? .warning : .normal)
            }
        }
        source.resume()
        pressureSource = source
    }
}
