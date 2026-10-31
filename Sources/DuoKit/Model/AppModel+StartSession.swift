import AppKit
import Foundation
import DuoControl

/// The New session row at All projects (DL-262, Q-339): a first row in the List that starts a Claude
/// session where the user says, by default in Home, else `~/Documents`. ⌘T at All projects presses it (F-446).
extension AppModel {
    /// The row's default: Home, else `~/Documents`, else nil (the row reads Choose…).
    public var startDefault: StartPlace? {
        let home = fixture.home.map { (name: $0.name, folder: liveFolders[$0.name] ?? URL(fileURLWithPath: $0.path)) }
        return StartDefault.resolve(home: home, documents: StartDefault.documentsURL, documentsExists: documentsExists ?? false)
    }

    /// The popup below the default, in order (DL-262): `~/Documents` when Home is the default, then the
    /// projects and the folders Claude has run in or the user chose, by last activity (chosen folders with
    /// no session after them, in the order chosen). Gone folders are left out; the default never changes for it.
    public var startOthers: [StartPlace] {
        let fm = FileManager.default
        let def = startDefault
        var out: [StartPlace] = []
        var seen = Set<String>()
        func add(_ p: StartPlace) {
            let key = p.folder.standardizedFileURL.path
            guard key != def?.folder.standardizedFileURL.path, seen.insert(key).inserted else { return }
            out.append(p)
        }
        let docs = StartDefault.documentsURL
        if def?.kind == .home, documentsExists == true { add(StartPlace(kind: .folder, label: "~/Documents", folder: docs)) }
        func recency(_ p: Fixture.Project) -> Int {
            fixture.sessions(inProject: p.name).map { WaitTime($0.wait).seconds }.min() ?? Int.max
        }
        let listed = fixture.projects.filter { $0.isHome != true && !$0.isMissing && !archivedProjectPaths.contains(liveFolders[$0.name]?.path ?? $0.path) }
            .sorted { recency($0) < recency($1) }
        for p in listed {
            let folder = liveFolders[p.name] ?? URL(fileURLWithPath: p.path)
            if p.isFolderOnly { add(StartPlace(kind: .folder, label: Self.tilde(folder.path), folder: folder)) }
            else { add(StartPlace(kind: .project, label: p.name, folder: folder, project: p.name)) }
        }
        for path in startFolders where startFoldersPresent.contains(path) {
            add(StartPlace(kind: .folder, label: Self.tilde(path), folder: URL(fileURLWithPath: path)))
        }
        _ = fm
        return out
    }

    nonisolated static func tilde(_ path: String) -> String { (path as NSString).abbreviatingWithTildeInPath }

    /// The row, ⌘T and `duo2 session new` at All projects with no project: start in the default, or, with
    /// none, open the popup and start nothing.
    public func pressNewSessionRow() {
        if let d = startDefault { startSession(in: d) } else { NewSessionPopup.show(self) }
    }

    /// Starts a Claude session in a place chosen on the row. A project's opens inside it with the new tab
    /// selected (DL-142 (5)); Home's and a plain folder's open in Home's pane.
    public func startSession(in place: StartPlace) {
        switch place.kind {
        case .home:
            if let name = place.project, let sid = newSession(in: name) { homeTab = sid }
        case .project:
            guard let name = place.project else { return }
            open(project: name)
            if let sid = newSession(in: name) { consoleTab = sid }
        case .folder:
            if let owner = fixture.projects.first(where: { !$0.isFolderOnly && liveFolders[$0.name]?.realPath == place.folder.realPath }) {
                return startSession(in: StartPlace(kind: owner.isHome == true ? .home : .project, label: owner.name, folder: place.folder, project: owner.name))
            }
            _ = startFolderSession(place.folder)
        }
    }

