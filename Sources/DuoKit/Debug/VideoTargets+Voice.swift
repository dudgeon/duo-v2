import AppKit
import Foundation

/// The 0.2.22 release film (`video/films/release-0-2-22`): Classic (DL-252) and voice input (DL-260 to DL-272), as window states
/// (`--state video-vc-*` and `video-vv-*`, with `--fixture video/fixture/fixture.json`). They stand on scene 5's project (the
/// shelf-scan window the intro and the 0.2.21 film use, Auto-add decision in chat), with:
/// - Classic: the window in Classic (the appearance is the app's own setting, applied as Settings does);
///   `video-vc-settings-*` are the Settings view itself, which `pipeline/capture.mjs` draws with `render-settings`.
/// - Voice, in chat: a real dictation of a spoken file (`video/fixture/dictation/chat.wav`) through voice input's own file
///   path at the pace it was spoken, so the recognizer settles a phrase at a time as it does from a microphone; each
///   `video-vv-chat-at-<tenths>` state is that run, captured that many tenths of a second in.
/// - Voice, in the terminal: the Tighten PRD goals tab's recorded Claude screen with the mic beside its input box, listening
///   with the level bars (from the chat run's levels), and the phrases in Claude's prompt as they were pasted.
/// - No microphone: the faint, struck-through mic (DL-265).
/// A microphone is "connected" in every state but `video-vv-nomic` (a fixed device, so the capture doesn't depend on the Mac's).
extension VideoTargets {
    nonisolated static let vvScreens = [
        "video-vc-classic", "video-vc-settings-light", "video-vc-settings-classic",
        "video-vv-chat-rest", "video-vv-chat-sent", "video-vv-nomic",
        "video-vv-chat-at-05", "video-vv-chat-at-10", "video-vv-chat-at-15", "video-vv-chat-at-20", "video-vv-chat-at-25", "video-vv-chat-at-30",
        "video-vv-chat-at-35", "video-vv-chat-at-40", "video-vv-chat-at-45", "video-vv-chat-at-50", "video-vv-chat-at-55", "video-vv-chat-at-60",
        "video-vv-chat-at-65", "video-vv-chat-at-70", "video-vv-chat-at-75", "video-vv-chat-at-80",
        "video-vv-chat-rec", "video-vv-term-live", "video-vv-term-rec",
        "video-vv-term-rest", "video-vv-term-l0", "video-vv-term-l1", "video-vv-term-l2", "video-vv-term-l3", "video-vv-term-done"]

    static let tighten = "Tighten PRD goals"

    /// A microphone that is (or isn't) there, whatever the Mac has.
    final class FixedMicrophone: VoiceDeviceSource {
        let usable: Bool
        init(usable: Bool) { self.usable = usable }
        func current() -> (name: String?, usable: Bool) { (usable ? "MacBook Air Microphone" : nil, usable) }
        func observe(_ changed: @escaping @MainActor () -> Void) {}
    }

    /// The terminal states' level bars and how much of the dictation has been pasted into Claude's prompt.
    nonisolated struct VVTerm { var listening: Bool, levels: [Double], phrases: Int }
    nonisolated static func vvTerm(_ name: String) -> VVTerm? {
        switch name {
        case "term-rest": return .init(listening: false, levels: [], phrases: 0)
        case "term-l0": return .init(listening: true, levels: [0.35, 0.8, 0.55], phrases: 0)
        case "term-l1": return .init(listening: true, levels: [0.7, 0.45, 0.9], phrases: 0)
        case "term-l2": return .init(listening: true, levels: [0.5, 0.85, 0.4], phrases: 1)
        case "term-l3": return .init(listening: true, levels: [0.2, 0.3, 0.15], phrases: 2)
        case "term-done": return .init(listening: false, levels: [], phrases: 2)
        default: return nil
        }
    }

    static var vvDir: URL?

    /// The recorded Claude screen with `typed` in its prompt row (the input box's last `❯ `), the cursor after it.
    static func vvPrompt(_ screen: String, _ typed: String) -> String {
        var rows = screen.components(separatedBy: "\n")
        guard let p = rows.lastIndex(where: { $0.contains("❯") }) else { return screen }
        rows[p] = rows[p].replacingOccurrences(of: "❯\u{1b}[0m ", with: "❯\u{1b}[0m " + typed)
        return rows.joined(separator: "\n")
    }

