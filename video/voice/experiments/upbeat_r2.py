"""Round 2: +10% tempo (atempo only) on B-brighter and three lighter clones. .venv/bin/python -I experiments/upbeat_r2.py"""
import json, subprocess, sys, shutil
from pathlib import Path
import numpy as np, soundfile as sf
sys.path.insert(0, str(Path(__file__).resolve().parent))
from low import stats
from upbeat import OUT, SR
W = OUT / "work"
TEMPO = 1.10
SRC = {"B-fast": "B2", "L20": "L20", "L7": "L7", "L14x12": "L14x12", "L3": "L3"}  # source work dirs
OVR = {"L20": "rr_L20_13", "L7": "rr_L7_13"}  # line-2 re-rolls (clone seed 13): line 2 broke the 4.0 wps cap after the tempo
def srcwav(k, i):
    if i == 2 and k in OVR: return W / OVR[k] / f"{OVR[k]}-2.wav"
    return W / k / f"{k}-{i}.wav"
def comb(k):
    parts = []
    for i in (1, 2, 3):
        x, _ = sf.read(srcwav(k, i), dtype="float32"); parts += [x, np.zeros(int(.6 * SR), dtype="float32")]
    return np.concatenate(parts[:-1])
names = {}
for key, src in SRC.items():
    if key == "B-fast": name = "B-fast"
    else: name = "B-light-%d" % round(stats(comb(src)[:-int(.6 * SR)], SR)[0])
    names[key] = name
    d = W / name; d.mkdir(exist_ok=True)
    for i in (1, 2, 3):
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(srcwav(src, i)), "-af", f"atempo={TEMPO}", "-ar", str(SR), "-ac", "1", str(d / f"{name}-{i}.wav")], check=True)
        meta = json.load(open(W / src / f"{src}-{i}.json")); meta["seed"] = 13 if (i == 2 and src in OVR) else meta["seed"]; meta["id"] = f"{name}-{i}"; json.dump(meta, open(d / f"{name}-{i}.json", "w"))
    parts = []
    for i in (1, 2, 3):
        x, _ = sf.read(d / f"{name}-{i}.wav", dtype="float32"); shutil.copy(d / f"{name}-{i}.wav", OUT / f"{name}-{i}.wav"); parts += [x, np.zeros(int(.6 * SR), dtype="float32")]
    c = np.concatenate(parts[:-1]); sf.write(OUT / f"{name}-all.wav", c, SR, subtype="PCM_16")
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(OUT / f"{name}-all.wav"), "-c:a", "aac", "-b:a", "128k", str(OUT / f"{name}-all.m4a")], check=True)
    print(key, name, "F0 %.0f spread %.2f dur %.1f" % (*stats(c, SR)[:2], len(c) / SR))
json.dump(names, open(W / "r2-names.json", "w"))
