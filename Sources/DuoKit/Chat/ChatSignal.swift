import DuoControl
import Foundation

// duo-signal, a sensor-only Claude Code mod (ENH-70; spike, DL-183). Behind `DUO_SIGNAL=1`, off by
// default. A session Duo starts on a Claude Code with mods (2.1.287+) gets `Mods/duo-signal` by
// `--plugin-dir`, from a read-only copy in the support folder (never inside the signed app, F-280),
// and the mod keeps a small JSON snapshot in `events/<launch id>.signal.json`, rewritten every
// 500 ms. Chat takes busy from it while it's fresh, and Claude's request ahead of the hook; the
// screen stays the authority for everything else, and the whole of it when the signal is missing,
// stale or broken. Nothing changes with the flag off, or on a CLI without mods (the work Mac's 2.1.219).

public enum DuoSignal {
    /// The flag: on when set to anything but "" (`Env.isSet`).
    public static let flag = "DUO_SIGNAL"
    /// Where the mod writes: the one variable it reads.
    public static let fileVariable = "DUO_SIGNAL_FILE"
    /// Mods shipped in 2.1.287 (F-279).
    public static let minimum = ChatVersion("2.1.287")!
    /// The mod writes every 500 ms: three missed heartbeats and chat reads the screen alone.
    public static let staleAfter: TimeInterval = 1.5

    public static var isOn: Bool { Env.isSet(flag) }

    /// Whether a session started now gets the mod: the flag is on, the CLI's version is known and
    /// has mods, and the mod passed `claude plugin validate` on this CLI (an unknown version is the
    /// work Mac's case until proved otherwise: never passed).
    public static func passes(on: Bool, cliVersion: String?, validated: Bool) -> Bool {
        guard on, validated, let v = cliVersion.flatMap(ChatVersion.init) else { return false }
        return v >= minimum
    }

    /// The arguments for a session: `--plugin-dir <copy>`, or none.
    public static func args(on: Bool, cliVersion: String?, validated: Bool, modDir: String?) -> [String] {
        guard passes(on: on, cliVersion: cliVersion, validated: validated), let modDir else { return [] }
        return ["--plugin-dir", modDir]
    }

    public static func file(for launchId: String, in dir: URL = DuoPaths.events) -> URL {
        dir.appending(path: "\(launchId).signal.json")
    }

    // MARK: Launch

    nonisolated(unsafe) private static var passed: Set<String> = []
    nonisolated(unsafe) private static var validated: [String: Bool] = [:]
    nonisolated(unsafe) private static var validating: Set<String> = []
    nonisolated(unsafe) private static var copied: String??
    private static let lock = NSLock()

    /// Whether the session with this launch id was started with the mod (chat reads a signal only then).
    public static func wasPassed(_ launchId: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return passed.contains(launchId)
    }

    /// The `--plugin-dir` arguments for a session starting now, recording that it got them. Never
    /// waits: the version comes from the cache the session start already filled (`ClaudeVersion.known`),
    /// and a CLI not yet validated (here or by an earlier launch) is validated in the background, for the next session.
    static func launchArgs(_ launchId: String, claude: String?, cliVersion: String?) -> [String] {
        guard isOn, let claude, let cliVersion, passes(on: true, cliVersion: cliVersion, validated: true) else { return [] }
        guard let mod = installedMod() else { return [] }
        let key = claude + "@" + cliVersion
        guard let ok = validation(mod: mod, key: key) else { validate(claude: claude, mod: mod, key: key); return [] }
        // The canary found mods can't run here: this launch, or (before this launch's answer) the last one.
        lock.lock(); let now = mayRun[key]; lock.unlock()
        let last = ModCanary.load(support: DuoPaths.support).flatMap { c in
            c.claude == claude && c.version == cliVersion ? c.step(ModCanary.mayRun).map { $0.state != .failed } : nil
        }
        if (now ?? last) == false { return [] }
        let a = args(on: true, cliVersion: cliVersion, validated: ok, modDir: mod)
        if !a.isEmpty { lock.lock(); passed.insert(launchId); lock.unlock() }
        return a
    }

