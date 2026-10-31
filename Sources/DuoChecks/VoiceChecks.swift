import DuoKit
import Foundation

/// Voice input (DL-260, DL-261): the state machine, the phrase splitter, the paste text and the
/// terminal mic's input-box finder, on recorded Claude Code screens. No audio.
@MainActor func voiceChecks() throws {
    print("voice input")
    typealias M = VoiceMachine
    // State machine
    var s = VoiceState.idle
    for (e, want) in [(VoiceEvent.start, VoiceState.asking), (.sheetAnswered(continueAsking: true), .preparing(progress: nil)),
                      (.modelProgress(0.4), .preparing(progress: 0.4)), (.modelReady, .listening), (.finish, .finishing), (.finished, .idle)] {
        s = M.next(s, e); check(s == want, "voice state: \(e) gives \(want)")
    }
    check(M.next(.asking, .sheetAnswered(continueAsking: false)) == .idle, "voice: Not Now returns to idle")
    check(M.next(.listening, .discard) == .idle, "voice: Esc discards")
    check(M.next(.listening, .failed("Stopped: nothing heard for 15 s.")) == .failed("Stopped: nothing heard for 15 s."), "voice: a listening failure keeps its line")
    check(M.next(.failed("x"), .dismiss) == .idle, "voice: a failure line is dismissed")
    check(M.next(.idle, .denied) == .denied && M.next(.denied, .start) == .asking, "voice: denied, then a press asks again")
    check(M.next(.idle, .restricted) == .restricted, "voice: restricted")
    // An isolated Duo never asks for the mic, unless launched with DUO_VOICE_LIVE=1 for a hands-on test
    check(VoiceInput.isolatedWithout([:], isolated: true), "voice: an isolated Duo doesn't ask")
    check(!VoiceInput.isolatedWithout(["DUO_VOICE_LIVE": "1"], isolated: true), "voice: DUO_VOICE_LIVE=1 lets an isolated Duo ask")
    check(!VoiceInput.isolatedWithout(["DUO_VOICE_LIVE": "0"], isolated: false), "voice: the user's own Duo asks")
    check(M.next(.idle, .finish) == .idle && M.next(.idle, .finished) == .idle, "voice: stray events leave idle alone")
    check(!VoiceState.idle.isActive && VoiceState.listening.isActive && !VoiceState.denied.isActive, "voice: which states are active")

    // Phrase splitter
    var t = VoiceTranscript()
    check(t.apply("add the", isFinal: false) == nil && t.volatile == "add the" && t.settled.isEmpty, "splitter: a partial stays volatile")
    check(t.apply("add the annual", isFinal: false) == nil && t.volatile == "add the annual", "splitter: a partial replaces the one before")
    check(t.apply("Add the annual plan.", isFinal: true) == "Add the annual plan." && t.volatile == "", "splitter: a final settles and clears the tail")
    t.apply("to the pricing", isFinal: false)
    check(t.allText == "Add the annual plan. to the pricing" && t.settledText == "Add the annual plan.", "splitter: settled text, then the tail")
    check(t.apply("  ", isFinal: true) == nil && t.settled.count == 1, "splitter: an empty final settles nothing")
    check(t.apply("To the pricing table.", isFinal: true) != nil && t.settledText == "Add the annual plan. To the pricing table.", "splitter: phrases join with one space")
    t.apply("and", isFinal: false)
    check(t.settleTail() == "and" && t.volatile == "" && t.settled.count == 3, "splitter: the tail settles at the end")

    // Paste bytes
    let first = VoiceTerminalText.paste("add the annual plan", first: true)
    let second = VoiceTerminalText.paste("to the table", first: false)
    check(first == "\u{1b}[200~add the annual plan\u{1b}[201~", "paste: the first phrase is one bracketed paste")
    check(second == "\u{1b}[200~ to the table\u{1b}[201~", "paste: later phrases start with a space")
    let nasty = VoiceTerminalText.paste("one\r\ntwo\u{1b}[201~three\r", first: true)
    check(!nasty.dropFirst(6).dropLast(6).contains("\r") && !nasty.dropFirst(6).dropLast(6).contains("\n") && !nasty.dropFirst(6).dropLast(6).contains("\u{1b}"), "paste: no Return and no escape inside the paste")
    check(!first.contains("\r") && !second.contains("\n"), "paste: Return is never sent")
    var u = VoiceTranscript(); u.apply("one", isFinal: true); u.apply("two", isFinal: true); u.apply("three", isFinal: false)
    check(VoiceTerminalText.unsent(u, sentCount: 1) == "two three", "paste: the unsent words are the unsent phrases and the tail")

    // Q-335: a blocked dictation never writes the clipboard in an isolated or scripted Duo.
    do {
        var written: [String] = []
        let v = VoiceInput()
        v.writeClipboard = { written.append($0) }
        v.host = VoiceInput.Host(update: { _, _, _ in }, paste: { _, _, _ in .blocked("Claude asked a question") }, ended: { _, _ in })
        v.isolated = { true }
        v.showFixture(.listening, target: .terminal("k"))
        v.deliver("add the plan", to: .terminal("k"))
        check(written.isEmpty, "voice: an isolated Duo never writes the clipboard when a question stops dictation")
        check(v.unsentWords == "add the plan", "voice: the unsent words are kept for duo2 voice status")
        check(v.notice?.text == VoiceTerminalText.questionNotice && v.state == .idle, "voice: the question notice shows and listening stops")
        let w = VoiceInput()
        var wrote: [String] = []
        w.writeClipboard = { wrote.append($0) }
        w.host = v.host
        w.isolated = { false }
        w.showFixture(.listening, target: .terminal("k"))
        w.deliver("add the plan", to: .terminal("k"))
        check(wrote == ["add the plan"], "voice: the user's own Duo puts the unsent words on the clipboard")
    }

    // F-447: no input device means no sheet, no macOS question and no AVAudioEngine.
    do {
        check(!VoiceDevice.usable(nil), "voice device: none is not usable")
        check(!VoiceDevice.usable((id: 42, channels: 0)), "voice device: a device with no input channels is not usable")
        check(VoiceDevice.usable((id: 42, channels: 1)), "voice device: a device with an input channel is usable")
        let here = VoiceDevice.defaultInput()
        print("  · this Mac's default input: \(here.map { "device \($0.id), \($0.channels) input channel(s)" } ?? "none")")
        let v = VoiceInput()
        v.isolated = { false }
        v.hasMicrophone = { false }
        v.start(.terminal("k"))
        check(v.state == .unavailable(VoiceCopy.noMic), "voice: with no microphone a press says so at once, before any sheet or prompt")
        check(SheetCenter.shared.current == nil, "voice: with no microphone the first-press sheet never shows")
    }

    // The input-box finder
    let cells = 4
    func rows(_ text: String) -> [String] { text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) }
    func assertSafe(_ name: String, _ screen: [String], cursor: (row: Int, col: Int)? = nil, expectBox: Bool? = nil) {
        let a = InputBoxFinder.find(rows: screen, cursor: cursor, micCells: cells)
        if let a {
            let line = Array(screen[a.row])
            check((a.firstCol...a.lastCol).allSatisfy { InputBoxFinder.isRuleChar(line[$0]) } && a.lastCol - a.firstCol + 1 == cells, "finder \(name): the mic's cells are rule characters")
        } else {
            check(true, "finder \(name): hidden")
        }
        if let e = expectBox { check((a != nil) == e, "finder \(name): \(e ? "finds the box" : "hides")") }
    }
    let rule = String(repeating: "─", count: 60)
    let empty = ["Claude says hi", "", rule, "❯ ", rule, "  ⏸ manual mode on · ? for shortcuts"]
    assertSafe("empty box", empty, expectBox: true)
    check(InputBoxFinder.find(rows: empty, micCells: cells) == VoiceMicAnchor(row: 4, firstCol: 54, lastCol: 57), "finder: the mic sits 2 columns in from the corner")
    assertSafe("> marker", ["x", rule, "> hello", rule, "footer"], expectBox: true)
    assertSafe("› marker", ["x", rule, "› hello", rule, "footer"], expectBox: true)
    assertSafe("multi-line box", ["x", rule, "❯ line one that is long", "  line two", "  line three", rule, "footer"], expectBox: true)
    assertSafe("text to the right edge", ["x", rule, "❯ " + String(repeating: "w", count: 58), "  wraps to here", rule, "footer"], expectBox: true)
    assertSafe("rounded sides", ["x", "╭" + String(repeating: "─", count: 58) + "╮", "│ ❯ hi " + String(repeating: " ", count: 51) + "│", "╰" + String(repeating: "─", count: 58) + "╯", "footer"], expectBox: true)
    assertSafe("effort label in the top rule", ["x", String(repeating: "▔", count: 40) + " ◐ medium · /effort ▔", "❯ ", rule, "footer"], expectBox: true)
    assertSafe("label in the bottom rule", ["x", rule, "❯ ", String(repeating: "─", count: 40) + " ◐ medium · /effort ─", "footer"], expectBox: false)
    assertSafe("text typed over the rule", ["x", rule, "❯ ", String(repeating: "─", count: 54) + "ab" + String(repeating: "─", count: 4), "f"], expectBox: false)
    assertSafe("a narrow pane", ["x", String(repeating: "─", count: 6), "❯ ", String(repeating: "─", count: 6)], expectBox: false)
    check(InputBoxFinder.find(rows: empty, scrolledBack: true, micCells: cells) == nil, "finder: hidden when scrolled back")
    check(InputBoxFinder.find(rows: empty, cursor: (4, 55), micCells: cells) == nil, "finder: hidden over the cursor")
    assertSafe("question: numbered choices", ["x", rule, " Do you want to proceed?", " ❯ 1. Yes", "   2. No", " Esc to cancel · Tab to amend"], expectBox: false)
    // A question drawn over the old box's rows: still no mic.
    assertSafe("question with a box above", empty + [" ❯ 1. Yes", " Esc to cancel"], expectBox: false)
    assertSafe("no rules at all", ["❯ hello", "world"], expectBox: false)

    // Recorded screens: every file of every version must pass, and the known ones are found or hidden as drawn.
    var dir = URL(fileURLWithPath: #filePath)
    for _ in 0..<3 { dir.deleteLastPathComponent() }
    let fm = FileManager.default
    var files: [URL] = []
    for root in ["Spikes/chat-mode/screens", "docs/research/chat-model-chip-screens", "docs/design/chat-mode-handoff/fixture-chat", "docs/design/chat-slash-handoff/fixture-chat", "docs/design/chat-paste-handoff/fixture-chat"] {
        guard let e = fm.enumerator(at: dir.appending(path: root), includingPropertiesForKeys: nil) else { continue }
        for case let f as URL in e where f.pathExtension == "txt" { files.append(f) }
    }
    var found = 0, hidden = 0, bad = 0
    var versions = Set<String>()
    for f in files {
        guard let text = try? String(contentsOf: f, encoding: .utf8) else { continue }
        if let v = f.path.firstMatch(of: /2\.1\.\d+/) { versions.insert(String(v.0)) }
        let screen = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if let a = InputBoxFinder.find(rows: screen, micCells: cells) {
            found += 1
            let line = Array(screen[a.row])
            if !(a.firstCol...a.lastCol).allSatisfy({ InputBoxFinder.isRuleChar(line[$0]) }) { bad += 1; print("    over text: \(f.path)") }
        } else { hidden += 1 }
    }
    print("    \(files.count) recorded screens (\(versions.sorted().joined(separator: ", "))): \(found) with the mic, \(hidden) hidden")
    check(files.count > 100 && bad == 0, "finder: the mic is never over text on \(files.count) recorded screens")
    check(found > 20, "finder: finds the box on recorded idle screens")
    for want in ["2.1.219", "2.1.284", "2.1.296"] { check(versions.contains(want), "finder: recorded screens of \(want) covered") }
    // Named screens
    func recorded(_ rel: String) -> [String]? {
        (try? String(contentsOf: dir.appending(path: rel), encoding: .utf8))?.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }
    // 2.1.311 draws rules only: no side borders, no corners (Geoff's Duo Dev). One screen recorded from the real claude (haiku, not logged in,
    // no turn sent), one rebuilt from it and his description (effort line above, placeholder in the prompt).
    for name in ["claude-2.1.311-real", "claude-2.1.311-geoff"] {
        if let s = recorded("docs/design/voice-input-handoff/fixture-screens/\(name).txt") {
            let a = InputBoxFinder.find(rows: s, micCells: 6)
            check(a != nil, "finder: \(name) (rules only) has the mic")
            if let a {
                let line = Array(s[a.row])
                check((a.firstCol...a.lastCol).allSatisfy { InputBoxFinder.isRuleChar(line[$0]) } && a.lastCol == line.count - 3, "finder: \(name): 6 rule cells, ending 2 columns in from the rule's end")
                check(a.promptRow == a.row - 1 && s[a.promptRow].hasPrefix("❯"), "finder: \(name): the prompt row is the one above the bottom rule")
            }
        }
    }
    if let idle219 = recorded("docs/research/chat-model-chip-screens/idle-2.1.219.txt") {
        check(InputBoxFinder.find(rows: idle219, micCells: cells) != nil, "finder: 2.1.219 idle screen has the mic")
    }
    if let eff = recorded("docs/research/chat-model-chip-screens/effort-2.1.296.txt") {
        check(InputBoxFinder.find(rows: eff, micCells: cells) == nil, "finder: 2.1.296's /effort picker hides the mic")
    }
    if let perm = recorded("Spikes/chat-mode/screens/tour-2.1.284/02-bash-permission.txt") {
        check(InputBoxFinder.find(rows: perm, micCells: cells) == nil, "finder: 2.1.284's permission question hides the mic")
    }
    if let menu = recorded("Spikes/chat-mode/screens/slash-2.1.284/menu-ask-100x40.txt") {
        assertSafe("2.1.284 slash menu", menu)
    }
    if let menu = recorded("Spikes/chat-mode/screens/slash-2.1.296-inline/menu-slash.txt") {
        assertSafe("2.1.296 slash menu", menu)
    }
}
