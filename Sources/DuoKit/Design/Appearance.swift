import AppKit
import DuoControl

/// Settings › General › Appearance (DL-224): Duo follows macOS (the default), or stays light or dark. Classic (DL-252) is legacy
/// Duo's warm paper look: always light, and the app icon in the Dock is recoloured to match.
/// `duo2 settings appearance system|light|dark|classic`.
public enum AppearanceSetting: String, CaseIterable, Sendable {
    case system, light, dark, classic

    public var label: String {
        switch self { case .system: "Match System"; case .light: "Light"; case .dark: "Dark"; case .classic: "Classic" }
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
        let setting = current
        let wasClassic = DuoScheme.classicActive
        DuoScheme.classicActive = setting == .classic
        switch setting {
        case .system: NSApp.appearance = nil
        case .light, .classic: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
        guard wasClassic != DuoScheme.classicActive else { return }
        // Classic and Light are both aqua, so AppKit sees no change and nothing would draw again. Pass through the other
        // appearance and back, in one turn: every `viewDidChangeEffectiveAppearance` (the terminal, the sheet field, the
        // editor) fires, and nothing is drawn in between. Then the web pages that sit out appearance changes hear of it.
        let target = NSApp.appearance
        NSApp.appearance = NSAppearance(named: .darkAqua)
        NSApp.appearance = target
        NSApp.applicationIconImage = DuoScheme.classicActive ? DuoClassicIcon.image : nil   // nil: the bundle's own icon
        NotificationCenter.default.post(name: DuoScheme.didChange, object: nil)
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
    case light, dark, classic

    /// Whether Classic is chosen (DL-252). Set only by `AppearanceSetting.apply()`; read by the colour providers, on any thread.
    nonisolated(unsafe) public static var classicActive = false

    /// Posted on the main thread after the scheme changed between Classic and not.
    public static let didChange = Notification.Name("DuoSchemeDidChange")

    /// From an appearance (`NSApp.effectiveAppearance`, or a view's): dark is the appearance; Classic is light with the flag.
    public static func resolved(_ appearance: NSAppearance) -> DuoScheme {
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .dark : classicActive ? .classic : .light
    }

    public var terminal: DuoTerminalColors {
        switch self { case .light: DuoTerminalPalette.light; case .dark: DuoTerminalPalette.dark; case .classic: DuoTerminalPalette.classic }
    }

    public var document: DuoWebTokens.DuoDocumentType {
        switch self { case .light: DuoWebTokens.documentLight; case .dark: DuoWebTokens.documentDark; case .classic: DuoWebTokens.documentClassic }
    }
}

/// Classic's Dock icon (DL-252): v2's two panes in Classic's values, drawn by scripts/gen-app-icon.swift from tokens.json.
@MainActor enum DuoClassicIcon {
    static let image: NSImage? = Bundle.main.url(forResource: "AppIconClassic", withExtension: "icns").flatMap { NSImage(contentsOf: $0) }
}
