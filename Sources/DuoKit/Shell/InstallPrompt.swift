import AppKit
import DuoControl

/// Asks once whether Duo may install what lets Claude sessions outside Duo use `duo2` (DL-75),
/// naming every change; asks again only when that list changes. Then keeps it current at every
/// launch (DL-74). Declining leaves Duo working: its own sessions get the primer directly.
@MainActor
public enum InstallPrompt {
    public static func run(cli: String) {
        if Installer.needsConsent(cli: cli) {
            let alert = NSAlert()
            alert.messageText = "Let Claude sessions outside Duo use it?"
            alert.informativeText = "Duo's own sessions already know about duo2. To let any Claude session on this Mac use it, Duo would:\n\n"
                + Installer.plannedChanges(cli: cli).map { "• " + $0 }.joined(separator: "\n\n")
            alert.addButton(withTitle: "Install")
            alert.addButton(withTitle: "Not Now")
            Installer.recordConsent(alert.runModal() == .alertFirstButtonReturn, cli: cli)
        }
        let report = Installer.install(cli: cli)
        if !report.lines.isEmpty { FileHandle.standardError.write(Data(("install: " + report.lines.joined(separator: " | ") + "\n").utf8)) }
    }
}
