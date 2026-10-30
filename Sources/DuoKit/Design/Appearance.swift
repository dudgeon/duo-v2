import AppKit
import DuoControl

/// Settings › General › Appearance (DL-224): Duo follows macOS (the default), or stays light or dark.
/// `duo2 settings appearance system|light|dark`.
public enum AppearanceSetting: String, CaseIterable, Sendable {
    case system, light, dark

    public var label: String {
        switch self { case .system: "Match System"; case .light: "Light"; case .dark: "Dark" }
    }

    /// What the user chose. `DUO_APPEARANCE` wins only in an isolated instance (a scripted run, for captures in each
    /// appearance): in the user's own Duo it is ignored, so an environment inherited from a launching shell can't pin the
    /// picker (C-122).
    @MainActor public static var current: AppearanceSetting {
        resolve(environment: ProcessInfo.processInfo.environment["DUO_APPEARANCE"], isolated: SupportFolder.isIsolated, saved: DuoState.load().appearance)
    }

    /// The rule in `current`, apart from where its inputs come from: the environment counts only when isolated.
    public static func resolve(environment: String?, isolated: Bool, saved: String?) -> AppearanceSetting {
        if isolated, let v = environment, let a = AppearanceSetting(rawValue: v) { return a }
        return saved.flatMap(AppearanceSetting.init(rawValue:)) ?? .system
    }

    /// Applies it at once, with no relaunch: nil follows macOS, live (also at sunset).
    @MainActor public static func apply() {
        switch current {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    /// Chooses it: saved, then applied. A failed save throws and applies nothing (the picker would otherwise show a choice
    /// that comes back as Match System at the next launch).
    @MainActor public static func set(_ a: AppearanceSetting) throws {
        try DuoState.write { $0.appearance = a.rawValue }
        apply()
    }

    /// A failed save, said on a Duo sheet (never a system alert).
    @MainActor public static func report(_ error: Error) {
        SheetCenter.shared.ask(DuoQuestion(
            title: "Duo couldn’t save the Appearance setting",
            paragraphs: [(error as? DuoState.WriteError)?.reason ?? error.localizedDescription],
            choices: [.init(label: "OK", isDefault: true, isCancel: true, action: {})]))
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