    /// At launch, beside `ClaudeVersion.warm`, whatever the flag: the mod canary (F-297), off the
    /// main thread and quiet. It copies and validates the mod (so the first session can have it when
    /// the flag is on) and asks `claude plugin test` whether mods may run here, then writes
    /// `mods/canary.json` for `duo2 doctor`. On a CLI without mods it reads the version and stops.
    public static func warm(_ claude: String) {
        DispatchQueue.global(qos: .utility).async { canary(claude: claude) }
    }

    public static func canary(claude: String, support: URL = DuoPaths.support) {
        let v = ClaudeVersion.known(claude)
        var c = ModCanary(at: Date(), claude: claude, version: v, steps: [])
        defer { c.save(support: support); lock.lock(); lastCanary = c; lock.unlock() }
        guard let v, let cv = ChatVersion(v), cv >= minimum else {
            c.set(.init(ModCanary.hasMods, .notApplicable, v.map { "\($0) has none; mods came in \(minimum). Duo works as before." }
                ?? "Duo couldn't read this Claude Code's version, so it checks nothing further."))
            return
        }
        c.set(.init(ModCanary.hasMods, .ok, v))
        guard let mod = installedMod() else {
            c.set(.init(ModCanary.installs, .failed, "Duo couldn't copy its mod into \(support.appending(path: "mods").path)."))
            return
        }
        let key = claude + "@" + v
        let (answer, out) = validation(mod: mod, key: key).map { ($0, "") } ?? validateNow(claude: claude, mod: mod, key: key)
        guard let ok = answer else {
            c.set(.init(ModCanary.installs, .unknown, "`claude plugin validate` didn't answer in \(Int(answerWithin)) s (a busy Mac?). Duo asks again at its next launch and passes nothing meanwhile."))
            return
        }
        guard ok else {
            c.set(.init(ModCanary.installs, .failed, "This Claude Code refuses it (`claude plugin validate`): \(lastLine(out)). Duo won't pass it to sessions."))
            return
        }
        c.set(.init(ModCanary.installs, .ok, "Copied to \(mod) and validated by this Claude Code."))
        // `plugin test` runs the mod's canary test (hooks/canary.test.ts) in the hooks' own
        // environment: no session, no tokens. It refuses when hooks modules are off here.
        let test = run(claude, ["plugin", "test", mod], timeout: answerWithin)
        guard test.status != nil else {   // no answer is no verdict: asked again next launch
            c.set(.init(ModCanary.mayRun, .unknown, "`claude plugin test` didn't answer in \(Int(answerWithin)) s (a busy Mac?). Duo asks again at its next launch."))
            return
        }
        let passed = test.status == 0 && test.out.contains("1 pass")
        lock.lock(); mayRun[key] = passed; lock.unlock()
        c.set(passed ? .init(ModCanary.mayRun, .ok, "`claude plugin test` loaded it and it wrote its snapshot.")
                     : .init(ModCanary.mayRun, .failed, lastLine(test.out)))
        guard passed else { return }
        c.set(isOn ? .init(ModCanary.loads, .unknown, "Not yet: no session has started with it since Duo opened.")
                   : .init(ModCanary.loads, .notApplicable, "Not passed to sessions: the sensor is off (DUO_SIGNAL)."))
    }

    nonisolated(unsafe) private static var lastCanary: ModCanary?
    nonisolated(unsafe) private static var mayRun: [String: Bool] = [:]
    nonisolated(unsafe) private static var heard = false

    /// A session started with the mod sent its first snapshot, or none in `silentAfter`: the canary's last step.
    static func noteLoaded(_ loaded: Bool, version: String?) {
        lock.lock()
        guard var c = lastCanary, !heard else { lock.unlock(); return }
        if loaded { heard = true }
        let f = DateFormatter(); f.timeStyle = .short
        c.set(loaded ? .init(ModCanary.loads, .ok, "A session started with it reported at \(f.string(from: Date())) (Claude Code \(version ?? "?")).")
                     : .init(ModCanary.loads, .failed, "A session started with it sent nothing in \(Int(silentAfter)) s: an organization policy (allowManagedModsOnly), an untrusted folder, or the mod crashed. Chat reads the screen as before."))
        lastCanary = c
        lock.unlock()
        let done = c
        DispatchQueue.global(qos: .utility).async { done.save(support: DuoPaths.support) }
    }
    /// How long `claude plugin validate` and `plugin test` may take (0.3 s on a quiet Mac); past it, no verdict.
    static let answerWithin: TimeInterval = 30
    /// How long a session started with the mod may stay silent before the canary says so.
    static let silentAfter: TimeInterval = 20

