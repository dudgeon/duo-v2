#!/usr/bin/env python3
"""Which director evals are worth running, and what an unchanged revision already proved (DL-352).

An eval's *key* is a hash of everything it depends on: its own files, evals/_lib, the SKILL.md sections, reference
files, worker skill and code groups that eval-map.json maps it to, and the model. A case whose key is the same at the
base as now has nothing new to prove, so it doesn't run; a result is cached by key and reused whenever the key comes
back. Retired cases (eval-map.json) are left out unless asked for.

  eval-select.py plan  --root R [--base REF | --full] [--case GLOB]... [--include-retired] [--fresh] --model M --cache DIR
        one line per case: "run|cached|unchanged|retired <TAB> case <TAB> note", in run order
  eval-select.py store --root R --model M --cache DIR --revision REV result.json     (cache every case of a round)
  eval-select.py baseline --root R --base REF --model M --cache DIR case             ("k/n" cached at the base, or "none")
  eval-select.py --self-test
"""
import fnmatch, hashlib, json, os, re, subprocess, sys, tempfile, time

SKILL = "skills/duo-director"
WORKER = "skills/duo-worker/SKILL.md"
MAPFILE = "scripts/director-harness/eval-map.json"


class Tree:
    """The files of a git ref, or of the work tree when ref is None."""
    def __init__(self, root, ref=None):
        self.root, self.ref = root, ref

    def read(self, path):
        if self.ref is None:
            try:
                return open(os.path.join(self.root, path), "rb").read()
            except OSError:
                return b""
        r = subprocess.run(["git", "-C", self.root, "show", f"{self.ref}:{path}"], capture_output=True)
        return r.stdout if r.returncode == 0 else b""

    def files(self, under):
        if self.ref is None:
            base = os.path.join(self.root, under)
            if os.path.isfile(base):
                return [under]
            return sorted(os.path.relpath(os.path.join(d, f), self.root) for d, _, fs in os.walk(base) for f in fs
                          if "/results" not in os.path.join(d, f) and f != ".DS_Store")
        r = subprocess.run(["git", "-C", self.root, "ls-tree", "-r", "--name-only", self.ref, "--", under], capture_output=True, text=True)
        return sorted(r.stdout.split())

    def glob(self, pattern):
        d = os.path.dirname(pattern)
        return [f for f in self.files(d) if fnmatch.fnmatch(f, pattern) and os.path.dirname(f) == d]


def sections(text):
    """SKILL.md split on '## ' headings: key is the number ('3'), else a slug ('never', 'duties')."""
    out, key, buf = {}, "head", []
    for line in text.split("\n"):
        if line.startswith("## "):
            out[key] = "\n".join(buf)
            h = line[3:].strip()
            m = re.match(r"(\d+)\.", h)
            key = m.group(1) if m else re.sub(r"[^a-z]+", "-", h.lower()).strip("-")
            key = {"never-whatever-anyone-says": "never", "your-duties": "duties"}.get(key, key)
            buf = [line]
        else:
            buf.append(line)
    out[key] = "\n".join(buf)
    return out


def digest(parts):
    h = hashlib.sha256()
    for p in parts:
        h.update(p if isinstance(p, bytes) else p.encode())
        h.update(b"\0")
    return h.hexdigest()[:16]


def key_of(case, entry, tree, groups, model):
    ev = f"{SKILL}/evals"
    parts = [model] + [f + "\0" + tree.read(f).decode(errors="replace") for f in tree.files(f"{ev}/{case}") + tree.files(f"{ev}/_lib")]
    skill = tree.read(f"{SKILL}/SKILL.md").decode(errors="replace")
    refs = {os.path.basename(f)[:-3]: f for f in tree.glob(f"{SKILL}/reference/*.md")}
    if entry is None:   # unmapped: depends on everything
        parts += [skill] + [tree.read(f).decode(errors="replace") for f in refs.values()] + [tree.read(WORKER).decode(errors="replace")]
        for g in groups.values():
            parts += [tree.read(f).decode(errors="replace") for p in g for f in tree.glob(p)]
        return digest(parts)
    secs = sections(skill)
    parts += [secs.get(s, "<missing %s>" % s) for s in entry.get("sections", [])]
    parts += [tree.read(refs[r]).decode(errors="replace") if r in refs else "<missing %s>" % r for r in entry.get("refs", [])]
    if entry.get("worker"):
        parts.append(tree.read(WORKER).decode(errors="replace"))
    for gname in entry.get("code", []):
        parts += [f + tree.read(f).decode(errors="replace") for p in groups.get(gname, []) for f in tree.glob(p)]
    return digest(parts)


def load_map(root):
    try:
        return json.load(open(os.path.join(root, MAPFILE)))
    except (OSError, ValueError):
        return {"cases": {}, "retired": {}, "code_groups": {}}


