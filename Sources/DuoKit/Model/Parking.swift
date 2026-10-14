import Darwin
import Foundation

// Parking (DL-192, park-handoff): ending a live Claude tab's process, keeping the tab, and resuming
// it when it is shown (DL-156's mechanism). Everything that decides whether a tab can park, and
// when Duo asks under memory pressure, is plain data here so DuoChecks can drive it.

/// Why a tab can't park, in the order the reasons are checked.
public enum ParkBlock: String, Sendable, Equatable {
    case shell, notRunning, alreadyParked, keepRunning, working, needsYou, background, subagent, onScreen

    /// Says it after the tab's name: “Release watcher” is set to Keep Running.
    public var why: String {
        switch self {
        case .shell: "is a shell"
        case .notRunning: "isn’t running in Duo"
        case .alreadyParked: "is already parked"
        case .keepRunning: "is set to Keep Running"
        case .working: "is working"
        case .needsYou: "is waiting on you"
        case .background: "is running something in the background"
        case .subagent: "has a subagent running"
        case .onScreen: "is on screen"
        }
    }
}

/// What the eligibility check reads about one tab.
public struct ParkInputs: Sendable {
    public var isShell = false
    /// A live Claude process in one of Duo's terminals.
    public var hasTerminal = true
    /// Restored or parked, and not resumed since.
    public var parked = false
    public var keepRunning = false
    public var state: SessionState? = .idle
    /// The argv of each direct child of the Claude process.
    public var children: [[String]] = []
    /// The session's recent hook events.
    public var events: [HookEvents.Event] = []
    public var onScreen = false
    public init() {}
}

public enum ParkCheck {
    /// Nil when the tab can park. `bulk` (Park Background Sessions, memory pressure) also keeps
    /// the tab on screen; a single park moves the pane to another tab first.
    public static func why(_ i: ParkInputs, bulk: Bool = false) -> ParkBlock? {
        if i.isShell { return .shell }
        if !i.hasTerminal { return i.parked ? .alreadyParked : .notRunning }
        if i.keepRunning { return .keepRunning }
        if i.state == .working { return .working }
        if i.state == .needsYou { return .needsYou }
        if hasBackgroundWork(i.children) { return .background }
        if runningSubagents(i.events) > 0 { return .subagent }
        if bulk && i.onScreen { return .onScreen }
        return nil
    }

    /// Claude Code runs every Bash and Monitor command as `<shell> -c source
    /// <CLAUDE_CONFIG_DIR>/shell-snapshots/snapshot-….sh …` (F-308), so a child with that in its
    /// argv is a command still running. MCP servers and `caffeinate` are children too, and not that.
    public static func hasBackgroundWork(_ children: [[String]]) -> Bool {
        children.contains { argv in argv.contains { $0.contains("/shell-snapshots/snapshot-") } }
    }

    /// SubagentStart without its SubagentStop, by agent id. A process that ended mid-subagent never
    /// wrote the Stop, so a new SessionStart or a SessionEnd forgets what came before it.
    public static func runningSubagents(_ events: [HookEvents.Event]) -> Int {
        var open = Set<String>()
        var anonymous = 0
        for e in events {
            switch e.name {
            case "SessionStart", "SessionEnd": open.removeAll(); anonymous = 0
            case "SubagentStart": if let id = e.agentId { open.insert(id) } else { anonymous += 1 }
            case "SubagentStop": if let id = e.agentId { open.remove(id) } else { anonymous = max(0, anonymous - 1) }
            default: break
            }
        }
        return open.count + anonymous
    }

    /// What Duo says after Park Background Sessions (park-handoff, "After Park Background Sessions").
    public static func notice(parked: Int, kept: [(name: String, block: ParkBlock)]) -> String {
        let why = kept.map { "“\($0.name)” \($0.block.why)" }.joined(separator: ", ")
        guard parked > 0 else { return kept.isEmpty ? "No idle sessions to park." : "No idle sessions to park: \(why)." }
        let s = parked == 1 ? "Parked 1 session." : "Parked \(parked) sessions."
        guard !kept.isEmpty else { return s + (parked == 1 ? " It picks up where it left off when you show it." : " Each picks up where it left off when you show it.") }
        return s + " \(kept.count) kept running: " + why + "."
    }
}

/// The processes under a process, for the eligibility check.
public enum ProcessTable {
    /// The argv of each direct child of `pid`.
    public static func children(of pid: Int32) -> [[String]] {
        guard pid > 0 else { return [] }
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL]   // macOS has no select-by-parent; filter
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else { return [] }
        var infos = [kinfo_proc](repeating: kinfo_proc(), count: size / MemoryLayout<kinfo_proc>.stride + 64)   // room for processes that start meanwhile
        size = infos.count * MemoryLayout<kinfo_proc>.stride
        guard sysctl(&mib, 3, &infos, &size, nil, 0) == 0 else { return [] }
        let n = size / MemoryLayout<kinfo_proc>.stride
        return infos.prefix(n).filter { $0.kp_eproc.e_ppid == pid }.map { ForegroundCommand.arguments($0.kp_proc.p_pid) }
    }
}

/// One memory-pressure episode at a time (park-handoff, "When it's asked"): at `.critical`, if a
/// tab can park, Duo asks once; not again until pressure has been back to normal. Another sheet
/// being up makes it wait its turn (a retry every 2 s) and drop if pressure has eased.
@MainActor public final class ParkPressure {
    public enum Level: Sendable { case normal, warning, critical }
    public private(set) var level = Level.normal
    /// Whether this episode has been asked.
    public private(set) var asked = false
    /// How many tabs could park now.
    public var eligible: () -> Int = { 0 }
    /// Another sheet is up.
    public var sheetUp: () -> Bool = { false }
    /// Puts the question up.
    public var ask: () -> Void = {}
    /// Runs the closure after a delay (a timer in the app, a list in the checks).
    public var later: (TimeInterval, @escaping @MainActor () -> Void) -> Void = { delay, work in
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { MainActor.assumeIsolated { work() } }
    }
    public static let retryEvery: TimeInterval = 2
    private var generation = 0

    public init() {}

    public func changed(to new: Level) {
        level = new
        generation += 1   // a retry still waiting belongs to the pressure before this
        switch new {
        case .normal: asked = false
        case .warning: break
        case .critical: attempt(generation)
        }
    }

    private func attempt(_ g: Int) {
        guard g == generation, level == .critical, !asked else { return }
        if sheetUp() {
            later(Self.retryEvery) { [weak self] in self?.attempt(g) }
            return
        }
        guard eligible() > 0 else { return }
        asked = true
        ask()
    }
}
