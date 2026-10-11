"""F0 (autocorrelation), energy and pause metrics for the voice2 samples. Run with .venv/bin/python -I."""
import json, glob, sys, subprocess
from pathlib import Path
import numpy as np, soundfile as sf
OUT = Path("/private/tmp/claude-501/-Users-geoff-repos-duo-v2/843380b2-bd65-4948-a0c2-2046c49a0953/scratchpad/voice2")

def f0_track(x, sr, fmin=70, fmax=400, hop=0.01, win=0.04):
    n, h = int(win * sr), int(hop * sr); lo, hi = int(sr / fmax), int(sr / fmin)
    f0 = []
    for s in range(0, len(x) - n * 2, h):
        fr = x[s:s + n * 2]; fr = fr - fr.mean()
        if np.sqrt((fr ** 2).mean()) < 0.01: f0.append(np.nan); continue
        ac = np.correlate(fr, fr, "full")[len(fr) - 1:]
        ac = ac / (ac[0] + 1e-9)
        seg = ac[lo:hi]; k = int(seg.argmax())
        f0.append(sr / (lo + k) if seg[k] > 0.45 else np.nan)
    return np.array(f0)

rows = {}
for p in sorted(glob.glob(str(OUT / "wav" / "*.wav"))):
    id_ = Path(p).stem
    x, sr = sf.read(p, dtype="float32")
    f0 = f0_track(x, sr); v = f0[~np.isnan(f0)]
    # median-filter-ish octave outlier removal
    med = np.median(v); v = v[(v > med / 1.6) & (v < med * 1.6)]
    st = 12 * np.log2(v / np.median(v))
    hop = int(0.02 * sr); rms = np.array([np.sqrt((x[i:i + hop] ** 2).mean()) for i in range(0, len(x) - hop, hop)])
    db = 20 * np.log10(rms + 1e-6); act = db > (db.max() - 35)
    sil = ~act; pauses = []; run = 0
    for s in sil:
        if s: run += 1
        else:
            if run * .02 >= 0.15: pauses.append(run * .02)
            run = 0
    asr = json.load(open(OUT / "wav" / f"{id_}.asr.json"))
    rows[id_] = dict(dur=round(len(x) / sr, 2), wps=asr["words_per_sec"], asr="PASS" if asr["passed"] else "FAIL",
                     f0_med_hz=round(float(med)), f0_sd_st=round(float(st.std()), 2),
                     f0_p5_p95_st=round(float(np.percentile(st, 95) - np.percentile(st, 5)), 1),
                     voiced=round(float(len(v) / max(1, len(f0))), 2),
                     energy_sd_db=round(float(db[act].std()), 2), n_pauses=len(pauses), pause_s=round(sum(pauses), 2))
json.dump(rows, open(OUT / "metrics.json", "w"), indent=1)
print(f"{'id':20}" + " ".join(f"{k:>12}" for k in next(iter(rows.values()))))
for k, r in rows.items(): print(f"{k:20}" + " ".join(f"{v:>12}" for v in r.values()))
