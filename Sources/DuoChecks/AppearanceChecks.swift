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
    // Style audit fix list: the terminal has a palette per scheme (the same in light and dark for now), and the web gets every token.
    check(DuoScheme.light.terminal.ansi == DuoScheme.dark.terminal.ansi && DuoScheme.dark.terminal.ansi.count == 16, "the terminal palette is picked by scheme; dark takes the base while it has no override of its own")
    let css = EditorController.tokenCSS()
    check(DuoWebTokens.colors.count == 39 && DuoWebTokens.colors.allSatisfy { css.contains("--duo-\($0.name):") }, "the web pages get all 39 colours as variables, generated from tokens")
    check(css.contains("--duo-font-ui:") && css.contains("--duo-font-mono:") && css.contains("--duo-font-document:") && css.contains("--duo-document-size: 13px") && css.contains("--duo-shadow-popover: 0px 12px 32px"), "the web pages get the faces, the document's type and the whole popover shadow")
    check(AppearanceSetting.allCases.map(\.rawValue) == ["system", "light", "dark"], "the setting is system, light or dark")

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
    check(Mirror(reflecting: DuoState()).children.count == 26, "a field added to DuoState is added to this check (and to its decoder) too")
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
