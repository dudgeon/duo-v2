#!/usr/bin/env python3
"""What a director eval round really cost: the agent's runs plus their judges (F-740).

`claude plugin eval` writes `costUsd` for the agent's runs only; each run's LLM judge is billed apart, in
`judgeCostUsd`, about half as much again. Every spend we report adds the two.

  eval-cost.py <result.json>                    one round: a line per case, then the round's total
  eval-cost.py --history <file|folder>...       every round found (deduplicated: run-evals.sh writes each round
                                                twice), oldest first, with the grand total
  eval-cost.py --total <result.json>...         the summed spend (runs + judges) as a bare number, for run-evals.sh's cap
  eval-cost.py --missed <result.json> | --rate <result.json> <case>   exit 0 on any miss | "k/n" for a case
  eval-cost.py --merge <out.json> <in.json>...  one result.json from several (each case once, the last file's wins)
  eval-cost.py --self-test                      proves the total includes the judges (DuoChecks runs it)
"""
import json, os, sys


def runs_of(case):
    for runs in case.get("arms", {}).values():
        for r in runs:
            yield r


def case_cost(case):
    """(runs, judges, total, n) for one case."""
    rs = list(runs_of(case))
    run = sum(r.get("costUsd") or 0 for r in rs)
    judge = sum(r.get("judgeCostUsd") or 0 for r in rs)
    return run, judge, run + judge, len(rs)


def round_cost(d):
    run = judge = 0.0
    for c in d.get("cases", []):
        r, j, _, _ = case_cost(c)
        run += r
        judge += j
    return run, judge, run + judge


def is_director_round(d):
    root = (d.get("suite") or {}).get("root", "") if isinstance(d.get("suite"), dict) else ""
    return root.rstrip("/").endswith("skills/duo-director") and "cases" in d


def report(d, out=sys.stdout):
    for c in d.get("cases", []):
        r, j, t, n = case_cost(c)
        passed = sum(1 for x in runs_of(c) if x.get("passed"))
        print(f"  {c['name']:<36} {passed}/{n}  ${t:.3f}  (runs ${r:.3f} + judge ${j:.3f})", file=out)
    r, j, t = round_cost(d)
    print(f"Round cost: ${t:.2f} (runs ${r:.2f} + judges ${j:.2f}; costUsd alone leaves out the judges)", file=out)


def files_under(paths):
    for p in paths:
        if os.path.isdir(p):
            for d, _, fs in os.walk(p):
                for f in fs:
                    if f in ("result.json", "aggregate-result.json"):
                        yield os.path.join(d, f)
        else:
            yield p


def history(paths):
    rounds = {}
    for f in files_under(paths):
        try:
            d = json.load(open(f))
        except (OSError, ValueError):
            continue
        if not isinstance(d, dict) or not is_director_round(d):
            continue
        key = (d.get("startedAt"), tuple(c["name"] for c in d["cases"]))
        rounds.setdefault(key, (d, f))
    total = [0.0, 0.0]
    for (started, names), (d, f) in sorted(rounds.items(), key=lambda kv: kv[0][0] or ""):
        r, j, t = round_cost(d)
        total[0] += r
        total[1] += j
        what = names[0] if len(names) == 1 else f"{len(names)} cases"
        n = sum(case_cost(c)[3] for c in d["cases"])
        print(f"{(started or '?')[:16]}  {what:<36} {n:>3} runs  ${t:.3f}  (costUsd ${r:.3f} + judge ${j:.3f})  {f}")
    print(f"{len(rounds)} rounds: ${total[0] + total[1]:.2f} (costUsd ${total[0]:.2f} + judges ${total[1]:.2f})")


def self_test():
    d = {"suite": {"root": "/x/skills/duo-director"}, "costUsd": 0.03, "cases": [
        {"name": "a", "arms": {"with": [{"passed": True, "costUsd": 0.01, "judgeCostUsd": 0.005},
                                        {"passed": False, "costUsd": 0.02, "judgeCostUsd": 0.01}]}}]}
    r, j, t = round_cost(d)
    ok = abs(t - 0.045) < 1e-9 and abs(j - 0.015) < 1e-9 and abs(r - d["costUsd"]) < 1e-9
    print("total includes judgeCostUsd" if ok else f"FAIL: total {t} (runs {r}, judge {j})")
    return 0 if ok else 1


if __name__ == "__main__":
    a = sys.argv[1:]
    if a and a[0] == "--total":
        print(f"{sum(round_cost(json.load(open(f)))[2] for f in a[1:]):.4f}")
        sys.exit(0)
    if a and a[0] == "--missed":      # exit 0 if some run in the round did not pass
        sys.exit(0 if any(not r.get("passed") for c in json.load(open(a[1]))["cases"] for r in runs_of(c)) else 1)
    if a and a[0] == "--rate":        # k/n for one case
        for c in json.load(open(a[1]))["cases"]:
            if c["name"] == a[2]:
                rs = list(runs_of(c))
                print(f"{sum(1 for r in rs if r.get('passed'))}/{len(rs)}")
        sys.exit(0)
    if a and a[0] == "--merge":
        ds = [json.load(open(f)) for f in a[2:]]
        byname = {c["name"]: c for d in ds for c in d.get("cases", [])}
        out = dict(ds[0]) if ds else {}
        out["cases"] = [byname[k] for k in sorted(byname)]
        json.dump(out, open(a[1], "w"))
        sys.exit(0)
    if a == ["--self-test"]:
        sys.exit(self_test())
    if a and a[0] == "--history":
        history(a[1:])
    elif len(a) == 1:
        report(json.load(open(a[0])))
    else:
        sys.exit(__doc__)
