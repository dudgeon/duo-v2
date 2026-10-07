import Foundation
import DuoControl

/// Runs `git` and `gh` for the GitHub features (DL-149, DL-157) so they can never block Duo:
/// no terminal prompts, no update notices, a time limit on every call, and both tools found by
/// explicit path (a Finder-launched app doesn't inherit the shell's PATH: legacy BUG-136).
/// Never stores or reads a token: git uses the user's credential helper, gh its own sign-in.
public enum GitTool {
    public struct Result: Sendable {
        public var status: Int32
        public var out: String
        public var err: String
        public var timedOut = false
        public var notFound = false
        public var ok: Bool { status == 0 && !timedOut && !notFound }
        /// stdout and stderr together, for classifying failures (git writes progress and errors to stderr).
        public var all: String { out + (out.isEmpty || err.isEmpty ? "" : "\n") + err }
    }

    /// Directories searched for `gh` (and `brew`), in order. `DUO_GH_PATH` points at a stub in checks, or is `none`.
    static let searchDirs = ["/opt/homebrew/bin", "/usr/local/bin", "\(NSHomeDirectory())/.local/bin", "/usr/bin"]

    public static var ghPath: String? {
        if let p = Env.value("DUO_GH_PATH") { return p == "none" ? nil : p }   // "none": no gh (checks)
        return searchDirs.map { "\($0)/gh" }.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    public static var brewPath: String? {
        ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"].first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// `/usr/bin/git` is a stub that raises macOS's "install developer tools" dialog when the Command
    /// Line Tools are missing (C-53). Check for them first so that dialog never appears.
    public static var gitPath: String? {
        if let p = Env.value("DUO_GIT_PATH") { return p == "none" ? nil : p }
        for p in ["/opt/homebrew/bin/git", "/usr/local/bin/git"] where FileManager.default.isExecutableFile(atPath: p) { return p }
        return toolsInstalled ? "/usr/bin/git" : nil
    }

    nonisolated(unsafe) private static var toolsChecked: Bool?
    private static let lock = NSLock()
    static var toolsInstalled: Bool {
        lock.lock(); defer { lock.unlock() }
        if let t = toolsChecked { return t }
        let dir = (try? String(contentsOfFile: "/var/db/xcode_select_link", encoding: .utf8)) ?? ""
        let t = FileManager.default.fileExists(atPath: "/Library/Developer/CommandLineTools/usr/bin/git")
            || FileManager.default.fileExists(atPath: "/Applications/Xcode.app/Contents/Developer/usr/bin/git")
            || (!dir.isEmpty && FileManager.default.fileExists(atPath: dir.trimmingCharacters(in: .whitespacesAndNewlines) + "/usr/bin/git"))
        toolsChecked = t
        return t
    }

    /// The environment every call gets. `GIT_OPTIONAL_LOCKS=0` keeps `git status` from taking the
    /// index lock while Claude is committing in the same repo.
    static func environment(extra: [String: String] = [:]) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["GIT_TERMINAL_PROMPT"] = "0"
        env["GIT_ASKPASS"] = "/usr/bin/false"    // never a password dialog
        env["SSH_ASKPASS"] = "/usr/bin/false"
        env["GIT_SSH_COMMAND"] = env["GIT_SSH_COMMAND"] ?? "ssh -oBatchMode=yes"
        env["GIT_OPTIONAL_LOCKS"] = "0"
        env["GH_PROMPT_DISABLED"] = "1"
        env["GH_NO_UPDATE_NOTIFIER"] = "1"
        env["GH_SPINNER_DISABLED"] = "1"
        env["NO_COLOR"] = "1"
        env["LC_ALL"] = "C"
        env["PATH"] = (searchDirs + [env["PATH"] ?? ""]).joined(separator: ":")
        for (k, v) in extra { env[k] = v }
        return env
    }

    public static func git(_ args: [String], in dir: URL?, timeout: TimeInterval = 15, env: [String: String] = [:]) -> Result {
        guard let path = gitPath else { return Result(status: 127, out: "", err: "git: the Command Line Tools aren't installed", notFound: true) }
        return run(path, args, in: dir, timeout: timeout, env: env)
    }

    public static func gh(_ args: [String], in dir: URL?, timeout: TimeInterval = 20, env: [String: String] = [:]) -> Result {
        guard let path = ghPath else { return Result(status: 127, out: "", err: "gh: command not found", notFound: true) }
        return run(path, args, in: dir, timeout: timeout, env: env)
    }

    /// Runs a tool with no shell, reading both pipes as it goes, and stops it after `timeout`.
    public static func run(_ exe: String, _ args: [String], in dir: URL?, timeout: TimeInterval, env: [String: String] = [:]) -> Result {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        if let dir { p.currentDirectoryURL = dir }
        p.environment = environment(extra: env)
        let outPipe = Pipe(), errPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = errPipe
        p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch {
            return Result(status: 127, out: "", err: "\(exe): \(error.localizedDescription)", notFound: true)
        }
        let group = DispatchGroup()
        nonisolated(unsafe) var out = Data(), err = Data()
        group.enter(); DispatchQueue.global().async { out = outPipe.fileHandleForReading.readDataToEndOfFile(); group.leave() }
        group.enter(); DispatchQueue.global().async { err = errPipe.fileHandleForReading.readDataToEndOfFile(); group.leave() }
        let done = DispatchSemaphore(value: 0)
        p.terminationHandler = { _ in done.signal() }
        var timedOut = false
        if done.wait(timeout: .now() + timeout) == .timedOut {
            timedOut = true
            p.terminate()
            if done.wait(timeout: .now() + 2) == .timedOut { kill(p.processIdentifier, SIGKILL); done.wait() }
        }
        group.wait()
        return Result(status: p.terminationStatus, out: String(decoding: out, as: UTF8.self),
                      err: String(decoding: err, as: UTF8.self), timedOut: timedOut)
    }

    /// Values a user typed go in as arguments, never as flags (legacy's hardening).
    public static func safeValue(_ s: String) -> Bool { !s.isEmpty && !s.hasPrefix("-") && !s.contains("\0") }
}