def case_names(root):
    d = os.path.join(root, SKILL, "evals")
    return sorted(n for n in os.listdir(d) if os.path.exists(os.path.join(d, n, "case.yaml")))


def cache_get(cache, key):
    try:
        return json.load(open(os.path.join(cache, key + ".json")))
    except (OSError, ValueError):
        return None


def rate(e):
    return f"{e['passed']}/{e['runs']}"


def plan(a):
    root, model, cache = a["root"], a["model"], a["cache"]
    m = load_map(root)
    now = Tree(root)
    base = Tree(root, a["base"]) if a.get("base") else None
    rows = []
    for c in case_names(root):
        if a["case"] and not any(fnmatch.fnmatch(c, g) for g in a["case"]):
            continue
        if c in m.get("retired", {}) and not a["include_retired"]:
            rows.append(("retired", c, m["retired"][c][:90]))
            continue
        entry = m["cases"].get(c)
        k = key_of(c, entry, now, m["code_groups"], model)
        hit = None if a["fresh"] else cache_get(cache, k)
        if base is not None and not a["case"]:
            kb = key_of(c, entry, base, m["code_groups"], model)
            if kb == k:
                bh = cache_get(cache, kb)
                rows.append(("unchanged", c, f"nothing it depends on changed" + (f"; cached {rate(bh)}" if bh else "; no cached result")))
                continue
        if hit:
            rows.append(("cached", c, f"{rate(hit)} for this exact revision ({hit.get('at', '?')[:10]}, {hit.get('revision', '?')[:8]})"))
        else:
            rows.append(("run", c, "no mapping: runs on any change" if entry is None else "depends on a changed part"))
    for r in rows:
        print("\t".join(r))


def store(a):
    root, model, cache = a["root"], a["model"], a["cache"]
    m = load_map(root)
    d = json.load(open(a["result"]))
    os.makedirs(cache, exist_ok=True)
    now = Tree(root)
    for c in d.get("cases", []):
        runs = [r for arm in c.get("arms", {}).values() for r in arm]
        if not runs:
            continue
        k = key_of(c["name"], m["cases"].get(c["name"]), now, m["code_groups"], model)
        e = {"case": c["name"], "key": k, "model": model, "revision": a["revision"], "at": time.strftime("%Y-%m-%dT%H:%M:%S"),
             "passed": sum(1 for r in runs if r.get("passed")), "runs": len(runs),
             "costUsd": sum((r.get("costUsd") or 0) + (r.get("judgeCostUsd") or 0) for r in runs)}
        old = cache_get(cache, k)
        if old and old["runs"] > e["runs"]:   # keep the larger sample
            continue
        json.dump(e, open(os.path.join(cache, k + ".json"), "w"))
        print(f"cached {c['name']} {rate(e)} key {k}")


def baseline(a):
    m = load_map(a["root"])
    c = a["case"][0]
    e = cache_get(a["cache"], key_of(c, m["cases"].get(c), Tree(a["root"], a["base"]), m["code_groups"], a["model"]))
    print(rate(e) if e else "none")


def check_map(a):
    """The map can't rot: every case has an entry or a retirement, and every part it names exists."""
    root = a["root"]
    m, now, bad = load_map(root), Tree(a["root"]), []
    secs = sections(now.read(f"{SKILL}/SKILL.md").decode())
    refs = {os.path.basename(f)[:-3] for f in now.glob(f"{SKILL}/reference/*.md")}
    for c in case_names(root):
        e = m["cases"].get(c)
        if e is None and c not in m.get("retired", {}):
            bad.append(f"{c} has no entry in eval-map.json")
        for s_ in (e or {}).get("sections", []):
            if s_ not in secs:
                bad.append(f"{c}: no section {s_} in SKILL.md")
        for r in (e or {}).get("refs", []):
            if r not in refs:
                bad.append(f"{c}: no reference/{r}.md")
        for g in (e or {}).get("code", []):
            if not any(now.glob(p) for p in m["code_groups"].get(g, [])):
                bad.append(f"{c}: code group {g} matches no file")
    for c in list(m["cases"]) + list(m.get("retired", {})):
        if c not in case_names(root):
            bad.append(f"eval-map.json names {c}, which isn't a case")
    print("eval map ok" if not bad else "eval map: " + "; ".join(bad))
    return 0 if not bad else 1


