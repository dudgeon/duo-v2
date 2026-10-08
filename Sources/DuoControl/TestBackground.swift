import Foundation

/// Whether this launch runs in the background (F-227): a test launch never takes the user's focus
/// or shows a window in their way. It runs as an accessory app (no Dock icon, no menu bar), never
/// activates, and its windows are drawn but transparent and click-through, so captures, terminals,
/// web views and the first responder all work as on screen.
///
/// A background launch is an isolated one (F-113) that a script started: a scripted flag
/// (`SupportFolder.scriptedFlags`) or an explicit `DUO_SUPPORT_DIR`. The user's own Duo (the real
/// support folder) and a release never are; nor is a test build opened plainly from Finder, which
/// shows as before. `DUO_TEST_FOREGROUND=1` brings a test launch forward for the rare visible gate
/// (check-scale's numbers, perf runs); those need Geoff's OK first (CLAUDE.md, Visible test runs).
public enum TestBackground {
    public static let foregroundVariable = "DUO_TEST_FOREGROUND"

    /// Decided at launch, from the arguments and the environment as the process started (before
    /// `SupportFolder.prepareForLaunch` sets `DUO_SUPPORT_DIR`), and whether the folder is isolated.
    public static func decide(arguments: [String], environment: [String: String], isolated: Bool) -> Bool {
        guard isolated, environment[foregroundVariable] != "1" else { return false }
        let given = environment[SupportFolder.variable].map { !$0.isEmpty } ?? false
        return given || SupportFolder.isScripted(arguments)
    }

    /// This process's answer, set once by the app at launch.
    nonisolated(unsafe) public static var isOn = false
}
