import Foundation

/// A Claude that Duo started but holds no terminal for (C-30, F-126). Duo lets go of a terminal only
/// once its process has ended, so this shouldn't happen; if it does, `duo2 session close` and
/// Archive end it rather than calling it "running elsewhere" for good.
extension AppModel {
    /// The process running this session, when it is Duo's own child and has no terminal in Duo.
    func orphanPid(_ sessionId: String) -> Int32? {
        let mine = Set(terminals.all.compactMap { $0.view.process?.shellPid } + terminals.closingPids)
        return Beacon.readAll().first { b in
            b.sessionId == sessionId && !mine.contains(b.pid) && ProcessLiveness.parent(b.pid) == getpid()
        }?.pid
    }

    /// SIGTERM, then SIGKILL if it's still running after the same wait a closed terminal gets.
    func endOrphan(_ pid: Int32) {
        kill(pid, SIGTERM)
        DispatchQueue.main.asyncAfter(deadline: .now() + TerminalStore.killAfter) {
            if ProcessLiveness.isRunning(pid), ProcessLiveness.parent(pid) == getpid() { kill(pid, SIGKILL) }
        }
        FileHandle.standardError.write(Data("orphan: ended pid \(pid), a session Duo started without a terminal\n".utf8))
    }
}
