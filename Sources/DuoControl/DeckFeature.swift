import Foundation

/// Whether Duo Decks shows (DL-307; Geoff, 2026-11-02: "cut 0.2.23 now, but keep Duo Decks out of it (hide its
/// screens) for its own release"). One switch for the app and `duo2`: on in debug and Duo Dev builds (`DEBUG`), off in a
/// release build. A release can turn it on with `defaults write com.dudgeon.duo DuoDecks -bool YES` (read by the app and
/// by `duo2`) or `DUO_DECKS=1` in the environment. Off, a `type: deck` note is plain Markdown, a .pptx has 0.2.22's
/// viewer, and no Decks menu item, picker or `duo2 deck` verb appears. The code stays in the build.
public enum DeckFeature {
    #if DEBUG
    public static let builtOn = true
    #else
    public static let builtOn = false
    #endif

    /// Set by DuoChecks to check both sides; nil in the app.
    nonisolated(unsafe) public static var override: Bool?

    public static var enabled: Bool {
        if let override { return override }
        if builtOn { return true }
        if ProcessInfo.processInfo.environment["DUO_DECKS"] == "1" { return true }
        if UserDefaults.standard.bool(forKey: "DuoDecks") { return true }
        return UserDefaults(suiteName: "com.dudgeon.duo")?.bool(forKey: "DuoDecks") ?? false
    }
}