    static func applyVoice(_ screen: String, _ model: AppModel) {
        let name = String(screen.dropFirst("video-v?-".count))
        // Read where they're read: the terminal mic on a recorded screen (a shell, as fixture terminals are), the file fed at
        // its spoken pace with its levels, and the appearance this state shows.
        setenv("DUO_VOICE_MIC_ON_SHELL", "1", 1)
        setenv("DUO_VOICE_FILE_REALTIME", "1", 1)
        if screen.hasSuffix("-classic") { setenv("DUO_APPEARANCE", "classic", 1); AppearanceSetting.apply() }
        applyS4S5("video-s5-chat", to: model)
        guard let v = model.fixture.videoS2, let base = model.fixture.baseDir else { return }
        let dir = URL(fileURLWithPath: base)
        vvDir = dir
        let project = v.project ?? "shelf-scan"
        let mic = screen != "video-vv-nomic"
        model.voice.deviceSource = FixedMicrophone(usable: mic)
        model.voice.hasMicrophone = { mic }
        func key(_ n: String) -> String { model.fixture.sessions.first { $0.project == project && $0.name == n }?.tabKey ?? n }
        if name == "chat-sent", let i = model.fixture.sessions.firstIndex(where: { $0.project == project && $0.name == autoAdd }) {
            let k = model.fixture.sessions[i].tabKey
            model.fixtureChats[k] = s6Chat(dir.appending(path: "chat-vv-sent"), cwd: v.cwd, picked: false, key: k)
        }
        if name == "term-live" || name == "term-rec" {
            // The Tighten PRD goals tab, in front: its recorded Claude screen. A live shell's text isn't in a window capture
            // (F-25), so the dictation's pastes are drawn into this screen as they're delivered (`vv-rec` routes voice input's
            // paste there, F-483); everything before the write is voice input's own.
            let k = key(tighten)
            let text = (try? String(contentsOf: dir.appending(path: "terms/tighten-prd.ans"), encoding: .utf8)) ?? ""
            model.fixtureTerminals[k] = TerminalSession(key: k, screen: vvPrompt(text, ""))
            model.consoleTab = k
        }
        if let t = vvTerm(name) {
            // The Tighten PRD goals tab in front, its recorded screen with what has been pasted into Claude's prompt so far.
            let k = key(tighten)
            // The phrases as macOS's recognizer settled them from the spoken file (dictation/recognized.json).
            let words = (try? Data(contentsOf: dir.appending(path: "dictation/recognized.json"))).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            let phrases = ((words?["terminal"] as? [String: Any])?["phrases"] as? [String]) ?? []
            let typed = phrases.prefix(t.phrases).joined(separator: " ")
            let screenText = (try? String(contentsOf: dir.appending(path: "terms/tighten-prd.ans"), encoding: .utf8)) ?? ""
            // The prompt row is the input box's `❯ ` line: the last one on the screen.
            var rows = screenText.components(separatedBy: "\n")
            if let p = rows.lastIndex(where: { $0.contains("❯") }) { rows[p] = rows[p].replacingOccurrences(of: "❯\u{1b}[0m ", with: "❯\u{1b}[0m " + typed) }
            model.fixtureTerminals[k] = TerminalSession(key: k, screen: rows.joined(separator: "\n"))
            model.consoleTab = k
        }
    }

    /// The `--then` actions a 0.2.22 state needs once its window exists.
    nonisolated static func vvActions(_ screen: String) -> [String] {
        let name = String(screen.dropFirst("video-v?-".count))
        let measure = ["wait:0.4", "video:vv-measure"]
        // Recorded: the dictation runs for real while the window is drawn 15 times a second (`vv-rec`), then the capture
        // is the moment after.
        if name == "chat-rec" { return ["wait:5", "video:vv-rec=chat|11", "wait:11.6"] + measure }
        if name == "term-live" { return ["wait:3.5"] + measure }
        if name == "term-rec" { return ["wait:5", "video:vv-rec=terminal|10", "wait:10.6"] + measure }
        if name.hasPrefix("chat-at-"), let tenths = Int(name.dropFirst("chat-at-".count)) {
            // The dictation runs as it would from the mic; the capture is taken this far in.
            return ["wait:2", "video:vv-feed=chat", "wait:\(Double(tenths) / 10)", "video:vv-measure"]
        }
        if let t = vvTerm(name) {
            let levels = t.levels.map { String($0) }.joined(separator: "|")
            return ["wait:2"] + (t.listening ? ["video:vv-listen=\(levels)"] : []) + measure
        }
        if name == "nomic" { return ["wait:2", "video:vv-hover"] + measure }
        return ["wait:2"] + measure
    }