    private static func lastLine(_ s: String) -> String {
        s.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.last { !$0.isEmpty } ?? "no answer"
    }

    /// Runs `claude <args>`, stdout and stderr together; nil status if it outlasts `timeout` (it's ended).
    static func run(_ path: String, _ args: [String], timeout: TimeInterval) -> (status: Int32?, out: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe; p.standardError = pipe; p.standardInput = FileHandle.nullDevice
        let exited = DispatchSemaphore(value: 0)
        p.terminationHandler = { _ in exited.signal() }
        guard (try? p.run()) != nil else { return (nil, "") }
        nonisolated(unsafe) var data = Data()
        let read = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async { data = pipe.fileHandleForReading.readDataToEndOfFile(); read.signal() }
        if exited.wait(timeout: .now() + timeout) == .timedOut {
            p.terminate()
            if exited.wait(timeout: .now() + 0.5) == .timedOut { kill(p.processIdentifier, SIGKILL) }
            return (nil, "")
        }
        _ = read.wait(timeout: .now() + 0.5)
        return (p.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    /// The environment that goes with them.
    static func environment(_ launchId: String) -> [String: String] {
        wasPassed(launchId) ? [fileVariable: file(for: launchId).path] : [:]
    }

    /// Validates the mod against this CLI once (`claude plugin validate`, 0.3 s), off the main thread.
    /// A refusal keeps it off for that CLI: the API is early access and may change in any release
    /// (F-279), and a module that doesn't load draws a line in the terminal (F-297). No answer (a busy
    /// Mac, F-297) is no verdict: nothing is remembered, nothing passed, and the next launch asks again.
    private static func validate(claude: String, mod: String, key: String) {
        guard validation(mod: mod, key: key) == nil else { return }
        lock.lock()
        guard !validating.contains(key) else { lock.unlock(); return }
        validating.insert(key)
        lock.unlock()
        DispatchQueue.global(qos: .utility).async { validateNow(claude: claude, mod: mod, key: key) }
    }

    /// `claude plugin validate`, now (off the main thread), remembered for this claude and version.
    @discardableResult
    private static func validateNow(claude: String, mod: String, key: String) -> (Bool?, String) {
        let r = run(claude, ["plugin", "validate", mod], timeout: answerWithin)
        guard r.status != nil else {
            lock.lock(); validating.remove(key); lock.unlock()
            DuoLog.write("signal: validate \(key): no answer in \(Int(answerWithin)) s")
            return (nil, "")
        }
        let out = r.out
        let ok = out.contains("Validation passed") && !out.contains("✘")
        lock.lock(); validated[key] = ok; validating.remove(key); lock.unlock()
        var all = stored(mod); all[key] = ok
        if let data = try? JSONSerialization.data(withJSONObject: all) { try? data.write(to: storedURL(mod), options: .atomic) }
        DuoLog.write("signal: validate \(key) \(ok ? "passed" : "failed"): \(out.suffix(200))")
        return (ok, out)
    }

    /// This CLI's answer: from this launch, or an earlier one's; nil while there is none yet.
    private static func validation(mod: String, key: String) -> Bool? {
        lock.lock(); let ok = validated[key]; lock.unlock()
        if let ok { return ok }
        guard let s = stored(mod)[key] else { return nil }
        lock.lock(); validated[key] = s; lock.unlock()
        return s
    }

    /// What earlier launches validated, beside the mod's copy (`mods/<build>/validated.json`, one
    /// answer per claude and version): sessions restored at launch start before a validation could finish.
    private static func storedURL(_ mod: String) -> URL {
        URL(fileURLWithPath: mod).deletingLastPathComponent().appending(path: "validated.json")
    }
    private static func stored(_ mod: String) -> [String: Bool] {
        (try? Data(contentsOf: storedURL(mod))).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Bool] } ?? [:]
    }

