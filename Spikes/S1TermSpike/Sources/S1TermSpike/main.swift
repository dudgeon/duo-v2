import AppKit
import SwiftTerm

// Spike S1: run a command in a SwiftTerm view, optionally resize / hide it, capture it, report.
//
//   S1TermSpike [--cmd claude] [--cols 100 --rows 32] [--term-program X] [--capture out.png]
//               [--after 4] [--resize 70x20] [--hide] [--report]
//
// Prints child pid and the child's CLAUDE* environment so the scrub can be checked.

struct Opts {
    var cmd = "claude"
    var args: [String] = []
    var cols = 100, rows = 32
    var termProgram: String?
    var capture: String?
    var after = 4.0
    var resize: (Int, Int)?
    var hide = false
    var metal = false
}

nonisolated(unsafe) var o = Opts()
var it = CommandLine.arguments.dropFirst().makeIterator()
while let a = it.next() {
    switch a {
    case "--cmd": o.cmd = it.next()!
    case "--arg": o.args.append(it.next()!)
    case "--cols": o.cols = Int(it.next()!)!
    case "--rows": o.rows = Int(it.next()!)!
    case "--term-program": o.termProgram = it.next()
    case "--capture": o.capture = it.next()
    case "--after": o.after = Double(it.next()!)!
    case "--resize":
        let p = it.next()!.split(separator: "x").map { Int($0)! }; o.resize = (p[0], p[1])
    case "--hide": o.hide = (it.next() ?? "on") == "on"
    case "--metal": o.metal = (it.next() ?? "on") == "on"
    default: break
    }
}

/// The scrubbed environment: everything except variables a parent Claude Code session leaks
/// (CLAUDECODE, CLAUDE_CODE_*, CLAUDE_PID, ...). CLAUDE_CONFIG_DIR is the user's and is kept.
func childEnvironment() -> [String] {
    var env = ProcessInfo.processInfo.environment.filter { k, _ in
        !(k == "CLAUDECODE" || (k.hasPrefix("CLAUDE_") && k != "CLAUDE_CONFIG_DIR"))
    }
    env["TERM"] = "xterm-256color"
    env["COLORTERM"] = "truecolor"
    env["LANG"] = env["LANG"] ?? "en_US.UTF-8"
    if let t = o.termProgram { env["TERM_PROGRAM"] = t } else { env.removeValue(forKey: "TERM_PROGRAM") }
    return env.map { "\($0.key)=\($0.value)" }
}

final class Delegate: NSObject, NSApplicationDelegate, LocalProcessTerminalViewDelegate {
    var window: NSWindow!
    var term: LocalProcessTerminalView!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .aqua)
        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let probe = NSAttributedString(string: "W", attributes: [.font: font]).size()
        let cell = CGSize(width: probe.width, height: ceil(font.ascender - font.descender + font.leading))
        let size = CGSize(width: cell.width * CGFloat(o.cols) + 4, height: cell.height * CGFloat(o.rows) + 4)
        window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .resizable, .closable], backing: .buffered, defer: false)
        window.colorSpace = .sRGB
        term = LocalProcessTerminalView(frame: NSRect(origin: .zero, size: size))
        term.font = font
        term.nativeBackgroundColor = NSColor(srgbRed: 0x15/255, green: 0x17/255, blue: 0x1B/255, alpha: 1)  // console
        term.nativeForegroundColor = NSColor(srgbRed: 0xE6/255, green: 0xE8/255, blue: 0xEB/255, alpha: 1) // consoleText
        term.processDelegate = self
        if o.metal { try? term.setUseMetal(true) }
        window.contentView = term
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()

        let cwd = FileManager.default.temporaryDirectory.appending(path: "s1-spike").path
        try? FileManager.default.createDirectory(atPath: cwd, withIntermediateDirectories: true)
        let exe = o.cmd.hasPrefix("/") ? o.cmd : "/usr/bin/env"
        let args = o.cmd.hasPrefix("/") ? o.args : [o.cmd] + o.args
        term.startProcess(executable: exe, args: args, environment: childEnvironment(), execName: nil, currentDirectory: cwd)
        print("started \(o.cmd) pid=\(term.process.shellPid) in \(cwd) grid=\(o.cols)x\(o.rows)")
        report(childPid: term.process.shellPid)

        if let (c, r) = o.resize {
            DispatchQueue.main.asyncAfter(deadline: .now() + o.after / 2) {
                self.window.setContentSize(CGSize(width: cell.width * CGFloat(c) + 4, height: cell.height * CGFloat(r) + 4))
                print("resized to \(c)x\(r)")
            }
        }
        if o.hide {
            DispatchQueue.main.asyncAfter(deadline: .now() + o.after / 2) { self.term.isHidden = true; print("hidden") }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + o.after) {
            if o.hide { self.term.isHidden = false }
            let alive = kill(self.term.process.shellPid, 0) == 0
            print("child alive after \(o.after)s: \(alive)")
            if let path = o.capture, let layer = self.term.layer {
                let scale: CGFloat = 2
                let w = Int(self.term.bounds.width * scale), h = Int(self.term.bounds.height * scale)
                if let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                       space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
                    ctx.scaleBy(x: scale, y: scale)
                    _ = layer
                    // Draw the view directly: SwiftTerm's frame driver bypasses cacheDisplay.
                    NSGraphicsContext.saveGraphicsState()
                    let ns = NSGraphicsContext(cgContext: ctx, flipped: self.term.isFlipped)
                    NSGraphicsContext.current = ns
                    if self.term.isFlipped { ctx.translateBy(x: 0, y: self.term.bounds.height); ctx.scaleBy(x: 1, y: -1) }
                    self.term.draw(self.term.bounds)
                    NSGraphicsContext.restoreGraphicsState()
                    if let img = ctx.makeImage() {
                        try? NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
                        print("captured \(path)")
                    }
                }
            }
            // The screen as text (SwiftTerm 2.0 keeps its Terminal internal; select-all reads it).
            self.term.selectAll()
            let text = self.term.getSelection() ?? ""
            print("---- screen ----")
            for (i, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                print(String(format: "%02d|", i) + line)
            }
            print("---- end ----")

            self.term.process.terminate()
            exit(0)
        }
    }

    func report(childPid: pid_t) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/ps")
            p.arguments = ["eww", "-o", "command=", "-p", String(childPid)]
            let pipe = Pipe(); p.standardOutput = pipe
            try? p.run(); p.waitUntilExit()
            let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let leaked = out.split(separator: " ").filter { $0.hasPrefix("CLAUDE") && !$0.hasPrefix("CLAUDE_CONFIG_DIR") }
            print("child CLAUDE* env vars: \(leaked.isEmpty ? "none" : leaked.map { String($0.split(separator: "=")[0]) }.joined(separator: ","))")
        }
    }

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) { print("grid now \(newCols)x\(newRows)") }
    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    func processTerminated(source: TerminalView, exitCode: Int32?) { print("process exited \(exitCode.map(String.init) ?? "?")") }
}

let app = NSApplication.shared
let delegate = Delegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
