import AppKit
import Foundation

/// An update notice until Sparkle (v1.1): Duo asks GitHub for the latest release and offers the
/// newer DMG once per version. Release builds check at launch; any build checks from
/// Duo › Check for Updates… or `duo2 update`.
public enum UpdateCheck {
    public static let releasesAPI = URL(string: "https://api.github.com/repos/dudgeon/duo-v2/releases/latest")!

    public struct Release: Sendable, Equatable {
        public var version: String
        public var page: URL
    }

    /// This build's version; development builds say 0.0.1 (bundle.sh).
    public static var current: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.1" }
    public static var isDevelopmentBuild: Bool { current == "0.0.1" }

    /// `0.1.10` is newer than `0.1.9`; a pre-release suffix sorts below its release.
    public static func isNewer(_ a: String, than b: String) -> Bool {
        func parts(_ v: String) -> (nums: [Int], pre: Bool) {
            let t = v.hasPrefix("v") ? String(v.dropFirst()) : v
            let core = t.split(separator: "-", maxSplits: 1)
            return (core[0].split(separator: ".").map { Int($0) ?? 0 }, core.count > 1)
        }
        let (x, xp) = parts(a), (y, yp) = parts(b)
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l != r { return l > r }
        }
        return yp && !xp
    }

    public static func latest() async -> Release? {
        var req = URLRequest(url: releasesAPI, timeoutInterval: 10)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        guard let (data, resp) = try? await URLSession.shared.data(for: req), (resp as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String, let page = (json["html_url"] as? String).flatMap(URL.init(string:)) else { return nil }
        return Release(version: tag.hasPrefix("v") ? String(tag.dropFirst()) : tag, page: page)
    }
}

extension AppModel {
    /// `userInitiated`: from the menu or `duo2 update`, which always answer; the launch check offers a
    /// newer release once per version and stays quiet otherwise.
    public func checkForUpdates(userInitiated: Bool, done: (@MainActor (String) -> Void)? = nil) {
        // Sparkle running (release builds): it checks on its own schedule, and the menu item is its.
        if let sparkle = sparkleCheck {
            if userInitiated && done == nil { sparkle() }
            if done == nil { return }
        }
        if !userInitiated, UpdateCheck.isDevelopmentBuild || !interactivePrompts { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard let r = await UpdateCheck.latest() else {
                let m = "Couldn't reach GitHub to check for a newer Duo."
                if userInitiated { done?(m) ?? self.info(m) }
                return
            }
            let current = UpdateCheck.current
            guard UpdateCheck.isNewer(r.version, than: current) || (userInitiated && UpdateCheck.isDevelopmentBuild) else {
                let m = "Duo \(current) is the latest."
                if userInitiated { done?(m) ?? self.info(m) }
                return
            }
            if !userInitiated, DuoState.load().skippedUpdate == r.version { return }
            if let done { return done("Duo \(r.version) is available (this is \(UpdateCheck.isDevelopmentBuild ? "a development build" : current)): \(r.page.absoluteString)") }
            self.confirm(title: "Duo \(r.version) is available",
                         detail: "You have \(UpdateCheck.isDevelopmentBuild ? "a development build" : current). Download the DMG from its GitHub release and drag Duo to Applications to replace this one. What you had open comes back when you relaunch.",
                         button: "Download") { ok in
                if ok { NSWorkspace.shared.open(r.page) } else { DuoState.update { $0.skippedUpdate = r.version } }
            }
        }
    }
}