    /// The mod's read-only copy in the support folder (`mods/<build>/duo-signal`), copied from the
    /// app on first use. Nil, and the flag in effect off, if the app has none or the copy fails.
    static func installedMod() -> String? {
        lock.lock(); defer { lock.unlock() }
        if let c = copied { return c }
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "dev"
        let src = Bundle.main.resourceURL?.appending(path: "mods/duo-signal")
        let dest = DuoPaths.support.appending(path: "mods/\(build)/duo-signal")
        let fm = FileManager.default
        var found: String?
        if fm.fileExists(atPath: dest.appending(path: "hooks/register.js").path) {
            found = dest.path
        } else if let src, fm.fileExists(atPath: src.appending(path: "hooks/register.js").path) {
            do {
                try? fm.removeItem(at: dest)
                try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.copyItem(at: src, to: dest)
                readOnly(dest)
                found = dest.path
            } catch { DuoLog.write("signal: the mod's copy failed: \(error)") }
        }
        copied = .some(found)
        return found
    }

    /// Read-only, so an interactive session writes nothing into it (F-280).
    private static func readOnly(_ dir: URL) {
        let fm = FileManager.default
        let all = (fm.enumerator(atPath: dir.path)?.allObjects as? [String] ?? []).map { dir.appending(path: $0).path }
        for p in all.reversed() + [dir.path] {
            var isDir: ObjCBool = false
            fm.fileExists(atPath: p, isDirectory: &isDir)
            try? fm.setAttributes([.posixPermissions: isDir.boolValue ? 0o555 : 0o444], ofItemAtPath: p)
        }
    }

    /// For the checks: forget what was validated, copied and passed.
    public static func reset() {
        lock.lock(); passed = []; validated = [:]; validating = []; copied = nil; mayRun = [:]; lastCanary = nil; heard = false; lock.unlock()
    }
    /// For the checks: a CLI's validation, as if it had run.
    public static func setValidated(_ claude: String, _ version: String, _ ok: Bool) {
        lock.lock(); validated[claude + "@" + version] = ok; lock.unlock()
    }
}

/// The mod's snapshot, read.
public struct ChatSignal: Equatable, @unchecked Sendable {
    public var seq: Int
    /// When the mod wrote it: its heartbeat.
    public var at: Date
    /// A turn is running (`turn.start` … `turn.complete`), dialogs included.
    public var busy: Bool
    /// The last turn ended by interruption (`turn.complete`'s `isAborted`).
    public var aborted = false
    /// The tool Claude asks about (`tool.check` answered `ask`), and its input.
    public var question: String?
    public var questionId: String?
    public var questionInput: ChatJSON = [:]
    public var version: String?

    public init(seq: Int, at: Date, busy: Bool, question: String? = nil, questionId: String? = nil, version: String? = nil) {
        self.seq = seq; self.at = at; self.busy = busy; self.question = question; self.questionId = questionId; self.version = version
    }

    public static func == (a: ChatSignal, b: ChatSignal) -> Bool {
        a.seq == b.seq && a.at == b.at && a.busy == b.busy && a.aborted == b.aborted && a.question == b.question && a.questionId == b.questionId && a.version == b.version
    }

    /// One snapshot; nil for anything that isn't the mod's version 1 (a half-written file reads as nil too).
    public static func parse(_ data: Data) -> ChatSignal? {
        guard let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any], o["v"] as? Int == 1,
              let seq = o["seq"] as? Int, let at = (o["at"] as? NSNumber)?.doubleValue, let busy = o["busy"] as? Bool else { return nil }
        var s = ChatSignal(seq: seq, at: Date(timeIntervalSince1970: at / 1000), busy: busy, version: o["version"] as? String)
        s.aborted = o["aborted"] as? Bool ?? false
        if let q = o["question"] as? [String: Any], let tool = q["tool"] as? String {
            s.question = tool
            s.questionId = q["id"] as? String
            s.questionInput = q["input"] as? ChatJSON ?? [:]
        }
        return s
    }

    /// Heard from within `staleAfter` (and not from the future: a clock that jumped is no heartbeat).
    public func isFresh(at now: Date) -> Bool {
        let age = now.timeIntervalSince(at)
        return age <= DuoSignal.staleAfter && age >= -DuoSignal.staleAfter
    }

    /// The screen as the signal reads it: an idle or busy screen takes busy from the signal; every
    /// other screen (dialogs, pickers, unknown, starting) is the screen's own, since chat answers
    /// them from what's drawn. A turn the signal saw interrupted reads as the screen's
    /// "Interrupted" would, which may draw a moment later. Stale, it changes nothing.
    public func overlay(_ s: ChatScreen, now: Date) -> ChatScreen {
        guard isFresh(at: now), s.kind == .idle || s.kind == .busy else { return s }
        var o = s
        o.kind = busy ? .busy : .idle
        if !busy, aborted { o.interrupted = true }
        return o
    }
}

