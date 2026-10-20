import DuoControl
import DuoKit
import Foundation

/// BUG-163 (F-340): a project name that matches several projects says it's ambiguous and lists them,
/// in duo2's replies, instead of "no project" (or silently taking the first).
@MainActor func ambiguousNameChecks() throws {
    print("projects: an ambiguous name is reported as ambiguous (BUG-163)")
    var fx = try repoFixture()
    func project(_ name: String, topic: String, path: String) throws -> Fixture.Project {
        try JSONDecoder().decode(Fixture.Project.self, from: JSONSerialization.data(withJSONObject: ["name": name, "topic": topic, "path": path, "goal": "g"]))
    }
    fx.projects.append(try project("twin", topic: "personal", path: "/tmp/dup-personal/twin"))
    fx.projects.append(try project("twin", topic: "work", path: "/tmp/dup-work/twin"))
    let m = AppModel(fixture: fx)
    func run(_ verb: String, _ args: [String]) -> ControlResponse {
        var out: ControlResponse?
        m.handle(ControlRequest(token: "", command: verb, args: args, session: nil, cwd: nil)) { out = $0 }
        let until = Date().addingTimeInterval(5)
        while out == nil, Date() < until { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
        return out ?? ControlResponse(ok: false, output: "no answer")
    }
    let amb = run("project show", ["twin"])
    check(!amb.ok && amb.output.contains("ambiguous") && !amb.output.hasPrefix("no project"), "project show: says the name is ambiguous, not that there's no match")
    check(amb.output.contains("personal/twin") && amb.output.contains("work/twin") && amb.output.contains("2 projects"), "and lists both matches by topic")
    let gone = run("project show", ["nothing-like-it"])
    check(!gone.ok && gone.output == "no project 'nothing-like-it'", "an unknown name still says there's no such project")
    let one = run("project show", [fx.projects.first { $0.name != "twin" && $0.kind == nil }!.name])
    check(one.ok, "a name only one project has still resolves")
    check(m.project(named: "twin") == nil && m.projects(named: "TWIN").count == 2, "project(named:) never picks the first of several; matching ignores case")
    let new = run("session new", ["--project", "twin"])
    check(!new.ok && new.output.contains("ambiguous"), "session new --project: ambiguous too")
}
