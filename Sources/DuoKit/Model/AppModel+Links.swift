import AppKit
import Foundation

/// Session links (DL-87): tasks are Markdown notes that link to the sessions working on them.
/// `duo2://session/<session id>` uses Claude's own id, so a link survives renames and retitling.
extension AppModel {
    public static func sessionURL(_ id: String) -> String { "duo2://session/\(id)" }

    /// `[title](duo2://session/<id>)`, for a note. Brackets in the title are escaped.
    public func sessionLink(_ key: String) -> String? {
        guard let s = (fixture.sessions + (fixture.archivedSessions ?? [])).first(where: { $0.tabKey == key || $0.sessionId == key }),
              let id = s.sessionId else { return nil }
        let title = s.name.replacingOccurrences(of: "[", with: "\\[").replacingOccurrences(of: "]", with: "\\]")
        return "[\(title)](\(Self.sessionURL(id)))"
    }

    /// Copy Link on a session's right-click menu.
    public func copySessionLink(_ key: String) {
        guard let link = sessionLink(key) else { return }
        FileActions.copy(link)
    }

    /// A link clicked in a document, or a `duo2://` URL opened from outside. Session links go to the
    /// session; relative links to files open them in Duo when they're in the project; anything else
    /// goes to the system (the browser, Mail).
    public func openLink(_ raw: String, from document: URL? = nil) {
        let text = raw.trimmingCharacters(in: CharacterSet(charactersIn: "<> "))
        if let url = URL(string: text), url.scheme == "duo2" {
            if url.host == "session", let id = url.pathComponents.dropFirst().first { return openSessionLink(id) }
            return info("Duo doesn't know the link \(text).")
        }
        if let url = URL(string: text), let scheme = url.scheme, !scheme.isEmpty {
            // Allowed sites open in a browser tab beside the note (DL-3); the rest in the browser.
            if ["http", "https"].contains(scheme.lowercased()), AllowedSites.allows(url), currentProject != nil, terminalsMode == .live {
                newBrowserTab(url)
            } else {
                NSWorkspace.shared.open(url)
            }
            return
        }
        // A relative link: a file next to the document, opened here if it's in this project.
        let path = text.split(separator: "#", maxSplits: 1).first.map(String.init)?.removingPercentEncoding ?? text
        guard let base = document?.deletingLastPathComponent() ?? projectFolder else { return }
        let target = URL(fileURLWithPath: path, relativeTo: base).standardizedFileURL
        guard FileManager.default.fileExists(atPath: target.path) else { return info("\(path) isn't there.") }
        if let folder = projectFolder?.standardizedFileURL.path, target.path.hasPrefix(folder + "/") {
            openDocument(String(target.path.dropFirst(folder.count + 1)))
        } else {
            NSWorkspace.shared.open(target)
        }
    }

    /// Focuses the session's tab, resuming it if it's closed. A session open in another app shows
    /// the console's explain-and-fork message (DB-3) when its tab comes up.
    public func openSessionLink(_ id: String) {
        if let s = fixture.archivedSessions?.first(where: { $0.sessionId == id }) {
            return info("\(s.name) is archived. Unarchive it from \(s.project)'s Archived fold to open it.")
        }
        guard let s = fixture.sessions.first(where: { $0.sessionId == id }) else {
            return info("No session with the id \(id.prefix(8))… is listed. It may have been deleted, or it ran on another Mac.")
        }
        if s.project == fixture.home?.name, altitude.isAllProjects { homeTab = s.tabKey; focusHomeRequest += 1; return }
        // Within the project already (a link in one of its notes): keep the note on screen.
        if currentProject?.name != s.project { open(project: s.project) }
        openConsoleTab(s.tabKey)
    }
}
