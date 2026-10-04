import Foundation

/// SRCH L15, FR-7.8: files that hold secrets are never read, and recognisable secrets are
/// redacted before anything is stored (snippets, keyword index, embedded text). Best effort
/// (FR-7.8.5); the patterns follow common secret scanners (Q-6 default).
public enum Secrets {
    /// File names never indexed. Users extend this later (FR-7.8.1).
    public static func isDenied(_ path: String) -> Bool {
        let name = (path as NSString).lastPathComponent.lowercased()
        if name == ".env" || name.hasPrefix(".env.") || name.hasSuffix(".env") { return true }
        if ["id_rsa", "id_dsa", "id_ecdsa", "id_ed25519", ".netrc", ".npmrc", ".pypirc", "credentials", ".git-credentials",
            "secrets.json", "secrets.yaml", "secrets.yml", "service-account.json"].contains(name) { return true }
        let ext = (name as NSString).pathExtension
        if ["pem", "key", "p12", "pfx", "keychain", "keystore", "jks", "kdbx", "ovpn", "asc", "gpg"].contains(ext) { return true }
        if path.contains("/.ssh/") || path.contains("/.aws/") || path.contains("/.gnupg/") { return true }
        return false
    }

    static let patterns: [NSRegularExpression] = [
        #"-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z ]*PRIVATE KEY-----"#,
        #"\bAKIA[0-9A-Z]{16}\b"#,                                   // AWS access key id
        #"(?i)aws(.{0,20})?(secret|access)?.{0,20}['\"][0-9a-zA-Z/+]{40}['\"]"#,
        #"\bgh[pousr]_[A-Za-z0-9]{36,}\b"#, #"\bgithub_pat_[A-Za-z0-9_]{60,}\b"#,
        #"\bsk-(ant-|proj-)?[A-Za-z0-9_\-]{20,}\b"#,                // Anthropic, OpenAI
        #"\bxox[abposr]-[A-Za-z0-9-]{10,}\b"#,                       // Slack
        #"\bAIza[0-9A-Za-z_\-]{35}\b"#,                              // Google API key
        #"\b(sk|rk)_(live|test)_[0-9a-zA-Z]{20,}\b"#,               // Stripe
        #"\beyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\b"#,  // JWT
        #"(?i)\b(bearer)\s+[A-Za-z0-9\-._~+/]{20,}=*"#,
        #"(?i)\b(api[_-]?key|secret|token|password|passwd|pwd)\b\s*[:=]\s*['\"]?[^\s'\"]{8,}['\"]?"#,
        #"(?i)\b[a-z][a-z0-9+.-]*://[^\s:/@]+:[^\s/@]+@"#,         // credentials in URLs
    ].map { try! NSRegularExpression(pattern: $0) }

    public static func redact(_ text: String) -> String {
        var s = text
        for re in patterns {
            s = re.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "[REDACTED]")
        }
        return s
    }
}
