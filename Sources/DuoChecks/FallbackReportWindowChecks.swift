import AppKit
import DuoKit
import Foundation

// F-749: the Debug report as a window to photograph in one shot, with Copy Report and Save to Project. Drawn off
// screen (no window is shown); the captures go to build/fallback-report/ for Geoff.
@MainActor func fallbackReportWindowChecks(_ report: String, folder: URL) throws {
    print("chat mode: the fallback report window, to photograph (F-749)")
    let cols = ChatFallbackReport.columns(report)
    check(cols.screen.hasPrefix("Screen the reader judged") && cols.screen.contains(" | ") && !cols.summary.contains("Screen the reader judged")
          && cols.summary.contains("rule: hooks-silent") && cols.summary.contains("Chat state history"),
          "the report splits in two: the judged screen on the right, the rest on the left in order")
    let out = repoRoot().appending(path: "build/fallback-report")
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    // The window is 94% of the visible screen: a 14-inch MacBook Pro's (1512 × 945, less the menu bar) and a 1080p display.
    for (name, screen) in [("laptop-1512", NSSize(width: 1512, height: 945 - 37)), ("display-1920", NSSize(width: 1920, height: 1080 - 25))] {
        let size = NSSize(width: (screen.width * 0.94).rounded(), height: (screen.height * 0.94 - 28).rounded())
        let v = FallbackReportView(report: report, save: nil, close: {})
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            v.appearance = NSAppearance(named: appearance)
            var png: Data?
            NSAppearance(named: appearance)!.performAsCurrentDrawingAppearance { png = v.png(size: size) }
            let file = out.appending(path: "\(name)-\(appearance == .aqua ? "light" : "dark").png")
            try png?.write(to: file)
            check(v.summaryOverflow() <= 0.5, "\(name) \(appearance == .aqua ? "light" : "dark"): every summary line wraps inside the visible column (overflow \(v.summaryOverflow()) pt)")
            check(png != nil && v.fontSize >= 11, "\(name) \(appearance == .aqua ? "light" : "dark"): the whole report fits at \(v.fontSize) pt (\(file.path))")
        }
    }
    let saved = try ChatFallbackReport.save(report, folder: folder, at: Date(timeIntervalSince1970: 1_790_000_000))
    check(saved.path.hasPrefix(folder.appending(path: ".duo/chat-reports").path) && (try? String(contentsOf: saved, encoding: .utf8))?.hasPrefix(report) == true,
          "Save to Project writes the report into the session's folder (\(saved.lastPathComponent))")
}
