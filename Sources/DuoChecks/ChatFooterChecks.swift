import DuoKit
import Foundation

// C-78, F-281: chat finds the footer's mode and busy rows by content. Claude Code 2.1.287+ draws each
// mod's `$.ui.status` line (`⚠ <mod>: <text>`) under the input box, above the mode row, so the mode
// row is the first, second, third… row below the last rule.

private let footerRule = String(repeating: "─", count: 100)

/// A screen in the shape of 2.1.296's with `mods` status lines between the box and the mode row.
private func footerScreen(mods: Int, mode: String, busy: Bool, menu: [String] = [], statusText: [String] = []) -> String {
    var rows = ["  ⏺ Earlier reply.", "", "", "                                                        ◐ medium · /effort",
                footerRule, "❯ ", footerRule]
    for i in 0..<mods { rows.append("  ⚠ mod\(i): " + (i < statusText.count ? statusText[i] : "ready \(i)")) }
    rows.append("  " + mode + (busy ? " · esc to interrupt" : " (shift+tab to cycle)") + " · ← for agents")
    rows += menu
    return rows.joined(separator: "\n")
}

@MainActor func chatFooterChecks() {
    print("chat mode: the footer's mode and busy rows are found by content, under any number of mod status lines (C-78)")
    let modes: [(String, ChatPermissionMode)] = [("⏸ manual mode on", .manual), ("⏵⏵ accept edits on", .acceptEdits), ("⏸ plan mode on", .plan),
                                                 ("⏵⏵ auto mode on", .auto), ("⏵⏵ bypass permissions on", .bypass)]
    var wrong: [String] = []
    for mods in 0...3 {
        for (text, mode) in modes {
            for busy in [false, true] {
                let r = ChatScreenReader.read(footerScreen(mods: mods, mode: text, busy: busy))
                if r.mode != mode || r.kind != (busy ? .busy : .idle) { wrong.append("\(mods) mods, \(mode), busy \(busy): \(String(describing: r.mode)) \(r.kind)") }
            }
        }
    }
    check(wrong.isEmpty, "0 to 3 mod status lines, busy and idle, in each mode: mode and busy read right (\(wrong))")

    // A status line may say anything; the `⚠` row is never the footer.
    let tricky = footerScreen(mods: 2, mode: "⏸ manual mode on", busy: false, statusText: ["plan mode on · esc to interrupt", "bypass permissions on"])
    let t = ChatScreenReader.read(tricky)
    check(t.mode == .manual && t.kind == .idle, "a status line that quotes a mode or `esc to interrupt` is not the footer (\(String(describing: t.mode)) \(t.kind))")

    // 2.1.219 draws the `/` menu under the box, from column 0; its rows hold words the signatures know.
    let menu = ["/plan                         plan mode on, esc to interrupt", "/auto                         auto mode on",
                "/permissions                  bypass permissions on", "/model                        Set the AI model for Claude Code"]
    let m = ChatScreenReader.read(footerScreen(mods: 0, mode: "⏸ manual mode on", busy: false, menu: menu))
    check(m.mode == .manual && m.kind == .idle && m.commands.map(\.name).contains("/plan"),
          "2.1.219's `/` menu below the box: its rows are not the mode or the busy row, and still list as commands (\(String(describing: m.mode)) \(m.kind))")
    let mm = ChatScreenReader.read(footerScreen(mods: 2, mode: "⏸ manual mode on", busy: true, menu: menu))
    check(mm.mode == .manual && mm.kind == .busy, "the menu open under two status lines and a busy mode row: still manual and busy")
    // Without a mode row the menu must not invent one.
    var bare = footerScreen(mods: 0, mode: "x", busy: false, menu: menu).components(separatedBy: "\n")
    bare.remove(at: 7)
    let b = ChatScreenReader.read(bare.joined(separator: "\n"))
    check(b.mode == nil && b.kind == .idle, "a menu with no mode row reads no mode and not busy")

    // The captured screens still read as before.
    let idle219 = ChatScreenReader.read(chipScreen("idle-2.1.219.txt")), idle296 = ChatScreenReader.read(chipScreen("idle-2.1.296.txt"))
    check(idle296.mode == .auto && idle296.kind == .idle && idle219.kind == .idle, "the captured idle screens (2.1.296, 2.1.219) read as before")
}
