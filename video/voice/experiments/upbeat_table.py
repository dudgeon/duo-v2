import json, sys
from pathlib import Path
import soundfile as sf
sys.path.insert(0, str(Path(__file__).resolve().parent))
from low import stats
from upbeat import OUT
rows = []
for k, name in {"A": "A-current", "B2": "B-brighter", "C": "C-lively", "D": "D-tempo", "B3": "E-milder"}.items():
    asr = [json.load(open(OUT / "work" / k / f"{k}-{i}.asr.json")) for i in (1, 2, 3)]
    words = sum(len(a["words"]) for a in asr); sp = sum(a["words"][-1]["end"] - a["words"][0]["start"] for a in asr)
    x, sr = sf.read(OUT / f"{name}-all.wav", dtype="float32"); f, sd, e = stats(x, sr)
    rows.append((name, round(f), round(sd, 2), round(words / sp, 2), " ".join("PASS" if a["passed"] else "FAIL" for a in asr), round(len(x) / sr, 1), [a["seed"] for a in asr]))
    print(rows[-1])
