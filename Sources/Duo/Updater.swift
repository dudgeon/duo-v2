import AppKit
import DuoControl
import DuoKit
import Sparkle

/// In-app updates with Sparkle (Phase L): release builds check the feed published with each GitHub
/// release, download the signed DMG, and replace Duo after asking. Development builds (0.0.1) and
/// scripted runs never start it.
///
/// Duo › Check for Updates… asks GitHub first and puts Duo's own question (Open Releases Page,
/// Install Now, Later; DL-114) before Sparkle's window; Install Now hands to Sparkle. Up to date
/// or GitHub unreachable, Sparkle answers as before. Where Sparkle isn't running, the question
/// offers the releases page only.
@MainActor
enum SparkleUpdater {
    static var controller: SPUStandardUpdaterController?
    /// Sparkle holds its delegate weakly.
    static var delegate: Delegate?

    static func start(model: AppModel) {
        guard !UpdateCheck.isDevelopmentBuild, Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil,
              model.interactivePrompts, !Env.autoconfirm else { return }
        let d = Delegate(model: model)
        delegate = d
        let c = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: d, userDriverDelegate: nil)
        controller = c
        model.sparkleCheck = { c.checkForUpdates(nil) }
    }

    /// Sparkle's scheduled check, on an install this account can't replace: Sparkle would show its
    /// window and then ask for an administrator password. Duo stops it there (Sparkle shows nothing
    /// for an update its delegate declines) and asks its own question, where Open Releases Page is
    /// the default (DL-114, F-93). Checks from the menu, and installs this account can replace, go
    /// on as Sparkle's.
    final class Delegate: NSObject, SPUUpdaterDelegate {
        weak var model: AppModel?

        init(model: AppModel) { self.model = model }

        func updater(_ updater: SPUUpdater, shouldProceedWithUpdate updateItem: SUAppcastItem, updateCheck: SPUUpdateCheck) throws {
            guard updateCheck == .updatesInBackground, !InstallLocation.canReplace(Bundle.main.bundleURL), let model else { return }
            model.offerSparkleUpdate(version: updateItem.displayVersionString)
            throw NSError(domain: "DuoUpdate", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Installing in place needs an administrator password; Duo asked with its own question instead (DL-114).",
            ])
        }
    }
}
