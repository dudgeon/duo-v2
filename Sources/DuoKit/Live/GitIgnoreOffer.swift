import AppKit
import Foundation

/// DL-50: in a git repository, Duo offers once to add `.duo/` to `.gitignore`, so its session
/// index stays out of commits that engineers see. Never silent; the answer is remembered.
@MainActor
enum GitIgnoreOffer {
    private static var checked: Set<String> = []
    private static var showing = false

    /// Called after refreshes; checks each project once per launch, off the main thread.
    static func consider(_ folders: [String: URL], interactive: Bool) {
        let fresh = folders.filter { !checked.contains($0.value.path) && FileManager.default.fileExists(atPath: $0.value.appending(path: ".duo").path) }
        guard !fresh.isEmpty, !showing else { return }
        for f in fresh.values { checked.insert(f.path) }
        let answered = DuoState.load().gitignore
        Task.detached(priority: .utility) {
            var offers: [(project: String, repo: URL)] = []
            for (name, folder) in fresh {
                guard let repo = gitRoot(folder), answered[repo.path] == nil, !isIgnored(folder.appending(path: ".duo"), repo: repo) else { continue }
                offers.append((name, repo))
            }
            guard let first = offers.first else { return }
            await MainActor.run { ask(project: first.project, repo: first.repo, interactive: interactive) }
        }
    }

    nonisolated static func gitRoot(_ folder: URL) -> URL? {
        var dir = folder.resolvingSymlinksInPath()
        while dir.path != "/" {
            if FileManager.default.fileExists(atPath: dir.appending(path: ".git").path) { return dir }
            dir.deleteLastPathComponent()
        }
        return nil
    }

    /// Asks git itself, so nested `.gitignore` files and ignored parents (like `.build/`) count.
    nonisolated static func isIgnored(_ path: URL, repo: URL) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = ["-C", repo.path, "check-ignore", "-q", path.path]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return true }  // no git: nothing to offer
        p.waitUntilExit()
        return p.terminationStatus == 0
    }

    static func ask(project: String, repo: URL, interactive: Bool) {
        let add: Bool
        if let auto = ProcessInfo.processInfo.environment["DUO_GITIGNORE_ANSWER"] {
            add = auto == "add"   // scripted runs and checks
        } else if interactive {
            showing = true
            let alert = NSAlert()
            alert.messageText = "Keep Duo's files out of git?"
            alert.informativeText = "Duo keeps a small .duo folder in “\(project)” for its list of sessions. “\(repo.lastPathComponent)” is a git repository. Add .duo/ to its .gitignore so the folder stays out of commits?"
            alert.addButton(withTitle: "Add to .gitignore")
            alert.addButton(withTitle: "Don't Add")
            add = alert.runModal() == .alertFirstButtonReturn
            showing = false
        } else {
            return  // captures never block on a prompt; ask next time
        }
        if add {
            let file = repo.appending(path: ".gitignore")
            var text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
            if !text.isEmpty && !text.hasSuffix("\n") { text += "\n" }
            text += (text.isEmpty ? "" : "\n") + "# Duo's session index (DL-50)\n.duo/\n"
            try? text.write(to: file, atomically: true, encoding: .utf8)
        }
        DuoState.update { $0.gitignore[repo.path] = add ? "added" : "declined" }
    }
}
