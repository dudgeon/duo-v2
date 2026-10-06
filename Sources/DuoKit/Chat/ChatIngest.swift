import Foundation

/// How a tool call reads on the dotted thread (handoff `tools`): a bold verb, its object, a detail.
enum ChatToolDescriber {
    /// The input, canonical: a PermissionRequest is matched to its call by this (F-103).
    static func key(_ name: String, _ input: ChatJSON) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: input, options: [.sortedKeys])) ?? Data()
        return name + ":" + String(decoding: data, as: UTF8.self)
    }

    /// A path as the session sees it: relative to its folder when inside it.
    static func show(_ path: String, cwd: String?) -> String {
        guard let cwd, path.hasPrefix(cwd.hasSuffix("/") ? cwd : cwd + "/") else {
            return path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")
        }
        return String(path.dropFirst(cwd.count + (cwd.hasSuffix("/") ? 0 : 1)))
    }

    static func step(id: String, name: String, input: ChatJSON, cwd: String?) -> ChatToolStep {
        let str = { (k: String) in input[k] as? String }
        var s = ChatToolStep(id: id, name: name, verb: name, object: "", inputKey: key(name, input))
        func path(_ p: String?) { if let p { s.object = show(p, cwd: cwd); s.objectKind = .path; s.path = p } }
        switch name {
        case "Read": s.verb = "Read"; path(str("file_path"))
        case "NotebookRead": s.verb = "Read"; path(str("notebook_path"))
        case "Grep": s.verb = "Search"; s.object = "“\(str("pattern") ?? "")”"; s.objectKind = .quoted
        case "Glob": s.verb = "Search"; s.object = str("pattern") ?? ""; s.objectKind = .code
        case "WebFetch":
            s.verb = "Fetch"
            let u = str("url") ?? ""
            s.object = u.replacingOccurrences(of: #"^https?://(www\.)?"#, with: "", options: .regularExpression)
            s.objectKind = .url; s.path = u
        case "WebSearch": s.verb = "Search"; s.object = "“\(str("query") ?? "")”"; s.objectKind = .quoted
        case "Edit", "MultiEdit", "NotebookEdit":
            s.verb = "Edit"; path(str("file_path") ?? str("notebook_path"))
            let edits: [(String, String)] = name == "MultiEdit"
                ? (input["edits"] as? [ChatJSON] ?? []).map { ($0["old_string"] as? String ?? "", $0["new_string"] as? String ?? "") }
                : [(str("old_string") ?? "", str("new_string") ?? str("new_source") ?? "")]
            s.diff = edits.flatMap { o, n in
                o.components(separatedBy: "\n").map { ChatDiffLine(kind: .del, number: nil, text: $0) }
                    + n.components(separatedBy: "\n").map { ChatDiffLine(kind: .add, number: nil, text: $0) }
            }
            count(&s)
        case "Write":
            s.verb = "Write"; path(str("file_path"))
            let lines = (str("content") ?? "").components(separatedBy: "\n")
            s.diff = lines.enumerated().map { ChatDiffLine(kind: .add, number: $0 + 1, text: $1) }
            count(&s)
        case "Bash":
            s.verb = "Bash"; s.object = str("command") ?? ""; s.objectKind = .code
            s.output = ["$ " + (str("command") ?? "")]
            if input["run_in_background"] as? Bool == true { s.detail = "in the background" }
        case "Task", "Agent":
            s.verb = "Agent"; s.object = str("description") ?? str("subagent_type") ?? "agent"
            let bg = input["run_in_background"] as? Bool ?? false
            s.detail = bg ? "in the background" : nil
            s.agent = ChatAgentResult(message: "", seconds: nil, toolUses: nil, background: bg, finished: false)
        case "TodoWrite": s.verb = "Update"; s.object = "the to-do list"
        default:
            // MCP and anything new: the tool's short name, and its first string input.
            s.verb = name.split(separator: "__").last.map(String.init) ?? name
            s.object = input.sorted { $0.key < $1.key }.compactMap { $0.value as? String }.first.map { $0.count > 80 ? String($0.prefix(79)) + "…" : $0 } ?? ""
        }
        return s
    }

    /// A folded step's first lines, when opened.
    static func preview(_ text: String?) -> [String]? {
        guard let text, !text.isEmpty else { return nil }
        let lines = text.components(separatedBy: "\n").map { $0.replacingOccurrences(of: #"^\s*\d+\t"#, with: "", options: .regularExpression) }
        return Array(lines.prefix(8)) + (lines.count > 8 ? ["…"] : [])
    }

    static func count(_ s: inout ChatToolStep) {
        guard let d = s.diff else { return }
        s.adds = d.filter { $0.kind == .add }.count
        s.dels = d.filter { $0.kind == .del }.count
    }

    /// Fills a step in from its result.
    static func finish(_ s: inout ChatToolStep, result: Any?, content: String?, isError: Bool, denial: String?, interrupt: Bool, cwd: String?) {
        let r = result as? ChatJSON
        if let denial {
            s.status = .declined
            if denial != "user-rejected" { s.error = content }
            return
        }
        if interrupt { s.status = .interrupted; return }
        if isError {
            let text = content ?? (result as? String) ?? ""
            let exit = text.chatMatch(#"Exit code (\d+)"#).flatMap { $0[1] }.flatMap { Int($0) }
            s.status = .failed(exit: exit)
            s.error = text.replacingOccurrences(of: #"^(Error: )?Exit code \d+\n?"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if s.name == "Bash" { s.output = nil }
            return
        }
        s.status = .done
        switch s.name {
        case "Read":
            if let f = r?["file"] as? ChatJSON, let n = (f["totalLines"] ?? f["numLines"]) as? Int { s.detail = "\(n) lines" }
            s.preview = preview((r?["file"] as? ChatJSON)?["content"] as? String ?? content)
        case "Grep":
            let files = r?["numFiles"] as? Int ?? 0
            if let lines = r?["numLines"] as? Int, r?["mode"] as? String == "content" { s.detail = "\(lines) match\(lines == 1 ? "" : "es") in \(files) file\(files == 1 ? "" : "s")" }
            else { s.detail = "\(files) file\(files == 1 ? "" : "s")" }
            s.preview = preview(r?["content"] as? String ?? (r?["filenames"] as? [String])?.map { show($0, cwd: cwd) }.joined(separator: "\n") ?? content)
        case "Glob":
            let n = r?["numFiles"] as? Int ?? (r?["filenames"] as? [Any])?.count ?? 0
            s.detail = "\(n) file\(n == 1 ? "" : "s")"
        case "WebFetch":
            if let b = r?["bytes"] as? Int { s.detail = b >= 1024 ? "\(Int((Double(b) / 1024).rounded())) KB" : "\(b) bytes" }
            s.preview = preview(r?["result"] as? String ?? content)
        case "Edit", "MultiEdit", "Write":
            // Claude's own patch has the line numbers (structuredPatch hunks).
            if let hunks = r?["structuredPatch"] as? [ChatJSON], !hunks.isEmpty {
                var lines: [ChatDiffLine] = []
                for h in hunks {
                    var old = h["oldStart"] as? Int ?? 1, new = h["newStart"] as? Int ?? 1
                    for l in h["lines"] as? [String] ?? [] {
                        switch l.first {
                        case "-": lines.append(ChatDiffLine(kind: .del, number: old, text: String(l.dropFirst()))); old += 1
                        case "+": lines.append(ChatDiffLine(kind: .add, number: new, text: String(l.dropFirst()))); new += 1
                        default: lines.append(ChatDiffLine(kind: .context, number: new, text: String(l.dropFirst()))); old += 1; new += 1
                        }
                    }
                }
                s.diff = lines
                count(&s)
            }
        case "Bash":
            let out = [(r?["stdout"] as? String) ?? content ?? "", (r?["stderr"] as? String) ?? ""].filter { !$0.isEmpty }.joined(separator: "\n")
            // The hook's result and the transcript's are the same output: set, never appended.
            s.output = [s.output?.first ?? "$ " + s.object] + out.components(separatedBy: "\n").filter { !$0.isEmpty }
            if r?["interrupted"] as? Bool == true { s.status = .interrupted }
            if let bg = r?["backgroundTaskId"] as? String, !bg.isEmpty { s.detail = "in the background" }
        case "Task", "Agent":
            let text = (r?["content"] as? [ChatJSON])?.compactMap { $0["text"] as? String }.joined(separator: "\n") ?? content ?? ""
            let async = r?["isAsync"] as? Bool ?? s.agent?.background ?? false
            let finished = !async || s.agent?.finished == true || r?["status"] as? String == "completed"
            s.agent = ChatAgentResult(message: async ? (s.agent?.message ?? "") : text,
                                      seconds: (r?["totalDurationMs"] as? Double).map { Int($0 / 1000) } ?? (r?["totalDurationMs"] as? Int).map { $0 / 1000 } ?? s.agent?.seconds,
                                      toolUses: r?["totalToolUseCount"] as? Int ?? s.agent?.toolUses, background: async, finished: finished)
            if async { s.detail = "in the background"; s.status = finished ? .done : .running }
        default: break
        }
    }
}

/// Parses hook payloads and transcript lines into the log.
@MainActor
public enum ChatIngest {
    static let iso: ISO8601DateFormatter = { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f }()

    /// A hook payload (`e` in `{"at": …, "e": …}`, HookEvents' format).
    public static func hook(_ e: ChatJSON, at: Double?, into log: ChatLog, chat: ChatSession? = nil) {
        guard let name = e["hook_event_name"] as? String else { return }
        let time = at.map { Date(timeIntervalSince1970: $0) }
        log.hooksSeen = true
        if let cwd = e["cwd"] as? String, log.cwd == nil { log.cwd = cwd }
        let tool = e["tool_name"] as? String
        let input = e["tool_input"] as? ChatJSON ?? [:]
        switch name {
        case "UserPromptSubmit":
            let source = e["source"] as? String
            log.prompt(e["prompt"] as? String ?? "", time: time, fromHook: true, injected: source != nil && source != "user")
        case "MessageDisplay":
            log.display(message: "\(e["message_id"] ?? "m")", delta: e["delta"] as? String ?? "", final: e["final"] as? Bool ?? false, time: time)
        case "PreToolUse":
            if let id = e["tool_use_id"] as? String, let tool { log.toolUse(id: id, name: tool, input: input, time: time) }
        case "PostToolUse":
            if let id = e["tool_use_id"] as? String {
                log.toolResult(id: id, name: tool, input: input, result: e["tool_response"], content: e["tool_response"] as? String, isError: false, time: time)
            }
            log.permissionResolved()
        case "PostToolUseFailure":
            if let id = e["tool_use_id"] as? String {
                let interrupt = e["is_interrupt"] as? Bool ?? false
                log.toolResult(id: id, name: tool, input: input, result: nil, content: e["error"] as? String, isError: !interrupt, interrupt: interrupt, time: time)
            }
            log.permissionResolved()
        case "PermissionRequest":
            if let tool { log.permissionPending(name: tool, input: input) }
            if tool == "AskUserQuestion" { log.toolUse(id: "ask-" + ChatToolDescriber.key("q", input), name: "AskUserQuestion", input: input, time: time) }
            chat?.pendingRequest = ChatRequest(tool: tool ?? "", input: input, at: time ?? Date())
        case "SubagentStart":
            if let id = e["agent_id"] as? String { log.agentStarted(id: id, agentType: e["agent_type"] as? String) }
        case "SubagentStop":
            log.agentFinished(agentType: e["agent_type"] as? String, message: e["last_assistant_message"] as? String, time: time, agentId: e["agent_id"] as? String)
        case "PostCompact":
            log.compacted(time: time)
        case "Stop":
            log.turnEnded(lastMessage: e["last_assistant_message"] as? String, time: time)
            chat?.pendingRequest = nil
        case "StopFailure":
            log.endStreaming(interrupted: false)
        default: break
        }
    }

    /// One transcript line.
    public static func record(_ r: ChatJSON, into log: ChatLog, chat: ChatSession? = nil) {
        guard let type = r["type"] as? String else { return }
        if r["isSidechain"] as? Bool == true { return }
        let time = (r["timestamp"] as? String).flatMap { iso.date(from: $0) }
        if let cwd = r["cwd"] as? String, log.cwd == nil { log.cwd = cwd }
        let message = r["message"] as? ChatJSON
        switch type {
        case "user":
            if r["isMeta"] as? Bool == true || r["isCompactSummary"] as? Bool == true { return }
            if let text = message?["content"] as? String {
                // Slash commands and their output are the TUI's own lines, not your messages.
                if text.hasPrefix("<command-") || text.hasPrefix("<local-command") { return }
                let origin = (r["origin"] as? ChatJSON)?["kind"] as? String
                log.prompt(text, time: time, fromHook: false, injected: origin != nil && origin != "human", planMode: r["permissionMode"] as? String == "plan")
                return
            }
            for b in message?["content"] as? [ChatJSON] ?? [] {
                switch b["type"] as? String {
                case "text":
                    // Claude Code's record of an interrupt (Esc): the reply ends, it isn't your message.
                    if let t = b["text"] as? String, t.hasPrefix("[Request interrupted by user") {
                        log.endStreaming(interrupted: true)
                    } else if let t = b["text"] as? String, !t.hasPrefix("<command-"), !t.hasPrefix("<local-command") {
                        log.prompt(t, time: time, fromHook: false)
                    }
                case "tool_result":
                    guard let id = b["tool_use_id"] as? String else { continue }
                    let content: String? = (b["content"] as? String)
                        ?? (b["content"] as? [ChatJSON])?.compactMap { $0["text"] as? String }.joined(separator: "\n")
                    let denial = r["toolDenialKind"] as? String
                    let result = r["toolUseResult"]
                    // A plan or question refused fires no hook: only this says so (F-103, F-106).
                    if let q = (result as? ChatJSON)?["answers"] as? [String: String] {
                        log.answer(q.map { "\($0.key) → \($0.value)" }.sorted().joined(separator: "\n"), time: time)
                    } else if denial != nil, log.step(id) == nil {
                        if let fb = r["userFeedback"] as? String, !fb.isEmpty { log.answer("You asked Claude to change the plan: \(fb)", time: time) }
                        else { log.answer(chat?.lastDeclined ?? "You declined Claude’s questions", time: time) }
                    }
                    log.toolResult(id: id, name: nil, input: nil, result: result, content: content, isError: b["is_error"] as? Bool ?? false,
                                   denial: denial, time: time)
                default: break
                }
            }
        case "assistant":
            if let m = message?["model"] as? String, let family = ["opus", "sonnet", "haiku", "fable"].first(where: { m.contains($0) }) {
                if log.model != family.capitalized { log.model = family.capitalized }
            }
            for b in message?["content"] as? [ChatJSON] ?? [] {
                switch b["type"] as? String {
                case "text":
                    if let t = b["text"] as? String { log.textBlock(t, time: time) }
                case "thinking", "redacted_thinking":
                    log.thinking(b["thinking"] as? String ?? "", durationMs: (r["thinkingDurationMs"] as? Double) ?? (r["thinkingDurationMs"] as? Int).map(Double.init), time: time)
                case "tool_use":
                    if let id = b["id"] as? String, let name = b["name"] as? String {
                        log.toolUse(id: id, name: name, input: b["input"] as? ChatJSON ?? [:], time: time)
                        log.transcriptTools.insert(id)
                    }
                default: break
                }
            }
        case "system":
            if r["subtype"] as? String == "compact_boundary" { log.compacted(time: time) }
        default: break
        }
    }

    /// JSON lines, skipping any that don't parse (two hooks writing at once can merge lines, F-105).
    public static func lines(_ data: Data) -> [ChatJSON] {
        data.split(separator: UInt8(ascii: "\n")).compactMap { try? JSONSerialization.jsonObject(with: Data($0)) as? ChatJSON }
    }
}

/// The permission, plan or question Claude is waiting on, from PermissionRequest (F-103): what the
/// card shows besides the screen's own labels.
public struct ChatRequest: @unchecked Sendable {
    public var tool: String
    public var input: ChatJSON
    public var at: Date
}
