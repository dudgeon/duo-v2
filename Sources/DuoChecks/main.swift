import DuoKit
import Foundation

// Plain assertions, run with `swift run DuoChecks`. Exit status is the number of failures.

nonisolated(unsafe) var failures = 0
nonisolated(unsafe) var passes = 0

func check(_ condition: @autoclosure () throws -> Bool, _ name: String, line: Int = #line) {
    do {
        if try condition() { passes += 1; print("  ✔ \(name)") }
        else { failures += 1; print("  ✘ \(name)  (line \(line))") }
    } catch {
        failures += 1; print("  ✘ \(name): \(error)  (line \(line))")
    }
}

func repoFixture() throws -> Fixture {
    var dir = URL(fileURLWithPath: #filePath)
    for _ in 0..<3 { dir.deleteLastPathComponent() }
    return try Fixture.load(from: dir.appending(path: "docs/design/build-handoff/fixture.json"))
}

@MainActor func run() throws {
    let f = try repoFixture()

    print("fixture")
    check(f.topics == ["Payments", "Growth", "Platform"], "topics decode")
    check(f.home?.name == "home", "home project")
    check(f.sessions.count == 11, "eleven sessions")
    check(f.needsYou.map(\.name) == ["Morning triage", "Copy review pass 2", "PRD v2 edits"], "needs-you longest wait first")

    print("ordering")
    check(WaitTime("1h") > WaitTime("12m") && WaitTime("3d") > WaitTime("1h") && WaitTime("now") < WaitTime("4m"), "wait times")
    check(SessionState.allCases.sorted() == [.needsYou, .readyForReview, .working, .idle, .resolved], "states most urgent first")

    print("target states")
    let project = AppModel(fixture: f)
    TargetState.project.apply(to: project)
    check(project.needsYouElsewhere.count == 2, "chip counts only other projects (2 need you)")
    let zoom4 = AppModel(fixture: f)
    TargetState.flowZoom4.apply(to: zoom4)
    check(zoom4.fixture.counts.needsYou == 2 && zoom4.fixture.counts.working == 5, "flow-zoom-4 counts: 2 need you, 5 working")
    check(zoom4.fixture.needsYou.map(\.name) == ["Morning triage", "PRD v2 edits"], "flow-zoom-4 action column one card shorter")
    check(zoom4.selectedActionSession == "checkout-redesign/PRD v2 edits", "flow-zoom-4 selection")

    print("launch options")
    let o = LaunchOptions(arguments: ["Duo", "--state", "flow-zoom-3", "--capture", "/tmp/x.png", "--left", "collapsed"])
    check(o.state == .flowZoom3 && o.capturePath == "/tmp/x.png" && o.collapseLeft && o.capturing, "flags parse")

    print("tokens")
    check(DuoTextStyle.body.spec.size == 13 && DuoTextStyle.body.spec.lineHeight == 20, "body 13/20")
    check(DuoTextStyle.sectionLabel.spec.uppercase && DuoTextStyle.sectionLabel.spec.tracking == 0.66, "section label caps +0.66")
    check(DuoMetric.paneOverviewHome == 340 && DuoMetric.paneProjectRight == 460, "pane widths")
}

do { try MainActor.assumeIsolated { try run() } } catch { print("✘ setup: \(error)"); failures += 1 }
print("\(passes) passed, \(failures) failed")
exit(Int32(failures))
