import Foundation

/// The mod canary (F-297): whether Claude Code mods can run on this Mac and Duo's own mod
/// (duo-signal, ENH-70) installs and loads. Duo checks at launch, in the background and quietly,
/// and writes `<support>/mods/canary.json`; `duo2 doctor` prints it. A diagnosis only: nothing in
/// Duo depends on it, and on a Claude Code without mods (2.1.219) it says so and checks nothing.
public struct ModCanary: Codable, Equatable, Sendable {
    public enum State: String, Codable, Sendable { case ok, failed, notApplicable = "n/a", unknown }

    public struct Step: Codable, Equatable, Sendable {
        public var name: String
        public var state: State
        public var detail: String
        public init(_ name: String, _ state: State, _ detail: String) { self.name = name; self.state = state; self.detail = detail }
    }

    /// The steps, in order.
    public static let hasMods = "Claude Code has mods"
    public static let installs = "Duo can install its mod"
    public static let mayRun = "Mods may run here"
    public static let loads = "Duo's mod loads in sessions"

    public var at: Date
    public var claude: String?
    public var version: String?
    public var steps: [Step]

    public init(at: Date, claude: String?, version: String?, steps: [Step]) {
        self.at = at; self.claude = claude; self.version = version; self.steps = steps
    }

    public static func url(support: URL) -> URL { support.appending(path: "mods/canary.json") }

    public static func load(support: URL) -> ModCanary? {
        guard let data = try? Data(contentsOf: url(support: support)) else { return nil }
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        return try? d.decode(ModCanary.self, from: data)
    }

    public func save(support: URL) {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.prettyPrinted, .sortedKeys]
        let u = Self.url(support: support)
        try? FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? e.encode(self) { try? data.write(to: u, options: .atomic) }
    }

    public func step(_ name: String) -> Step? { steps.first { $0.name == name } }

    /// The step set (or added) in place.
    public mutating func set(_ s: Step) {
        if let i = steps.firstIndex(where: { $0.name == s.name }) { steps[i] = s } else { steps.append(s) }
    }

    /// One line: what a user needs to know.
    public var summary: String {
        if step(Self.hasMods)?.state == .notApplicable { return "not available: this Claude Code (\(version ?? "unknown")) has no mods. Duo works as before." }
        if let f = steps.first(where: { $0.state == .failed }) { return "not working: \(f.name.lowercased()) failed. \(f.detail)" }
        if step(Self.loads)?.state == .ok { return "working: Duo's mod loads in its sessions." }
        if let u = steps.first(where: { $0.state == .unknown && $0.name != Self.loads }) { return "no verdict yet: \(u.detail)" }
        if steps.contains(where: { $0.state == .unknown }) || steps.count < 3 { return "not checked yet." }
        return "available: Duo's mod installs and mods may run here."
    }

    /// For `duo2 doctor`: the summary, then each step.
    public func lines(now: Date = Date()) -> [String] {
        let f = DateFormatter(); f.dateStyle = .short; f.timeStyle = .short
        var out = ["Claude Code mods: \(summary) (checked \(f.string(from: at)), \(claude ?? "no claude") \(version ?? ""))"]
        for s in steps {
            let mark = switch s.state { case .ok: "✔"; case .failed: "✘"; case .notApplicable: "–"; case .unknown: "?" }
            out.append("  \(mark) \(s.name): \(s.detail)")
        }
        return out
    }

    /// For `duo2 doctor` when Duo hasn't checked yet.
    public static let notChecked = "Claude Code mods: not checked yet (Duo checks at launch)."
}