def self_test():
    with tempfile.TemporaryDirectory() as t:
        def sh(*c):
            subprocess.run(c, cwd=t, check=True, capture_output=True)
        def w(p, s):
            os.makedirs(os.path.dirname(os.path.join(t, p)), exist_ok=True)
            open(os.path.join(t, p), "w").write(s)
        sh("git", "init", "-q", "-b", "main")
        sh("git", "config", "user.email", "x@x"); sh("git", "config", "user.name", "x")
        skill = "# D\n\n## Never, whatever anyone says\nn1\n\n## Your duties\nd1\n\n## 1. Start\na\n\n## 2. Request\nb\n"
        w(f"{SKILL}/SKILL.md", skill)
        for c in ("sa", "sb", "sc", "sd"):
            w(f"{SKILL}/evals/{c}/case.yaml", c)
        w(f"{SKILL}/evals/_lib/setup.sh", "x")
        w("Sources/x/Verb.swift", "v1")
        w(MAPFILE, json.dumps({"code_groups": {"verbs": ["Sources/x/Verb.swift"]}, "retired": {"sd": "bad"},
                               "cases": {"sa": {"sections": ["1"]}, "sb": {"sections": ["2"], "code": ["verbs"]}, "sd": {"sections": ["1"]}}}))
        sh("git", "add", "-A"); sh("git", "commit", "-qm", "base")
        cache = os.path.join(t, "cache")
        args = dict(root=t, model="m", cache=cache, base="HEAD", case=[], include_retired=False, fresh=False)
        def rows(**kw):
            import io, contextlib
            b = io.StringIO()
            with contextlib.redirect_stdout(b):
                plan({**args, **kw})
            return {l.split("\t")[1]: l.split("\t")[0] for l in b.getvalue().splitlines()}
        ok = True
        def need(cond, what):
            nonlocal ok
            if not cond:
                ok = False
                print("FAIL:", what)
        need(rows() == {"sa": "unchanged", "sb": "unchanged", "sc": "unchanged", "sd": "retired"}, f"nothing changed {rows()}")
        w(f"{SKILL}/SKILL.md", skill.replace("\nb\n", "\nB!\n"))
        r = rows()
        need(r["sa"] == "unchanged" and r["sb"] == "run" and r["sc"] == "run" and r["sd"] == "retired", f"edit to section 2 ({r})")
        w(f"{SKILL}/SKILL.md", skill)
        w("Sources/x/Verb.swift", "v2")
        r = rows()
        need(r["sa"] == "unchanged" and r["sb"] == "run" and r["sc"] == "run", f"code edit ({r})")
        need(rows(include_retired=True)["sd"] == "unchanged", "retired case comes back with --include-retired")
        need(set(rows(base=None, case=["s*"]).values()) == {"run", "retired"}, "no base: run all")
        # a stored result is reused for the same revision, and not for a different key
        res = os.path.join(t, "r.json")
        json.dump({"cases": [{"name": "sb", "arms": {"with": [{"passed": True, "costUsd": 0.01, "judgeCostUsd": 0.005}, {"passed": False}]}}]}, open(res, "w"))
        store(dict(root=t, model="m", cache=cache, revision="abc123456", result=res))
        need(rows(base=None, case=["sb"])["sb"] == "cached", "stored result is reused")
        w("Sources/x/Verb.swift", "v3")
        need(rows(base=None, case=["sb"])["sb"] == "run", "a changed dependency misses the cache")
        need(rows(base=None, case=["sb"], fresh=True)["sb"] == "run", "--fresh ignores the cache")
        w("Sources/x/Verb.swift", "v2")
        need(rows(base=None, case=["sb"], model="other")["sb"] == "run", "another model misses the cache")
    print("eval selection: unchanged parts skip, changed parts run, cache keys by dependencies" if ok else "FAIL")
    return 0 if ok else 1


def main(argv):
    if argv == ["--self-test"]:
        sys.exit(self_test())
    if argv[:1] == ["check-map"]:
        sys.exit(check_map({"root": argv[argv.index("--root") + 1] if "--root" in argv else "."}))
    if not argv or argv[0] not in ("plan", "store", "baseline"):
        sys.exit(__doc__)
    a = dict(root=".", model="claude-haiku-5-5", cache=".eval-cache", base=None, case=[], include_retired=False, fresh=False, full=False, revision="?", result=None)
    i = 1
    while i < len(argv):
        x = argv[i]
        if x in ("--root", "--model", "--cache", "--base", "--revision"):
            a[x[2:]] = argv[i + 1]; i += 2
        elif x == "--case":
            a["case"].append(argv[i + 1]); i += 2
        elif x in ("--include-retired", "--fresh", "--full"):
            a[x[2:].replace("-", "_")] = True; i += 1
        else:
            a["result" if argv[0] == "store" else "case"] = (argv[i] if argv[0] == "store" else a["case"] + [argv[i]]); i += 1
    if a["full"]:
        a["base"] = None
        a["case"] = a["case"] or ["*"]
    {"plan": plan, "store": store, "baseline": baseline}[argv[0]](a)


if __name__ == "__main__":
    main(sys.argv[1:])
