"""Assemble voice-samples: D post-process, naming, combined files, metrics. .venv/bin/python -I experiments/upbeat_finish.py"""
import json, subprocess, sys, shutil
from pathlib import Path
import numpy as np, soundfile as sf
sys.path.insert(0, str(Path(__file__).resolve().parent))
from low import stats
from upbeat import OUT, SR
W = OUT / "work"
NAMES = {"A": "A-current", "B2": "B-brighter", "C": "C-lively", "B3": "E-milder", "D": "D-tempo"}
# D: A at +5% tempo, +0.5 semitone: asetrate raises pitch+speed by 2^(0.5/12); atempo supplies the rest
r = 2 ** (0.5 / 12); (W / "D").mkdir(exist_ok=True)
for i in (1, 2, 3):
    src = W / "A" / f"A-{i}.wav"; dst = W / "D" / f"D-{i}.wav"
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(src), "-af", f"asetrate={SR*r:.2f},aresample={SR},atempo={1.05/r:.5f}", "-ar", str(SR), "-ac", "1", str(dst)], check=True)
    meta = json.load(open(W / "A" / f"A-{i}.json")); meta["id"] = f"D-{i}"; json.dump(meta, open(W / "D" / f"D-{i}.json", "w"))
for k, name in NAMES.items():
    parts = []
    for i in (1, 2, 3):
        x, sr = sf.read(W / k / f"{k}-{i}.wav", dtype="float32"); parts += [x]
        shutil.copy(W / k / f"{k}-{i}.wav", OUT / f"{name}-{i}.wav")
    gap = np.zeros(int(0.6 * SR), dtype="float32"); comb = np.concatenate([parts[0], gap, parts[1], gap, parts[2]])
    sf.write(OUT / f"{name}-all.wav", comb, SR, subtype="PCM_16")
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(OUT / f"{name}-all.wav"), "-c:a", "aac", "-b:a", "128k", str(OUT / f"{name}-all.m4a")], check=True)
    print(name, "all F0 %.0f" % stats(comb, SR)[0], "dur %.1f" % (len(comb) / SR))