/// Reads a session's signal file for its chat: every 50 ms while the chat is on screen, every 2 s
/// off it (ENH-45). Only for a session started with the mod; otherwise it never touches the disk.
@MainActor
final class ChatSignalReader {
    private(set) var signal: ChatSignal?
    private weak var chat: ChatSession?
    private var timer: Timer?
    private var stamp: Date?
    private var fresh = false
    private var ticks = 0
    /// When this session was first seen started with the mod, for the canary's silent case.
    private var since: Date?
    private var toldSilent = false
    nonisolated static let interval: TimeInterval = 0.05

    func start(for chat: ChatSession) {
        guard DuoSignal.isOn, timer == nil else { return }
        self.chat = chat
        timer = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    func stop() { timer?.invalidate(); timer = nil }

    /// The screen as a fresh signal reads it; the screen itself otherwise.
    func overlay(_ s: ChatScreen, now: Date) -> ChatScreen {
        guard let signal else { return s }
        return signal.overlay(s, now: now)
    }

    private func tick() {
        guard let chat else { return stop() }
        let id = chat.launchId ?? chat.key
        guard DuoSignal.wasPassed(id) else { return }
        if since == nil { since = Date() }
        if signal == nil, !toldSilent, let s = since, Date().timeIntervalSince(s) > DuoSignal.silentAfter {
            toldSilent = true
            DuoSignal.noteLoaded(false, version: chat.cliVersion)
        }
        ticks += 1
        if !chat.isShown(), ticks % 40 != 0 { return }
        let url = DuoSignal.file(for: id)
        var changed = false
        if let mtime = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date, mtime != stamp {
            stamp = mtime
            if let data = try? Data(contentsOf: url), let s = ChatSignal.parse(data) {
                let old = signal
                signal = s
                if old == nil { DuoSignal.noteLoaded(true, version: s.version) }
                if s.busy != old?.busy || s.aborted != old?.aborted || s.questionId != old?.questionId {
                    changed = true
                    ChatSignalTrace.note("signal", "busy=\(s.busy) aborted=\(s.aborted) question=\(s.question ?? "-") lag=\(Int(Date().timeIntervalSince(s.at) * 1000))ms")
                }
                if let tool = s.question, chat.pendingRequest == nil, s.isFresh(at: Date()) {
                    chat.pendingRequest = ChatRequest(tool: tool, input: s.questionInput, at: s.at)
                    ChatSignalTrace.note("request", "signal \(tool)")
                }
            }
        }
        let f = signal?.isFresh(at: Date()) ?? false
        if f != fresh { fresh = f; changed = true; ChatSignalTrace.note("fresh", "\(f)") }
        if changed { chat.reread() }
    }
}

/// Diagnostics for the spike's measurements (`DUO_SIGNAL_TRACE=1`): one stderr line per change,
/// `signal-trace <epoch ms> <what> <detail>`, with the flag on or off.
enum ChatSignalTrace {
    nonisolated(unsafe) static var on = Env.isSet("DUO_SIGNAL_TRACE")
    nonisolated(unsafe) private static var last: [String: String] = [:]

    static func note(_ what: String, _ detail: String) {
        guard on else { return }
        let ms = Int64(Date().timeIntervalSince1970 * 1000)
        FileHandle.standardError.write(Data("signal-trace \(ms) \(what) \(detail)\n".utf8))
    }

    /// Notes `detail` under `what` only when it changed.
    static func change(_ what: String, _ detail: @autoclosure () -> String) {
        guard on else { return }
        let detail = detail()
        guard last[what] != detail else { return }
        last[what] = detail
        note(what, detail)
    }
}
