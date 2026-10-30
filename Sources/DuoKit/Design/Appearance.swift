import AppKit

/// Settings › General › Appearance (DL-224): Duo follows macOS (the default), or stays light or dark.
/// `duo2 settings appearance system|light|dark`.
public enum AppearanceSetting: String, CaseIterable, Sendable {
    case system, light, dark

    public var label: String {
        switch self { case .system: "Match System"; case .light: "Light"; case .dark: "Dark" }
    }

    /// What the user chose; a scripted run's `DUO_APPEARANCE` wins, for captures in each appearance.
    @MainActor public static var current: AppearanceSetting {
        if let v = ProcessInfo.processInfo.environment["DUO_APPEARANCE"], let a = AppearanceSetting(rawValue: v) { return a }
        return DuoState.load().appearance.flatMap(AppearanceSetting.init(rawValue:)) ?? .system
    }

    /// Applies it at once, with no relaunch: nil follows macOS, live (also at sunset).
    @MainActor public static func apply() {
        switch current {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    @MainActor public static func set(_ a: AppearanceSetting) {
        DuoState.update { $0.appearance = a.rawValue }
        apply()
    }
}

/// The look the app is drawing in now: what a token resolves to and which terminal palette applies. Views never ask;
/// only the places that copy a resolved value out of the appearance (the terminal, the web pages) do.
public enum DuoScheme: Sendable {
    case light, dark

    /// From an appearance (`NSApp.effectiveAppearance`, or a view's).
    public static func resolved(_ appearance: NSAppearance) -> DuoScheme {
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .dark : .light
    }

    public var terminal: DuoTerminalColors {
        switch self { case .light: DuoTerminalPalette.light; case .dark: DuoTerminalPalette.dark }
    }
}