    /// A Claude session in a folder that isn't a project. The id is minted now so `duo2` can name it; the
    /// start waits off the main thread for macOS's folder prompt (F-28).
    @discardableResult
    public func startFolderSession(_ folder: URL, id: String = UUID().uuidString.lowercased()) -> String? {
        guard terminalsMode == .live else { return nil }
        rememberStartFolder(folder)
        let home = fixture.home?.name
        Task { @MainActor [weak self] in
            let problem = await Task.detached { Self.openFolder(folder.path) }.value
            guard let self else { return }
            if let problem { return self.info(problem) }
            _ = self.terminals.session(id, command: .newClaude(sessionID: id, prompt: nil, remoteControl: nil, name: nil), cwd: folder.path)
            self.fixture.sessions.append(Fixture.Session(name: LiveSnapshot.untitled(Date()), project: home ?? Self.tilde(folder.path), state: .working, wait: "now",
                                                         question: nil, options: nil, summary: nil, forkOf: nil, document: nil, sessionId: id, remoteControl: nil))
            if self.altitude.isAllProjects { self.homeTab = id }
        }
        return id
    }

    /// Opens the folder to read, which is what raises macOS's privacy prompt for Documents and waits for
    /// the answer. Returns why it can't be started in, or nil. Always called off the main thread.
    nonisolated static func openFolder(_ path: String) -> String? {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { return "\(tilde(path)) isn't there any more, so no session was started." }
        guard let d = opendir(path) else {
            return "macOS didn't let Duo open \(tilde(path)), so no session was started. If a profile on this Mac blocks it, ask its administrator; otherwise allow Duo under System Settings › Privacy & Security › Files and Folders."
        }
        closedir(d)
        return nil
    }

    func rememberStartFolder(_ folder: URL) {
        let path = folder.standardizedFileURL.path
        guard !fixture.projects.contains(where: { liveFolders[$0.name]?.standardizedFileURL.path == path }), path != StartDefault.documentsURL.path else { return }
        var list = startFolders.filter { $0 != path }
        list.insert(path, at: 0)
        startFolders = Array(list.prefix(12))
        startFoldersPresent.insert(path)
        let kept = startFolders
        _ = DuoState.update { $0.startFolders = kept }
    }

    /// The popup's Choose Another Folder…: the system folder panel; what it gives joins the list and starts a session.
    public func chooseStartFolder() {
        guard interactivePrompts else { return info("Choose Another Folder… opens a folder picker; scripted runs use `duo2 session new --folder <path>`.") }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Start Here"
        panel.message = "Duo starts a Claude session in this folder."
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        DuoFocus.take()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        startSession(in: StartPlace(kind: .folder, label: Self.tilde(url.path), folder: url))
    }
}

/// The popup on the row (DL-262): a system menu. The default first and ticked, a rule, the others, a rule,
/// Choose Another Folder…, New Project…, and Choose Home Folder… when there's no Home.
@MainActor public enum NewSessionPopup {
    final class Item: NSMenuItem {
        var run: () -> Void = {}
        @objc func fire() { run() }
    }

    public static func menu(_ model: AppModel) -> NSMenu {
        let menu = NSMenu()
        func add(_ title: String, ticked: Bool = false, _ run: @escaping () -> Void) {
            let i = Item(title: title, action: #selector(Item.fire), keyEquivalent: "")
            i.run = run; i.target = i
            if ticked { i.state = .on }
            menu.addItem(i)
        }
        if let d = model.startDefault {
            add(d.label, ticked: true) { model.startSession(in: d) }
            menu.addItem(.separator())
        }
        let others = model.startOthers
        for p in others { add(p.label) { model.startSession(in: p) } }
        if !others.isEmpty { menu.addItem(.separator()) }
        add("Choose Another Folder…") { model.chooseStartFolder() }   // action: session new
        add("New Project…") { model.showNewProject() }   // action: project new
        if model.fixture.home == nil { add("Choose Home Folder…") { model.chooseHomeFolder() } }   // action: home set
        return menu
    }

    static func show(_ model: AppModel) {
        menu(model).popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }
}
