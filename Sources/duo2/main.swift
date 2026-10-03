import DuoControl
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
case "help":
    print(ControlCommand.help(), terminator: "")
case "doctor":
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
                                 session: env["DUO_SESSION_ID"], cwd: FileManager.default.currentDirectoryPath)
    do {
        let r = try ControlClient.send(request, socket: endpoint.socket)
        if r.ok { print(r.output, terminator: r.output.hasSuffix("\n") ? "" : "\n") } else { fail(r.output) }
    } catch {
        fail("\(error). Run `duo2 doctor`.", code: 69)
    }
}