    /// One `video:vv-*` action (`act` sends them here).
    static func vvAct(_ verb: String, _ arg: String, on model: AppModel) {
        switch verb {
        case "vv-feed":   // voice input on the chat composer, from the spoken file, as the mic would hear it
            guard let dir = vvDir, let k = model.consoleTab else { return }
            model.voice.start(.chat(k), source: .file(dir.appending(path: "dictation/\(arg).wav")))
            vvTrace(model)
        case "vv-listen":   // the terminal mic listening, its bars at these three levels (oldest first), as 20 Hz polls leave them
            guard let k = model.consoleTab, let t = model.fixtureTerminals[k], let slot = t.view.superview as? TerminalSlot.SlotView else { return }
            for l in arg.split(separator: "|").compactMap({ Double($0) }) {
                model.voice.showFixture(.listening, target: .terminal(k), level: l, onMicrophone: true)
                slot.mic.tick()
            }
            slot.mic.needsDisplay = true
        case "vv-rec":   // vv-rec=<clip>|<seconds>: dictate the clip into the session showing, recording the middle pane
            let a = arg.split(separator: "|").map(String.init)
            guard let dir = vvDir, let k = model.consoleTab, a.count == 2, let secs = Double(a[1]) else { return }
            let target: VoiceTarget = model.fixtureChats[k] != nil ? .chat(k) : .terminal(k)
            FileHandle.standardError.write(Data("vv-rec: target \(target) terminal=\(model.fixtureTerminals[k] != nil)\n".utf8))
            if case .terminal = target, model.fixtureTerminals[k] != nil {
                // Each settled phrase as voice input delivers it (one paste, a space before all but the first) goes into the
                // recorded Claude prompt. A terminal in a background window doesn't redraw what's fed to it later, so the
                // screen is drawn again with the prompt holding everything pasted so far (F-483).
                let host = model.voice.host   // nil in a fixture state, which wires no voice host
                let screen = (try? String(contentsOf: dir.appending(path: "terms/tighten-prd.ans"), encoding: .utf8)) ?? ""
                var typed = ""
                model.voice.host = VoiceInput.Host(update: host?.update ?? { _, _, _ in }, paste: { _, phrase, first in
                    FileHandle.standardError.write(Data("vv-paste: \(phrase.debugDescription)\n".utf8))
                    typed += (first ? "" : " ") + phrase
                    model.fixtureTerminals[k] = TerminalSession(key: k, screen: vvPrompt(screen, typed))
                    return .sent
                }, ended: host?.ended ?? { _, _ in })
            }
            vvRecord(model, seconds: secs, region: CGRect(x: 300, y: 40, width: 840, height: 1061))
            model.voice.start(target, source: .file(dir.appending(path: "dictation/\(a[0]).wav")))
            vvTrace(model)
        case "vv-hover":   // the pointer resting on the chat mic: its tooltip is drawn by the film (macOS draws tooltips outside the window)
            break
        case "vv-measure": vvMeasure(model)
        default: FileHandle.standardError.write(Data("video: unknown action \(verb)\n".utf8))
        }
    }

