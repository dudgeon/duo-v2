import AppKit
import Foundation

/// Probes for the perf regression checks (F-600): real DuoKit views driven by hand, counted with `Work`.
@MainActor public enum PerfProbe {
    /// One terminal mic over a Claude terminal showing `screen` (no window, so its own 20 Hz timer never starts): screen
    /// reads over `ticks` idle ticks, then over two ticks after new output, then after an input event (F-599, F-600).
    public static func micReads(screen: String, ticks: Int) -> (idle: Int, afterOutput: Int, afterInput: Int) {
        let s = TerminalSession(key: "perf-probe", command: .newClaude(sessionID: UUID().uuidString.lowercased(), prompt: nil), cwd: NSTemporaryDirectory(), running: false)
        s.view.resize(cols: 80, rows: 24)
        func settle() { RunLoop.main.run(until: Date().addingTimeInterval(0.15)) }
        s.view.feed(text: screen.replacingOccurrences(of: "\n", with: "\r\n"))
        settle()
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 660, height: 420))
        host.addSubview(s.view)
        let mic = TerminalMicView(frame: NSRect(origin: .zero, size: TerminalMicView.size))
        host.addSubview(mic)
        mic.session = s
        Work.reset()
        for _ in 0..<ticks { mic.tick() }
        let idle = Work.value(.micScreenRead)
        s.view.feed(text: "\r\nmore output\r\n")
        settle()
        Work.reset()
        mic.tick(); mic.tick()
        let afterOutput = Work.value(.micScreenRead)
        TerminalMicView.inputGeneration &+= 1
        Work.reset()
        mic.tick(); mic.tick()
        return (idle, afterOutput, Work.value(.micScreenRead))
    }
}
