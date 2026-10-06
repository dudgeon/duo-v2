import AppKit
import DuoControl
import DuoSearch
import Foundation

/// What each `duo2` verb does in the app (DL-71, DL-72). The verbs and their help are the action
/// registry (`DuoAction.all`); this is their behaviour, calling the same model methods the UI
/// uses. `DuoChecks` fails if an app verb has no case here.
extension AppModel {
    public struct Reply {
        public var ok: Bool
        public var text: String
        public var json: Any?
        public static func ok(_ text: String, _ json: Any? = nil) -> Reply { Reply(ok: true, text: text, json: json) }
        public static func fail(_ text: String) -> Reply { Reply(ok: false, text: text, json: nil) }
    }

    /// Verbs the app answers (everything not `local`); for the check.
    public static let appVerbs: Set<ActionID> = Set(DuoAction.all.filter { !$0.local }.map(\.id))

    public func handle(_ req: ControlRequest, done: @escaping @MainActor (ControlResponse) -> Void) {
        guard let (action, rest) = DuoAction.resolve([req.command] + req.args) else {
            return done(.init(ok: false, output: "unknown command '\(req.command)'. Run `duo2 help`."))
        }
        let inv = Invocation(rest)
        perform(action.id, inv, req) { r in
            if r.ok, inv.json, let j = r.json ?? (r.text as Any?),
               let data = try? JSONSerialization.data(withJSONObject: j is String ? ["result": j] : j, options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed]) {
                done(.init(ok: true, output: String(decoding: data, as: UTF8.self)))
            } else {
                done(.init(ok: r.ok, output: r.text))
            }
        }
    }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    func perform(_ id: ActionID, _ inv: Invocation, _ req: ControlRequest, _ done: @escaping @MainActor (Reply) -> Void) {
        switch id {
        // MARK: Duo
        case .ping:
            done(.ok("Duo \(getpid()), \(terminalsMode == .live ? "live" : "fixture"), \(fixture.projects.count) projects"))
        case .status:
            done(statusReply())
        case .needsYou:
            let list = fixture.needsYou
            let lines = list.map { s in "\(s.project) / \(s.name)" + (s.wait.map { " · \($0)" } ?? "") + (s.question.map { "\n  \($0)" } ?? "") }
            done(.ok(lines.isEmpty ? "Nothing needs you." : lines.joined(separator: "\n"), list.map(sessionJSON)))
        case .undo:
            guard let m = NSApp.windows.first(where: { $0.title == "Duo" })?.undoManager, m.canUndo else { return done(.fail("nothing to undo")) }
            let name = m.undoActionName
            m.undo()
            done(.ok("Undid \(name.isEmpty ? "the last change" : name)."))

        // MARK: What's on screen
        case .goAll: zoomOut(); done(.ok("Showing All projects."))
        case .goHome: goHome(); done(.ok("Showing Home."))
        case .open:
            guard let name = inv[0] else { return done(.fail("usage: \(id.action.usage)")) }
            guard let p = project(named: name) else { return done(.fail("no project '\(name)'")) }
            var session: String?
            if let s = inv[1] { guard let found = findSession(s, in: p.name) else { return done(.fail("no session '\(s)' in \(p.name)")) }; session = found.name }
            open(project: p.name, session: session)
            if let f = inv.flags["file"] {
                guard let rel = relativePath(f, project: p.name, cwd: req.cwd) else { return done(.fail("'\(f)' isn't in \(p.name)")) }
                openDocument(rel)
            }
            done(.ok("Opened \(p.name)."))
        case .peek:
            let want = inv[0].map { $0 == "open" } ?? !peekOpen
            if want != peekOpen { togglePeek() }
            done(.ok(peekOpen ? "Peek open." : "Peek closed."))
        case .peekJump:
            guard peekOpen else { return done(.fail("the peek isn't open")) }
            jumpToPeekSelection(); done(.ok("Jumped."))
        case .viewSidebar:
            switch inv[0] { case "show": leftCollapsed = false; case "hide": leftCollapsed = true; default: leftCollapsed.toggle() }
            done(.ok(leftCollapsed ? "Left pane hidden." : "Left pane showing."))
        case .viewSort:
            guard let s = inv[0].flatMap(MapSort.init(rawValue:)) else { return done(.fail("usage: \(id.action.usage)")) }
            setMapSort(s)
            done(.ok("All projects sorted by \(s.title.lowercased())."))
        case .viewFilter:
            mapFilter = inv.positional.joined(separator: " ")
            let m = mapLayout
            done(.ok(mapFilter.isEmpty ? "Filter cleared." : "\(m.shown) of \(m.total) match '\(mapFilter)'."))
        case .viewHidden:
            switch inv[0] { case "on": setShowHiddenFiles(true); case "off": setShowHiddenFiles(false); default: setShowHiddenFiles(!showHiddenFiles) }
            done(.ok(showHiddenFiles ? "Hidden files showing." : "Hidden files hidden."))
        case .viewFolder:
            guard let f = inv[0], currentProject != nil else { return done(.fail(currentProject == nil ? "no project is open" : "usage: \(id.action.usage)")) }
            let path = f.hasSuffix("/") ? String(f.dropLast()) : f
            if (inv[1] == "open") != isFolderOpen(path) { toggleFolder(path) }
            done(.ok("\(path)/ \(isFolderOpen(path) ? "open" : "closed")."))
        case .viewTab:
            guard let tab = inv[0] else { return done(.fail("usage: \(id.action.usage)")) }
            guard currentProject != nil else { return done(.fail("no project is open")) }
            if tab == "Project" { rightTab = "Project" } else if openDocuments.contains(tab) || fixture.groups.contains(where: { $0.name == tab }) {
                rightTab = tab; if openDocuments.contains(tab) { selectedFile = tab }
            } else { return done(.fail("no tab '\(tab)'. Tabs: \((["Project"] + openDocuments).joined(separator: ", "))")) }
            done(.ok("Showing \(tab)."))
        case .viewGroup:
            guard let g = inv[0] else { return done(.fail("usage: \(id.action.usage)")) }
            let key = expandedGroups.first { $0.hasSuffix(g) } ?? g
            if inv[1] == "collapse" { expandedGroups.remove(key) } else { expandedGroups.insert(key) }
            done(.ok(inv[1] == "collapse" ? "Collapsed \(g)." : "Expanded \(g)."))
        case .viewSelect:
            guard let s = inv[0].flatMap({ findSession($0, in: nil) }) else { return done(.fail("no session '\(inv[0] ?? "")'")) }
            if peekOpen { peekSelection = s.id } else { selectedActionSession = s.id }
            done(.ok("Selected \(s.name)."))

        // MARK: Projects
        case .projects:
            let ps = fixture.projects
            let lines = ps.map { p in
                (p.isHome == true ? "★ " : "") + p.name
                    + (p.isMissing ? " (missing: \(p.missing ?? "folder not found"); was at \(p.path))" : p.isFolderOnly ? " (folder, no project file)" : "")
                    + (p.staleSessions.map { " (\($0) session(s) still filed under \(p.movedFrom ?? "its old place"): duo2 project reconnect \(p.name))" } ?? "")
                    + (isArchived(p.name) ? " [archived]" : "") + (p.goal.isEmpty ? "" : " — \(p.goal)")
                    + ([p.health, p.next].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ").nonEmptyOrNil.map { " (\($0))" } ?? "")
            }
            done(.ok(lines.joined(separator: "\n"), ps.map(projectJSON)))
        case .projectShow:
            guard let name = inv[0] ?? projectFor(cwd: req.cwd)?.name, let p = project(named: name) else { return done(.fail("no project '\(inv[0] ?? "")'")) }
            let sessions = fixture.sessions(inProject: p.name)
            var j = projectJSON(p)
            j["sessions"] = sessions.map(sessionJSON)
            let text = (projectPayload(p.name) ?? p.name) + "\(sessions.count) sessions: " + sessions.prefix(10).map(\.name).joined(separator: ", ")
            done(.ok(text, j))
        case .projectMake:
            guard let name = inv[0], let p = project(named: name) else { return done(.fail("no folder '\(inv[0] ?? "")'")) }
            guard p.isFolderOnly else { return done(.fail("\(p.name) is already a project")) }
            if inv.has("not-now") {
                notNowProject(p.name)
                return done(.ok("\(p.name)'s Make a Project notice is hidden; its Project tab still offers it. Undo: duo2 undo"))
            }
            makeProject(p.name)
            done(.ok("\(p.name) is now a project (PROJECT.md written and opened). Undo: duo2 undo"))
        case .projectMerge:
            guard let s = inv[0], let target = inv.flags["into"] ?? inv[1], let src = project(named: s), let dst = project(named: target) else {
                return done(.fail("usage: \(id.action.usage)"))
            }
            let count = fixture.sessions(inProject: src.name).filter { $0.sessionId != nil }.count
            mergeProject(src.name, into: dst.name) { ok in
                done(ok ? .ok("Merged \(count) session(s) from \(src.name) into \(dst.name). Undo: duo2 undo") : .fail("Not merged: the user clicked Cancel in Duo, or there was nothing to move. Nothing changed and nothing is pending."))
            }

        // MARK: Sessions
        case .sessions:
            let project = inv.flags["project"].flatMap { project(named: $0)?.name }
            if inv.flags["project"] != nil, project == nil { return done(.fail("no project '\(inv.flags["project"]!)'")) }
            let list = (project.map { fixture.sessions(inProject: $0) } ?? fixture.sessions).filter { $0.sessionId != nil }
            let lines = list.map { s in "\(s.sessionId!.prefix(8))  \(stateWord(s.state).padding(toLength: 9, withPad: " ", startingAt: 0)) \(s.project) / \(s.name)" }
            done(.ok(lines.isEmpty ? "No sessions." : lines.joined(separator: "\n"), list.map(sessionJSON)))
        case .sessionShow:
            guard let key = inv[0] ?? req.session, let s = findSession(key, in: nil), let sid = s.sessionId else { return done(.fail("no session '\(inv[0] ?? "")'")) }
            var j = sessionJSON(s)
            var text = sessionPayload(s.tabKey) ?? s.name
            if let folder = liveFolders[s.project], let t = ClaudeStorage.transcript(sessionId: sid, cwd: folder.path) ?? (FileManager.default.fileExists(atPath: SessionArchive.copyURL(sid).path) ? SessionArchive.copyURL(sid) : nil) {
                let turns = SessionSource.read(t.path).turns
                let recent = turns.suffix(Int(inv.flags["turns"] ?? "3") ?? 3)
                j["turns"] = turns.count
                j["recent"] = recent.map { ["turn": $0.index, "text": String($0.text.prefix(1500))] }
                text += "\n\(turns.count) turns. Most recent:\n" + recent.map { "— turn \($0.index)\n\(String($0.text.prefix(1500)))" }.joined(separator: "\n")
            }
            done(.ok(text, j))
        case .sessionNew:
            let name = inv.flags["project"] ?? projectFor(cwd: req.cwd)?.name ?? currentProject?.name ?? fixture.home?.name
            guard let name, let p = project(named: name) else { return done(.fail("no project '\(name ?? "")'")) }
            guard let sid = newSession(in: p.name, prompt: inv.flags["prompt"]) else { return done(.fail("couldn't start a session in \(p.name)")) }
            if p.isHome == true, altitude.isAllProjects { homeTab = sid } else if currentProject?.name == p.name { consoleTab = sid }
            done(.ok("Started session \(sid) in \(p.name).", ["id": sid, "project": p.name]))
        case .sessionOpen:
            guard let k = inv[0], let s = findSession(k, in: nil) else { return done(.fail("no session '\(inv[0] ?? "")'")) }
            if s.project == fixture.home?.name, altitude.isAllProjects { homeTab = s.tabKey } else { open(project: s.project); openConsoleTab(s.tabKey) }
            done(.ok("Showing \(s.name)."))
        case .sessionClose:
            guard let k = inv[0] ?? visibleSessionId, let s = findSession(k, in: nil) ?? fixture.sessions.first(where: { $0.tabKey == k }) else { return done(.fail("no session to close")) }
            guard terminals.existing(s.tabKey) != nil else { return done(.fail("\(s.name) isn't running in Duo")) }
            closeSession(s.tabKey)
            done(.ok("Closed \(s.name). It stays listed and resumable."))
        case .projectArchive, .projectUnarchive:
            guard let name = inv[0], let p = project(named: name) else { return done(.fail(inv[0].map { "no project '\($0)'" } ?? "usage: \(id.action.usage)")) }
            let on = id == .projectArchive
            guard isArchived(p.name) != on else { return done(.ok("\(p.name) is already \(on ? "archived" : "in its column").")) }
            setArchived(p.name, on)
            done(.ok(on ? "Archived \(p.name): it's in the Archived rollup under the map. Undo: duo2 undo" : "\(p.name) is back in its column."))
        case .browserTabs, .browserRead, .browserClick, .browserFill, .browserWait, .browserScreenshot, .browserGo, .browserBack, .browserForward, .browserClose,
             .browserZoom, .browserPrint, .browserUpload, .browserDownloads:
            browserVerb(id, inv, cwd: req.cwd, done)
        case .browserOpen:
            let u = inv[0].flatMap { AllowedSites.url(from: $0) }
            if inv[0] != nil, u == nil { return done(.fail("'\(inv[0]!)' isn't an address")) }
            guard let id = newBrowserTab(u), let tab = webTabs[id] else { return done(.fail("open a project first: browser tabs sit in its right pane")) }
            done(.ok(tab.blocked != nil ? "\(u!.host ?? "") isn't on the allow list: the tab offers Allow or Open in Browser (duo2 browser allow \(u!.host ?? ""))."
                     : u.map { "Opened \($0.absoluteString) in a browser tab." } ?? "Opened a new browser tab.", ["tab": id]))
        case .browserAllow:
            guard let h = inv[0] else { return done(.fail("usage: \(id.action.usage)")) }
            let host = URL(string: h)?.host ?? h
            done(.ok(AllowedSites.add(host) ? "\(host) is allowed: its pages open in Duo." : "\(host) was already allowed."))
        case .browserSites:
            let list = AllowedSites.load()
            done(.ok((list.isEmpty ? "No sites allowed yet (localhost always is)." : list.joined(separator: "\n")) + "\nThe list: \(AllowedSites.file.path)", ["sites": list]))
        case .update:
            checkForUpdates(userInitiated: true, open: inv.has("open")) { done(.ok($0, $1)) }
        case .tasks, .taskMake, .taskAdd, .taskNew, .taskSession, .taskStatus,
             .taskRename, .taskArchive, .taskUnarchive, .taskDelete, .taskMove, .taskLink, .taskReveal:
            taskVerb(id, inv, req, done)
        case .sessionTask:
            sessionTaskVerb(inv, req, done)
        case .sessionLink:
            guard let k = inv[0], let s = findSession(k, in: nil), let link = sessionLink(s.tabKey) else { return done(.fail(inv[0].map { "no session '\($0)'" } ?? "usage: \(id.action.usage)")) }
            done(.ok(link, ["link": link, "url": Self.sessionURL(s.sessionId ?? "")]))
        case .homeSet:
            guard let path = inv[0] else { return done(.fail("usage: \(id.action.usage)")) }
            let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath, relativeTo: req.cwd.map { URL(fileURLWithPath: $0) })
            if let why = setHome(url) { return done(.fail(why)) }
            done(.ok("Home is \(Self.short(url.standardizedFileURL.path)). Projects in it show on the map by the folder they sit in; everything else is still listed. Undo: duo2 undo"))
        case .projectMoveIntoHome:
            guard let name = inv[0], project(named: name) != nil else { return done(.fail(inv[0].map { "no project or folder '\($0)'" } ?? "usage: \(id.action.usage)")) }
            let into = inv.flags["into"]
            guard let place = homePlace(named: into) else {
                return done(.fail(liveRoot == nil ? "There's no Home folder yet: duo2 home set <folder>" : "Home has no topic folder '\(into ?? "")'. Choose from: \(homePlaces().map(\.label).joined(separator: ", "))"))
            }
            moveIntoHome(name, into: place) { r in
                switch r { case .success(let m): done(.ok(m)); case .failure(let e): done(.fail("\(e)")) }
            }
        case .settings:
            let st = DuoState.load()
            func show() -> String {
                let c = ClaudeLocator.resolve()
                return ["claude-path: \(st.claudePath ?? "auto") (runs \(c ?? "nothing found"))",
                        "notify: \(DuoState.load().notifyNeedsYou ? "on" : "off")", "dock-badge: \(DuoState.load().dockBadge ? "on" : "off")",
                        "home: \(liveRoot.map { Self.short($0.path) } ?? "none")"].joined(separator: "\n")
            }
            guard let key = inv[0] else { return done(.ok(show())) }
            guard let value = inv[1] else { return done(.fail("usage: \(id.action.usage)")) }
            switch key {
            case "claude-path":
                if value == "auto" { setClaudePath(nil) }
                else {
                    let path = (value as NSString).expandingTildeInPath
                    guard FileManager.default.isExecutableFile(atPath: path) else { return done(.fail("\(value) isn't a program Duo can run")) }
                    setClaudePath(path)
                }
            case "notify", "dock-badge":
                guard value == "on" || value == "off" else { return done(.fail("usage: \(id.action.usage)")) }
                DuoState.update { if key == "notify" { $0.notifyNeedsYou = value == "on" } else { $0.dockBadge = value == "on" } }
                updateDockBadge()
                SettingsInfo.shared.revision += 1
            default: return done(.fail("no setting '\(key)'. Settings: claude-path, notify, dock-badge"))
            }
            done(.ok(show()))
        case .projectReconnect:
            guard let name = inv[0], let p = project(named: name) else { return done(.fail(inv[0].map { "no project or folder '\($0)'" } ?? "usage: \(id.action.usage)")) }
            let to = inv.flags["to"].map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
            let from = p.isMissing ? p.path : p.movedFrom
            let target = to ?? (p.isMissing ? p.movedTo.map { URL(fileURLWithPath: $0) } : liveFolders[p.name])
            guard let from, let target else {
                return done(.fail(p.isMissing ? "Duo hasn't found where \(p.name) went; pass --to <folder>" : "\(p.name)'s sessions are all where it is"))
            }
            reconnect(from: from, to: target, name: p.name) { r in
                switch r { case .success(let m): done(.ok(m)); case .failure(let e): done(.fail("\(e)")) }
            }
        case .projectForget:
            guard let name = inv[0], let p = project(named: name) else { return done(.fail("usage: \(id.action.usage)")) }
            guard p.isMissing else { return done(.fail("\(p.name)'s folder is there; only a missing folder can be removed from Duo")) }
            forgetFolder(p.name)
            done(.ok("Removed \(p.name) from Duo; its sessions stay in Claude's storage and search. Undo: duo2 undo"))
        case .projectNew:
            guard let name = inv[0] else { return done(.fail("usage: \(id.action.usage)")) }
            let into = inv.flags["into"]
            guard let place = homePlace(named: into) else {
                return done(.fail(liveRoot == nil ? "There's no Home folder yet: duo2 home set <folder>" : "Home has no topic folder '\(into ?? "")'. Choose from: \(homePlaces().map(\.label).joined(separator: ", "))"))
            }
            if let why = createProject(named: name, goal: inv.flags["goal"] ?? "", in: place.folder, moving: [], startSession: inv.has("session")) { return done(.fail(why)) }
            done(.ok("Made the project \(name) at \(Self.short(place.folder.appending(path: name).path))\(inv.has("session") ? ", with a Claude session in it" : ""). Undo: duo2 undo"))
        case .docRevert:
            guard editor.url != nil else { return done(.fail("no document is open in Duo")) }
            let finish: @MainActor (Int) -> Void = { n in done(n > 0 ? .ok("Reverted \(n) of Claude's change(s).") : .fail("no change of Claude's there to revert")) }
            if inv.has("all") { editor.revertAll(finish) }
            else if let line = inv.flags["line"].flatMap(Int.init) {
                editor.run("return duo.revertAtLine(n)", ["n": line]) { v in finish((v as? Int) ?? 0) }
            } else { editor.revertAtCaret(finish) }
        case .migrations, .migratePlan, .migrateApply, .migrateUndo:
            migrateVerb(id, inv, done)
        case .inventory:
            // Reads every transcript's head: off the main thread, so Duo keeps answering.
            Task.detached(priority: .userInitiated) {
                let r = Inventory.build()
                await MainActor.run { self.inventoryReply(r, done) }
            }
        case .evidence:
            guard let name = inv[0], let folder = liveFolders[name] ?? (FileManager.default.fileExists(atPath: (name as NSString).expandingTildeInPath) ? URL(fileURLWithPath: (name as NSString).expandingTildeInPath) : nil) else {
                return done(.fail("usage: \(id.action.usage)"))
            }
            let cwd = folder.resolvingSymlinksInPath().path
            let ids = Set(fixture.sessions.filter { $0.project == name }.compactMap(\.sessionId))
            let titles = Dictionary(fixture.sessions.compactMap { s in s.sessionId.map { ($0, s.name) } }, uniquingKeysWith: { a, _ in a })
            Task.detached(priority: .userInitiated) {
                let transcripts = ClaudeStorage.history().filter { ids.contains($0.id) || $0.cwd == cwd }
                let evidence = transcripts.map { Inventory.evidence($0.transcript, cwd: $0.cwd) }
                await MainActor.run { self.evidenceReply(name, evidence, titles, done) }
            }
        case .sessionArchive, .sessionUnarchive:
            guard let k = inv[0], let s = findSession(k, in: nil) else { return done(.fail(inv[0].map { "no session '\($0)'" } ?? "usage: \(id.action.usage)")) }
            let on = id == .sessionArchive
            if let why = setSessionArchived(s.tabKey, on) { return done(.fail(why)) }
            done(.ok(on ? "Archived \(s.name): it's in \(s.project)'s Archived fold, still searchable. Undo: duo2 undo" : "\(s.name) is back in \(s.project)'s list."))
        case .sessionDelete:
            guard let k = inv[0], let s = findSession(k, in: nil) else { return done(.fail(inv[0].map { "no session '\($0)'" } ?? "usage: \(id.action.usage)")) }
            deleteSession(s.tabKey) { r in
                switch r { case .success(let m): done(.ok(m)); case .failure(let e): done(.fail("\(e)")) }
            }
        case .idle:
            let b = idleGroups()
            let text = b.isEmpty ? "Nothing idle." : b.map { bucket in
                "\(bucket.label) · \(bucket.rows.count)\n" + bucket.rows.map { r in
                    "  \(r.id.prefix(8))  \(r.name)  \(r.unfiled ? "Unfiled" : r.project ?? "")  \(r.openIn.map { "open in \($0)" } ?? r.age)"
                }.joined(separator: "\n")
            }.joined(separator: "\n")
            done(.ok(text, b.map { ["label": $0.label, "sessions": $0.rows.map { ["id": $0.id, "title": $0.name, "project": $0.project ?? "", "age": $0.age] }] as [String: Any] }))
        case .sessionFork:
            guard let k = inv[0], let s = findSession(k, in: nil), let sid = s.sessionId else { return done(.fail("usage: \(id.action.usage)")) }
            open(project: s.project)
            resumeAsFork(sid, in: s.project)
            done(.ok("Forked \(s.name) in \(s.project) as a new session with the same history."))
        case .shellNew:
            newShell(); done(.ok("Opened a shell in \(currentProject?.name ?? fixture.home?.name ?? "the console")."))
        case .groups, .groupNew, .groupAdd, .groupRemove, .groupRename, .groupDelete:
            groupVerb(id, inv, req, done)
        case .sessionMove where inv.has("new"):
            guard let k = inv[0], let s = findSession(k, in: nil), let sid = s.sessionId, let name = inv.flags["to"] ?? inv[1] else {
                return done(.fail("usage: \(id.action.usage)"))
            }
            if let why = newProjectProblem(name) { return done(.fail(why)) }
            confirm(title: "Move “\(s.name)” to a new project “\(name)”?",
                    detail: "Duo makes \(name)'s folder in Home with a starter PROJECT.md. Files stay where they are; the session moves to the new folder the next time you resume it. You can undo this.",
                    button: "Create and Move") { [weak self] ok in
                guard let self else { return }
                guard ok else { return done(.fail("Not moved: the user clicked Cancel in Duo. Nothing changed and nothing is pending.")) }
                if let why = self.createProject(named: name, moving: [sid]) { return done(.fail(why)) }
                done(.ok("Made the project \(name) in Home and filed \(s.name) in it; it moves there on its next resume. Undo: duo2 undo"))
            }
        case .sessionMove:
            guard let k = inv[0], let s = findSession(k, in: nil), let sid = s.sessionId, let to = inv.flags["to"] ?? inv[1], let dst = project(named: to) else {
                return done(.fail("usage: \(id.action.usage)"))
            }
            moveSessions([sid], to: dst.name) { ok in
                done(ok ? .ok("Filed \(s.name) in \(dst.name); it moves there on its next resume. Undo: duo2 undo") : .fail("Not moved: the user clicked Cancel in Duo. Nothing changed and nothing is pending."))
            }
        case .sessionNote, .sessionNext:
            guard let sid = req.session else { return done(.fail("not run from a Claude session (no session id)")) }
            let text = inv.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return done(.fail("usage: \(id.action.usage)")) }
            done(setNarration(sid, kind: id == .sessionNote ? "note" : "next", text: text) ? .ok("Noted.") : .fail("Duo doesn't know session \(sid.prefix(8)) yet"))
        case .sessionChat:
            chatVerb(inv, req, done)
        case .sessionCarryOn:
            guard let old = inv[0] else { return done(.fail("usage: \(id.action.usage)")) }
            guard let new = carryOn(findSession(old, in: nil)?.sessionId ?? old) else { return done(.fail("no archived copy of session \(old)")) }
            done(.ok("Started session \(new.prefix(8)), carrying on from \(old.prefix(8)).", ["id": new]))

        // MARK: Files
        case .files, .fileNew, .fileNewFolder, .fileTemplate, .fileTemplates, .fileRename, .fileDuplicate, .fileMove, .fileTrash,
             .fileReveal, .fileOpenWith, .filePath, .fileConvert:
            fileVerb(id, inv, req, done)

        // MARK: Documents
        case .docOpen:
            guard let f = inv[0] else { return done(.fail("usage: \(id.action.usage)")) }
            guard let (p, rel) = locate(f, inv, req) else {
                // A file outside every project opens as a tab in the project asked for, or on screen (DL-106).
                let url = URL(fileURLWithPath: (f as NSString).expandingTildeInPath, relativeTo: req.cwd.map { URL(fileURLWithPath: $0, isDirectory: true) }).absoluteURL
                guard let target = inv.flags["project"] ?? currentProject?.name, FileManager.default.fileExists(atPath: url.path) else {
                    return done(.fail("'\(f)' isn't a file in a project Duo knows; to open a file from elsewhere, open a project or pass --project"))
                }
                if currentProject?.name != target { open(project: target) }
                guard openFile(at: url) != nil else { return done(.fail("'\(f)' is a folder, not a file")) }
                return done(.ok("Opened \(url.path) in \(target)."))
            }
            if currentProject?.name != p { open(project: p) }
            openDocument(rel)
            done(.ok("Opened \(rel) in \(p)."))
        case .docClose:
            // An outside file's tab is named by its path (DL-106).
            let outsideTab = inv[0].flatMap { f -> String? in
                let t = Self.outsideFilePrefix + URL(fileURLWithPath: (f as NSString).expandingTildeInPath).standardizedFileURL.path
                return openDocuments.contains(t) ? t : nil
            }
            if inv.has("others") {
                guard let keep = outsideTab ?? inv[0].flatMap({ relativePath($0, project: currentProject?.name, cwd: req.cwd) }) ?? rightTab else { return done(.fail("no document showing")) }
                closeOtherDocuments(than: keep); return done(.ok("Closed every tab but \(keep)."))
            }
            guard let path = outsideTab ?? inv[0].flatMap({ relativePath($0, project: currentProject?.name, cwd: req.cwd) }) ?? rightTab, openDocuments.contains(path) else {
                return done(.fail("that document isn't open"))
            }
            closeDocument(path); done(.ok("Closed \(path)."))
        case .docTabs:
            let tabs = ["Project"] + openDocuments
            done(.ok(tabs.map { ($0 == (rightTab ?? "Project") ? "▸ " : "  ") + $0 }.joined(separator: "\n"), ["tabs": tabs, "showing": rightTab ?? "Project"]))
        case .docStatus:
            guard let path = inv[0] else { return done(.fail("usage: \(id.action.usage)")) }
            // A project path first (as Claude names files), then the caller's folder.
            let url = locate(path, inv, req).flatMap { l in liveFolders[l.project]?.appending(path: l.rel) }
                ?? URL(fileURLWithPath: (path as NSString).expandingTildeInPath, relativeTo: req.cwd.map { URL(fileURLWithPath: $0, isDirectory: true) }).absoluteURL
            done(.ok(editorIfLoaded?.status(of: url) ?? "not open in Duo"))
        case .docRead:
            if let f = inv[0], let (p, rel) = locate(f, inv, req), let folder = liveFolders[p] {
                let url = folder.appending(path: rel)
                if editorIfLoaded?.url?.standardizedFileURL == url.standardizedFileURL {
                    editor.run("return duo.text()") { v in done(.ok(v as? String ?? "")) }
                } else {
                    // A deck or any other file that isn't text: say so, never its bytes (C-26).
                    if FileKind.isBinary(url) {
                        return done(.fail("\(rel) isn't text" + (Self.isDeck(rel) ? ": `duo2 slide shapes \(SendFormat.quoted(rel))` reads its slides" : "")))
                    }
                    guard let data = FileManager.default.contents(atPath: url.path) else { return done(.fail("can't read \(rel)")) }
                    done(.ok(String(decoding: data, as: UTF8.self)))
                }
            } else if inv[0] == nil, let e = editorIfLoaded, e.url != nil {
                e.run("return duo.text()") { v in done(.ok(v as? String ?? "")) }
            } else { done(.fail(inv[0] == nil ? "no document is open in the editor" : "'\(inv[0]!)' isn't a file in a project Duo knows")) }
        case .docSelection:
            documentSelectionPayload { p in done(p.map { .ok($0) } ?? .fail("nothing is selected in the editor")) }
        case .docSelect:
            guard let a = inv[0].flatMap(Int.init), editorIfLoaded?.url != nil else { return done(.fail("usage: \(id.action.usage) (with a document showing)")) }
            editor.run("return duo.selectLines(a, b)", ["a": a, "b": inv[1].flatMap(Int.init) ?? a]) { _ in done(.ok("Selected.")) }
        case .docSave:
            guard editorIfLoaded?.url != nil else { return done(.fail("no document is open")) }
            editor.saveNow(); done(.ok("Saved."))
        case .docFormat:
            guard let f = inv[0], DuoCommand.allCases.contains(where: { $0.formatName == f }), editorIfLoaded?.url != nil else { return done(.fail("usage: \(id.action.usage)")) }
            editor.run("duo.exec(f); return 1", ["f": f]) { _ in done(.ok("Done.")) }
        case .docTable:
            // Format › Table's commands at the caret (DL-113); `doc select` puts the caret first.
            let words = ["insert": "tableInsert", "row-above": "tableRowAbove", "row-below": "tableRowBelow", "column-before": "tableColumnBefore",
                         "column-after": "tableColumnAfter", "delete-row": "tableDeleteRow", "delete-column": "tableDeleteColumn",
                         "align-left": "tableAlignLeft", "align-center": "tableAlignCenter", "align-right": "tableAlignRight",
                         "next": "tableNext", "previous": "tablePrevious"]
            guard let w = inv[0], let f = words[w], editorIfLoaded?.url != nil else { return done(.fail("usage: \(id.action.usage) (with a document showing)")) }
            editor.run("duo.exec(f); return duo.text()", ["f": f]) { v in
                done(.ok(w == "insert" ? "Inserted a table at the caret." : "Done."))
            }
        case .docFind:
            guard !inv.text.isEmpty, editorIfLoaded?.url != nil else { return done(.fail("usage: \(id.action.usage) (with a document showing)")) }
            editor.run("return duo.find(q)", ["q": inv.text]) { v in done(.ok("Selected the next match at offset \(v as? Int ?? -1).")) }
        case .docProp:
            guard let e = editorIfLoaded, e.url != nil, let sub = inv[0] else { return done(.fail("usage: \(id.action.usage) (with a document showing)")) }
            let name = inv[1], value = inv.positional.dropFirst(2).joined(separator: " ")
            func show(_ v: Any?) -> String {
                guard let d = v as? [String: Any], let props = d["properties"] as? [[String: Any]] else { return "" }
                return props.map { p in
                    let val = (p["value"] as? [String]).map { "[" + $0.joined(separator: ", ") + "]" } ?? "\(p["value"] ?? "")"
                    return "\(p["name"] ?? ""): \(val)  (\(p["type"] ?? "text"), line \(p["line"] ?? 0))"
                }.joined(separator: "\n")
            }
            if sub != "list" && sub != "get", let why = e.readOnlyReason { return done(.fail("the document is read-only (\(why))")) }
            switch sub {
            case "list":
                e.run("return duo.listProperties()") { v in
                    let d = v as? [String: Any]
                    if let bad = d?["invalid"] as? Int { return done(.ok("Not valid YAML from line \(bad): \(d?["why"] ?? "")\n" + show(v))) }
                    let text = show(v)
                    done(.ok(text.isEmpty ? "No properties." : text, ["properties": d?["properties"] ?? []]))
                }
            case "get":
                guard let name else { return done(.fail("usage: duo2 doc prop get <name>")) }
                e.run("return duo.listProperties()") { v in
                    let p = ((v as? [String: Any])?["properties"] as? [[String: Any]])?.first { $0["name"] as? String == name }
                    guard let p else { return done(.fail("no property '\(name)'")) }
                    done(.ok((p["value"] as? [String]).map { $0.joined(separator: "\n") } ?? "\(p["value"] ?? "")", ["property": p]))
                }
            case "set":
                guard let name, !value.isEmpty else { return done(.fail("usage: duo2 doc prop set <name> <value>")) }
                e.run("return duo.agentSetProperty(k, v)", ["k": name, "v": value]) { _ in done(.ok("Set \(name); the user sees the line marked as changed by Claude. It autosaves.")) }
            case "remove":
                guard let name else { return done(.fail("usage: duo2 doc prop remove <name>")) }
                e.run("return duo.agentSetProperty(k, null)", ["k": name]) { _ in done(.ok("Removed \(name).")) }
            case "type":
                guard let name, let t = inv[2] else { return done(.fail("usage: duo2 doc prop type <name> <type>")) }
                e.run("const l = duo.propertyLine(k); return l == null ? {result: 'no property'} : duo.convertProperty(l, t)", ["k": name, "t": t]) { v in
                    let r = (v as? [String: Any])?["result"] as? String ?? "failed"
                    done(r == "changed" || r == "unchanged" ? .ok("\(name) is now \(t)\((v as? [String: Any])?["value"].map { ": \($0)" } ?? "").") : .fail(r == "needs date" ? "can't read \(name)'s value as a date; set it with `duo2 doc prop set \(name) 2026-10-14`" : r))
                }
            default:
                done(.fail("usage: \(id.action.usage)"))
            }
        case .docInsert:
            guard let e = editorIfLoaded, e.url != nil, let text = inv[0] else { return done(.fail("usage: \(id.action.usage) (with a document showing)")) }
            if let why = e.readOnlyReason { return done(.fail("the document is read-only (\(why))")) }
            let line: Any = inv.flags["line"].flatMap(Int.init) ?? NSNull()
            e.run("return duo.agentInsertAtLine(l, t)", ["l": line, "t": text.replacingOccurrences(of: "\\n", with: "\n")]) { _ in
                done(.ok("Inserted; the user sees it highlighted. It autosaves."))
            }
        case .docReplace:
            guard let e = editorIfLoaded, e.url != nil, let find = inv[0], let repl = inv[1] else { return done(.fail("usage: \(id.action.usage) (with a document showing)")) }
            if let why = e.readOnlyReason { return done(.fail("the document is read-only (\(why))")) }
            e.run("return duo.agentReplace(f, t)", ["f": find.replacingOccurrences(of: "\\n", with: "\n"), "t": repl.replacingOccurrences(of: "\\n", with: "\n")]) { v in
                let r = (v as? [String: Any])?["result"] as? String ?? "failed"
                done(r == "replaced" ? .ok("Replaced at line \((v as? [String: Any])?["line"] as? Int ?? 0); highlighted for the user.") : .fail("text \(r)"))
            }

        case .docEdit:
            guard let raw = inv[0], let j = (try? JSONSerialization.jsonObject(with: Data(raw.utf8))) as? [String: Any],
                  let path = j["file_path"] as? String else { return done(.fail("usage: \(id.action.usage) (JSON with file_path)")) }
            // Relative paths are relative to the caller's folder, as Claude's tools take them.
            let target = URL(fileURLWithPath: (path as NSString).expandingTildeInPath, relativeTo: req.cwd.map { URL(fileURLWithPath: $0, isDirectory: true) })
                .absoluteURL.resolvingSymlinksInPath().standardizedFileURL.path
            guard let e = editorIfLoaded, let open = e.url, open.resolvingSymlinksInPath().standardizedFileURL.path == target else {
                return done(.fail("not open in Duo's editor"))
            }
            if let why = e.readOnlyReason { return done(.fail("open in Duo but read-only (\(why)); leave it, or ask the user")) }
            if e.conflict { return done(.fail("open in Duo with a conflict the user hasn't resolved; ask the user before changing it")) }
            let edits: Any = (j["edits"] as? [[String: Any]]) ?? (j["old_string"] != nil ? [j] : [])
            e.run("return duo.agentEdit(e, c)", ["e": edits, "c": j["content"] ?? NSNull()]) { v in
                let r = v as? [String: Any] ?? [:]
                switch r["result"] as? String {
                case "applied": done(.ok("Applied in Duo's editor\((r["line"] as? Int).map { " at line \($0)" } ?? ""); the user sees it highlighted, and it saves to disk within a second.", r))
                case "unchanged": done(.ok("No change: the document already reads that way.", r))
                default: done(.fail((r["reason"] as? String) ?? "couldn't apply the edit"))
                }
            }

        case .docResolve:
            guard let side = inv[0], ["mine", "theirs"].contains(side) else { return done(.fail("usage: \(id.action.usage)")) }
            guard let e = editorIfLoaded, e.conflict else { return done(.fail("the showing document isn't in conflict")) }
            e.resolve(keepMine: side == "mine") { ok in done(ok ? .ok(side == "mine" ? "Kept the user's text and saved it; the file's version is in history." : "Took the file's version; the user's text is in history.") : .fail("couldn't resolve")) }
        case .docHistory:
            guard let url = inv[0].flatMap({ locate($0, inv, req) }).flatMap({ l in liveFolders[l.project]?.appending(path: l.rel) }) ?? editorIfLoaded?.url
                    ?? inv[0].map({ URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }) else { return done(.fail("usage: \(id.action.usage)")) }
            let list = FileHistory.index(url)
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm:ss"
            let lines = list.map { "\(f.string(from: Date(timeIntervalSince1970: $0.at)))  \($0.source.padding(toLength: 16, withPad: " ", startingAt: 0)) \($0.bytes) bytes  \(FileHistory.blob(url, hash: $0.hash).path)" }
            done(.ok(lines.isEmpty ? "No versions kept for \(url.lastPathComponent)." : lines.joined(separator: "\n"),
                     list.map { ["at": $0.at, "source": $0.source, "bytes": $0.bytes, "path": FileHistory.blob(url, hash: $0.hash).path] }))

        // MARK: HTML pages
        case .slide, .slideGo, .slideShapes, .slideNotes, .slidePick, .slideElement:
            slideVerb(id, inv, req, done)
        case .htmlReload:
            guard let v = visiblePage, v.pageURL != nil else { return done(.fail("no web page is showing")) }
            v.reload(); done(.ok("Reloaded."))
        case .htmlPick:
            guard let v = visiblePage, v.pageURL != nil else { return done(.fail("no web page is showing")) }
            if let sel = inv[0] {
                v.pick(selector: sel) { ok in done(ok ? .ok("Picked \(sel). `duo2 html element` describes it; the user sees it outlined.") : .fail("no element matches \(sel)")) }
            } else { v.startPicking(); done(.ok("The picker is on: the user clicks an element.")) }
        case .htmlStop:
            visiblePage?.stopPicking(); done(.ok("Picker closed."))
        case .htmlElement:
            guard let v = visiblePage, let url = v.pageURL else { return done(.fail("no web page is showing")) }
            let describe: @MainActor (SendFormat.Element?, CGRect?) -> Void = { [weak self] e, rect in
                guard let self, let e else { return done(.fail("no element (pick one, or pass a selector)")) }
                v.screenshot(rect: rect) { shot in
                    let j = (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(e))) as? [String: Any]
                    done(.ok(SendFormat.element(e, path: self.displayPath(url), screenshot: shot), (j ?? [:]).merging(["screenshot": shot ?? NSNull()]) { $1 }))
                }
            }
            if let sel = inv[0] { v.describe(selector: sel, describe) } else { describe(v.picked, nil) }
        case .htmlSelection:
            htmlSelectionPayload { p in done(p.map { .ok($0) } ?? .fail("nothing is selected in the page")) }

        // MARK: Send to Claude
        case .sendFile, .sendSession, .sendProject, .sendSelection, .sendElement, .sendText:
            sendVerb(id, inv, req, done)
        case .selection:
            var parts: [String] = []
            let group = DispatchGroup()
            group.enter(); documentSelectionPayload { if let p = $0 { parts.append(p) }; group.leave() }
            group.enter(); htmlSelectionPayload { if let p = $0 { parts.append(p) }; group.leave() }
            group.notify(queue: .main) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if let d = self.visiblePage as? DeckViewer, let s = d.pickedShape, let url = d.pageURL {
                        parts.append(SendFormat.shape(s, path: self.displayPath(url), screenshot: nil))
                    } else if let v = self.visiblePage, let e = v.picked, let url = v.pageURL { parts.append(SendFormat.element(e, path: self.displayPath(url), screenshot: nil)) }
                    if let f = self.selectedFile, self.terminalsMode == .live { parts.append("Selected in Files: \(f)") }
                    done(parts.isEmpty ? .fail("nothing is selected") : .ok(parts.joined(separator: "\n")))
                }
            }

        case .walkSetup:
            guard let t = inv[0] else { return done(.fail("usage: \(id.action.usage)")) }
            walkSetup(t, done: done)
        case .searchRebuild:
            rebuildSearchIndex(); done(.ok("Rebuilding the search index; `duo2 search-status` shows progress."))
        case .help, .doctor, .legacy, .install, .uninstall, .hook, .compose, .search, .searchStatus, .updateProbe:
            done(.fail("`duo2 \(id.rawValue)` runs in the CLI, not the app"))
        }
    }

    // MARK: Files

    private func fileVerb(_ id: ActionID, _ inv: Invocation, _ req: ControlRequest, _ done: @escaping @MainActor (Reply) -> Void) {
        // The path's project: --project, else the first of the caller's project and the showing one
        // that has the path (a terminal in another folder still reaches the project on screen).
        let candidates = inv.flags["project"].map { [$0] } ?? [projectFor(cwd: req.cwd)?.name, currentProject?.name].compactMap { $0 }
        let projectName = inv[0].flatMap { a in candidates.first { relativePath(a, project: $0, cwd: req.cwd) != nil } } ?? candidates.first
        guard let projectName, let p = project(named: projectName), let folder = liveFolders[p.name] else { return done(.fail("no project here (use --project)")) }
        let isCurrent = currentProject?.name == p.name
        func url(_ s: String?) -> (URL, String)? {
            guard let s, let rel = relativePath(s, project: p.name, cwd: req.cwd) else { return nil }
            return (folder.appending(path: rel), rel)
        }
        func dir() -> URL? {
            guard let d = inv.flags["in"] else { return folder }
            guard let (u, _) = url(d) else { return nil }
            return u
        }
        func rel(_ u: URL) -> String { relativePathIn(u, folder: folder) ?? u.path }
        /// Usage when the argument is missing; otherwise say the path wasn't found and where Duo looked.
        func missing(_ a: String?) -> Reply {
            guard let a else { return .fail("usage: \(id.action.usage)") }
            return .fail("no '\(a)' in \(p.name) (\(folder.path)). Pass --project <name>, or a path from the project's folder.")
        }
        func after(_ then: @escaping @MainActor () -> Void = {}) { refreshLive(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { MainActor.assumeIsolated { then() } } }
        do {
            switch id {
            case .files:
                let base = inv[0].flatMap { relativePath($0, project: p.name, cwd: req.cwd) }
                // Three levels from disk, not the tree's open folders (DL-105); --hidden adds dotfiles.
                let listed = terminalsMode == .live ? LiveSnapshot.topLevelFiles(folder, showHidden: inv.has("hidden") || showHiddenFiles)
                                                    : fixture.projectFiles[p.name] ?? []
                let all = listed.filter { base == nil || $0.hasPrefix(base! + "/") }
                done(.ok(all.isEmpty ? "No files listed for \(p.name)." : "\(p.name) (\(folder.path)):\n" + all.joined(separator: "\n"), all))
            case .fileNew, .fileNewFolder:
                guard let d = dir() else { return done(.fail("no folder '\(inv.flags["in"]!)'")) }
                var made = id == .fileNew ? try FileActions.newMarkdown(in: d) : try FileActions.newFolder(in: d)
                if let n = inv.flags["name"] { made = try FileActions.rename(made, to: id == .fileNew && !n.contains(".") ? n + ".md" : n) }
                let r = rel(made)
                after { if id == .fileNew, isCurrent { self.openDocument(r) } }
                done(.ok("Created \(r) in \(p.name).", ["path": r, "project": p.name]))
            case .fileTemplate:
                guard let name = inv[0] else { return done(.fail("usage: \(id.action.usage)")) }
                let home = fixture.home.flatMap { liveFolders[$0.name] }
                guard let t = FileActions.templates(project: folder, home: home).first(where: { $0.deletingPathExtension().lastPathComponent == name || $0.lastPathComponent == name }) else {
                    return done(.fail("no template '\(name)'. `duo2 file templates` lists them."))
                }
                guard let d = dir() else { return done(.fail("no folder '\(inv.flags["in"]!)'")) }
                let r = rel(try FileActions.newFromTemplate(t, in: d))
                after { if isCurrent { self.openDocument(r) } }
                done(.ok("Created \(r) in \(p.name) from \(t.lastPathComponent).", ["path": r, "project": p.name]))
            case .fileTemplates:
                let ts = FileActions.templates(project: folder, home: fixture.home.flatMap { liveFolders[$0.name] })
                done(.ok(ts.isEmpty ? "No templates: add .md files to a templates folder." : ts.map { $0.deletingPathExtension().lastPathComponent }.joined(separator: "\n"), ts.map(\.path)))
            case .fileRename:
                guard let name = inv[1] else { return done(.fail("usage: \(id.action.usage)")) }
                guard let (u, old) = url(inv[0]) else { return done(missing(inv[0])) }
                let dest = try FileActions.rename(u, to: name)
                let new = rel(dest)
                if isCurrent { moved(old, to: new, url: dest) } else { retab(p.name, old, new); after() }
                done(.ok("Renamed to \(new) in \(p.name).", ["path": new, "project": p.name]))
            case .fileDuplicate:
                guard let (u, _) = url(inv[0]) else { return done(missing(inv[0])) }
                let r = rel(try FileActions.duplicate(u)); after()
                done(.ok("Duplicated as \(r) in \(p.name).", ["path": r, "project": p.name]))
            case .fileMove:
                // <path>… <folder>: the same move as a drop on the tree (DL-117). A path may be
                // anywhere on the Mac (a Finder drop); across volumes it's copied, as Finder does.
                guard inv.positional.count >= 2 else { return done(.fail("usage: \(id.action.usage)")) }
                let target = inv.positional.last!
                guard let (d, _) = url(target) else { return done(missing(target)) }
                var sources: [URL] = []
                for a in inv.positional.dropLast() {
                    if let (u, _) = url(a) { sources.append(u); continue }
                    let abs = (a as NSString).expandingTildeInPath
                    guard abs.hasPrefix("/"), FileManager.default.fileExists(atPath: abs) else { return done(missing(a)) }
                    sources.append(URL(fileURLWithPath: abs))
                }
                let clash: FileDrop.Clash? = inv.has("replace") ? .replace : inv.has("keep-both") ? .keepBoth : nil
                let (plans, refused) = FileDrop.plan(sources, into: d)
                if let why = refused.first { return done(.fail(why)) }
                if clash == nil, let c = plans.first(where: \.clashes) {
                    return done(.fail("“\(c.dest.lastPathComponent)” already exists in \(rel(d)); pass --replace (the one there goes to the Trash) or --keep-both"))
                }
                guard !plans.isEmpty else { return done(.ok("Already there.")) }
                let items = try plans.map { try FileDrop.perform($0, clash: clash) }
                if isCurrent { followTabs(items, back: false) } else {
                    for m in items where m.mode == .move { if let o = relativePathIn(m.source, folder: folder) { retab(p.name, o, rel(m.dest)) } }
                    after()
                }
                registerUndo(items.allSatisfy { $0.mode == .copy } ? "Copy" : "Move") { model in
                    let left = FileDrop.undo(items)
                    if model.currentProject?.name == p.name { model.followTabs(items, back: true) } else { model.refreshLive() }
                    if !left.isEmpty { model.info("Undo couldn't put everything back: " + left.joined(separator: "; ") + ".") }
                }
                let lines = items.map { "\($0.mode == .copy ? "Copied" : "Moved") to \(rel($0.dest))" + ($0.replaced != nil ? " (the one there is in the Trash)" : "") }
                done(.ok(lines.joined(separator: "\n") + " in \(p.name). Undo: duo2 undo", ["path": rel(items[0].dest), "paths": items.map { rel($0.dest) }, "project": p.name] as [String: Any]))
            case .fileTrash:
                guard let (u, r) = url(inv[0]) else { return done(missing(inv[0])) }
                if isCurrent { closeDocumentsUnder(r) }
                try FileActions.trash(u); after()
                done(.ok("Moved \(r) (in \(p.name)) to the Trash."))
            case .fileReveal:
                guard let (u, _) = url(inv[0]) else { return done(missing(inv[0])) }
                FileActions.reveal(u); done(.ok("Shown in Finder."))
            case .fileOpenWith:
                guard let (u, _) = url(inv[0]) else { return done(missing(inv[0])) }
                if let name = inv.flags["app"] {
                    guard let app = FileActions.apps(for: u).first(where: { FileManager.default.displayName(atPath: $0.path).localizedCaseInsensitiveContains(name) })
                            ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: name) else { return done(.fail("no app '\(name)' opens this")) }
                    NSWorkspace.shared.open([u], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
                    done(.ok("Opened in \(FileManager.default.displayName(atPath: app.path))."))
                } else { FileActions.openInDefaultApp(u); done(.ok("Opened in the default app.")) }
            case .filePath:
                guard let (u, r) = url(inv[0]) else { return done(missing(inv[0])) }
                let out = inv.has("link") ? FileActions.markdownLink(name: u.lastPathComponent, relative: r) : inv.has("relative") ? r : u.path
                if inv.has("copy") { FileActions.copy(out) }
                done(.ok(out))
            case .fileConvert:
                // The bar's Convert to Markdown (DL-123), without its question: a taken name fails
                // unless --as names another or --replace sends the old copy to the Trash.
                guard let (u, r) = url(inv[0]) else { return done(missing(inv[0])) }
                guard AppModel.isWordDocument(u) else { return done(.fail("\(r) isn't a Word document (.docx)")) }
                var md = u.deletingPathExtension().appendingPathExtension("md")
                if let n = inv.flags["as"] {
                    guard !n.contains("/") else { return done(.fail("--as takes a file name, not a path")) }
                    md = u.deletingLastPathComponent().appending(path: n.lowercased().hasSuffix(".md") ? n : n + ".md")
                }
                if FileManager.default.fileExists(atPath: md.path), !inv.has("replace") {
                    return done(.fail("“\(md.lastPathComponent)” already exists beside it; pass --as \"\(AppModel.freeMarkdownName(md).lastPathComponent)\" or --replace (the one there goes to the Trash)"))
                }
                startConversion(isCurrent ? r : u.path, docx: u, md: md, replace: inv.has("replace"), allowEmpty: inv.has("anyway"), show: isCurrent) { result in
                    switch result {
                    case .success(let c):
                        var lines = ["Converted \(r) to \(rel(c.markdown))" + (c.images.map { " (pictures in \(rel($0))/)" } ?? "") + " in \(p.name). The .docx is unchanged."]
                        if !c.done.isEmpty { lines.append(c.done.joined(separator: " · ")) }
                        if !c.gaps.isEmpty { lines.append("Not carried over: " + c.gaps.joined(separator: " · ")) }
                        lines.append("Undo: duo2 undo")
                        done(.ok(lines.joined(separator: "\n"), ["path": rel(c.markdown), "images": c.images.map(rel) as Any, "project": p.name,
                                                                  "done": c.done, "gaps": c.gaps] as [String: Any]))
                    case .failure(let e):
                        done(.fail(e is CancellationError ? "cancelled" : "couldn’t convert \(r): \(e)"))
                    }
                }
            default: done(.fail("not a file verb"))
            }
        } catch {
            done(.fail(error.localizedDescription))
        }
    }

    /// Tabs of a project that isn't showing follow a rename or move.
    private func retab(_ project: String, _ old: String, _ new: String) {
        openDocumentsByProject[project] = openDocumentsByProject[project]?.map { $0 == old ? new : $0.hasPrefix(old + "/") ? new + $0.dropFirst(old.count) : $0 }
    }

    // MARK: Send

    private func sendVerb(_ id: ActionID, _ inv: Invocation, _ req: ControlRequest, _ done: @escaping @MainActor (Reply) -> Void) {
        let toNew = inv.has("new")
        var key: String?
        if let to = inv.flags["to"] {
            guard let s = findSession(to, in: nil) ?? fixture.sessions.first(where: { $0.tabKey == to }) else { return done(.fail("no session '\(to)'")) }
            key = s.tabKey
        } else if !toNew {
            switch sendTarget {
            case .success(let t): key = t.key
            case .failure(let why): return done(.fail("\(why.reason). Use --to <session id> or --new."))
            }
        }
        if let key, key == req.session, inv.flags["to"] == nil {
            return done(.fail("the session showing is this one; pass --to <session id> or --new"))
        }
        let deliver: @MainActor (String?) -> Void = { [weak self] text in
            guard let self, let text else { return done(.fail("nothing to send")) }
            if toNew { self.sendToNewSession(text); return done(.ok("Starting a new session; the context goes into its prompt when it's ready.")) }
            guard let key, self.send(text, to: key) else {
                return done(.fail(key.flatMap { self.terminals.existing($0)?.notReadyReason } ?? "that session isn't running in Duo"))
            }
            done(.ok("In the prompt of \(self.fixture.sessions.first { $0.tabKey == key }?.name ?? key), not sent: the user adds the request."))
        }
        switch id {
        case .sendFile:
            guard let f = inv[0], let (p, rel) = locate(f, inv, req), let folder = liveFolders[p] else { return done(.fail("'\(inv[0] ?? "")' isn't a file in a project Duo knows")) }
            let abs = folder.appending(path: rel).path
            let cwd = key.flatMap(cwd(of:)).map { URL(fileURLWithPath: $0).standardizedFileURL.path }
            deliver(SendFormat.file(cwd.map { abs.hasPrefix($0 + "/") ? String(abs.dropFirst($0.count + 1)) : abs } ?? abs))
        case .sendSession:
            guard let k = inv[0], let s = findSession(k, in: nil) else { return done(.fail("no session '\(inv[0] ?? "")'")) }
            deliver(sessionPayload(s.tabKey))
        case .sendProject:
            guard let n = inv[0], let p = project(named: n) else { return done(.fail("no project '\(inv[0] ?? "")'")) }
            deliver(projectPayload(p.name))
        case .sendSelection:
            documentSelectionPayload { [weak self] p in
                if let p { deliver(p) } else { self?.htmlSelectionPayload(deliver) }
            }
        case .sendElement:
            pickedElementPayload { p in
                deliver(p)
                if p != nil { self.visiblePage?.stopPicking() }
            }
        case .sendText:
            guard !inv.text.isEmpty else { return done(.fail("usage: \(id.action.usage)")) }
            deliver(SendFormat.clean(inv.text.replacingOccurrences(of: "\\n", with: "\n")))
        default: done(.fail("not a send verb"))
        }
    }

    // MARK: Lookups

    func project(named name: String) -> Fixture.Project? {
        fixture.projects.first { $0.name == name } ?? fixture.projects.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
            ?? (name == "home" || name == "Home" ? fixture.home : nil)
    }

    /// The project whose folder holds `cwd` (deepest wins).
    func projectFor(cwd: String?) -> Fixture.Project? {
        guard let cwd else { return nil }
        let c = URL(fileURLWithPath: cwd).resolvingSymlinksInPath().path
        return fixture.projects.compactMap { p -> (Fixture.Project, Int)? in
            guard let f = liveFolders[p.name]?.resolvingSymlinksInPath().path, c == f || c.hasPrefix(f + "/") else { return nil }
            return (p, f.count)
        }.max { $0.1 < $1.1 }?.0
    }

    /// A session by id, id prefix (8+ characters is plenty), or exact title (within a project if given).
    func inventoryReply(_ r: Inventory.Report, _ done: @escaping @MainActor (Reply) -> Void) {
        let f = ByteCountFormatter()
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let lines = r.buckets.map { b -> String in
            var flags: [String] = []
            if b.cwdMissing { flags.append("folder missing") }
            if b.collision { flags.append("collision: \(b.cwds.count) folders") }
            if b.junkDrawer { flags.append("catch-all") }
            if b.sweepSoon > 0 { flags.append("\(b.sweepSoon) swept within 7 days (\(b.archivedByDuo) in Duo's archive)") }
            let cwd = b.cwds.first.map { $0.replacingOccurrences(of: home, with: "~") } ?? b.folder
            return "\(cwd)  \(b.sessions) session(s), \(f.string(fromByteCount: b.bytes))" + (flags.isEmpty ? "" : "  [" + flags.joined(separator: "; ") + "]")
        }
        let dups = r.duplicates.map { "duplicate \($0.key.prefix(8)): in \($0.value.joined(separator: ", "))" }
        done(.ok("Claude keeps sessions \(r.periodDays) days. \(r.buckets.count) folders:\n" + (lines + dups).joined(separator: "\n"),
                 r.buckets.map { ["folder": $0.folder, "cwds": $0.cwds, "sessions": $0.sessions, "bytes": $0.bytes, "cwdMissing": $0.cwdMissing,
                                  "collision": $0.collision, "catchAll": $0.junkDrawer, "sweepWithin7Days": $0.sweepSoon, "inDuoArchive": $0.archivedByDuo] as [String: Any] }))
    }

    func evidenceReply(_ name: String, _ evidence: [Inventory.Evidence], _ titles: [String: String], _ done: @escaping @MainActor (Reply) -> Void) {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let df = DateFormatter(); df.dateFormat = "MMM d"
        let text = Inventory.clusters(evidence).map { c -> String in
            let from = c.first?.first.map(df.string) ?? "?", to = (c.compactMap { $0.last ?? $0.first }.max()).map(df.string) ?? "?"
            return "\(from)–\(to) (\(c.count) session(s))\n" + c.map { e in
                let title = titles[e.sessionId] ?? e.title ?? String(e.sessionId.prefix(8))
                return "  \(e.sessionId.prefix(8))  \(title)  edited \(e.edited.count)\(e.partial ? "+ (partial)" : "")  home: \(e.candidateHome.map { $0.replacingOccurrences(of: home, with: "~") } ?? "-")"
            }.joined(separator: "\n")
        }.joined(separator: "\n")
        done(.ok(text.isEmpty ? "No sessions with transcripts in \(name)." : text,
                 evidence.map { ["id": $0.sessionId, "edited": $0.edited, "candidateHome": $0.candidateHome ?? NSNull(), "partial": $0.partial] as [String: Any] }))
    }

    func findSession(_ key: String, in project: String?) -> Fixture.Session? {
        let everything = fixture.sessions + (fixture.archivedSessions ?? [])
        let pool = project.map { p in everything.filter { $0.project == p } } ?? everything
        return pool.first { $0.sessionId == key } ?? pool.first { key.count >= 4 && ($0.sessionId?.hasPrefix(key) ?? false) }
            ?? pool.first { $0.name == key }
    }

    /// A path as the project sees it: relative to its folder. Accepts absolute paths inside it,
    /// `~` paths, and paths relative to the caller's folder.
    func relativePath(_ s: String, project: String?, cwd: String?) -> String? {
        guard let project, let folder = liveFolders[project] else { return nil }
        let expanded = (s as NSString).expandingTildeInPath
        let url: URL
        if expanded.hasPrefix("/") { url = URL(fileURLWithPath: expanded) }
        else if let cwd, let inside = relativePathIn(URL(fileURLWithPath: cwd), folder: folder) ?? (URL(fileURLWithPath: cwd).resolvingSymlinksInPath().path == folder.resolvingSymlinksInPath().path ? "" : nil) {
            url = folder.appending(path: inside.isEmpty ? expanded : inside + "/" + expanded)
        } else { url = folder.appending(path: expanded) }
        guard let r = relativePathIn(url, folder: folder), FileManager.default.fileExists(atPath: folder.appending(path: r).path) else { return nil }
        return r
    }

    func relativePathIn(_ url: URL, folder: URL) -> String? {
        let f = folder.resolvingSymlinksInPath().standardizedFileURL.path
        let u = url.resolvingSymlinksInPath().standardizedFileURL.path
        return u.hasPrefix(f + "/") ? String(u.dropFirst(f.count + 1)) : nil
    }

    /// A file anywhere Duo knows: in --project, the caller's project, the showing one, or any
    /// project for an absolute path.
    func locate(_ s: String, _ inv: Invocation, _ req: ControlRequest) -> (project: String, rel: String)? {
        let candidates = [inv.flags["project"], projectFor(cwd: req.cwd)?.name, currentProject?.name].compactMap { $0 }
        for p in candidates { if let r = relativePath(s, project: p, cwd: req.cwd) { return (p, r) } }
        let expanded = (s as NSString).expandingTildeInPath
        if expanded.hasPrefix("/"), let p = projectFor(cwd: (expanded as NSString).deletingLastPathComponent), let r = relativePath(expanded, project: p.name, cwd: nil) {
            return (p.name, r)
        }
        return nil
    }

    // MARK: Shapes

    func stateWord(_ s: SessionState) -> String {
        switch s { case .needsYou: "needs-you"; case .readyForReview: "review"; case .working: "working"; case .idle: "idle"; case .resolved: "resolved" }
    }

    func sessionJSON(_ s: Fixture.Session) -> [String: Any] {
        var j: [String: Any] = ["title": s.name, "project": s.project, "state": stateWord(s.state)]
        if let v = s.sessionId { j["id"] = v }
        if let v = s.wait { j["wait"] = v }
        if let v = s.question { j["question"] = v }
        if let v = s.options { j["options"] = v }
        if let v = s.summary { j["summary"] = v }
        j["running"] = terminals.existing(s.tabKey) != nil
        return j
    }

    func projectJSON(_ p: Fixture.Project) -> [String: Any] {
        var j: [String: Any] = ["name": p.name, "goal": p.goal, "folder": liveFolders[p.name]?.path ?? p.path, "kind": p.isFolderOnly ? "folder" : p.isHome == true ? "home" : "project"]
        if let v = p.health { j["health"] = v }
        if let v = p.next { j["next"] = v }
        if let v = p.topic { j["topic"] = v }
        if p.isMissing { j["kind"] = "missing"; j["missing"] = p.missing ?? ""; if let t = p.movedTo { j["movedTo"] = t } }
        if let n = p.staleSessions { j["staleSessions"] = n; j["movedFrom"] = p.movedFrom ?? "" }
        return j
    }

    func statusReply() -> Reply {
        var j: [String: Any] = [:]
        var lines: [String] = []
        switch altitude {
        case .allProjects:
            j["view"] = "all-projects"
            let home = homeTab.flatMap { k in fixture.sessions.first { $0.tabKey == k } }
            lines.append("All projects" + (home.map { ", Home on \($0.name)" } ?? ""))
            if let h = home { j["session"] = sessionJSON(h) }
        case .project(let p):
            j["view"] = "project"; j["project"] = p
            let s = consoleTab.flatMap { k in fixture.sessions.first { $0.tabKey == k } }
            lines.append("Project \(p)" + (s.map { ", console on \($0.name)" } ?? ""))
            if let s { j["session"] = sessionJSON(s) }
            let tab = rightTab ?? "Project"
            j["rightTab"] = tab
            j["documents"] = openDocuments
            lines.append("Right pane: \(tab)" + (openDocuments.isEmpty ? "" : " (open: \(openDocuments.joined(separator: ", ")))"))
            if let v = visiblePage, v.picking { lines.append("Element picker on" + (v.picked.map { ": <\($0.label)> picked" } ?? "")) }
        }
        let c = fixture.counts
        j["counts"] = ["needsYou": c.needsYou, "review": c.readyForReview, "working": c.working, "idle": c.idle]
        lines.append("\(c.needsYou) need you · \(c.readyForReview) to review · \(c.working) working · \(c.idle) idle")
        return .ok(lines.joined(separator: "\n"), j)
    }

    /// Ends one session's process and moves its pane to the next tab (⌘W, `duo2 session close`).
    public func closeSession(_ key: String) {
        guard terminals.existing(key) != nil else { return }
        let s = fixture.sessions.first { $0.tabKey == key }
        terminals.close(key)
        if let s {
            let next = tabSessions(inProject: s.project).first { $0.tabKey != key }?.tabKey
            if homeTab == key { homeTab = next }
            if consoleTab == key { consoleTab = next }
        }
        fixture = fixture
    }
}

private extension String {
    var nonEmptyOrNil: String? { isEmpty ? nil : self }
}
