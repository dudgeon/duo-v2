import AppKit
import DuoControl
import DuoKit
import Foundation

// Multi-window slice 1 (DL-311; docs/design/multi-window-handoff): the window registry, a project in one
// window (DL-308), the colour order (DL-312, DL-313), Classic (board 4c A), Home in one window (Q-431),
// which window duo2 acts on (Q-430), and C-150's passes with two windows. No AppKit windows: the core's
// hooks stay nil, and every window is a model. `DUO_CHECKS=windows swift run DuoChecks`.
@MainActor func multiWindowChecks() throws {
    print("multi-window slice 1: the registry, DL-308, colours, Classic, Home, duo2's window (Q-430), C-150")
    _ = NSApplication.shared
    let f = try repoFixture()
    let core = AppCore(fixture: f)
    core.setColourNewWindows(true, save: false)
    let one = AppModel(core: core)
    let projects = f.projects.filter { $0.name != f.home?.name }.map(\.name)
    let (p, q) = (projects[0], projects[1])

    // MARK: The registry
    check(one.windowNumber == 1 && one.windowColourID == nil, "the first window is window 1, None (board 4b A)")
    check(one.windowTitle == "Duo", "a window at All projects is titled Duo (DL-311)")
    let two = core.openWindow()
    check(core.models.count == 2 && core.primary === one && two.windowNumber == 2, "New Window adds window 2; window 1 stays the primary")
    check(two.altitude == .allProjects, "a new window opens at All projects (board 1 A)")
    check(core.focusLog.last == 2, "the new window comes forward")
    let three = core.openWindow(project: q)
    check(three.windowNumber == 3 && three.altitude == .project(q) && three.windowTitle == q, "Open in New Window opens the project in window 3, titled by it")
    check(core.model(named: "3") === three && core.model(named: q) === three && core.model(named: "9") == nil, "a window by number or by its project")

    // MARK: DL-308: a project lives in one window
    let before = core.models.count
    let again = core.openWindow(project: q)
    check(again === three && core.models.count == before && core.focusLog.last == 3, "Open in New Window on a project a window shows brings that window forward")
    let shown = one.open(project: q)
    check(shown === three && one.altitude == .allProjects, "opening it from another window brings its window forward; that window stays put")
    one.open(project: p)
    check(one.altitude == .project(p) && core.model(showing: p) === one, "a project no window shows opens where you are")
    let sessionInQ = f.sessions.first { $0.project == q }
    if let s = sessionInQ {
        _ = one.open(project: q, session: s.name)
        check(three.consoleTab == s.tabKey && one.altitude == .project(p), "a session asked for opens in its project's window")
    }

    // MARK: Colours (DL-312, DL-313)
    let order = DuoWindowColour.all.map(\.id)
    check(order == ["blue", "ochre", "purple", "green", "coral", "teal", "deep-blue", "deep-ochre", "deep-purple", "deep-green", "deep-coral", "deep-teal"],
          "the order is Blue, Ochre, Purple, Green, Coral, Teal, then the deep steps (DL-313)")
    check(two.windowColourID == "blue" && three.windowColourID == "ochre", "new windows take Blue, then Ochre")
    check(AppCore.nextColour(taken: []).id == "blue", "no colour taken: Blue")
    check(AppCore.nextColour(taken: [nil, "blue", "purple"]).id == "ochre", "the first colour no open window has")
    check(AppCore.nextColour(taken: Array(order.prefix(6))).id == "deep-blue", "all light taken: the deep steps")
    check(AppCore.nextColour(taken: order).id == "blue" && AppCore.nextColour(taken: order + ["blue"]).id == "ochre", "all twelve taken: round again, fewest first (Q-444)")
    do {
        let c = AppCore(fixture: f); c.setColourNewWindows(true, save: false)
        let first = AppModel(core: c)
        let more = (0..<12).map { _ in c.openWelcomeWindowForChecks() }
        check(first.windowColourID == nil && more.map { $0.windowColourID ?? "none" } == order, "twelve new windows take the twelve colours in order")
        c.closeWindow(more[1])   // ochre's window closes
        check(c.openWelcomeWindowForChecks().windowColourID == "ochre", "a closed window's colour is the next one free")
        c.setColourNewWindows(false, save: false)
        check(c.openWelcomeWindowForChecks().windowColourID == nil, "with the switch off, new windows open None (DL-312)")
    }
    two.setWindowColour("deep-teal")
    check(two.windowColour?.name == "Deep teal", "a window's colour can be changed (swatch, Window › Window Colour)")
    let blue = DuoWindowColour.all[0]
    check(WindowTint.nsColor(.ground, blue) != DuoNSColor.ground && WindowTint.nsColor(.pane, nil) === DuoNSColor.pane, "a colour overrides its surfaces; None draws the plain tokens")
    func hex(_ c: NSColor, _ a: NSAppearance.Name) -> String {
        var s = ""
        NSAppearance(named: a)!.performAsCurrentDrawingAppearance {
            let r = c.usingColorSpace(.sRGB)!
            s = String(format: "#%02X%02X%02X", Int(round(r.redComponent * 255)), Int(round(r.greenComponent * 255)), Int(round(r.blueComponent * 255)))
        }
        return s
    }
    check(hex(WindowTint.nsColor(.ground, blue), .aqua) == "#B2D5FA" && hex(WindowTint.nsColor(.ground, blue), .darkAqua) == "#2266A4", "Blue's toolbar is #B2D5FA light, #2266A4 dark (palette.json)")
    check(hex(WindowTint.nsColor(.pane, blue), .aqua) == "#ECF4FD" && hex(WindowTint.nsColor(.chatGround, blue), .darkAqua) == "#0C1218", "Blue's pane and chat tints")
    two.setWindowColour("blue")
    check(two.toolbarText2 == DuoColor.text && one.toolbarText2 == DuoColor.text2, "on a coloured toolbar text2 draws as text (DL-313)")

    // MARK: Classic (board 4c A)
    DuoScheme.classicActive = true
    NotificationCenter.default.post(name: DuoScheme.didChange, object: nil)
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    check(core.classicOn && two.windowColour == nil && two.windowColourID == "blue", "Classic turns window colours off, and each window keeps its colour")
    check(two.toolbarText2 == DuoColor.text2, "under Classic the toolbar is Classic's")
    DuoScheme.classicActive = false
    NotificationCenter.default.post(name: DuoScheme.didChange, object: nil)
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    check(!core.classicOn && two.windowColour?.id == "blue", "each window gets its colour back after Classic")

    // MARK: Home in one window (Q-431)
    check(one.ownsHome && !two.ownsHome && core.homeOwner === one, "Home is live in the primary at first")
    core.showHome(in: two)
    check(two.ownsHome && !one.ownsHome, "Show Here moves Home to this window")
    core.detach(two)
    check(core.homeOwner === one, "when Home's window closes, Home goes back to the primary")
    check(core.closeWindow(three) && core.models.count == 1, "Close Window closes a second window")
    check(!core.closeWindow(one) && core.models.count == 1, "the last window only hides; Duo keeps running")
    check(core.freeWindowNumber() == 2, "a closed window's number is free again")

    // MARK: duo2's window (Q-430)
    let w2 = core.openWindow(project: q)   // window 2 on q
    func req(_ cmd: String, _ args: [String], session: String? = nil) -> ControlRequest { ControlRequest(token: "", command: cmd, args: args, session: session) }
    var t = core.target(for: req("status", ["--window", "2"]))
    check(t.model === w2 && t.request.args.isEmpty, "--window <n> picks window n and is taken out of the arguments")
    t = core.target(for: req("view", ["sidebar", "--window=\(q)", "hide"]))
    check(t.model === w2 && t.request.args == ["sidebar", "hide"], "--window=<project> picks the window showing it")
    t = core.target(for: req("status", ["--window", "7"]))
    check(t.model == nil && t.error?.contains("no window '7'") == true, "an unknown window is an error, never a guess")
    check(core.target(for: req("status", [])).model === one, "no session and no --window: the primary window")
    if let s = sessionInQ, let sid = s.sessionId {
        check(core.target(for: req("status", [], session: sid)).model === w2, "the caller's session's window: the window on its project")
    }
    core.keyWindowID = ObjectIdentifier(NSObject())   // some other window is key
    check(core.target(for: req("status", [])).model === one, "never the key window")
    var out: ControlResponse?
    core.handle(req("window", ["list"])) { out = $0 }
    check(out?.ok == true && out?.output.split(separator: "\n").count == 2 && out?.output.contains(q) == true, "duo2 window list lists both windows")
    core.handle(req("window", ["colour", "coral", "--window", "2"])) { out = $0 }
    check(out?.ok == true && w2.windowColourID == "coral" && one.windowColourID == nil, "duo2 window colour <name> --window 2 colours window 2 only")
    core.handle(req("window", ["colour", "chartreuse"])) { out = $0 }
    check(out?.ok == false, "an unknown colour is refused")
    core.handle(req("open", [q])) { out = $0 }
    check(out?.ok == true && one.altitude == .project(p) && core.focusLog.last == 2, "duo2 open <project> from the primary brings its window forward (DL-308)")
    core.handle(req("window", ["focus", "1"])) { out = $0 }
    check(out?.ok == true && core.focusLog.last == 1, "duo2 window focus 1")
    core.handle(req("window", ["home", "--window", "2"])) { out = $0 }
    check(w2.ownsHome, "duo2 window home --window 2 is Show Here in window 2")
    core.handle(req("window", ["new"])) { out = $0 }
    check(out?.ok == true && core.models.count == 3, "duo2 window new opens a window")
    let w3 = core.models[2]
    core.handle(req("window", ["close", "3"])) { out = $0 }
    check(out?.ok == true && core.models.count == 2 && !core.models.contains { $0 === w3 }, "duo2 window close 3")
    core.handle(req("status", [])) { out = $0 }
    check(out?.output.contains("window 1 of 2") == true, "status lists the windows")

    // MARK: C-150: the app-wide passes see every window
    if let s = sessionInQ {
        w2.consoleTab = s.tabKey
        check(core.visibleSessionIds.contains(s.tabKey) && one.consoleTab != s.tabKey,
              "a session on screen only in window 2 counts as on screen (notify skips it)")
        check(core.model(forProject: q) === w2 && core.model(forProject: "nowhere") === core.keyModel, "a notification or Dock click goes to its project's window, else the key window")
        let focused = core.focusLog.count
        one.openFromNotification(sessionId: s.sessionId ?? "", project: q)
        check(one.altitude == .project(p) && (s.sessionId == nil || w2.selectedActionSession == s.id) && core.focusLog.count > focused && core.focusLog.last == 2,
              "a notification clicked from the primary's Notifier opens window 2, which shows the project")
    }
}

extension AppCore {
    /// A new window with no project, as File › New Window makes it.
    @MainActor func openWelcomeWindowForChecks() -> AppModel { openWindow() }
}
