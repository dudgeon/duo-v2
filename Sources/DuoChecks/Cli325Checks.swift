import DuoKit
import Foundation

// F-731 to F-734: Claude Code 2.1.323 to 2.1.325 against chat mode's screen reader. The screens are the real TUI
// on the chat spike's mock API (scratch config, 100×34): `Spikes/chat-mode/screens/tour-2.1.323`, `tour-2.1.325`
// (the dialog tour with `--permission-mode default`) and `cli-2.1.325` (`run-extra.sh`). `DUO_CHECKS=cli325` runs these alone.
@MainActor func cli325Checks() throws {
    print("Claude Code 2.1.323 and 2.1.325: the dialog tour and the new dialogs (F-731 to F-734)")
    for v in ["2.1.323", "2.1.325"] {
        func read(_ n: String) -> ChatScreen { ChatScreenReader.read(spikeScreen("tour-\(v)/\(n).txt"), cols: 100) }
        let idle = read("01-markdown")
        check(idle.kind == .idle && idle.input == "" && idle.mode == .manual, "\(v): idle, empty input, manual mode (\(idle.kind) \(idle.mode?.rawValue ?? "-"))")
        // The dialogs now offer "Yes, and switch to auto mode" as option 3, and No moves from 3 to 4.
        let bash = read("02-bash-permission")
        check(bash.kind == .permission && bash.title == "Do you want to proceed?", "\(v): a Bash permission (\(bash.kind))")
        check(bash.options.map(\.n) == [1, 2, 3, 4] && bash.options[0].label == "Yes" && bash.options[3].label == "No"
              && bash.options[2].label.hasPrefix("Yes, and switch to auto mode"), "\(v): its four options, No last (\(bash.options.map(\.label)))")
        let edit = read("03-edit-permission")
        check(edit.kind == .permission && edit.options.last?.label == "No" && edit.options.map(\.n) == Array(1...edit.options.count), "\(v): an edit permission (\(edit.options.map(\.label)))")
        let plan = read("09-plan")
        check(plan.kind == .plan && plan.options.count == 3 && plan.options[0].label == "Yes, and use auto mode"
              && plan.options[2].label == "Tell Claude what to change", "\(v): plan approval, first option now 'use auto mode' (\(plan.options.map(\.label)))")
        let ask = read("04-question")
        check(ask.kind == .question && ask.options.map(\.label) == ["Blue", "Green", "Grey"], "\(v): a question (\(ask.kind))")
        check(read("05-multi").kind == .question && read("06-review").kind == .questionReview, "\(v): multi-select and review pages")
        check(read("12-unknown-model-picker").kind == .picker, "\(v): /model reads as its picker")
        check(read("13-retrying").kind == .busy, "\(v): the retry line reads busy")
        check(read("11-interrupted").interrupted, "\(v): interrupted")
        let trust = ChatSignatures.trust(for: v)
        check(trust == .newer, "\(v): trusted as a newer 2.1.x, dialogs answered from chat (\(trust))")
    }
    print("2.1.325: sandbox, read-only git outside the project, auto mode that can't check")
    let sandbox = ChatScreenReader.read(spikeScreen("cli-2.1.325/sandbox-bash-permission.txt"), cols: 100)
    check(sandbox.kind == .permission && sandbox.options.count == 4, "a sandboxed Bash now asks like any other: a permission card (\(sandbox.kind))")
    let other = ChatScreenReader.read(spikeScreen("cli-2.1.325/other-repo-status.txt"), cols: 100)
    check(other.kind == .permission && other.options.count == 4 && other.options[1].label.hasPrefix("Yes, and don’t ask again for: git"),
          "read-only git in another repository asks first, with its own 'don't ask again' (\(other.kind) \(other.options.map(\.label)))")
    check(other.body?.contains("requires approval") == true || other.kindLabel?.contains("requires approval") == true,
          "its 'This command requires approval' line is kept (\(other.kindLabel ?? "-") | \(other.body ?? "-"))")
    // Auto mode, behind a gateway that doesn't pass the safety check through: a full-screen notice, no input box. Chat
    // can't answer it (Enter, Shift+Tab, Esc each mean something else), so it is the terminal's; it must never be taken for
    // a permission card.
    let cannot = ChatScreenReader.read(spikeScreen("cli-2.1.325/auto-mode-cannot-check.txt"), cols: 100)
    check(cannot.kind == .unknown, "'Auto mode can't check actions in this session' is an unknown screen: the terminal answers it (\(cannot.kind))")
    let idleManual = ChatScreenReader.read(spikeScreen("cli-2.1.325/idle-manual.txt"), cols: 100)
    check(idleManual.kind == .idle && idleManual.mode == .manual, "auto mode that falls back reads as an idle, manual screen (\(idleManual.kind))")

    // `--permission-mode auto` on a model that can't use it starts in Manual, says so, and its dialogs lose the auto option.
    let fell = ChatScreenReader.read(spikeScreen("cli-2.1.325/auto-unavailable-idle-manual.txt"), cols: 100)
    check(fell.kind == .idle && fell.mode == .manual, "auto mode unavailable: an idle, manual screen (\(fell.kind) \(fell.mode?.rawValue ?? "-"))")
    let fellPerm = ChatScreenReader.read(spikeScreen("cli-2.1.325/auto-unavailable-bash-permission.txt"), cols: 100)
    check(fellPerm.kind == .permission && fellPerm.options.map(\.n) == [1, 2, 3] && fellPerm.options[2].label == "No", "its permission has three options, No last (\(fellPerm.options.map(\.label)))")
    print("2.1.311 to 2.1.325: `claude plugin validate` prints a ✘ advisory above a passing verdict (F-731)")
    let advisory = spikeScreen("cli-2.1.325/validate-passed-with-advisory.txt")
    let failed = spikeScreen("cli-2.1.325/validate-failed.txt")
    check(advisory.contains("✘ Found 2 problems") && advisory.contains("✔ Validation passed"), "the fixture is the real report: a ✘ advisory and a passing verdict")
    check(DuoSignal.passed(advisory, status: 0), "a passing report with a ✘ advisory above it passes (Duo used to refuse it: 'Duo won't pass it to sessions')")
    check(!DuoSignal.passed(failed, status: 1), "a failing report fails")
    check(!DuoSignal.passed(advisory, status: 1) && !DuoSignal.passed("", status: 0), "a bad exit status, or no report, never passes")
    check(DuoSignal.passed("Validating plugin manifest: /x\n\n✔ Validation passed\n", status: 0), "the older, short report passes")
}
