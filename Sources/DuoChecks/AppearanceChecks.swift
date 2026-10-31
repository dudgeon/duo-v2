import AppKit
import DuoKit
import Foundation

// The dark appearance (DL-224): Dark B "Ink" values resolve by appearance, and the setting names its three choices.
@MainActor func appearanceChecks() throws {
    print("dark appearance: tokens by appearance, the setting (DL-224)")
    func hex(_ c: NSColor, _ name: NSAppearance.Name) -> String {
        var out = ""
        NSAppearance(named: name)!.performAsCurrentDrawingAppearance {
            let s = c.usingColorSpace(.sRGB) ?? c
            out = String(format: "#%02X%02X%02X", Int(round(s.redComponent * 255)), Int(round(s.greenComponent * 255)), Int(round(s.blueComponent * 255)))
        }
        return out
    }
    check(hex(DuoNSColor.ground, .aqua) == "#F3F4F6" && hex(DuoNSColor.ground, .darkAqua) == "#131518", "ground: light as before, Ink in dark")
    check(hex(DuoNSColor.console, .aqua) == "#15171B" && hex(DuoNSColor.console, .darkAqua) == "#0C0D10", "the console stays in light and sinks in dark")
    check(hex(DuoNSColor.chatGround, .aqua) == "#F3F4F6" && hex(DuoNSColor.chatGround, .darkAqua) == "#0C0D10", "chat's ground is the console colour in dark only")
    check(hex(DuoNSColor.needsYou, .darkAqua) == "#F97316" && hex(DuoNSColor.onNeedsYou, .darkAqua) == "#0C0D10", "the accent is the console's orange in dark, with dark text on it")
    // Classic (DL-252, option C'): legacy Duo's paper, as one more answer from the same colour providers, light only.
    print("Classic: a tokens block, no per-view code")
    DuoScheme.classicActive = true
    defer { DuoScheme.classicActive = false }
    check(hex(DuoNSColor.ground, .aqua) == "#F0E9D6" && hex(DuoNSColor.pane, .aqua) == "#FBF8EE" && hex(DuoNSColor.text, .aqua) == "#1A1410", "Classic: paper-deep ground, paper pane, ink text")
    check(hex(DuoNSColor.selected, .aqua) == "#F2D9B8" && hex(DuoNSColor.paneFocus, .aqua) == "#C66A2E" && hex(DuoNSColor.paneFocusOnConsole, .aqua) == "#E08F4A", "Classic: selected in accent-soft, the active-pane rule in orange")
    check(hex(DuoNSColor.needsYou, .aqua) == "#B91C1C" && hex(DuoNSColor.needsYouOnConsole, .aqua) == "#DC2626", "Classic: needs you is red, so orange never means two things")
    check(hex(DuoNSColor.console, .aqua) == "#1A1410" && hex(DuoNSColor.consoleText, .aqua) == "#F0E9D6", "Classic: the brown-black console")
    check(hex(DuoNSColor.console, .darkAqua) == "#0C0D10" && hex(DuoNSColor.ground, .darkAqua) == "#131518", "Classic is light only: dark ignores it")
    check(hex(DuoNSColor.diffDelText, .aqua) == "#B42318", "Classic leaves a token it doesn't list alone (diffDelText)")
    check(DuoScheme.classic.terminal.ansi != DuoScheme.light.terminal.ansi && DuoScheme.classic.document.size == 16 && DuoScheme.classic.document.lineHeight == 27
          && DuoScheme.classic.document.family == "font-serif" && DuoScheme.light.document.size == 13, "Classic's terminal is v1's warm palette and its page is New York 16/27")
    DuoScheme.classicActive = false
    check(hex(DuoNSColor.paneFocus, .aqua) == hex(DuoNSColor.text, .aqua) && hex(DuoNSColor.paneFocusOnConsole, .darkAqua) == hex(DuoNSColor.consoleText, .darkAqua)
          && hex(DuoNSColor.paneFocus, .aqua) == "#1F2328", "v2 draws the pane-focus rule in the text colour as before")

    // The guardrail that keeps "here" and "needs you" apart in every scheme: needs you stays 3:1 off the selected fill, and at least
    // 15 degrees of hue off the selected fill and the pane-focus rule (an achromatic colour has no hue to confuse).
    func rgb(_ c: NSColor, _ n: NSAppearance.Name) -> (Double, Double, Double) {
        var out = (0.0, 0.0, 0.0)
        NSAppearance(named: n)!.performAsCurrentDrawingAppearance {
            let s = c.usingColorSpace(.sRGB) ?? c
            out = (Double(s.redComponent), Double(s.greenComponent), Double(s.blueComponent))
        }
        return out
    }
    func lum(_ c: (Double, Double, Double)) -> Double {
        func f(_ v: Double) -> Double { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * f(c.0) + 0.7152 * f(c.1) + 0.0722 * f(c.2)
    }
    func ratio(_ a: (Double, Double, Double), _ b: (Double, Double, Double)) -> Double {
        let (x, y) = (lum(a), lum(b)); return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }
    func hue(_ c: (Double, Double, Double)) -> Double? {
        let (mx, mn) = (max(c.0, c.1, c.2), min(c.0, c.1, c.2))
        guard mx - mn > 0.12 else { return nil }   // nearly grey: no hue to confuse
        let d = mx - mn
        let h = mx == c.0 ? (c.1 - c.2) / d : mx == c.1 ? 2 + (c.2 - c.0) / d : 4 + (c.0 - c.1) / d
        return (h * 60 + 360).truncatingRemainder(dividingBy: 360)
    }
    func apart(_ a: (Double, Double, Double), _ b: (Double, Double, Double)) -> Bool {
        guard let x = hue(a), let y = hue(b) else { return true }
        let d = abs(x - y); return min(d, 360 - d) >= 15
    }
    for (scheme, name, classic) in [("light", NSAppearance.Name.aqua, false), ("dark", .darkAqua, false), ("classic", .aqua, true)] {
        DuoScheme.classicActive = classic
        let (ny, sel, focus) = (rgb(DuoNSColor.needsYou, name), rgb(DuoNSColor.selected, name), rgb(DuoNSColor.paneFocus, name))
        let (nyc, hov, focusc) = (rgb(DuoNSColor.needsYouOnConsole, name), rgb(DuoNSColor.consoleHover, name), rgb(DuoNSColor.paneFocusOnConsole, name))
        check(ratio(ny, sel) >= 3 && apart(ny, sel) && apart(ny, focus), "\(scheme): needs you is 3:1 and 15° of hue from selected, and 15° from the pane-focus rule")
        check(ratio(nyc, hov) >= 3 && apart(nyc, hov) && apart(nyc, focusc), "\(scheme): needs you on the console is 3:1 and 15° of hue from its hover fill, and 15° from the rule")
    }
    DuoScheme.classicActive = false

    // Style audit fix list: the terminal has a palette per scheme (the same in light and dark for now), and the web gets every token.
    check(DuoScheme.light.terminal.ansi == DuoScheme.dark.terminal.ansi && DuoScheme.dark.terminal.ansi.count == 16, "the terminal palette is picked by scheme; dark takes the base while it has no override of its own")
    let css = EditorController.tokenCSS()
    check(DuoWebTokens.colors.count == 41 && DuoWebTokens.colors.allSatisfy { css.contains("--duo-\($0.name):") }, "the web pages get all 41 colours as variables, generated from tokens")
    check(css.contains("--duo-font-ui:") && css.contains("--duo-font-mono:") && css.contains("--duo-font-document:") && css.contains("--duo-document-size: 13px") && css.contains("--duo-shadow-popover: 0px 12px 32px"), "the web pages get the faces, the document's type and the whole popover shadow")
    check(AppearanceSetting.allCases.map(\.rawValue) == ["system", "light", "dark", "classic"], "the setting is system, light, dark or classic")

    // C-122: Appearance stuck on Match System, and Light did nothing, on Geoff's Mac. DuoState's decoder never read `appearance`
    // back, so every load saw nil and every other update (which loads, changes and writes) wrote the file without it.
    print("C-122: the appearance setting survives the state file")
    let dir = FileManager.default.temporaryDirectory.appending(path: "duo-c122-\(getpid())")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let stateURL = dir.appending(path: "state.json")
    DuoState.update(stateURL) { $0.appearance = "light" }
    check(DuoState.load(stateURL).appearance == "light", "Light, saved, is Light when read back (it was Match System)")
    DuoState.update(stateURL) { $0.showHiddenFiles = true }
    check(DuoState.load(stateURL).appearance == "light" && DuoState.load(stateURL).showHiddenFiles, "another setting's write keeps the appearance (it used to drop it)")
    var full = DuoState()
    full.seen = ["a": 1]; full.home = "/h"; full.homePromptDismissed = true; full.foldedProperties = ["f"]; full.sourceDocuments = ["s"]
    full.reviewSessions = ["d": "s"]; full.forgottenFolders = ["x"]; full.notNowFolders = ["n"]; full.claudePath = "/c"; full.notifyNeedsYou = false
    full.dockBadge = false; full.appearance = "dark"; full.legacyDismissed = "l"; full.legacyBackup = "b"; full.root = "/r"; full.skippedUpdate = "1"
    full.gitignore = ["g": "y"]; full.projects = ["p"]; full.archivedProjects = ["ap"]; full.archivedSessions = ["as"]; full.mapSort = "name"
    full.homeView = "board"; full.showHiddenFiles = true; full.dismissedExplainers = ["e"]; full.keepRunning = ["k"]
    let again = try? JSONDecoder().decode(DuoState.self, from: JSONEncoder().encode(full))
    check(again == full, "every stored field of the state survives encode and decode")
    check(Mirror(reflecting: DuoState()).children.count == 27, "a field added to DuoState is added to this check (and to its decoder) too")
    check(AppearanceSetting.resolve(environment: "system", isolated: false, saved: "light") == .light, "DUO_APPEARANCE in the user's own Duo does not pin the picker")
    check(AppearanceSetting.resolve(environment: "dark", isolated: true, saved: "light") == .dark, "in a scripted, isolated run it still wins, for captures")
    // A failed write is reported, not swallowed; an unreadable file is left alone rather than written over.
    let blocker = dir.appending(path: "afile")
    try? Data("x".utf8).write(to: blocker)
    var thrown: DuoState.WriteError?
    do { try DuoState.write(blocker.appending(path: "state.json")) { $0.appearance = "dark" } } catch { thrown = error as? DuoState.WriteError }
    check(thrown != nil && DuoState.update(blocker.appending(path: "state.json"), { $0.appearance = "dark" }) == false, "a write that can't land throws and says so (it was try?)")
    let broken = dir.appending(path: "broken.json")
    try? Data("{ not json".utf8).write(to: broken)
    check((try? DuoState.write(broken) { $0.appearance = "dark" }) == nil && (try? String(contentsOf: broken, encoding: .utf8)) == "{ not json", "a state file that can't be read is not overwritten")
}
