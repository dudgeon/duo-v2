import Foundation

// Voice input's pure logic (DL-260, DL-261): the state machine, the phrase splitter and the terminal's
// paste text. No audio and no AppKit, so DuoChecks tests it directly.

/// Where voice input stands. Each case has its line on voice-input-handoff `composer`.
public enum VoiceState: Equatable, Sendable {
    case idle
    /// Duo's own sheet is up, before macOS is asked.
    case asking
    /// Waiting for Apple's speech model; `progress` is 0...1 when Apple reports it.
    case preparing(progress: Double?)
    case listening
    /// The last phrases are landing (usually under 0.2 s).
    case finishing
    /// Can't start (no microphone, no model for the language, an isolated Duo); the line says why.
    case unavailable(String)
    case denied
    case restricted
    /// Stopped by itself (no speech for 15 s, the microphone went away); words are kept.
    case failed(String)

    public var isActive: Bool {
        switch self { case .asking, .preparing, .listening, .finishing: true; default: false }
    }
}

public enum VoiceEvent: Equatable, Sendable {
    /// The mic, ⇧⌘D or `duo2 voice start`.
    case start
    /// The first-press sheet's answer.
    case sheetAnswered(continueAsking: Bool)
    case modelProgress(Double?)
    case modelReady
    case finish
    case finished
    case discard
    case denied, restricted
    case unavailable(String)
    case failed(String)
    /// A notice's 6 s, a keystroke: the line goes away.
    case dismiss
}

public enum VoiceMachine {
    /// The state after `event`. Events that make no sense in a state leave it as it is.
    public static func next(_ s: VoiceState, _ e: VoiceEvent) -> VoiceState {
        switch (s, e) {
        case (_, .denied): return .denied
        case (_, .restricted): return .restricted
        case (_, .unavailable(let why)): return .unavailable(why)
        case (.asking, .sheetAnswered(let go)): return go ? .preparing(progress: nil) : .idle
        case (.preparing, .modelProgress(let p)): return .preparing(progress: p)
        case (.preparing, .modelReady), (.asking, .modelReady): return .listening
        case (.preparing, .finish), (.asking, .finish): return .idle
        case (.listening, .finish): return .finishing
        case (.finishing, .finished), (.listening, .finished), (.preparing, .finished): return .idle
        case (.preparing, .discard), (.listening, .discard), (.finishing, .discard), (.asking, .discard): return .idle
        case (.preparing, .failed(let w)), (.listening, .failed(let w)), (.finishing, .failed(let w)), (.idle, .failed(let w)): return .failed(w)
        case (.idle, .start), (.denied, .start), (.restricted, .start), (.unavailable, .start), (.failed, .start): return .asking
        case (.denied, .dismiss), (.restricted, .dismiss), (.unavailable, .dismiss), (.failed, .dismiss): return .idle
        default: return s
        }
    }
}

/// Progressive results from the recognizer: a volatile result replaces the one before it, a final
/// one settles a phrase (handoff: settled text in `text`, the volatile tail in `text2`).
public struct VoiceTranscript: Equatable, Sendable {
    public private(set) var settled: [String] = []
    public private(set) var volatile = ""
    public init() {}

    /// Feeds one result; returns the phrase that just settled, if it did.
    @discardableResult
    public mutating func apply(_ text: String, isFinal: Bool) -> String? {
        let t = text.split(whereSeparator: { $0.isNewline }).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        if isFinal {
            volatile = ""
            guard !t.isEmpty else { return nil }
            settled.append(t)
            return t
        }
        volatile = t
        return nil
    }

    /// Everything said so far, settled phrases only, one space between.
    public var settledText: String { settled.joined(separator: " ") }
    /// The settled text, a space, then the volatile tail.
    public var allText: String { [settledText, volatile].filter { !$0.isEmpty }.joined(separator: " ") }

    /// Takes whatever is still volatile as settled (the recognizer ended without finalising it).
    @discardableResult
    public mutating func settleTail() -> String? {
        guard !volatile.isEmpty else { return nil }
        return apply(volatile, isFinal: true)
    }
}

/// What the terminal gets: each settled phrase one bracketed paste, a space before every phrase but
/// the first, no Return.
@MainActor public enum VoiceTerminalText {
    public static func paste(_ phrase: String, first: Bool) -> String {
        let one = phrase.split(whereSeparator: { $0.isNewline }).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return TerminalSession.bracketed((first ? "" : " ") + one)
    }

    /// The words that were never sent, for the clipboard.
    public static func unsent(_ t: VoiceTranscript, sentCount: Int) -> String {
        var rest = Array(t.settled.dropFirst(sentCount))
        if !t.volatile.isEmpty { rest.append(t.volatile) }
        return rest.joined(separator: " ")
    }

    public static let questionNotice = "Voice input stopped: Claude asked a question. Your words are on the clipboard."
}
