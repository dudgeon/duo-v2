@preconcurrency import AVFoundation
import AppKit
import DuoControl
import Foundation
import Observation

/// Where dictated words go.
public enum VoiceTarget: Equatable, Sendable {
    case chat(String)
    case terminal(String)
    public var key: String { switch self { case .chat(let k), .terminal(let k): k } }
}

public enum VoicePasteResult: Equatable, Sendable {
    case sent
    /// Why not (a question is waiting): listening stops and the unsent words go to the clipboard.
    case blocked(String)
}

/// A line over the terminal mic or under the chat field that goes after 6 s.
public struct VoiceNotice: Equatable, Sendable {
    public var text: String
    public var target: VoiceTarget
}

/// Words people see for each state (voice-input-handoff `composer`).
public enum VoiceCopy {
    public static let denied = "Duo can’t use the microphone."
    public static let restricted = "Your Mac’s administrator doesn’t allow voice input for Duo"
    public static let noMic = "No microphone found."
    public static let noMicAside = "Plug one in or pick one in System Settings › Sound."
    /// Stand-in (Q-340): AVAudioEngine refused a device that looked usable.
    public static let micFailed = "The microphone didn’t start."
    public static let keptAside = "Your words are kept."
    public static let isolated = "The microphone isn’t available in an isolated Duo."
    public static let tooltip = "Voice input ⇧⌘D · hold to talk"
    public static let sheetTitle = "Use your voice in Duo?"
    public static let sheetBody = "Duo turns what you say into text, on this Mac, using Apple’s speech recognition. Nothing is recorded or sent anywhere."
    public static let sheetBox = "macOS will ask whether Duo may use the microphone."
    public static let sheetBoxAside = "You can change this later in System Settings › Privacy & Security."
    public static func notAvailable(in language: String) -> String { "Voice input isn’t available in \(language) on this Mac." }

    /// The aside after a state's main line, in `text2`.
    public static func aside(for s: VoiceState) -> String? {
        switch s {
        case .unavailable(let w) where w == noMic: noMicAside
        case .failed: keptAside
        default: nil
        }
    }

    /// The line `duo2 voice status` and the fixtures use.
    public static func line(_ s: VoiceState) -> String {
        switch s {
        case .idle: "Voice input is off."
        case .asking: "Waiting for your answer to Duo’s question."
        case .preparing(let p): p.map { "Getting the speech model from Apple · \(Int($0 * 100))%" } ?? "Getting the speech model from Apple"
        case .listening: "Listening."
        case .finishing: "Finishing…"
        case .unavailable(let w), .failed(let w): w
        case .denied: denied
        case .restricted: restricted
        }
    }
}

/// Voice input (DL-260, DL-261): one dictation at a time, into a chat composer or a terminal's prompt.
/// The recognizer is Apple's, on this Mac. Words land through `host`: the chat field shows them as they
/// settle, the terminal gets each settled phrase as one paste, and never a Return.
@MainActor @Observable
public final class VoiceInput {
    public struct Host {
        /// Chat: the transcript changed (settled and volatile text); `final` once, when the dictation ends.
        public var update: (VoiceTarget, VoiceTranscript, _ final: Bool) -> Void
        /// Terminal: paste one settled phrase (`first`: no leading space); `.blocked` stops listening.
        public var paste: (VoiceTarget, String, _ first: Bool) -> VoicePasteResult
        /// The dictation is over; `kept` false means Esc discarded it (chat removes its words).
        public var ended: (VoiceTarget, _ kept: Bool) -> Void
        public init(update: @escaping (VoiceTarget, VoiceTranscript, Bool) -> Void,
                    paste: @escaping (VoiceTarget, String, Bool) -> VoicePasteResult,
                    ended: @escaping (VoiceTarget, Bool) -> Void) {
            self.update = update; self.paste = paste; self.ended = ended
        }
    }

    /// The app's one voice input (the composer's keys reach it from the text view).
    public static weak var current: VoiceInput?

