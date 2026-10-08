import AppKit
import Darwin
import DuoControl

/// Watches Duo's main thread and logs each stall of 250 ms or more (DL-139, F-163). A background
/// thread posts a no-op to the main queue every 50 ms and waits for it to run. While one is late
/// past half a second, it samples the main thread's stack every 50 ms: it suspends the thread,
/// walks its frame pointers into a buffer allocated beforehand (nothing that could take a lock the
/// main thread holds), then resumes it. When the main thread answers, the stall, the screen and
/// the samples go to `HangLog` (up to 30 samples, 1.5 s of a long stall, 64 frames each). With no stall, its cost is one wakeup and one empty block every 50 ms.
public final class HangMonitor: @unchecked Sendable {
    public static let shared = HangMonitor()

    private let lock = NSLock()
    private var running = false
    private var mainThread: thread_act_t = 0
    private var stackLow: UInt = 0, stackHigh: UInt = 0
    /// Says what's on screen; read on the main thread when a stall ends.
    private var screen: @MainActor () -> String = { "" }
    private let frames = UnsafeMutablePointer<UInt>.allocate(capacity: HangMonitor.maxFrames)
    static let maxFrames = 64
    static let interval: TimeInterval = 0.05
    static let sampleAfter: TimeInterval = 0.5
    static let maxSamples = 30
    /// A stall this long is written while it goes on.
    static let writeOngoingAfter: TimeInterval = 2
    private var pings = 0
    private var screenNow = ""
    private var lastScreen: String { lock.lock(); defer { lock.unlock() }; return screenNow }
    private func setLastScreen(_ s: String) { lock.lock(); screenNow = s; lock.unlock() }

    /// Starts watching; call on the main thread. `screen` describes what Duo shows.
    @MainActor public func start(screen: @escaping @MainActor () -> String) {
        lock.lock(); defer { lock.unlock() }
        guard !running else { return }
        running = true
        self.screen = screen
        mainThread = mach_thread_self()
        let me = pthread_self()
        stackHigh = UInt(bitPattern: pthread_get_stackaddr_np(me))
        stackLow = stackHigh - UInt(pthread_get_stacksize_np(me))
        let t = Thread { [self] in watch() }
        t.name = "Duo hang monitor"
        t.qualityOfService = .utility
        t.start()
    }

    public func stop() { lock.lock(); running = false; lock.unlock() }

    private var isRunning: Bool { lock.lock(); defer { lock.unlock() }; return running }

    private func watch() {
        let answered = DispatchSemaphore(value: 0)
        while isRunning {
            let sent = Date()
            pings += 1
            // What's on screen, every 2 s while the main thread answers: a stall still going can't ask.
            if pings % 40 == 1 { DispatchQueue.main.async { [self] in let s = screen(); setLastScreen(s); answered.signal() } }
            else { DispatchQueue.main.async { answered.signal() } }
            if answered.wait(timeout: .now() + Self.interval) == .success {
                Thread.sleep(forTimeInterval: Self.interval)
                continue
            }
            // Late: keep waiting, sampling once it's past half a second: every 50 ms for 1.5 s, then
            // once a second. Past 2 s the stall is written while it goes on, and again every 10 s,
            // so a freeze that never ends still leaves its stacks (F-208).
            var samples: [[String]] = []
            var lastSample = Date.distantPast, written: Date?
            while answered.wait(timeout: .now() + Self.interval) == .timedOut {
                let now = Date(), stuck = now.timeIntervalSince(sent)
                if stuck >= Self.sampleAfter, samples.count < Self.maxSamples
                    || (samples.count < Self.maxSamples * 2 && now.timeIntervalSince(lastSample) >= 1), let s = sampleMain() {
                    samples.append(s); lastSample = now
                }
                if stuck >= Self.writeOngoingAfter, written.map({ now.timeIntervalSince($0) >= 10 }) ?? true {
                    written = now
                    let r = HangLog.Record(at: sent, ms: Int(stuck * 1000), screen: lastScreen, version: Self.version,
                                           samples: samples.isEmpty ? nil : samples, binary: samples.isEmpty ? nil : Self.binary, ongoing: true)
                    DispatchQueue.global(qos: .utility).async { HangLog.append(r) }
                }
            }
            let ms = Int(Date().timeIntervalSince(sent) * 1000)
            guard Double(ms) / 1000 >= HangLog.threshold else { continue }
            let kept = samples
            DispatchQueue.main.async { [self] in
                let r = HangLog.Record(at: sent, ms: ms, screen: screen(), version: Self.version,
                                       samples: kept.isEmpty ? nil : kept, binary: kept.isEmpty ? nil : Self.binary)
                DispatchQueue.global(qos: .utility).async { HangLog.append(r) }
            }
        }
    }

    /// The main thread's return addresses, innermost first: Duo's own as `Duo@0xoffset`, others named.
    private func sampleMain() -> [String]? {
        guard thread_suspend(mainThread) == KERN_SUCCESS else { return nil }
        var n = 0
        var state = arm_thread_state64_t()
        var count = mach_msg_type_number_t(MemoryLayout<arm_thread_state64_t>.size / MemoryLayout<UInt32>.size)
        let kr = withUnsafeMutablePointer(to: &state) {
            $0.withMemoryRebound(to: natural_t.self, capacity: Int(count)) { thread_get_state(mainThread, ARM_THREAD_STATE64, $0, &count) }
        }
        if kr == KERN_SUCCESS {
            frames[0] = UInt(state.__pc); frames[1] = UInt(state.__lr); n = 2
            var fp = UInt(state.__fp)
            // Each frame record: [fp] = caller's fp, [fp + 8] = return address. Stay inside the stack.
            while n < Self.maxFrames, fp >= stackLow, fp + 16 <= stackHigh, fp % 8 == 0 {
                let rec = UnsafePointer<UInt>(bitPattern: fp)!
                let ret = rec[1], next = rec[0]
                if ret == 0 { break }
                frames[n] = ret; n += 1
                if next <= fp { break }
                fp = next
            }
        }
        thread_resume(mainThread)
        guard n > 0 else { return nil }
        return (0..<n).map { Self.describe(frames[$0] & 0x0000_FFFF_FFFF_FFFF) }
    }

    static let executable = Bundle.main.executablePath ?? ""
    static let version = "\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"))"
    /// The executable and its load address, for `atos -o <path> -l <address>`.
    static let binary: String = {
        for i in 0..<_dyld_image_count() where String(cString: _dyld_get_image_name(i)) == executable {
            return executable + "@0x" + String(UInt(bitPattern: _dyld_get_image_header(i)), radix: 16)
        }
        return executable
    }()

    static func describe(_ addr: UInt) -> String {
        var info = Dl_info()
        guard dladdr(UnsafeRawPointer(bitPattern: addr), &info) != 0, let base = info.dli_fbase else { return "?@0x" + String(addr, radix: 16) }
        let image = info.dli_fname.map { String(cString: $0) } ?? "?"
        if image == executable { return "Duo@0x" + String(addr - UInt(bitPattern: base), radix: 16) }
        let name = info.dli_sname.map { String(cString: $0) } ?? "?"
        return "\(name) (\((image as NSString).lastPathComponent))"
    }
}
