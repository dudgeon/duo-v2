import AppKit
import Observation
import SwiftUI

/// Whether Duo moves at all, and how fast (DL-129, DL-130). One flag for every view, the split
/// view and the web pages: Reduce Motion makes all of Duo's own motion instant.
///
/// - `DUO_REDUCE_MOTION=1|0` overrides the system setting, for proof runs.
/// - `DUO_MOTION_SCALE=<n>` stretches every duration n times, so a capture can take frames
///   mid-motion at set times (Q-77). Delays (`rowHold`) stretch too, unless
///   `DUO_MOTION_HOLD=<seconds>` sets them, so a slowed fade needn't wait out a slowed hold.
@MainActor @Observable public final class MotionSettings {
    public static let shared = MotionSettings()

    public private(set) var reduce: Bool
    public let scale: Double
    public let holdOverride: Double?
    @ObservationIgnored private let forced: Bool?

    init() {
        let env = ProcessInfo.processInfo.environment
        forced = env["DUO_REDUCE_MOTION"].map { $0 == "1" }
        scale = env["DUO_MOTION_SCALE"].flatMap(Double.init).map { max(0.01, $0) } ?? 1
        holdOverride = env["DUO_MOTION_HOLD"].flatMap(Double.init)
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
    @MainActor var delay: Double { MotionSettings.shared.holdOverride ?? seconds * MotionSettings.shared.scale }

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

extension AnyTransition {
    /// A fold's rows (DL-130): they fade in over the second half of `fold`, once the rows around
    /// them have made room, and fade out over its first half. At once with Reduce Motion.
    @MainActor static var foldRows: AnyTransition {
        let half = DuoMotionToken.fold.duration / 2
        guard half > 0 else { return .identity }
        return .asymmetric(insertion: .opacity.animation(.easeOut(duration: half).delay(half)),
                           removal: .opacity.animation(.easeIn(duration: half)))
    }
}

extension AnyTransition {
    /// A row joining a list or leaving it (DL-130): `rowIn`, `rowOut`. At once with Reduce Motion.
    @MainActor static var listRow: AnyTransition {
        .asymmetric(insertion: .opacity.animation(DuoMotionToken.rowIn.animation),
                    removal: .opacity.animation(DuoMotionToken.rowOut.animation))
    }
}

extension AnyTransition {
    /// A tab opening or closing (DL-130): it fades in (`tabIn`) or out (`tabOut`); the strip
    /// slides the others (`tabMove`).
    @MainActor static var tab: AnyTransition {
        .asymmetric(insertion: .opacity.animation(DuoMotionToken.tabIn.animation),
                    removal: .opacity.animation(DuoMotionToken.tabOut.animation))
    }

    /// A notice bar arriving under the tab strip, or leaving (DL-130): it slides down from under
    /// the strip, pushing what's below (the container animates `noticeIn` / `noticeOut` and clips).
    @MainActor static var notice: AnyTransition { .move(edge: .top) }
}
