import Foundation

/// `/branch` and `/fork` made in a Duo session leave both sessions live, each in its own tab (DL-227, DL-228,
/// F-344). `/branch` switches the same process to the new id, so the tab is split: the process keeps the new id
/// in a tab right of the original, and the original is resumed in its old place. `/fork` copies the conversation
/// into Claude's background; a tab right of the original attaches to it.
extension AppModel {
    /// The SessionStart hook's source for a session (`clear`, `resume`, `fork` …), noted for `followSessionChanges`.
    public func noteSessionStart(_ sid: String, source: String?) {
        guard let source else { return }
        startSources[sid] = source
        if source == "fork" { refreshLive() }   // look for it now, not at the next poll
    }

    /// Whether the terminal's process moved to `newId` by `/branch`: the hook said `fork` (same pid, the
    /// process is the terminal's), or the new transcript names the old session in `forkedFrom`.
    public func isBranch(newId: String, from old: String, folder: URL) -> Bool {
        if ForkSource.classify(source: startSources[newId], ownsPid: true, parentIsDuoTab: false) == .branch { return true }
        guard let transcript = ClaudeStorage.transcript(sessionId: newId, cwd: folder.path) else { return false }
        return ThreadCache.shared.declaredParents([(newId, transcript)])[newId] == old
    }

    /// The thread row's fold id, which `duo2 view group ‹original id›` matches by suffix.
    public func threadFoldKey(project: String, original: String) -> String { "\(project)/thread/\(original)" }

    /// `/branch`: the terminal's tab becomes the branch's tab right of the original's place, selected; the
    /// original reopens in its old place by `claude --resume`; the thread opens; task links are copied.
    public func splitBranch(from old: Fixture.Session, to new: String, folder: URL) {
        let oldKey = old.tabKey
        let order = consoleTabKeys(inProject: old.project)   // before the tab changes hands
        var index = SessionIndex.load(project: folder)
        if !index.sessions.contains(where: { $0.sessionId == new }) {
            var entry = SessionIndex.Entry(sessionId: new, provenance: "forked-from:\(oldKey)")
            entry.fork = ForkSource.Kind.branch.rawValue
            index.sessions.append(entry)
            try? index.save(project: folder)
        }
        continueTasks(from: oldKey, to: new)
        let wasConsole = consoleTab == oldKey, wasHome = homeTab == oldKey
        chats.rekey(oldKey, to: new)
        terminals.rekey(oldKey, to: new)
        if wasConsole { consoleTab = new }
        if wasHome { homeTab = new }
        consoleTabOrder[old.project] = ForkPlacement.inserting(new, after: oldKey, in: order + [new])
        expandedGroups.insert(threadFoldKey(project: old.project, original: oldKey))
        // The original comes back at its prompt: a second Claude process that costs nothing until used.
        _ = terminal(project: old.project, session: oldKey)
        fixture = fixture   // tabs depend on which terminals exist
        refreshLive()
    }

    /// `/fork`: a job in Claude's background whose parent is one of Duo's tabs gets a tab right of it that
    /// attaches, unselected; it joins the parent's tasks and its thread opens. Jobs found at the first look
    /// are the baseline and open nothing. The fork is listed at once, before it has a transcript (2.1.219).
    public func adoptForks(into snapshot: inout Fixture) {
        let jobs = ForkSource.jobs()
        guard var seen = forksSeen else { forksSeen = Set(jobs.compactMap(\.sessionId)); return }
        defer { forksSeen = seen }
        for job in jobs {
            guard let fid = job.sessionId, !seen.contains(fid) else { continue }
            seen.insert(fid)
            guard terminals.existing(job.parent) != nil,
                  let parent = snapshot.sessions.first(where: { $0.tabKey == job.parent }) ?? fixture.sessions.first(where: { $0.tabKey == job.parent }),
                  let folder = liveFolders[parent.project], ForkSource.classify(source: "fork", ownsPid: false, parentIsDuoTab: true) == .fork else { continue }
            let order = consoleTabKeys(inProject: parent.project)
            var index = SessionIndex.load(project: folder)
            if !index.sessions.contains(where: { $0.sessionId == fid }) {
                var entry = SessionIndex.Entry(sessionId: fid, provenance: "forked-from:\(job.parent)")
                entry.fork = ForkSource.Kind.fork.rawValue
                index.sessions.append(entry)
                try? index.save(project: folder)
            }
            continueTasks(from: job.parent, to: fid)
            _ = terminals.session(fid, command: .attachClaude(short: job.short, sessionID: fid), cwd: folder.path)
            if !snapshot.sessions.contains(where: { $0.sessionId == fid }) {
                snapshot.sessions.append(Fixture.Session(name: parent.name, project: parent.project, state: .idle, wait: "now", question: nil, options: nil,
                                                         summary: nil, forkOf: parent.name, document: nil, sessionId: fid, liveProcess: true,
                                                         forkParent: job.parent, fork: ForkSource.Kind.fork.rawValue))
            }
            consoleTabOrder[parent.project] = ForkPlacement.inserting(fid, after: job.parent, in: order + [fid])
            expandedGroups.insert(threadFoldKey(project: parent.project, original: job.parent))
        }
    }

    /// A fork's tab, the all-tabs row and the chat strip carry the fork mark (DL-228 B): the session's parent, if it is one.
    public func forkParentName(of key: String) -> String? {
        guard let s = fixture.sessions.first(where: { $0.tabKey == key }), s.forkParent != nil || s.forkOf != nil else { return nil }
        return s.forkOf ?? s.forkParent.flatMap { p in fixture.sessions.first { $0.tabKey == p }?.name }
    }
}
