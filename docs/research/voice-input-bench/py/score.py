#!/usr/bin/env python3
"""Scorer for the voice-input benchmark (see ../SPEC.md, Scoring).

usage: score.py --manifest M.jsonl [--set NAME] [--summary-dir DIR] [--models-dir DIR]
                RESULTS.jsonl [name=RESULTS2.jsonl ...]
Each results file is one engine+mode run; the engine name is the file stem unless
given as name=path. Reads <results>.time (from run.sh) for peak RSS if present.
Only summaries are written (never per-clip detail), so it is safe on the takes set.
Model size on disk: du of <models-dir>/<name>, dropping trailing '.tag' parts until a folder exists.
"""
import argparse, json, os, re, statistics, subprocess

KEEP = set(".-/_@")


def normalise(s):
    s = (s or "").lower()
    for a, b in (("‘", "'"), ("’", "'"), ("‛", "'"), ("“", '"'), ("”", '"')):
        s = s.replace(a, b)
    out = []
    n = len(s)
    for i, c in enumerate(s):
        if c.isalnum():
            out.append(c)
        elif c in KEEP and 0 < i < n - 1 and s[i - 1].isalnum() and s[i + 1].isalnum():
            out.append(c)
        elif c == "'":
            continue  # apostrophes vanish on both sides alike
        else:
            out.append(" ")
    return " ".join("".join(out).split())


def lev(a, b):
    if not a:
        return len(b)
    if not b:
        return len(a)
    prev = list(range(len(b) + 1))
    for i, x in enumerate(a, 1):
        cur = [i]
        for j, y in enumerate(b, 1):
            cur.append(min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (x != y)))
        prev = cur
    return prev[-1]


def compact(s):
    return re.sub(r"[^a-z0-9]", "", (s or "").lower())


def strict(s):
    return re.sub(r"[^a-z0-9.\-/_@]", "", (s or "").lower())


def pct(vals, p):
    if not vals:
        return None
    v = sorted(vals)
    return v[max(0, min(len(v) - 1, int(round(p / 100 * (len(v) - 1)))))]


def read_jsonl(p):
    with open(p) as f:
        return [json.loads(l) for l in f if l.strip()]


def parse_time(path):
    info = {}
    if not os.path.exists(path):
        return info
    txt = open(path).read()
    m = re.search(r"(\d+)\s+maximum resident set size", txt)
    if m:
        info["peak_rss_mb"] = round(int(m.group(1)) / 1048576, 1)
    m = re.search(r"([\d.]+)\s+real", txt)
    if m:
        info["wall_s"] = float(m.group(1))
    return info


def du_mb(path):
    if not path or not os.path.exists(path):
        return None
    try:
        return round(int(subprocess.check_output(["du", "-sk", path]).split()[0]) / 1024, 1)
    except Exception:
        return None


def score(manifest, results, path):
    mrows = {r["id"]: r for r in manifest}
    ed = rw = wed = wrw = bed = 0
    th_l = th_s = tn = 0
    finals, firsts = [], []
    proc = aud = 0.0
    load_ms = None
    n = 0
    for r in results:
        if r.get("load_ms") is not None and load_ms is None:
            load_ms = r["load_ms"]
        m = mrows.get(r["id"])
        if m is None:
            continue
        n += 1
        hyp = normalise(r.get("hyp", "")).split()
        ref = normalise(m["ref"]).split()
        wri = normalise(m.get("written") or m["ref"]).split()
        e_sp, e_wr = lev(ref, hyp), lev(wri, hyp)
        ed += e_sp; rw += len(ref)
        wed += e_wr; wrw += len(wri)
        # Best-form: per clip, the fewer edits against either the spoken or the written form, so a
        # model is penalised neither for writing "Package.swift" nor for "package dot swift".
        bed += min(e_sp, e_wr)
        ch, sh = compact(r.get("hyp", "")), strict(r.get("hyp", ""))
        for t in m.get("terms") or []:
            tn += 1
            th_l += compact(t) in ch
            th_s += strict(t) in sh
        if r.get("final_ms") is not None:
            finals.append(r["final_ms"])
        if r.get("first_partial_ms") is not None:
            firsts.append(r["first_partial_ms"])
        proc += r.get("proc_ms") or 0
        aud += r.get("audio_ms") or 0
    s = {
        "n_clips": n,
        "wer": ed / rw if rw else None,
        "written_wer": wed / wrw if wrw else None,
        "best_wer": bed / rw if rw else None,
        "ref_words": rw,
        "n_terms": tn,
        "term_hit_lenient": th_l / tn if tn else None,
        "term_hit_strict": th_s / tn if tn else None,
        "final_ms_median": statistics.median(finals) if finals else None,
        "final_ms_p90": pct(finals, 90),
        "first_partial_ms_median": statistics.median(firsts) if firsts else None,
        "rtf": proc / aud if aud else None,
        "load_ms": load_ms,
    }
    s.update(parse_time(path + ".time"))
    return s


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--manifest", required=True)
    ap.add_argument("--set", default=None, help="set name (default: manifest stem)")
    ap.add_argument("--summary-dir", default=None, help="write summary-<set>.json here")
    ap.add_argument("--models-dir", default=os.path.expanduser("~/Library/Caches/duo-voice-input/models"))
    ap.add_argument("results", nargs="+")
    a = ap.parse_args()
    manifest = read_jsonl(a.manifest)
    setname = a.set or os.path.splitext(os.path.basename(a.manifest))[0]
    summaries = {}
    for spec in a.results:
        if "=" in spec and not os.path.exists(spec):
            name, path = spec.split("=", 1)
        else:
            path = spec
            name = os.path.basename(path)
            name = name[:-6] if name.endswith(".jsonl") else name
        s = score(manifest, read_jsonl(path), path)
        cands, b = [], name
        while b:
            cands.append(b)
            b = b.rsplit(".", 1)[0] if "." in b else ""
        for c in cands:
            sz = du_mb(os.path.join(a.models_dir, c))
            if sz is not None:
                s["model_size_mb"] = sz
                break
        summaries[name] = s
    if a.summary_dir:
        os.makedirs(a.summary_dir, exist_ok=True)
        with open(os.path.join(a.summary_dir, f"summary-{setname}.json"), "w") as f:
            json.dump({"set": setname, "engines": summaries}, f, indent=2)

    def fmt(v, k):
        if v is None:
            return "-"
        if k in ("wer", "best_wer", "written_wer", "term_hit_lenient", "term_hit_strict"):
            return f"{v*100:.1f}%"
        if k == "rtf":
            return f"{v:.3f}"
        if isinstance(v, float):
            return f"{v:.0f}" if abs(v) >= 100 else f"{v:.1f}"
        return str(v)

    cols = [("n_clips", "n"), ("best_wer", "WER*"), ("wer", "WER"), ("written_wer", "wWER"), ("term_hit_lenient", "term len"),
            ("term_hit_strict", "term strict"), ("final_ms_median", "final med ms"), ("final_ms_p90", "final p90 ms"),
            ("first_partial_ms_median", "1st partial ms"), ("rtf", "RTF"), ("load_ms", "load ms"),
            ("peak_rss_mb", "RSS MB"), ("model_size_mb", "disk MB")]
    print(f"Set: {setname}\n")
    print("| engine | " + " | ".join(c[1] for c in cols) + " |")
    print("|" + "---|" * (len(cols) + 1))
    for name, s in summaries.items():
        print(f"| {name} | " + " | ".join(fmt(s.get(k), k) for k, _ in cols) + " |")


if __name__ == "__main__":
    main()
