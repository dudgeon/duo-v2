import AppKit
import Foundation

/// Plain shell tabs in the console (DL-8, surfaces-handoff DB-4). Shells aren't sessions: they're
/// not in the list on the left or in the counts, and never need you. Typing `claude` in one turns
/// its tab into a session tab in place. Shells aren't restored on relaunch.
extension AppModel {
    static let shellPrefix = "shell:"

    public func isShell(_ key: String) -> Bool { key.hasPrefix(Self.shellPrefix) }

    /// A session with a live terminal in Duo (ENH-7: "active"). Ended terminals don't count.
    public func hasOpenTerminal(_ key: String) -> Bool {
        _ = endedRevision
        if let fixed = fixtureActive { return fixed.contains(key) }
        return terminals.existing(key).map { !$0.exited } ?? false
    }

    /// ⇧⌘T or the chevron's New Shell: a login shell in the project's folder (Home's at All projects).
    public func newShell() {
        let project = altitude.isAllProjects ? fixture.home?.name : currentProject?.name
        guard let project else { return }
        let folder = liveFolders[project]?.path ?? FileManager.default.homeDirectoryForCurrentUser.path
        let key = Self.shellPrefix + UUID().uuidString.lowercased()
        _ = terminals.session(key, command: .shell, cwd: folder)
        shellTabs[project, default: []].append(key)
        shellTitles[key] = ((ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh") as NSString).lastPathComponent
        if altitude.isAllProjects { homeTab = key } else { consoleTab = key }
    }

    /// The shells open in a project, in the order they were opened.
    public func shells(inProject project: String) -> [String] {
        // Fixture mode has no processes: its targets list shells by name alone.
        (shellTabs[project] ?? []).filter { terminalsMode != .live || terminals.existing($0) != nil }
    }

    /// On each refresh: shell titles follow the command running in them, and a shell running
    /// `claude` becomes that session's tab (DL-8).
    func followShells(_ beacons: [Beacon]) {
        for (project, keys) in shellTabs {
            for key in keys {
                guard let t = terminals.existing(key), let proc = t.view.process, proc.running else { continue }
                let shellPid = proc.shellPid
                if let b = beacons.first(where: { AppOwning.descends($0.pid, from: shellPid) }) {
                    promote(key, to: b.sessionId, in: project)
                    continue
                }
                if let title = ForegroundCommand.title(ptyFD: proc.childfd, shellPid: shellPid), shellTitles[key] != title {
                    shellTitles[key] = title
                }
            }
        }
    }

    private func promote(_ key: String, to sessionId: String, in project: String) {
        if let folder = liveFolders[project] {
            var index = SessionIndex.load(project: folder)
            if !index.sessions.contains(where: { $0.sessionId == sessionId }) {
                index.sessions.append(.init(sessionId: sessionId, provenance: "promoted-from-shell"))
                try? index.save(project: folder)
            }
        }
        shellTabs[project]?.removeAll { $0 == key }
        shellTitles[key] = nil
        terminals.rekey(key, to: sessionId)
        if consoleTab == key { consoleTab = sessionId }
        if homeTab == key { homeTab = sessionId }
        NSAccessibility.post(element: NSApp.mainWindow as Any, notification: .announcementRequested,
                             userInfo: [.announcement: "Now a Claude session", .priority: NSAccessibilityPriorityLevel.medium.rawValue])
        refreshLive()
    }

    /// A shell that exits cleanly closes its tab; one that fails keeps it, with the bar (DB-4).
    func shellEnded(_ t: TerminalSession) {
        guard isShell(t.key), (t.ended?.status ?? 0) == 0 else { return }
        closeShell(t.key)
    }

    public func closeShell(_ key: String) {
        terminals.close(key)
        for p in shellTabs.keys { shellTabs[p]?.removeAll { $0 == key } }
        shellTitles[key] = nil
        let project = altitude.isAllProjects ? fixture.home?.name : currentProject?.name
        let next = project.map { p in (tabSessions(inProject: p).map(\.tabKey) + shells(inProject: p)).first } ?? nil
        if consoleTab == key { consoleTab = next }
        if homeTab == key { homeTab = next }
    }
}

extension AppOwning {
    /// Whether `pid` is `ancestor` or runs under it.
    static func descends(_ pid: Int32, from ancestor: Int32) -> Bool {
        var p = pid
        for _ in 0..<8 {
            if p == ancestor { return true }
            p = ppid(p)
            if p <= 1 { return false }
        }
        return false
    }
}

/// What a shell is running, for its tab's title (DB-4): the foreground job's command, or the
/// shell's own name while it waits at its prompt.
public enum ForegroundCommand {
    static let interpreters: Set<String> = ["sh", "bash", "zsh", "dash", "fish", "python", "python3", "node", "ruby", "perl", "env"]

    static func title(ptyFD: Int32, shellPid: Int32) -> String? {
        guard ptyFD >= 0 else { return nil }
        let pgid = tcgetpgrp(ptyFD)
        guard pgid > 0 else { return nil }
        let args = arguments(pgid)
        guard let first = args.first else { return nil }
        let name = (first as NSString).lastPathComponent.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        if pgid == shellPid { return name }
        // A script run by an interpreter shows as the script: `./export-funnel.sh`, not `bash`.
        if interpreters.contains(name), args.count > 1, let script = args.dropFirst().first(where: { !$0.hasPrefix("-") }) { return script }
        return ([name] + args.dropFirst()).joined(separator: " ")
    }

    /// A process's argv, from KERN_PROCARGS2.
    public static func arguments(_ pid: Int32) -> [String] {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 4 else { return [] }
        var buf = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buf, &size, nil, 0) == 0 else { return [] }
        let argc = Int(buf.withUnsafeBytes { $0.load(as: Int32.self) })
        var i = 4
        while i < size, buf[i] != 0 { i += 1 }   // the executable path
        while i < size, buf[i] == 0 { i += 1 }   // padding
        var out: [String] = []
        while out.count < argc, i < size {
            let start = i
            while i < size, buf[i] != 0 { i += 1 }
            out.append(String(decoding: buf[start..<i], as: UTF8.self))
            i += 1
        }
        return out
    }
}
