#!/usr/bin/env python3
"""Drift warnings for the merge gate and the weekly tidy-up (ENH-281 to ENH-283, ENH-285; DL-240).

    python3 -I scripts/check-hygiene.py [--ref REF] [--base REF] [--tasks DIR] [--today YYYY-MM-DD] [--json]

Read-only. It reads the records and design docs at REF (default HEAD) with `git show`, and the task notes in
DIR (default <main checkout>/tasks, which git ignores). It prints one line per warning and always exits 0, so
it warns and never blocks; --strict exits 1 when there are warnings, --summary prints counts (the merge gate's form). Sections:
  records    a Q row whose status isn't closed (closed, answered, defaulted, decided, built, ...) while its text says **Answered or **Decided (ENH-281), and
             stand-in questions open longer than 14 days, aged from the commit that added the row
  design     docs/design/README.md's handoff status against surfaces.md's rows that target the handoff (ENH-283)
  tasks      in-progress, review or open notes with no date in the last 7 days, or naming a merged branch (ENH-282)
  catalogue  REF changes Sources/ against --base (default refs/remotes/origin/main) but not
             docs/product/features.md, once that file exists (ENH-285)
"""
import argparse, datetime as dt, json, os, re, subprocess, sys

STANDIN_DAYS, TASK_DAYS = 14, 7


def git(*args, cwd=None):
    r = subprocess.run(["git", *args], cwd=cwd, capture_output=True, text=True)
    return r.stdout if r.returncode == 0 else None


def show(ref, path, cwd):
    return git("show", f"{ref}:{path}", cwd=cwd)


def cells(line):
    return [c.strip() for c in line.strip().strip("|").split("|")]


def unstruck(text):
    return re.sub(r"~~.*?~~", "", text)


def q_added_dates(cwd, ref):
    """The date each Q-n row first appeared, from one pass over the file's history."""
    out = git("log", "-p", "--diff-merges=first-parent", "--format=@@C %cs", ref, "--", "docs/plan/concerns-and-questions.md", cwd=cwd) or ""
    seen, date = {}, None
    for line in out.splitlines():
        if line.startswith("@@C "):
            date = line[4:]
        elif line.startswith("+| Q-"):
            m = re.match(r"\+\| (Q-\d+) ", line)
            if m and date and (m.group(1) not in seen or date < seen[m.group(1)]):
                seen[m.group(1)] = date
    return seen


def check_records(cwd, ref, today):
    text = show(ref, "docs/plan/concerns-and-questions.md", cwd) or ""
    added = q_added_dates(cwd, ref)
    warn = []
    for line in text.splitlines():
        if not line.startswith("| Q-"):
            continue
        c = cells(line)
        if len(c) < 5:
            continue
        qid, status, rest = c[0], c[3], " ".join(c[1:3] + c[4:])
        # Rows don't all keep the header's column order: when the Status cell isn't a status, the last cell is.
        word = r"[*~ ]*(open|closed|answered|defaulted|decided|built|resolved|superseded|done|dropped|withdrawn)\b"
        if not re.match(word, status, re.I):
            status = c[-1]
        if re.match(word, status, re.I) and not re.match(r"[*~ ]*open", status, re.I):
            continue
        body = unstruck(rest + " " + status)
        m = re.search(r"\*\*(Answered|Decided)\b[^*]{0,60}", body, re.I)
        if m:
            warn.append({"section": "records", "key": f"q:{qid}:answered",
                         "text": f"{qid} reads open, but its text says \"{m.group(0).strip('* ')[:60]}\": close it"})
            continue
        if re.search(r"stand-in|nothing drawn", body, re.I) and qid in added:
            age = (today - dt.date.fromisoformat(added[qid])).days
            if age > STANDIN_DAYS:
                warn.append({"section": "records", "key": f"q:{qid}:standin", "age": age,
                             "text": f"{qid} is a stand-in question open {age} days (since {added[qid]})"})
    return warn


def readme_state(status):
    s = status.lower()
    if "not built" in s:
        return "not built"
    if "building" in s:
        return "building"
    if "built" in s:
        return "built"
    return None


def surface_built(status):
    s = status.lower()
    if "not built" in s:
        return False
    return s.startswith("designed") or s.startswith("built") or s.startswith("changed by decision") or " built" in s


def check_design(cwd, ref):
    readme = show(ref, "docs/design/README.md", cwd) or ""
    surfaces = show(ref, "docs/design/system/surfaces.md", cwd) or ""
    rows = [cells(l) for l in surfaces.splitlines() if l.startswith("| ") and not l.startswith("| Surface") and not l.startswith("|---")]
    warn = []
    for line in readme.splitlines():
        m = re.match(r"\| `([a-z0-9-]+)-handoff/` \|", line)
        if not m:
            continue
        c = cells(line)
        short, state = m.group(1), readme_state(c[-1])
        if state not in ("not built", "building"):
            continue
        hits = [r for r in rows if len(r) >= 3 and re.search(rf"(^|[\s/]){re.escape(short)}(-handoff)?[\s/`]", r[2] + " ")]
        built = [r for r in hits if surface_built(r[1])]
        if built:
            warn.append({"section": "design", "key": f"design:{short}",
                         "text": f"docs/design/README.md says {short}-handoff is \"{state}\", but surfaces.md marks it built ({built[0][0][:50]}): update the README row"})
    return warn


