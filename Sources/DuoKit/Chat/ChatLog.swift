import Foundation
import Observation

/// The conversation chat mode draws (handoff `window`, `text`, `tools`, `status`).
@MainActor
@Observable
public final class ChatLog {
    public internal(set) var items: [ChatItem] = []

    public init() {}

    /// The screen says a reply ended without its hook (an interrupt, F-105).
    public func endStreaming(interrupted: Bool) {}
}

/// One entry in the transcript.
public enum ChatItem: Identifiable, Equatable, Sendable {
    case you(ChatYou)

    public var id: String {
        switch self {
        case .you(let y): y.id
        }
    }
}

/// Your message: a blue bubble on the right.
public struct ChatYou: Equatable, Sendable {
    public var id: String
    public var text: String
    public var time: Date?
}
