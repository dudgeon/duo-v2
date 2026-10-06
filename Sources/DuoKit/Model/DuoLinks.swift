import Foundation

/// The Help menu's pages on GitHub (DL-108, m4). Opening one sends nothing: a new issue opens
/// GitHub's form, filled in, for the user to edit and submit.
public enum DuoLinks {
    static let repo = "https://github.com/dudgeon/duo-v2"

    public static let duo2Reference = URL(string: "\(repo)/blob/main/docs/cli/duo2.md")!

    /// This version's release notes; a development build has none, so the list of releases.
    public static var releaseNotes: URL {
        UpdateCheck.isDevelopmentBuild ? URL(string: "\(repo)/releases")! : URL(string: "\(repo)/releases/tag/v\(UpdateCheck.current)")!
    }

    public static var newIssue: URL {
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        let body = """
        Duo \(UpdateCheck.current) (build \(build))
        \(ProcessInfo.processInfo.operatingSystemVersionString)

        What happened:


        What I expected:

        """
        var c = URLComponents(string: "\(repo)/issues/new")!
        c.queryItems = [URLQueryItem(name: "body", value: body)]
        return c.url!
    }
}
