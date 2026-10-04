import AppKit

/// Every question or notice Duo shows, as a sheet on its window. An app-modal alert
/// (`runModal`) stops the main run loop: `duo2`, Claude's edit hook and the 2-second refresh all
/// wait until it's answered, so one unanswered question froze Duo for Claude and for scripts
/// (F-54). A sheet blocks only the window. Sheets queue: a second waits for the first.
@MainActor
public enum DuoAlert {
    public static func present(_ alert: NSAlert, then: @escaping @MainActor (NSApplication.ModalResponse) -> Void = { _ in }) {
        guard let window = NSApp.windows.first(where: { $0.title == "Duo" && $0.isVisible }) else {
            // No window yet (launch): try again shortly rather than block.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { MainActor.assumeIsolated { present(alert, then: then) } }
            return
        }
        if window.attachedSheet != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { MainActor.assumeIsolated { present(alert, then: then) } }
            return
        }
        alert.beginSheetModal(for: window) { r in MainActor.assumeIsolated { then(r) } }
    }
}
