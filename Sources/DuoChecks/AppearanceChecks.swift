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
    check(AppearanceSetting.allCases.map(\.rawValue) == ["system", "light", "dark"], "the setting is system, light or dark")
}
