import AppKit
import Darwin

/// Chat mode's performance harness (F-157): a long session's transcript followed by the fixture
/// chat, then timed. Results go to stderr as `perf: {json}` lines.
///
///   perf-follow:<session id>|<cwd>   the visible fixture chat follows that transcript, as a live one
///                                    does (ChatFeed); times the open and the first draw
///   perf-scroll:<frames>|<points>    scrolls up from the bottom, one step a frame; times each frame
///   perf-middle                      scrolls to the middle of the feed and holds
///   perf-watch:<seconds>|<label>     reports main-thread stalls over the next seconds (a live append)
///   perf-report                      memory and the feed's size
@MainActor
enum ChatPerf {
    static let watchdog = Watchdog()
    static var scrollTimer: Timer?

    static func perform(_ parts: [String], on model: AppModel) {
        let args = parts.count > 1 ? parts[1].split(separator: "|", omittingEmptySubsequences: false).map(String.init) : []
        switch parts[0] {
        case "perf-follow":
            guard args.count == 2, let tab = model.consoleTab, let c = model.fixtureChats[tab] else { return say(["error": "no fixture chat"]) }
            watchdog.start()
            let t0 = CACurrentMediaTime()
            c.log.reset()
            c.follow(sessionId: args[0], cwd: args[1])
            let returned = CACurrentMediaTime()
            // The feed may load in the background: wait for the log, then draw it.
            func whenLoaded(_ tries: Int) {
                guard c.log.items.isEmpty, tries < 400 else {
                    let loaded = CACurrentMediaTime()
                    let window = NSApp.windows.first { $0.title == "Duo" }
                    window?.contentView?.layoutSubtreeIfNeeded()
                    window?.displayIfNeeded()
                    let drawn = CACurrentMediaTime()
                    say(["event": "follow", "follow_returned_ms": ms(returned - t0), "loaded_ms": ms(loaded - t0), "first_draw_ms": ms(drawn - loaded),
                         "items": c.log.items.count, "steps": c.log.steps.count, "footprint_mb": footprintMB()])
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) { MainActor.assumeIsolated { say(watchdog.take(label: "follow-until-drawn+1s")) } }
                    return
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) { MainActor.assumeIsolated { whenLoaded(tries + 1) } }
            }
            whenLoaded(0)
        case "perf-scroll":
            let frames = Int(args.first ?? "") ?? 240, step = Double(args.count > 1 ? args[1] : "") ?? 40
            guard let sv = chatScroll() else { return say(["error": "no chat scroll view"]) }
            scroll(sv, frames: frames, step: step)
        case "perf-middle":
            guard let sv = chatScroll(), let doc = sv.documentView else { return }
            doc.scroll(NSPoint(x: 0, y: doc.bounds.height / 2))
            sv.reflectScrolledClipView(sv.contentView)
            say(["event": "middle", "y": Int(sv.contentView.bounds.minY), "height": Int(doc.bounds.height)])
        case "perf-watch":
            let secs = Double(args.first ?? "") ?? 3
            watchdog.start()
            let before = chatScroll().map { Int($0.contentView.bounds.minY) }
            DispatchQueue.main.asyncAfter(deadline: .now() + secs) {
                MainActor.assumeIsolated {
                    var r = watchdog.take(label: args.count > 1 ? args[1] : "watch")
                    let sv = chatScroll()
                    r["y_before"] = before ?? -1
                    r["y_after"] = sv.map { Int($0.contentView.bounds.minY) } ?? -1
                    r["height"] = sv?.documentView.map { Int($0.bounds.height) } ?? -1
                    if let tab = model.consoleTab, let c = model.fixtureChats[tab] { r["items"] = c.log.items.count }
                    say(r)
                }
            }
        case "perf-wheel":
            let frames = Int(args.first ?? "") ?? 240, step = Int32(args.count > 1 ? args[1] : "") ?? 40
            guard let sv = chatScroll() else { return say(["error": "no chat scroll view"]) }
            wheel(sv, frames: frames, step: step)
        case "perf-views":
            // AppKit views SwiftUI hosts, with how many views are under each (what a measure walks).
            func count(_ v: NSView) -> Int { 1 + v.subviews.reduce(0) { $0 + count($1) } }
            func walk(_ v: NSView, _ depth: Int, _ out: inout [String]) {
                let n = count(v)
                if n >= 8 || depth < 3 { out.append(String(repeating: " ", count: depth) + "\(type(of: v)) \(n) \(Int(v.frame.width))x\(Int(v.frame.height))") }
                if depth < 14 { for s in v.subviews where count(s) >= 8 { walk(s, depth + 1, &out) } }
            }
            var out: [String] = []
            if let root = NSApp.windows.first(where: { $0.title == "Duo" })?.contentView { walk(root, 0, &out) }
            FileHandle.standardError.write(Data(("views:\n" + out.joined(separator: "\n") + "\n").utf8))
            // The chat's document, by class: what each realized row costs AppKit.
            var classes: [String: Int] = [:]
            func tally(_ v: NSView) { classes[String(describing: type(of: v)).components(separatedBy: "<").first ?? "", default: 0] += 1; v.subviews.forEach(tally) }
            if let doc = chatScroll()?.documentView { tally(doc) }
            say(["event": "views", "chat_views": classes.values.reduce(0, +), "by_class": classes])
        case "perf-append":
            // perf-append:<from>|<to>|<lines>|<label>: appends lines to the followed transcript, one
            // every 50 ms, as a live session writes them; reports stalls and where the view went.
            guard args.count >= 3, let lines = try? String(contentsOfFile: args[0], encoding: .utf8).split(separator: "\n").map(String.init),
                  let h = FileHandle(forWritingAtPath: args[1]) else { return say(["error": "perf-append: no files"]) }
            let count = min(Int(args[2]) ?? 50, lines.count)
            watchdog.start()
            let before = chatScroll().map { Int($0.contentView.bounds.minY) } ?? -1
            let beforeHeight = chatScroll()?.documentView.map { Int($0.bounds.height) } ?? -1
            for i in 0..<count {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05 * Double(i)) {
                    h.seekToEndOfFile(); h.write(Data((lines[i] + "\n").utf8))
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05 * Double(count) + 1) {
                MainActor.assumeIsolated {
                    try? h.close()
                    var r = watchdog.take(label: args.count > 3 ? args[3] : "append")
                    let sv = chatScroll()
                    r.merge(["event": "append", "lines": count, "y_before": before, "height_before": beforeHeight,
                             "y_after": sv.map { Int($0.contentView.bounds.minY) } ?? -1,
                             "height_after": sv?.documentView.map { Int($0.bounds.height) } ?? -1, "footprint_mb": footprintMB()]) { a, _ in a }
                    say(r)
                }
            }
        case "perf-sample":
            // perf-sample:<seconds>|<file>: samples this process (sample(1)) while the next actions run.
            guard args.count == 2 else { return }
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/sample")
            p.arguments = [String(ProcessInfo.processInfo.processIdentifier), args[0], "-file", args[1]]
            p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
            try? p.run()
        case "perf-bottom":
            guard let sv = chatScroll(), let doc = sv.documentView else { return }
            doc.scroll(NSPoint(x: 0, y: max(0, doc.bounds.height - sv.contentView.bounds.height)))
            sv.reflectScrolledClipView(sv.contentView)
        case "perf-report":
            var r: [String: Any] = ["event": "report", "footprint_mb": footprintMB()]
            if let tab = model.consoleTab, let c = model.fixtureChats[tab] { r["items"] = c.log.items.count; r["steps"] = c.log.steps.count }
            if let sv = chatScroll(), let doc = sv.documentView { r["height"] = Int(doc.bounds.height); r["y"] = Int(sv.contentView.bounds.minY) }
            say(r)
        default: break
        }
    }

    /// The chat's scroll view: the one with the tallest document in Duo's window.
    static func chatScroll() -> NSScrollView? {
        func all(_ v: NSView) -> [NSScrollView] { ((v as? NSScrollView).map { [$0] } ?? []) + v.subviews.flatMap(all) }
        guard let w = NSApp.windows.first(where: { $0.title == "Duo" }), let root = w.contentView?.superview else { return nil }
        return all(root).filter { $0.documentView != nil && $0.frame.width > 300 }.max { ($0.documentView?.bounds.height ?? 0) < ($1.documentView?.bounds.height ?? 0) }
    }

    /// One step a display frame, from the bottom up: each frame's own work (the scroll, SwiftUI's
    /// update, layout and display) and the gap between frames (what a person sees as a hitch).
    static func scroll(_ sv: NSScrollView, frames: Int, step: Double) {
        guard let doc = sv.documentView, let window = sv.window else { return }
        let bottom = max(0, doc.bounds.height - sv.contentView.bounds.height)
        doc.scroll(NSPoint(x: 0, y: bottom))
        sv.reflectScrolledClipView(sv.contentView)
        window.displayIfNeeded()
        watchdog.start()
        var work: [Double] = [], gaps: [Double] = []
        var last = CACurrentMediaTime(), n = 0, y = bottom
        let started = last
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { _ in
            MainActor.assumeIsolated {
                let now = CACurrentMediaTime()
                gaps.append(now - last)
                y = max(0, y - step)
                doc.scroll(NSPoint(x: 0, y: y))
                sv.reflectScrolledClipView(sv.contentView)
                window.contentView?.layoutSubtreeIfNeeded()
                window.displayIfNeeded()
                last = CACurrentMediaTime()
                work.append(last - now)
                n += 1
                if n >= frames || y <= 0 {
                    scrollTimer?.invalidate()
                    var r = watchdog.take(label: "scroll")
                    r.merge(["event": "scroll", "frames": n, "step_pt": step, "travelled_pt": Int(bottom - y), "wall_ms": ms(last - started),
                             "work_ms": stats(work), "gap_ms": stats(gaps), "hitches_over_33ms": gaps.filter { $0 > 0.0334 }.count,
                             "height": Int(doc.bounds.height), "footprint_mb": footprintMB()]) { a, _ in a }
                    say(r)
                }
            }
        }
        scrollTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    /// A scroll step a frame, as a trackpad's events move the clip view: AppKit and SwiftUI do their own
    /// update and display in between, as they do for a person; only the gaps between frames are timed.
    static func wheel(_ sv: NSScrollView, frames: Int, step: Int32) {
        guard let doc = sv.documentView else { return }
        doc.scroll(NSPoint(x: 0, y: max(0, doc.bounds.height - sv.contentView.bounds.height)))
        sv.reflectScrolledClipView(sv.contentView)
        watchdog.start()
        var gaps: [Double] = []
        var last = CACurrentMediaTime(), n = 0
        let started = last, y0 = sv.contentView.bounds.minY
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { _ in
            MainActor.assumeIsolated {
                let now = CACurrentMediaTime()
                gaps.append(now - last)
                last = now
                // What a wheel event does to the clip view; synthesized wheel events don't reach
                // SwiftUI's scroll view in a window that isn't frontmost.
                sv.contentView.scroll(to: NSPoint(x: 0, y: max(0, sv.contentView.bounds.minY - CGFloat(step))))
                sv.reflectScrolledClipView(sv.contentView)
                n += 1
                if n >= frames || sv.contentView.bounds.minY <= 0 {
                    scrollTimer?.invalidate()
                    var r = watchdog.take(label: "wheel")
                    r.merge(["event": "wheel", "frames": n, "step_pt": Int(step), "travelled_pt": Int(y0 - sv.contentView.bounds.minY), "wall_ms": ms(CACurrentMediaTime() - started),
                             "gap_ms": stats(gaps), "hitches_over_33ms": gaps.filter { $0 > 0.0334 }.count,
                             "height": Int(doc.bounds.height), "footprint_mb": footprintMB()]) { a, _ in a }
                    say(r)
                }
            }
        }
        scrollTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    static func stats(_ xs: [Double]) -> [String: Double] {
        guard !xs.isEmpty else { return [:] }
        let s = xs.sorted()
        func p(_ q: Double) -> Double { ms(s[min(s.count - 1, Int(Double(s.count) * q))]) }
        return ["mean": ms(xs.reduce(0, +) / Double(xs.count)), "p50": p(0.5), "p90": p(0.9), "p99": p(0.99), "max": ms(s.last!)]
    }

    nonisolated static func ms(_ s: Double) -> Double { (s * 10000).rounded() / 10 }

    static func footprintMB() -> Int {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) { $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) } }
        return kr == KERN_SUCCESS ? Int(info.phys_footprint / 1_048_576) : -1
    }

    static func say(_ r: [String: Any]) {
        let data = (try? JSONSerialization.data(withJSONObject: r, options: [.sortedKeys])) ?? Data()
        FileHandle.standardError.write(Data(("perf: " + String(decoding: data, as: UTF8.self) + "\n").utf8))
    }
}