    public private(set) var state: VoiceState = .idle
    public private(set) var transcript = VoiceTranscript()
    public private(set) var target: VoiceTarget?
    /// 0...1, smoothed, for the level meter.
    public private(set) var level: Double = 0
    public private(set) var notice: VoiceNotice?
    /// ⇧⌘D is held (hold-to-talk): the hint reads "Listening while you hold ⇧⌘D".
    public var holding = false
    /// Where the terminal mic last was (screen cells' rect in its view), for the notice.
    @ObservationIgnored public var host: Host?
    /// Whether the app asks for the microphone itself: false in a scripted or isolated Duo, unless that Duo was
    /// launched with `DUO_VOICE_LIVE=1` for a person's own hands-on test (a gated, visible dev instance): then it
    /// asks for the microphone and uses the clipboard as the user's own Duo does.
    @ObservationIgnored public var isolated: () -> Bool = { VoiceInput.isolatedWithout(ProcessInfo.processInfo.environment) }
    /// Whether there is a microphone to listen to (VoiceDevice; replaceable in checks).
    @ObservationIgnored public var hasMicrophone: () -> Bool = { VoiceDevice.hasMicrophone }
    /// Ends a file feed early, as the mic's stop does (finish, Esc, a switch away).
    @ObservationIgnored private var fileStop: (@Sendable () -> Void)?

    public static func isolatedWithout(_ env: [String: String], isolated: Bool = SupportFolder.isIsolated) -> Bool {
        isolated && env["DUO_VOICE_LIVE"] != "1"
    }

    /// The words a blocked dictation didn't send (always kept; on the clipboard only in the user's own Duo).
    public private(set) var unsentWords: String?
    @ObservationIgnored public var writeClipboard: (String) -> Void = { text in
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
    @ObservationIgnored private var mic: MicCapture?
    @ObservationIgnored private var recognizer: AppleRecognizer?
    @ObservationIgnored private var runTask: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var sentPhrases = 0
    @ObservationIgnored private var lastHeard = Date()
    @ObservationIgnored private var silenceTimer: Task<Void, Never>?
    @ObservationIgnored private var waiting: [@MainActor (VoiceState) -> Void] = []
    @ObservationIgnored private var heldSince: Date?

    /// Whether there is a microphone, and its name: read at rest and kept up to date by the device source, so the mics
    /// change look by themselves when one connects or goes (NoMic.dc.html).
    public private(set) var microphoneAvailable = true
    public private(set) var microphoneName: String?
    @ObservationIgnored public var deviceSource: VoiceDeviceSource = CoreAudioDeviceSource() { didSet { refreshMicrophone(); attachDeviceSource() } }
    /// The running dictation listens to the microphone (not a file), so losing the device ends it.
    @ObservationIgnored private var runsOnMicrophone = false

    public init() {
        refreshMicrophone()
        attachDeviceSource()
    }

    private func attachDeviceSource() {
        deviceSource.observe { [weak self] in self?.refreshMicrophone() }
    }

    /// Reads the device now, and acts on a change: a lost microphone ends a dictation that was using it (the words
    /// stay), a found one clears the "No microphone found." line.
    public func refreshMicrophone() {
        let c = deviceSource.current()
        microphoneAvailable = c.usable
        microphoneName = c.usable ? c.name : nil
        if !c.usable, runsOnMicrophone, state == .listening || state == .finishing {
            stopAndKeep(.failed("Stopped: the microphone went away."))
        } else if c.usable, case .unavailable(let why) = state, why == VoiceCopy.noMic {
            state = .idle
            notice = nil
        }
    }

    /// `duo2 voice status` when nothing is running.
    public var microphoneLine: String {
        microphoneAvailable ? "Voice input is off." + (microphoneName.map { " Microphone: \($0)." } ?? "") : "Voice input is off: no microphone connected."
    }

    public var isActive: Bool { state.isActive }

    // MARK: Presses

    /// The mic or ⇧⌘D: starts, or finishes what's running.
    public func toggle(_ target: VoiceTarget) {
        switch state {
        case .listening, .preparing, .asking: finishOrCancel()
        case .finishing: break
        default: start(target)
        }
    }

    /// Key down of ⇧⌘D: a tap toggles; held past 0.3 s ends on key-up (`keyUp`).
    public func keyDown(_ target: VoiceTarget) {
        guard heldSince == nil else { return }
        heldSince = Date()
        if state == .listening { finishOrCancel() } else if state == .idle || !state.isActive { start(target) }
    }

    public func keyUp() {
        guard let t = heldSince else { return }
        heldSince = nil
        // Held past 0.3 s: hold-to-talk, ends on release. A quicker tap leaves it listening (the toggle).
        if Date().timeIntervalSince(t) > 0.3, state == .listening || state.isActive { finishOrCancel() }
        holding = false
    }

    /// Said while the key is down and past the threshold, so the hint can read "while you hold".
    public func noteHolding() { if heldSince != nil, state == .listening { holding = true } }

    private func finishOrCancel() {
        if state == .listening { finish() } else { discard() }
    }

    // MARK: Start

    /// Starts a dictation. `source` is the microphone, or a file (`duo2 voice file`: no microphone, no questions).
    public func start(_ target: VoiceTarget, source: VoiceAudioSource = .microphone, done: (@MainActor (VoiceState) -> Void)? = nil) {
        if let done { waiting.append(done) }
        guard !state.isActive else { return }
        self.target = target
        transcript = VoiceTranscript()
        sentPhrases = 0
        notice = nil
        unsentWords = nil
        holding = false
        generation += 1
        let gen = generation
        set(.start)
        if case .microphone = source {
            if isolated() { return fail(.unavailable(VoiceCopy.isolated)) }
            // No input device: say so before Duo's sheet or macOS's microphone question, which would be pointless
            // (F-447: AVAudioEngine raised and took Duo down on a Mac mini with no microphone).
            if !hasMicrophone() { return fail(.unavailable(VoiceCopy.noMic)) }
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .denied: return fail(.denied)
            case .restricted: return fail(.restricted)
            case .notDetermined:
                return ask(gen: gen) { [weak self] in self?.begin(source, gen: gen) }
            default: break
            }
        }
        begin(source, gen: gen)
    }

