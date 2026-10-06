import AppKit
import Observation
import SwiftUI

/// Whether Duo moves at all, and how fast (DL-129, DL-130). One flag for every view, the split
/// view and the web pages: Reduce Motion makes all of Duo's own motion instant.
///
/// - `DUO_REDUCE_MOTION=1|0` overrides the system setting, for proof runs.
/// - `DUO_MOTION_SCALE=<n>` stretches every duration n times, so a capture can take frames
///   mid-motion at set times (Q-77). Delays (`rowHold`) stretch too.
@MainActor @Observable public final class MotionSettings {
    public static let shared = MotionSettings()

    public private(set) var reduce: Bool
    public let scale: Double
    @ObservationIgnored private let forced: Bool?

    init() {
        let env = ProcessInfo.processInfo.environment
        forced = env["DUO_REDUCE_MOTION"].map { $0 == "1" }
        scale = env["DUO_MOTION_SCALE"].flatMap(Double.init).map { max(0.01, $0) } ?? 1
        reduce = forced ?? NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                let s = MotionSettings.shared
                s.reduce = s.forced ?? NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            }
        }
    }
}

public extension DuoMotionToken {
    /// The duration as run: scaled for proof runs, zero with Reduce Motion.
    @MainActor var duration: Double {
        MotionSettings.shared.reduce ? 0 : seconds * MotionSettings.shared.scale
    }

    /// A delay (`rowHold`): scaled, but kept with Reduce Motion, which removes motion, not time.
    @MainActor var delay: Double { seconds * MotionSettings.shared.scale }

    /// The SwiftUI animation for this token, or nil with Reduce Motion (the change happens at once).
    @MainActor var animation: Animation? {
        let s = MotionSettings.shared
        guard !s.reduce else { return nil }
        let d = seconds * s.scale
        switch ease {
        case .out: return .easeOut(duration: d)
        case .in: return .easeIn(duration: d)
        case .inOut: return .easeInOut(duration: d)
        case .none: return .linear(duration: d)
        }
    }

    /// The CSS timing for the web pages: `<ms>ms <easing>`.
    @MainActor var css: String {
        let e: String = switch ease { case .out: "ease-out"; case .in: "ease-in"; case .inOut: "ease-in-out"; case .none: "linear" }
        return "\(Int((duration * 1000).rounded()))ms \(e)"
    }
}

public extension View {
    /// `.animation(token.animation, value:)`, read from the shared flag.
    @MainActor func duoAnimation<V: Equatable>(_ token: DuoMotionToken, value: V) -> some View {
        animation(token.animation, value: value)
    }
}

/// Runs a change with a token's animation, or plainly with Reduce Motion.
@MainActor public func withDuoAnimation<R>(_ token: DuoMotionToken, _ body: () throws -> R) rethrows -> R {
    try withAnimation(token.animation, body)
}
