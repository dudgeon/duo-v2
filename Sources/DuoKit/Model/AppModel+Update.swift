import AppKit
import DuoControl
import Foundation

/// Duo's own update check (F-69, DL-114): Duo asks GitHub for the latest release and, when it's
/// newer, asks with its own question: Open Releases Page (download the DMG and install it by
/// hand), Install Now (Sparkle, release builds) or Later. Duo › Check for Updates… and
/// `duo2 update` ask from any build; builds without Sparkle also check at launch.
public enum UpdateCheck {
    public static let releasesAPI = URL(string: "https://api.github.com/repos/dudgeon/duo-v2/releases/latest")!

    public struct Release: Sendable, Equatable {
        public var version: String
        public var page: URL
        /// The release's own notes on GitHub (its body, which `release.sh --notes` writes), as Markdown.
        public var notes: String

        public init(version: String, page: URL, notes: String = "") { self.version = version; self.page = page; self.notes = notes }
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
        return Release(version: tag.hasPrefix("v") ? String(tag.dropFirst()) : tag, page: page, notes: json["body"] as? String ?? "")
    }
}

extension UpdateCheck {
    static let repo = "https://github.com/dudgeon/duo-v2"
    /// Every release, for when GitHub didn't answer.
    public static let releasesList = URL(string: "\(repo)/releases")!
    /// One release's page on GitHub, where its DMG is.
    public static func releasePage(_ version: String) -> URL { URL(string: "\(repo)/releases/tag/v\(version)")! }

    /// What an update check found, decided from GitHub's answer, this build's version and whether
    /// this account can replace Duo where it's installed (DL-114). Pure, so DuoChecks feeds it.
    public enum Plan: Equatable, Sendable {
        /// GitHub didn't answer: Check for Updates… hands to Sparkle as before, or says so.
        case unreachable
        /// Nothing newer: Sparkle answers as before, or Duo says so.
        case upToDate(current: String, page: URL)
        /// A newer release: Duo asks (`question`).
        case offer(Offer)
    }

    public struct Offer: Equatable, Sendable {
        public var version: String
        public var current: String
        public var page: URL
        /// Replacing Duo where it's installed needs an administrator password: this account
        /// can't write the app or its folder (`InstallLocation.canReplace`).
        public var needsAdmin: Bool
        /// Sparkle is running, so Install Now can hand to it.
        public var canInstallNow: Bool
        /// The folder Duo is installed in, for the question's wording.
        public var folder: String
        /// The release's notes, as Markdown (DL-132 b).
        public var notes: String

        public init(version: String, current: String, page: URL, needsAdmin: Bool, canInstallNow: Bool, folder: String, notes: String = "") {
            self.version = version; self.current = current; self.page = page
            self.needsAdmin = needsAdmin; self.canInstallNow = canInstallNow; self.folder = folder; self.notes = notes
        }

        /// Install Now is the default only when it can install without a password; otherwise
        /// Open Releases Page is.
        public var installNowIsDefault: Bool { canInstallNow && !needsAdmin }
    }

    /// `userInitiated`: a development build (0.0.1) is offered the latest release even though its
    /// number is lower, so the question can be seen.
    public static func plan(latest: Release?, current: String, installWritable: Bool, sparkle: Bool,
                            folder: String = "", userInitiated: Bool = true) -> Plan {
        guard let r = latest else { return .unreachable }
        let dev = current == "0.0.1"
        guard isNewer(r.version, than: current) || (userInitiated && dev) else { return .upToDate(current: current, page: r.page) }
        return .offer(Offer(version: r.version, current: current, page: r.page, needsAdmin: !installWritable,
                            canInstallNow: sparkle && !dev, folder: folder, notes: r.notes))
    }