    /// Duo's sheet before macOS asks (first-press.html); Not Now asks nothing. Public so the harness draws it
    /// without asking macOS.
    public static func firstPressQuestion(notNow: @escaping @MainActor () -> Void, proceed: @escaping @MainActor () -> Void) -> DuoQuestion {
        DuoQuestion(
            title: VoiceCopy.sheetTitle,
            paragraphs: [VoiceCopy.sheetBody],
            items: [.init(what: VoiceCopy.sheetBox, path: VoiceCopy.sheetBoxAside, sub: true)],
            choices: [
                .init(label: "Not Now", isCancel: true, action: notNow),
                .init(label: "Continue", isDefault: true, action: proceed),
            ])
    }

    private func ask(gen: Int, then go: @escaping @MainActor () -> Void) {
        SheetCenter.shared.ask(Self.firstPressQuestion(
            notNow: { [weak self] in
                guard let self, self.generation == gen else { return }
                self.set(.sheetAnswered(continueAsking: false)); self.finishedRun()
            },
            proceed: { [weak self] in
                guard let self, self.generation == gen else { return }
                self.set(.sheetAnswered(continueAsking: true))
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    DispatchQueue.main.async { MainActor.assumeIsolated {
                        guard self.generation == gen else { return }
                        if granted { go() } else { self.fail(AVCaptureDevice.authorizationStatus(for: .audio) == .restricted ? .restricted : .denied) }
                    } }
                }
            }))
    }

    private func begin(_ source: VoiceAudioSource, gen: Int) {
        if case .microphone = source { runsOnMicrophone = true } else { runsOnMicrophone = false }
        if state == .asking { set(.sheetAnswered(continueAsking: true)) }
        let recognizer = AppleRecognizer()
        self.recognizer = recognizer
        let buffers: AsyncStream<VoiceBuffer>
        do {
            switch source {
            case .microphone:
                let m = MicCapture(level: { [weak self] l in DispatchQueue.main.async { MainActor.assumeIsolated { self?.take(level: l) } } },
                                   lost: { [weak self] in DispatchQueue.main.async { MainActor.assumeIsolated { self?.micLost(gen: gen) } } })
                try m.start()
                mic = m
                buffers = m.stream
            case .file(let url):
                // DUO_VOICE_FILE_REALTIME=1: at the pace it was spoken, so a live check can act mid-dictation.
                let feed = try FileFeed.stream(url, realtime: ProcessInfo.processInfo.environment["DUO_VOICE_FILE_REALTIME"] == "1")
                fileStop = feed.stop
                if ProcessInfo.processInfo.environment["DUO_VOICE_FILE_REALTIME"] == "1" {
                    // As the mic's tap does: each buffer's level, for the bars (DL-266).
                    let (levelled, out) = AsyncStream<VoiceBuffer>.makeStream(bufferingPolicy: .unbounded)
                    Task { [weak self] in
                        for await b in feed.stream {
                            let l = VoiceLevel.of(b.buffer)
                            await MainActor.run { self?.take(level: l) }
                            out.yield(b)
                        }
                        out.finish()
                    }
                    buffers = levelled
                } else {
                    buffers = feed.stream
                }
            }
        } catch VoiceAudioError.noMicrophone {
            return fail(.unavailable(VoiceCopy.noMic))
        } catch VoiceAudioError.micFailed(let why) {
            DuoLog.write("voice: the microphone failed to start: \(why)")
            return fail(.unavailable(VoiceCopy.micFailed))
        } catch {
            return fail(.unavailable("Voice input can’t read that audio: \(error)."))
        }
        runTask = Task { [weak self] in
            do {
                try await recognizer.prepare { p in Task { @MainActor in self?.progress(p, gen: gen) } }
                guard let self, self.generation == gen else { return }
                self.set(.modelReady)
                self.lastHeard = Date()
                self.watchSilence(gen: gen, mic: source == .microphone)
                try await recognizer.run(buffers: buffers) { text, isFinal in
                    Task { @MainActor in self.result(text, isFinal: isFinal, gen: gen) }
                }
                guard self.generation == gen else { return }
                self.completed()
            } catch let e as VoiceRecognizerError {
                guard let self, self.generation == gen else { return }
                self.stopCapture()
                switch e {
                case .unavailable(let l): self.fail(.unavailable(VoiceCopy.notAvailable(in: l)))
                case .speechDenied: self.fail(.denied)
                case .speechRestricted: self.fail(.restricted)
                }
            } catch {
                guard let self, self.generation == gen else { return }
                self.stopCapture()
                self.fail(.failed("Stopped: \(error.localizedDescription)."))
            }
        }
    }

    // MARK: Results

    private func take(level l: Float) { level = level * 0.5 + Double(l) * 0.5 }

    private func progress(_ p: Double?, gen: Int) {
        guard generation == gen, case .preparing = state else { return }
        set(.modelProgress(p))
    }

    private func result(_ text: String, isFinal: Bool, gen: Int) {
        if ProcessInfo.processInfo.environment["DUO_VOICE_TRACE"] == "1" {
            FileHandle.standardError.write(Data("voice-result: gen=\(gen)/\(generation) state=\(state) final=\(isFinal) \(text.debugDescription)\n".utf8))
        }
        guard generation == gen, state == .listening || state == .finishing, let target else { return }
        if !text.trimmingCharacters(in: .whitespaces).isEmpty { lastHeard = Date() }
        let phrase = transcript.apply(text, isFinal: isFinal)
        switch target {
        case .chat: host?.update(target, transcript, false)
        case .terminal: if let phrase { deliver(phrase, to: target) }
        }
    }

    /// One settled phrase into the terminal. A question on screen stops everything. Public for DuoChecks.
    public func deliver(_ phrase: String, to target: VoiceTarget) {
        switch host?.paste(target, phrase, sentPhrases == 0) ?? .blocked("no terminal") {
        case .sent: sentPhrases += 1
        case .blocked:
            // The phrase wasn't sent: it and everything after go to the clipboard.
            let unsent = ([phrase] + [transcript.volatile].filter { !$0.isEmpty }).joined(separator: " ")
            // An isolated or scripted Duo never writes the user's clipboard (Q-335): the words are kept here and
            // `duo2 voice status` reports them.
            unsentWords = unsent
            if !isolated() { writeClipboard(unsent) }
            stopCapture()
            generation += 1
            runTask?.cancel()
            Task { await recognizer?.cancel() }
            notice = VoiceNotice(text: VoiceTerminalText.questionNotice, target: target)
            expireNotice()
            state = .idle
            host?.ended(target, true)
            finishedRun()
        }
    }

    private func watchSilence(gen: Int, mic: Bool) {
        silenceTimer?.cancel()
        guard mic else { return }
        silenceTimer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self, self.generation == gen, self.state == .listening else { return }
                if Date().timeIntervalSince(self.lastHeard) > 15 {
                    self.stopAndKeep(.failed("Stopped: nothing heard for 15 s."))
                    return
                }
            }
        }
    }

    private func micLost(gen: Int) {
        guard generation == gen, state == .listening else { return }
        stopAndKeep(.failed("Stopped: the microphone went away."))
    }

    /// Stops listening, keeps the words, and shows `why` as a line.
    private func stopAndKeep(_ why: VoiceState) {
        generation += 1
        stopCapture()
        runTask?.cancel()
        let t = target
        Task { await recognizer?.cancel() }
        _ = transcript.settleTail()
        state = why
        if let t {
            if case .chat = t { host?.update(t, transcript, true) }
            host?.ended(t, true)
        }
        expireLine()
        finishedRun()
    }

    // MARK: Finish and discard

    /// The mic or ⇧⌘D: stops listening; the last phrases land. Never sends (Return sends after it, DL-263).
    public func finish() {
        guard state == .listening else { return }
        set(.finish)
        stopCapture()   // ends the buffer stream; the recognizer finalizes and `run` returns
    }

    /// Finishes, and calls `done` once the last phrases have landed.
    public func finishWhenDone(_ done: @escaping @MainActor (VoiceState) -> Void) {
        guard state.isActive else { return done(state) }
        waiting.append(done)
        // Already finishing: just wait for it (discarding here would drop the last words).
        if state == .listening { finish() } else if state != .finishing { discard() }
    }

    /// Esc: drops the dictation.
    public func discard() {
        guard state.isActive else { return }
        generation += 1
        stopCapture()
        runTask?.cancel()
        Task { await recognizer?.cancel() }
        let t = target
        state = .idle
        if let t { host?.ended(t, false) }
        finishedRun()
    }

    private func completed() {
        guard let t = target else { return finishedRun() }
        if let phrase = transcript.settleTail(), case .terminal = t { deliver(phrase, to: t) }
        guard state.isActive else { return }
        if case .chat = t { host?.update(t, transcript, true) }
        state = .idle
        host?.ended(t, true)
        finishedRun()
    }

    private func stopCapture() {
        silenceTimer?.cancel()
        mic?.stop(); mic = nil
        fileStop?(); fileStop = nil
        level = 0
        holding = false
    }

    // MARK: State

    private func set(_ e: VoiceEvent) { state = VoiceMachine.next(state, e) }

    private func fail(_ s: VoiceEvent) {
        stopCapture()
        state = VoiceMachine.next(state, s)
        runsOnMicrophone = false
        // On a terminal there's no hint row: the no-microphone line shows as a notice at the mic, for 6 s.
        if case .unavailable(let why) = state, why == VoiceCopy.noMic, case .terminal? = target {
            notice = VoiceNotice(text: "\(VoiceCopy.noMic) \(VoiceCopy.noMicAside)", target: target!)
            expireNotice()
        }
        expireLine()
        finishedRun()
    }

    /// A line that stays 6 s, or until you type.
    private func expireLine() {
        let shown = state
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
            MainActor.assumeIsolated { if let self, self.state == shown { self.state = .idle } }
        }
    }

    private func expireNotice() {
        let n = notice
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
            MainActor.assumeIsolated { if let self, self.notice == n { self.notice = nil } }
        }
    }

    /// A key typed while a line shows clears it.
    public func dismissLine() {
        if !state.isActive, state != .idle { state = .idle }
        notice = nil
    }

    private func finishedRun() {
        let s = state
        let w = waiting
        waiting = []
        for f in w { f(s) }
    }

    // MARK: Fixtures

    /// Puts the UI in a state without a microphone (FixtureHarness).
    public func showFixture(_ s: VoiceState, target: VoiceTarget, transcript: VoiceTranscript = VoiceTranscript(), holding: Bool = false, level: Double = 0.6, onMicrophone: Bool = false) {
        runsOnMicrophone = onMicrophone
        self.target = target; state = s; self.transcript = transcript; self.holding = holding; self.level = level
    }
}
