import AppKit
import Foundation

/// When the user last typed into each session, by its key, from their own keystrokes only: a key
/// monitor sees what reaches a Claude terminal or a chat's composer. Duo's own pastes (Send to
/// Claude, drafts, a director's message) make no key events, so they never count. DL-199's
/// guards read it: Duo doesn't press Enter in a worker the user typed into recently, and DL-200's
/// "typing in a worker pauses its director there" counts from it.
@MainActor
public enum UserTyping {
    static var last: [String: Date] = [:]
    /// When a director last sent to each worker (in this run of Duo).
    static var directorSent: [String: Date] = [:]
    static var installed = false

    /// Called on each keystroke's session (the app persists a directed worker's pause, DL-200).
    public static var onType: (@MainActor (String) -> Void)?
    public static func note(_ key: String, at date: Date = Date()) { last[key] = date; onType?(key) }
    public static func lastKey(_ key: String) -> Date? { last[key] }
    public static func noteDirectorSend(_ key: String, at date: Date = Date()) { directorSent[key] = date }

    /// The user typed into it since its director's last message (or ever, if it never sent one):
    /// the director is paused there until the user hands it back (DL-200).
    public static func pausedSinceDirector(_ key: String) -> Date? {
        guard let k = last[key] else { return nil }
        if let s = directorSent[key], s >= k { return nil }
        return k
    }

    /// Forget everything (the checks).
    public static func reset() { last = [:]; directorSent = [:] }

    /// The session a responder types into: a terminal's key, or a chat composer's session.
    static func key(of responder: NSResponder?, terminals: TerminalStore) -> String? {
        if let v = responder as? GuardedTerminalView { return terminals.all.first { $0.view === v }?.key }
        if let c = responder as? ComposerTextView { return c.coordinator?.chat.key }
        return nil
    }

    /// Installs the key monitor once (live mode).
    static func install(terminals: TerminalStore) {
        guard !installed else { return }
        installed = true
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak terminals] e in
            MainActor.assumeIsolated {
                if let terminals, let k = key(of: e.window?.firstResponder, terminals: terminals) { note(k) }
            }
            return e
        }
    }
}