    /// The question, as `standins2-handoff/q47-writable` and `q47-admin` draw it (DL-132 b): the
    /// release's notes in a box under "You have …", Later apart at the left, then the other way
    /// to install and the default. Later skips the version until the next launch (F-69).
    @MainActor public static func question(_ o: Offer, openPage: @escaping @MainActor () -> Void,
                                           installNow: @escaping @MainActor () -> Void,
                                           later: @escaping @MainActor () -> Void) -> DuoQuestion {
        let have = o.current == "0.0.1" ? "a development build" : o.current
        var q = DuoQuestion(title: "Duo \(o.version) is available.", paragraphs: ["You have \(have)."], choices: [])
        q.notes = notesLines(o.notes)
        q.leadingCancel = true
        let place = o.folder.isEmpty ? "" : " in `\(o.folder)`"
        if o.needsAdmin {
            q.paragraphs.append("Installing it here needs an administrator password: this account can't replace Duo\(place). Open Releases Page to download the DMG from GitHub and install it by hand.")
        } else if o.canInstallNow {
            q.paragraphs.append("Install Now downloads it and replaces this copy, then Duo relaunches with what you had open. Or open its releases page to download the DMG and install it by hand.")
        } else {
            q.paragraphs.append("Download the DMG from its releases page and drag Duo to Applications to replace this one. What you had open comes back when you relaunch.")
        }
        let open = DuoQuestion.Choice(label: "Open Releases Page", isDefault: !o.installNowIsDefault, action: openPage)
        q.choices = [.init(label: "Later", isCancel: true, action: later)]
        if o.canInstallNow {
            let install = DuoQuestion.Choice(label: "Install Now", isDefault: o.installNowIsDefault, action: installNow)
            q.choices += o.installNowIsDefault ? [open, install] : [install, open]
        } else {
            q.choices.append(open)
        }
        return q
    }

    /// A release's Markdown notes as the question's lines: headings and blank lines dropped,
    /// list items as `•`, emphasis and code marks taken out.
    public static func notesLines(_ md: String) -> [String] {
        md.components(separatedBy: .newlines).compactMap { raw -> String? in
            var l = raw.trimmingCharacters(in: .whitespaces)
            if l.isEmpty || l.hasPrefix("#") || l.hasPrefix("---") { return nil }
            for m in ["- ", "* ", "+ "] where l.hasPrefix(m) { l = "• " + l.dropFirst(2) }
            if let r = l.range(of: #"^\d+[.)] "#, options: .regularExpression) { l = "• " + l[r.upperBound...] }
            l = l.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "__", with: "").replacingOccurrences(of: "`", with: "")
            l = l.replacingOccurrences(of: #"\[([^\]]+)\]\([^)]+\)"#, with: "$1", options: .regularExpression)
            return l
        }
    }

    /// `duo2 update`'s answer: what's newest, its releases page, and whether installing in place
    /// needs an administrator password.
    public static func summary(_ p: Plan, installedAt: String, installWritable: Bool, sparkle: Bool) -> String {
        let place = installWritable
            ? "Installed at \(installedAt): installing in place needs no administrator password"
                + (sparkle ? " (Install Now in Duo › Check for Updates…)." : "; this build doesn't update itself, so install the DMG by hand.")
            : "Installed at \(installedAt): installing in place needs an administrator password, so download the DMG from the releases page and install it by hand."
        switch p {
        case .unreachable:
            return "Couldn't reach GitHub to check for a newer Duo.\nReleases page: \(releasesList.absoluteString)\n\(place)"
        case .upToDate(let current, let page):
            return "Duo \(current) is the latest.\nReleases page: \(page.absoluteString)\n\(place)"
        case .offer(let o):
            let have = o.current == "0.0.1" ? "a development build" : o.current
            return "Duo \(o.version) is available (this is \(have)).\nReleases page: \(o.page.absoluteString)\n\(place)"
        }
    }

    /// The releases page for a plan: the newer release's, the latest's, or every release.
    public static func page(_ p: Plan) -> URL {
        switch p {
        case .unreachable: releasesList
        case .upToDate(_, let page): page
        case .offer(let o): o.page
        }
    }
}

extension AppModel {
    /// The app Duo runs as, and whether this account can replace it there.
    static var installedApp: URL { Bundle.main.bundleURL }
    static var installWritable: Bool { InstallLocation.canReplace(installedApp) }