/// Pings the main thread every 5 ms from a background thread: how long each ping waited is how
/// long the main thread was busy (a beach ball shows after about 2 s of it).
final class Watchdog: @unchecked Sendable {
    private let lock = NSLock()
    private var waits: [Double] = []
    private var running = false

    func start() {
        lock.lock(); waits = []; let was = running; running = true; lock.unlock()
        guard !was else { return }
        Thread.detachNewThread { [self] in
            while true {
                lock.lock(); let go = running; lock.unlock()
                guard go else { return }
                let sent = CACurrentMediaTime()
                let done = DispatchSemaphore(value: 0)
                DispatchQueue.main.async { done.signal() }
                done.wait()
                let w = CACurrentMediaTime() - sent
                lock.lock(); waits.append(w); lock.unlock()
                Thread.sleep(forTimeInterval: 0.005)
            }
        }
    }

    /// Stalls since start: the longest, the time spent in stalls over 50 ms, and how many passed 250 ms.
    func take(label: String) -> [String: Any] {
        lock.lock(); let w = waits; waits = []; lock.unlock()
        return ["watch": label, "stall_max_ms": ChatPerf.ms(w.max() ?? 0), "stall_total_over_50ms_ms": ChatPerf.ms(w.filter { $0 > 0.05 }.reduce(0, +)),
                "stalls_over_250ms": w.filter { $0 > 0.25 }.count, "pings": w.count]
    }
}

