/// The five attention states a session carries (handoff §2.2), most urgent first.
public enum SessionState: String, Codable, CaseIterable, Comparable, Sendable {
    case needsYou
    case readyForReview
    case working
    case idle
    case resolved

    public static func < (a: SessionState, b: SessionState) -> Bool {
        allCases.firstIndex(of: a)! < allCases.firstIndex(of: b)!
    }

    /// Words for accessibility labels; colour never carries the meaning alone (handoff §10).
    public var spokenName: String {
        switch self {
        case .needsYou: "needs you"
        case .readyForReview: "ready for review"
        case .working: "working"
        case .idle: "idle"
        case .resolved: "resolved"
        }
    }

    /// What a session row says at its right (DL-91, DL-133): a session open in Duo reads what it's
    /// doing, `at prompt` or `working`, rather than how long ago; one that needs you keeps its wait.
    /// The session list and All projects' tiles both use it.
    public func waitText(_ wait: String?, open: Bool) -> String? {
        guard open else { return wait }
        switch self {
        case .idle: return "at prompt"
        case .working: return "working"
        default: return wait
        }
    }
}