    /// Ten times a second while it runs: what the recognizer has settled and is still hearing, and the level (for the report).
    static func vvTrace(_ model: AppModel) {
        let t0 = Date()
        func step() {
            let v = model.voice
            FileHandle.standardError.write(Data(String(format: "vv-trace: %.1f state=%@ level=%.2f settled=%@ volatile=%@\n", Date().timeIntervalSince(t0),
                "\(v.state)", v.level, v.transcript.settled.joined(separator: " / ").debugDescription, v.transcript.volatile.debugDescription).utf8))
            if v.state.isActive || Date().timeIntervalSince(t0) < 1 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { MainActor.assumeIsolated { step() } }
            }
        }
        step()
    }

    /// Draws the window's `region` (window points, from the top left) `fps` times a second for `seconds`, as the capture
    /// draws it (no permission, the window never shown), into $DUO_VIDEO_REC_DIR: frame-NNNN.png at the capture scale and
    /// times.json (each frame's seconds from the first). `pipeline/capture.mjs` makes them a video.
    static func vvRecord(_ model: AppModel, seconds: Double, region: CGRect, fps: Double = 15) {
        guard let dirPath = ProcessInfo.processInfo.environment["DUO_VIDEO_REC_DIR"],
              let window = NSApp.windows.filter({ $0.frame.width > 1000 }).max(by: { $0.frame.width < $1.frame.width }),   // the main window, once it exists (a background launch may not count it visible)
              let frame = window.contentView?.superview else { FileHandle.standardError.write(Data("vv-rec: no window yet\n".utf8)); return }
        let dir = URL(fileURLWithPath: dirPath)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let scale = WindowCapture.scale
        let rect = NSRect(x: region.minX, y: frame.bounds.height - region.maxY, width: region.width, height: region.height)
        let t0 = Date()
        let encode = DispatchQueue(label: "duo.video.record", qos: .userInitiated, attributes: .concurrent)
        let group = DispatchGroup()
        var times: [Double] = []
        func shot() {
            let n = times.count
            times.append(Date().timeIntervalSince(t0))
            guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(rect.width * scale), pixelsHigh: Int(rect.height * scale), bitsPerSample: 8,
                                             samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return }
            rep.size = rect.size
            frame.layoutSubtreeIfNeeded()
            frame.cacheDisplay(in: rect, to: rep)
            // A terminal's background is transparent in the drawing (F-25): paint the console colour under it, as the capture does.
            var out = rep
            if let under = WindowCapture.underlay, let flat = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: rep.pixelsWide, pixelsHigh: rep.pixelsHigh,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) {
                flat.size = rect.size   // before the context, which takes its scale from it
                guard let ctx = NSGraphicsContext(bitmapImageRep: flat) else { return }
                NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = ctx
                under.setFill(); NSRect(origin: .zero, size: rect.size).fill()
                rep.draw(in: NSRect(origin: .zero, size: rect.size))
                NSGraphicsContext.restoreGraphicsState()
                out = flat
            }
            let url = dir.appending(path: String(format: "frame-%04d.png", n))
            nonisolated(unsafe) let r = out
            encode.async(group: group) { try? r.representation(using: .png, properties: [:])?.write(to: url) }
        }
        func tick() {
            shot()
            if Date().timeIntervalSince(t0) < seconds {
                let next = Double(times.count) / fps - Date().timeIntervalSince(t0)
                DispatchQueue.main.asyncAfter(deadline: .now() + max(0.001, next)) { MainActor.assumeIsolated { tick() } }
            } else {
                group.notify(queue: .main) {
                    let json = try? JSONSerialization.data(withJSONObject: ["fps": fps, "scale": scale, "region": [region.minX, region.minY, region.width, region.height], "times": times])
                    try? json?.write(to: dir.appending(path: "times.json"))
                    FileHandle.standardError.write(Data("vv-rec: \(times.count) frames in \(String(format: "%.1f", times.last ?? 0)) s\n".utf8))
                }
            }
        }
        tick()
    }

    /// `video.vv.*`: the chat composer and the terminal mic, in window points (`--then anchors:` adds them).
    static func vvMeasure(_ model: AppModel) {
        func put(_ id: String, _ v: NSView?) {
            guard let v, let w = v.window else { return }
            let r = v.convert(v.bounds, to: nil)
            Anchors.web[id] = CGRect(x: r.minX, y: w.frame.height - r.maxY, width: r.width, height: r.height)
        }
        if let k = model.consoleTab {
            put("video.vv.composer", (model.chats.existing(k) ?? model.fixtureChats[k])?.composerView)
            if let t = model.fixtureTerminals[k], let slot = t.view.superview as? TerminalSlot.SlotView {
                put("video.vv.termmic", slot.mic.isHidden ? nil : slot.mic)
                put("video.vv.terminal", t.view)
            }
        }
        FileHandle.standardError.write(Data("video:vv-measure: \(Anchors.web.keys.filter { $0.hasPrefix("video.vv.") }.sorted())\n".utf8))
    }
}
