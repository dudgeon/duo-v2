import AppKit
import DuoKit
import Sparkle

/// In-app updates with Sparkle (Phase L): release builds check the feed published with each GitHub
/// release, download the signed DMG, and replace Duo after asking. Development builds (0.0.1) and
/// scripted runs never start it, and Duo › Check for Updates… falls back to the GitHub notice
/// (F-69) when Sparkle isn't running.
@MainActor
enum SparkleUpdater {
    static var controller: SPUStandardUpdaterController?

    static func start(model: AppModel) {
        guard !UpdateCheck.isDevelopmentBuild, Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil,
              model.interactivePrompts, ProcessInfo.processInfo.environment["DUO_AUTOCONFIRM"] == nil else { return }
        let c = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        controller = c
        model.sparkleCheck = { c.checkForUpdates(nil) }
    }
}
