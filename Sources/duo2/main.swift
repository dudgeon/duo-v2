import DuoControl
import DuoSearch
import Foundation

// `duo2` (DL-37): the command line for the Duo app. Coexists with legacy `duo` (DL-16).

let args = Array(CommandLine.arguments.dropFirst())
let name = args.first ?? "help"
let env = ProcessInfo.processInfo.environment

func fail(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data("duo2: \(message)\n".utf8))
    exit(code)
}

guard let command = ControlCommand.all.first(where: { $0.name == name || "--\($0.name)" == name }) else {
    fail("unknown command '\(name)'. Run `duo2 help`.", code: 64)
}

switch command.name {
case "search", "search-status":
    exit(runSearch(command.name, Array(args.dropFirst())))
case "help":
    print(ControlCommand.help(), terminator: "")
case "legacy":
    let sub = args.dropFirst().first
    let backups = ControlEndpoint.file.deletingLastPathComponent().appending(path: "backups")
    switch sub {
    case "disable":
        guard args.contains("--yes") else { fail("this changes ~/.claude (after a backup). Run `duo2 legacy disable --yes` to go ahead.", code: 64) }
        guard !LegacyDuo.detect().isEmpty else { print("Nothing of legacy Duo's to disable."); exit(0) }
        do {
            let b = try LegacyDuo.disable(backupRoot: backups)
            print("Disabled legacy Duo's instructions. Backup: \(b.path)\nUndo with: duo2 legacy restore \"\(b.path)\"")
        } catch { fail("\(error)") }
    case "restore":
        guard let path = args.dropFirst(2).first else { fail("usage: duo2 legacy restore <backup folder>", code: 64) }
        do { try LegacyDuo.restore(from: URL(fileURLWithPath: path)); print("Restored from \(path).") } catch { fail("\(error)") }
    default:
        let found = LegacyDuo.detect()
        if found.isEmpty { print("No legacy Duo instructions in \(LegacyDuo.claudeDir.path).") }
        else {
            print("Legacy Duo installed these into \(LegacyDuo.claudeDir.path); they load into every Claude session, Duo v2's too:")
            for f in found { print("  - \(f.what): \(f.path)") }
            print("To turn them off (everything is backed up first, and can be restored): duo2 legacy disable --yes")
        }
    }
case "doctor":
    let archive = ControlEndpoint.file.deletingLastPathComponent().appending(path: "archive")
    if let walker = FileManager.default.enumerator(at: archive, includingPropertiesForKeys: [.fileSizeKey]) {
        var bytes = 0, sessions = 0
        for case let u as URL in walker {
            bytes += (try? u.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            if u.pathExtension == "jsonl", u.deletingLastPathComponent().lastPathComponent == "archive" { sessions += 1 }
        }
        print("Session archive: \(sessions) sessions, \(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)) (\(archive.path); no limit, DL-56).")
    }
    let legacy = LegacyDuo.detect()
    if !legacy.isEmpty { print("Legacy Duo's instructions are still installed (\(legacy.map(\.what).joined(separator: ", "))). See `duo2 legacy`.") }
    guard let (endpoint, source) = ControlEndpoint.discover() else {
        print("Duo isn't running, or this terminal can't see it: no \(ControlEndpoint.socketVariable) in the environment and no live \(ControlEndpoint.file.path).")
        exit(1)
    }
    print("Found Duo through \(source): \(endpoint.socket)")
    do {
        let r = try ControlClient.send(ControlRequest(token: endpoint.token, command: "ping", args: []), socket: endpoint.socket)
        print(r.ok ? "Reachable: \(r.output)" : "Reached Duo, but it refused: \(r.output)")
        exit(r.ok ? 0 : 1)
    } catch {
        print("Not reachable: \(error).")
        print("Inside Claude's sandbox, add this socket to sandbox.network.allowUnixSockets in your settings. Duo's own terminals do this for you.")
        exit(1)
    }
default:
    guard let (endpoint, _) = ControlEndpoint.discover() else { fail("Duo isn't running. Run `duo2 doctor`.", code: 69) }
    let request = ControlRequest(token: endpoint.token, command: command.name, args: Array(args.dropFirst()),
                                 // Claude's own id is current after /clear; Duo's may be stale (F-29).
                                 session: env["CLAUDE_CODE_SESSION_ID"] ?? env["DUO_SESSION_ID"],
                                 cwd: FileManager.default.currentDirectoryPath)
    do {
        let r = try ControlClient.send(request, socket: endpoint.socket)
        if r.ok { print(r.output, terminator: r.output.hasSuffix("\n") ? "" : "\n") } else { fail(r.output) }
    } catch {
        fail("\(error). Run `duo2 doctor`.", code: 69)
    }
}
