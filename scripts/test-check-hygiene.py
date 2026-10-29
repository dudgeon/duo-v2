#!/usr/bin/env python3
"""Tests for check-hygiene.py (DL-240, ENH-281 to ENH-283, ENH-285) on a throwaway git repo.

    python3 -I scripts/test-check-hygiene.py        prints "check-hygiene tests: n passed", exit 1 on a failure
"""
import json, os, subprocess, sys, tempfile, textwrap

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, "check-hygiene.py")


def run(cwd, *args, env=None):
    return subprocess.run(list(args), cwd=cwd, capture_output=True, text=True, check=True, env=env).stdout


def write(root, path, text):
    full = os.path.join(root, path)
    os.makedirs(os.path.dirname(full), exist_ok=True)
    with open(full, "w") as f:
        f.write(textwrap.dedent(text).lstrip())


def commit(root, msg, date):
    env = dict(os.environ, GIT_AUTHOR_DATE=f"{date}T12:00:00", GIT_COMMITTER_DATE=f"{date}T12:00:00")
    run(root, "git", "add", "-A", env=env)
    run(root, "git", "commit", "-q", "-m", msg, env=env)


def hygiene(root, *extra):
    out = run(root, sys.executable, "-I", SCRIPT, "--json", "--today", "2026-10-29", *extra)
    return json.loads(out)["warnings"]


def main():
    passed, failures = 0, []

    def check(name, cond):
        nonlocal passed
        if cond:
            passed += 1
        else:
            failures.append(name)

    with tempfile.TemporaryDirectory() as tmp:
        repo, tasks = os.path.join(tmp, "repo"), os.path.join(tmp, "tasks")
        os.makedirs(repo)
        run(repo, "git", "init", "-q", "-b", "main")
        run(repo, "git", "config", "user.email", "t@example.com")
        run(repo, "git", "config", "user.name", "t")
        write(repo, "docs/plan/concerns-and-questions.md", """
            | ID | Question | Blocks | Status | Notes |
            |---|---|---|---|---|
            | Q-1 | **Old stand-in.** Built with a stand-in. | Low | open | |
            | Q-2 | **New question** | v1 | open | **Answered (Geoff, 2026-10-20): DL-9.** |
            | Q-3 | **Closed stand-in.** Built as a stand-in. | v1 | closed | |
            | Q-4 | **Struck answer** | v1 | open | ~~**Answered: DL-1.**~~ still open |
            | Q-5 | **Odd columns.** Built with a stand-in. | Low | Geoff: is this right? | open |
            """)
        write(repo, "docs/design/README.md", """
            | Doc | What it is | Status |
            |---|---|---|
            | `alpha-handoff/` | Alpha | Target; not built |
            | `beta-handoff/` | Beta | Target; built |
            | `gamma-handoff/` | Gamma | Target; building |
            """)
        write(repo, "docs/design/system/surfaces.md", """
            | Surface | Status | Targets | Open | Code |
            |---|---|---|---|---|
            | Alpha view | Designed (DL-1) | alpha `a.html` | — | A |
            | Gamma view | Designed, not built | gamma `g.html` | — | G |
            """)
        write(repo, "Sources/App/main.swift", "// v1\n")
        commit(repo, "start", "2026-10-01")
        run(repo, "git", "branch", "feature/done")
        run(repo, "git", "update-ref", "refs/remotes/origin/main", "HEAD")

        write(tasks, "stale.md", "---\nstatus: in-progress\n---\n## Progress\n- 2026-10-10: started\n")
        write(tasks, "fresh.md", "---\nstatus: in-progress\n---\n## Progress\n- 2026-10-28: going\n")
        write(tasks, "merged.md", "---\nstatus: review\n---\nBranch `feature/done`.\n- 2026-10-28: ready\n")
        write(tasks, "finished.md", "---\nstatus: done\n---\n- 2026-09-01: done\n")

        w = hygiene(repo, "--tasks", tasks)
        keys = {x["key"] for x in w}
        check("old open stand-in is flagged", "q:Q-1:standin" in keys)
        check("odd-column open stand-in is flagged", "q:Q-5:standin" in keys)
        check("closed stand-in is not flagged", not any(k.startswith("q:Q-3") for k in keys))
        check("open row with an answer is flagged", "q:Q-2:answered" in keys)
        check("struck-through answer is ignored", not any(k.startswith("q:Q-4") for k in keys))
        check("README not built vs surfaces designed", "design:alpha" in keys)
        check("README built is not checked", "design:beta" not in keys)
        check("building vs not built in surfaces is fine", "design:gamma" not in keys)
        check("stale task note", "task:stale:stale" in keys)
        check("fresh task note is quiet", not any(k.startswith("task:fresh") for k in keys))
        check("merged branch in a review note", "task:merged:merged:feature/done" in keys)
        check("done note is ignored", not any(k.startswith("task:finished") for k in keys))
        check("no catalogue warning before the catalogue exists", not any(x["section"] == "catalogue" for x in w))

        q1 = [x for x in w if x["key"] == "q:Q-1:standin"]
        check("stand-in age from the adding commit", bool(q1) and q1[0]["age"] == 28)

        # The catalogue (ENH-285): once it exists, a branch changing Sources/ must touch it.
        write(repo, "docs/product/features.md", "# Features\n")
        commit(repo, "catalogue", "2026-10-02")
        run(repo, "git", "update-ref", "refs/remotes/origin/main", "HEAD")
        run(repo, "git", "checkout", "-q", "-b", "feature/x")
        write(repo, "Sources/App/main.swift", "// v2\n")
        commit(repo, "change the app", "2026-10-03")
        w = hygiene(repo, "--tasks", tasks)
        check("app change without a catalogue row", any(x["section"] == "catalogue" for x in w))
        write(repo, "docs/product/features.md", "# Features\n- FEAT-1 changed\n")
        commit(repo, "catalogue row", "2026-10-03")
        w = hygiene(repo, "--tasks", tasks)
        check("app change with a catalogue row is quiet", not any(x["section"] == "catalogue" for x in w))

        out = run(repo, sys.executable, "-I", SCRIPT, "--summary", "--today", "2026-10-29", "--tasks", tasks)
        check("summary prints counts", out.strip().splitlines()[-1].startswith("hygiene: records"))
        r = subprocess.run([sys.executable, "-I", SCRIPT, "--strict", "--today", "2026-10-29", "--tasks", tasks], cwd=repo, capture_output=True)
        check("--strict fails on warnings", r.returncode == 1)
        r = subprocess.run([sys.executable, "-I", SCRIPT, "--today", "2026-10-29", "--tasks", tasks], cwd=repo, capture_output=True)
        check("warnings never fail by default", r.returncode == 0)

    for f in failures:
        print("FAIL", f)
    print(f"check-hygiene tests: {passed} passed" + (f", {len(failures)} failed" if failures else ""))
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
