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
}