    /// `userInitiated`: from the menu or `duo2 update`, which always answer. Without Sparkle the
    /// launch check offers a newer release once per version and stays quiet otherwise; with it,
    /// Sparkle checks on its own schedule (and hands to `offerSparkleUpdate` when it can't install
    /// in place, `Updater.swift`). `open`: `duo2 update --open` opens the releases page too.
    public func checkForUpdates(userInitiated: Bool, open: Bool = false, done: (@MainActor (String, [String: Any]) -> Void)? = nil) {
        if sparkleCheck != nil, !userInitiated { return }
        if !userInitiated, UpdateCheck.isDevelopmentBuild || !interactivePrompts { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            let latest = await UpdateCheck.latest()
            let app = Self.installedApp, writable = Self.installWritable, sparkle = self.sparkleCheck != nil
            let plan = UpdateCheck.plan(latest: latest, current: UpdateCheck.current, installWritable: writable, sparkle: sparkle,
                                        folder: app.deletingLastPathComponent().path, userInitiated: userInitiated)
            if let done {
                var text = UpdateCheck.summary(plan, installedAt: app.path, installWritable: writable, sparkle: sparkle)
                let page = UpdateCheck.page(plan)
                if open { NSWorkspace.shared.open(page); text += "\nOpened the releases page." }
                var data: [String: Any] = ["current": UpdateCheck.current, "page": page.absoluteString, "installedAt": app.path,
                                           "needsAdmin": !writable, "reachable": plan != .unreachable]
                if case .offer(let o) = plan { data["latest"] = o.version }
                if case .upToDate = plan { data["latest"] = UpdateCheck.current }
                return done(text, data)
            }
            switch plan {
            case .unreachable, .upToDate:
                // As before: Sparkle's window answers; without it, Duo says so.
                if let sparkle = self.sparkleCheck { return sparkle() }
                if userInitiated {
                    self.info(plan == .unreachable ? "Couldn't reach GitHub to check for a newer Duo." : "Duo \(UpdateCheck.current) is the latest.")
                }
            case .offer(let o):
                if !userInitiated, DuoState.load().skippedUpdate == o.version { return }
                self.offerUpdate(o)
            }
        }
    }

    /// Sparkle's scheduled check found `version`, but this account can't replace Duo where it's
    /// installed (`Updater.swift`): Duo asks instead of Sparkle's password prompt, once per version.
    public func offerSparkleUpdate(version: String) {
        guard DuoState.load().skippedUpdate != version else { return }
        offerUpdate(.init(version: version, current: UpdateCheck.current, page: UpdateCheck.releasePage(version),
                          needsAdmin: !Self.installWritable, canInstallNow: sparkleCheck != nil,
                          folder: Self.installedApp.deletingLastPathComponent().path))
    }

    /// Asks the update question (DL-114). Later remembers the version, so the launch and
    /// scheduled checks don't ask about it again; the menu still does.
    public func offerUpdate(_ o: UpdateCheck.Offer) {
        let q = UpdateCheck.question(o, openPage: { NSWorkspace.shared.open(o.page) },
                                     installNow: { [weak self] in self?.sparkleCheck?() },
                                     later: { DuoState.update { $0.skippedUpdate = o.version } })
        if ProcessInfo.processInfo.environment["DUO_AUTOCONFIRM"] != nil {   // scripted checks: say it, open nothing
            let buttons = q.choices.map { $0.isDefault ? "[\($0.label)]" : $0.label }.joined(separator: ", ")
            FileHandle.standardError.write(Data("question: \(q.title) | \(q.paragraphs.joined(separator: " / ")) | \(buttons)\n".utf8))
            return
        }
        SheetCenter.shared.ask(q)
    }
}
