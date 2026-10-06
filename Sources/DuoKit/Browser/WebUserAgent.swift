import Foundation

/// What Duo's web views add to WebKit's user agent (F-117). A bare WKWebView sends
/// "… AppleWebKit/605.1.15 (KHTML, like Gecko)" with no "Version/x Safari/605.1.15", and Google
/// (Docs, Sheets, sign-in) then calls the browser unsupported. Duo runs the system's WebKit, the
/// same engine as the installed Safari, so it says the same as that Safari.
public enum WebUserAgent {
    /// The token every DuoWebView sets as `applicationNameForUserAgent`.
    public static let applicationName = token(safariVersion: installedSafariVersion(), os: ProcessInfo.processInfo.operatingSystemVersion)

    /// "Version/<Safari's version> Safari/605.1.15". Without Safari's version, macOS 26 and later
    /// number Safari after the system (Safari 26 on macOS 26); before that, nothing is claimed.
    public static func token(safariVersion: String?, os: OperatingSystemVersion) -> String {
        let version = safariVersion.flatMap(majorMinor) ?? (os.majorVersion >= 26 ? "\(os.majorVersion).\(os.minorVersion)" : nil)
        guard let version else { return "" }
        return "Version/\(version) Safari/605.1.15"  // 605.1.15 is frozen in every Safari's string
    }

    /// "27.0.1" → "27.0" (Safari's own string carries major.minor only); nil for anything else.
    static func majorMinor(_ v: String) -> String? {
        let parts = v.split(separator: ".").prefix(2)
        guard let first = parts.first, Int(first) != nil, parts.allSatisfy({ Int($0) != nil }) else { return nil }
        return parts.count == 2 ? parts.joined(separator: ".") : "\(first).0"
    }

    static func installedSafariVersion() -> String? {
        let plist = URL(fileURLWithPath: "/Applications/Safari.app/Contents/Info.plist")
        return (NSDictionary(contentsOf: plist)?["CFBundleShortVersionString"] as? String)
    }
}
