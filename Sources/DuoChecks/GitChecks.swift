import Darwin
import DuoKit
import Foundation

// DL-149, DL-157: the GitHub engine against local bare repos and a stub `gh` only. Nothing here
// reaches GitHub: `https://github.com/acme/website.git` is redirected to a bare repo by git's
// `url.<path>.insteadOf`, so the real code paths run.

private func sh(_ args: [String], in dir: URL, env: [String: String] = [:]) -> GitTool.Result {
    GitTool.git(args, in: dir, timeout: 30, env: env)
}

private func write(_ url: URL, _ text: String) {
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? text.write(to: url, atomically: true, encoding: .utf8)
}

/// A stub `gh` that answers from files in its folder and logs every call (one per line).
private func stubGH(_ dir: URL, login: String?, permission: String, protected: Bool, prURL: String?) -> URL {
    let log = dir.appending(path: "gh.log")
    let auth = login.map { #"{"hosts":{"github.com":[{"state":"success","active":true,"host":"github.com","login":"\#($0)"}]}}"# } ?? #"{"hosts":{}}"#
    let view = #"{"viewerPermission":"\#(permission)","visibility":"PRIVATE","defaultBranchRef":{"name":"main"},"isFork":false,"parent":null}"#
    let script = """
    #!/bin/sh
    echo "$*" >> '\(log.path)'
    case "$1 $2" in
      "auth status") echo '\(auth)' ;;
      "repo view") echo '\(view)' ;;
      "api repos/acme/website/branches/main") echo '\(protected)' ;;
      "api repos/acme/website/rules/branches/main") echo '' ;;
      "repo fork") git remote add fork "$DUO_STUB_FORK" ;;
      "pr list") echo '[]' ;;
      "pr create") \(prURL.map { "echo '\($0)'" } ?? "echo 'To get started with GitHub CLI, please run:  gh auth login'") ;;
      *) echo "stub: $*" >&2; exit 1 ;;
    esac
    """
    let url = dir.appending(path: "gh")
    write(url, script)
    chmod(url.path, 0o755)
    return url
}

@MainActor func gitChecks() throws {
    print("GitHub: links, status, failures (DL-149, DL-157)")
    let p1 = RemoteRepo.parse("https://github.com/acme/website")
    check(p1?.repo.slug == "acme/website" && p1?.repo.host == "github.com" && p1?.branch == nil, "a plain https link")
    check(RemoteRepo.parse("https://github.com/acme/website/tree/geoff/pricing-copy")?.branch == "geoff/pricing-copy", "a /tree/ link names its branch")
    check(RemoteRepo.parse("git@github.com:acme/website.git")?.repo.slug == "acme/website", "an ssh link")
    check(RemoteRepo.parse("acme/website")?.repo.host == "github.com", "owner/repo means GitHub")
    check(RemoteRepo.parse("https://github.example.com/acme/website.git")?.repo.isGitHub == true, "an Enterprise host keeps its own host")
    check(RemoteRepo.parse("--upload-pack=x/y") == nil && RemoteRepo.parse("acme") == nil, "a flag or a bare word is no repo")
    let cmp = RemoteRepo(host: "github.com", owner: "acme", name: "website").compareURL(base: "main", head: "b", headOwner: "geoffd", title: "T & x", body: "B")
    check(cmp.absoluteString.hasPrefix("https://github.com/acme/website/compare/main...geoffd:b?expand=1&title=T%20%26%20x"), "the compare page fills the PR in")

    check(GitFailure.classify("remote: error: GH006: Protected branch update failed for refs/heads/main.").kind == .protected, "GH006 is a protected branch")
    check(GitFailure.classify(" ! [rejected]        feat -> feat (fetch first)").kind == .notFastForward, "fetch first is not fast-forward")
    check(GitFailure.classify("remote: Permission to acme/website.git denied to geoffd.\nfatal: unable to access 'x': The requested URL returned error: 403").kind == .noWrite, "a 403 is no write access")
    check(GitFailure.classify("fatal: could not read Username for 'https://github.com': terminal prompts disabled").kind == .signedOut, "no credential is signed out (F-194)")
    check(GitFailure.classify("remote: error: GH009: Secrets detected! This push failed.").kind == .secrets, "GH009 is secrets")
    check(GitFailure.classify("Resource protected by organization SAML enforcement.").kind == .sso, "SAML is single sign-on")
    check(GitFailure.classify("x", timedOut: true).kind == .offline, "a time-out is offline")
    let w = GitFailure(kind: .noWrite, details: "").words(repo: "acme/website", branch: "b", login: "geoffd")
    check(w.title == "You can’t push to acme/website" && w.body.contains("your account, geoffd,"), "the 403 words name the account")

    // A sandbox: upstream (bare), a fork (bare), and Duo's copy.
    let sand = FileManager.default.temporaryDirectory.appending(path: "duo-git-\(getpid())").resolvingSymlinksInPath()
    try? FileManager.default.removeItem(at: sand)
    try FileManager.default.createDirectory(at: sand, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: sand) }
    let home = sand.appending(path: "home")
    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    let cfg = home.appending(path: ".gitconfig")
    let upstream = sand.appending(path: "upstream.git"), forkBare = sand.appending(path: "fork.git")
    write(cfg, """
    [user]
    \tname = Tester
    \temail = t@example.com
    [init]
    \tdefaultBranch = main
    [url "\(upstream.path)"]
    \tinsteadOf = https://github.com/acme/website.git
    [url "\(forkBare.path)"]
    \tinsteadOf = https://github.com/tester/website.git
    """)
    setenv("GIT_CONFIG_GLOBAL", cfg.path, 1)
    setenv("GIT_CONFIG_NOSYSTEM", "1", 1)
    setenv("DUO_GH_PATH", "none", 1)   // never the real gh: no gh unless a check sets the stub
    defer { unsetenv("GIT_CONFIG_GLOBAL"); unsetenv("GIT_CONFIG_NOSYSTEM"); unsetenv("DUO_GH_PATH"); unsetenv("DUO_STUB_FORK") }

    _ = sh(["init", "-q", "--bare", upstream.path], in: sand)
    _ = sh(["init", "-q", "--bare", forkBare.path], in: sand)
    let seed = sand.appending(path: "seed")
    _ = sh(["clone", "-q", upstream.path, seed.path], in: sand)
    write(seed.appending(path: "README.md"), "hi\n")
    write(seed.appending(path: "content/faq.md"), "one\ntwo\n")
    _ = sh(["add", "."], in: seed); _ = sh(["commit", "-qm", "init"], in: seed)
    _ = sh(["push", "-q", "origin", "main"], in: seed)
    _ = sh(["symbolic-ref", "HEAD", "refs/heads/main"], in: upstream)

    print("GitHub: copy a repo on a new branch (board 3)")
    let repo = RemoteRepo(host: "github.com", owner: "acme", name: "website")
    let dest = sand.appending(path: "Home/website/pricing-copy")
    let c = RepoOps.clone(repo, into: dest, newBranch: "tester/pricing-copy", from: "main", existing: nil, excludeDuoFiles: true)
    check((try? c.get()) == dest.path, "copied into the project's folder")
    write(dest.appending(path: "_PROJECT.md"), "---\ntype: project\n---\n")
    var st = RepoProbe.status(of: dest)
    check(st?.branch == "tester/pricing-copy" && st?.origin?.slug == "acme/website", "on the new branch, origin is acme/website")
    check(st?.changes.isEmpty == true, "_PROJECT.md is kept out of git (.git/info/exclude)")
    check(st?.upstream == nil, "the new branch isn't on GitHub yet")
    check(RepoOps.clone(repo, into: dest, newBranch: nil, from: nil, existing: nil, excludeDuoFiles: false).failureKind == .unknown, "a folder already there is refused")
    let sub = dest.appending(path: "content")
    check(RepoProbe.root(of: sub)?.resolvingSymlinksInPath().path == dest.resolvingSymlinksInPath().path, "a project inside a repo finds its root (DL-157)")

    print("GitHub: push and open a PR, with write access (board 6)")
    write(dest.appending(path: "content/faq.md"), "one\nTWO\n")
    write(dest.appending(path: "content/plans.json"), "{}\n")
    st = RepoProbe.status(of: dest)
    check(Set(st?.changes.map(\.path) ?? []) == ["content/faq.md", "content/plans.json"] && st?.changes.first { $0.path == "content/plans.json" }?.kind == .new, "changed and new files")
    let plan = RepoOps.PushPlan(files: ["content/faq.md", "content/plans.json"], message: "Pricing: FAQ", openPR: true, prTitle: "Pricing: FAQ", prBody: "Body", base: "main", draft: false, fork: false, browser: false)
    let pushed = RepoOps.push(dest, plan: plan, login: nil)
    check((try? pushed.get())?.compareURL?.absoluteString.contains("compare/main...tester/pricing-copy") == true, "without gh the PR is GitHub's compare page")
    st = RepoProbe.status(of: dest)
    check(st?.upstream == "origin/tester/pricing-copy" && st?.ahead == 0 && st?.changes.isEmpty == true, "pushed with upstream, nothing left")

    print("GitHub: someone else pushed; Get Latest; a conflict and Put Back (board 9)")
    let other = sand.appending(path: "other")
    _ = sh(["clone", "-q", "-b", "tester/pricing-copy", upstream.path, other.path], in: sand)
    write(other.appending(path: "content/faq.md"), "one\nTwo!\n")
    _ = sh(["commit", "-qam", "theirs"], in: other); _ = sh(["push", "-q", "origin", "HEAD"], in: other)
    write(dest.appending(path: "content/faq.md"), "one\ntwo?\n")
    _ = sh(["commit", "-qam", "mine"], in: dest)
    let nff = RepoOps.push(dest, plan: .init(files: [], message: "", openPR: false, prTitle: "", prBody: "", base: "main", draft: false, fork: false, browser: false), login: nil)
    check(nff.failureKind == .notFastForward, "a push behind GitHub is refused as not fast-forward, never forced")
    let m = RepoOps.merge(dest, from: nil)
    check(m.failureKind == .conflict, "Get Latest stops at a conflict")
    st = RepoProbe.status(of: dest)
    check(st?.hasConflict == true && st?.merging == true, "the status shows the conflict")
    check(RepoOps.merge(dest, from: nil).failureKind == .conflict, "a second Get Latest is refused while one is stopped")
    _ = RepoOps.putBack(dest)
    st = RepoProbe.status(of: dest)
    check(st?.hasConflict == false && st?.merging == false && (try? String(contentsOf: dest.appending(path: "content/faq.md"), encoding: .utf8)) == "one\ntwo?\n", "Put Back restores your version")

    print("GitHub: a protected main, moved to a branch (board 10)")
    let hook = upstream.appending(path: "hooks/pre-receive")
    write(hook, "#!/bin/sh\nwhile read o n r; do [ \"$r\" = refs/heads/main ] && { echo 'error: GH006: Protected branch update failed for refs/heads/main.' >&2; exit 1; }; done; exit 0\n")
    chmod(hook.path, 0o755)
    let onMain = sand.appending(path: "onmain")
    _ = sh(["clone", "-q", upstream.path, onMain.path], in: sand)
    write(onMain.appending(path: "README.md"), "hi there\n")
    _ = sh(["commit", "-qam", "edit on main"], in: onMain)
    let prot = RepoOps.push(onMain, plan: .init(files: [], message: "", openPR: false, prTitle: "", prBody: "", base: "main", draft: false, fork: false, browser: false), login: nil)
    // A local remote isn't github.com, so set it as Duo's copies are.
    _ = prot
    _ = sh(["remote", "set-url", "origin", "https://github.com/acme/website.git"], in: onMain)
    let prot2 = RepoOps.push(onMain, plan: .init(files: [], message: "", openPR: false, prTitle: "", prBody: "", base: "main", draft: false, fork: false, browser: false), login: nil)
    check(prot2.failureKind == .protected, "GH006 from the hook is a protected branch")
    let moved = RepoOps.moveToBranch(onMain, newBranch: "tester/readme")
    st = RepoProbe.status(of: onMain)
    let mainAt = sh(["rev-parse", "main"], in: onMain).out, upAt = sh(["rev-parse", "origin/main"], in: onMain).out
    check((try? moved.get()) == "tester/readme" && st?.branch == "tester/readme" && st?.ahead == 0 && mainAt == upAt, "the commit moves to a new branch and main goes back to GitHub's")

    print("GitHub: read only, the fork and gh pr create (board 7)")
    let ghDir = sand.appending(path: "gh")
    let gh = stubGH(ghDir, login: "tester", permission: "READ", protected: true, prURL: "https://github.com/acme/website/pull/7")
    setenv("DUO_GH_PATH", gh.path, 1)
    setenv("DUO_STUB_FORK", "https://github.com/tester/website.git", 1)
    let access = GitHubAccess.probe(repo)
    check(access.login == "tester" && access.readOnly && access.canPush == false && access.protectedDefault == true, "the probe reads access and protection through gh")
    write(dest.appending(path: "content/new.md"), "x\n")
    let forkPlan = RepoOps.PushPlan(files: ["content/new.md"], message: "New", openPR: true, prTitle: "New", prBody: "Body", base: "main", draft: true, fork: true, browser: false)
    let fk = RepoOps.push(dest, plan: forkPlan, login: "tester")
    let log = (try? String(contentsOf: ghDir.appending(path: "gh.log"), encoding: .utf8)) ?? ""
    check((try? fk.get())?.prNumber == 7 && (try? fk.get())?.remote == "fork", "pushed to the fork and opened PR #7")
    check(log.contains("repo fork acme/website --clone=false --remote --remote-name fork"), "the fork keeps origin (--remote-name fork)")
    check(log.contains("--head tester:tester/pricing-copy") && log.contains("--draft"), "the PR names the fork's branch and is a draft")
    check(RepoProbe.remoteURL(dest, "origin") == "https://github.com/acme/website.git", "origin still means acme/website")

    let gh2 = stubGH(ghDir, login: nil, permission: "WRITE", protected: false, prURL: nil)
    setenv("DUO_GH_PATH", gh2.path, 1)
    check(GitHubAccess.sign() == .signedOut, "signed out read from gh's JSON, not its exit code (F-196)")
    let gh3 = stubGH(ghDir, login: "tester", permission: "WRITE", protected: false, prURL: nil)
    setenv("DUO_GH_PATH", gh3.path, 1)
    write(dest.appending(path: "content/new2.md"), "y\n")
    let silent = RepoOps.push(dest, plan: .init(files: ["content/new2.md"], message: "m", openPR: true, prTitle: "t", prBody: "b", base: "main", draft: false, fork: false, browser: false), login: "tester")
    check(silent.failureKind != nil, "gh exiting 0 with no PR URL is a failure, not a PR")
}

extension Result where Failure == GitFailure {
    var failureKind: GitFailure.Kind? { if case .failure(let f) = self { return f.kind }; return nil }
}