def check_tasks(cwd, tasks_dir, base, today):
    warn = []
    if not tasks_dir or not os.path.isdir(tasks_dir):
        return warn
    heads = (git("for-each-ref", "--format=%(refname:short) %(objectname)", "refs/heads", cwd=cwd) or "").split("\n")
    branches = dict(h.split(" ", 1) for h in heads if " " in h)
    branches.pop("main", None)
    for name in sorted(os.listdir(tasks_dir)):
        if not name.endswith(".md"):
            continue
        text = open(os.path.join(tasks_dir, name), encoding="utf-8", errors="replace").read()
        m = re.search(r"^status:\s*(\S+)", text, re.M)
        status = m.group(1) if m else ""
        if status not in ("in-progress", "review", "open"):
            continue
        slug = name[:-3]
        dates = [d for d in re.findall(r"\b(20\d\d-\d\d-\d\d)\b", text)]
        last = max(dates) if dates else None
        try:
            age = (today - dt.date.fromisoformat(last)).days if last else None
        except ValueError:
            age = None
        if age is not None and age > TASK_DAYS:
            warn.append({"section": "tasks", "key": f"task:{slug}:stale", "age": age,
                         "text": f"tasks/{name} is {status} with nothing dated after {last} ({age} days)"})
        for br in sorted(set(re.findall(r"`([A-Za-z0-9._/+-]+)`", text))):
            sha = branches.get(br)
            if sha and subprocess.run(["git", "merge-base", "--is-ancestor", sha, base], cwd=cwd).returncode == 0:
                warn.append({"section": "tasks", "key": f"task:{slug}:merged:{br}",
                             "text": f"tasks/{name} is {status}, but its branch {br} is merged: ask the director to update it"})
                break
    return warn


def check_catalogue(cwd, ref, base):
    if show(ref, "docs/product/features.md", cwd) is None:
        return []
    files = (git("diff", "--name-only", f"{base}...{ref}", cwd=cwd) or "").split()
    app = [f for f in files if f.startswith("Sources/") and not f.startswith(("Sources/DuoChecks/", "Sources/DuoKit/Debug/"))]
    if app and "docs/product/features.md" not in files:
        return [{"section": "catalogue", "key": f"catalogue:{ref}",
                 "text": f"{len(app)} app file(s) changed and docs/product/features.md didn't: update the feature's row, or say why it isn't a feature change"}]
    return []


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--ref", default="HEAD")
    ap.add_argument("--base", default="refs/remotes/origin/main")
    ap.add_argument("--repo", default=os.getcwd())
    ap.add_argument("--tasks")
    ap.add_argument("--today")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--strict", action="store_true")
    ap.add_argument("--summary", action="store_true", help="counts per section; only the branch's own (catalogue) warnings in full")
    a = ap.parse_args()
    cwd = a.repo
    common = (git("rev-parse", "--path-format=absolute", "--git-common-dir", cwd=cwd) or "").strip()
    tasks = a.tasks or (os.path.join(os.path.dirname(common), "tasks") if common else None)
    today = dt.date.fromisoformat(a.today) if a.today else dt.date.today()
    if git("rev-parse", "--verify", "-q", a.base, cwd=cwd) is None:
        a.base = a.ref
    warn = (check_records(cwd, a.ref, today) + check_design(cwd, a.ref)
            + check_tasks(cwd, tasks, a.base, today) + check_catalogue(cwd, a.ref, a.base))
    if a.json:
        json.dump({"ref": a.ref, "today": today.isoformat(), "warnings": warn}, sys.stdout, indent=1)
        print()
    elif a.summary:
        for w in warn:
            if w["section"] == "catalogue":
                print(f"warn  {w['section']:<9} {w['text']}")
        counts = {}
        for w in warn:
            counts[w["section"]] = counts.get(w["section"], 0) + 1
        print("hygiene: " + (", ".join(f"{k} {v}" for k, v in counts.items()) or "no warnings")
              + ("  (scripts/check-hygiene.py lists them; the weekly tidy-up reports them)" if warn else ""))
    else:
        for w in warn:
            print(f"warn  {w['section']:<9} {w['text']}")
        print(f"hygiene: {len(warn)} warning(s)")
    return 1 if (a.strict and warn) else 0


if __name__ == "__main__":
    sys.exit(main())
