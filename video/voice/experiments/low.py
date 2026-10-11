"""voice3: low-pitched narrator candidates. .venv/bin/python -I experiments/low.py design|clone"""
import json, sys
from pathlib import Path
import numpy as np, soundfile as sf
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import tts
OUT = Path("/private/tmp/claude-501/-Users-geoff-repos-duo-v2/843380b2-bd65-4948-a0c2-2046c49a0953/scratchpad/voice3"); OUT.mkdir(parents=True, exist_ok=True)
SR = 24000
REF = ("Last weekend I finally walked to the market by the river. The air was cool, and the bread smelled wonderful. "
       "I stayed far longer than planned. Have you ever done that?")
PASSAGE = ("Duo vee two is built around your projects. Each one keeps its sessions, its documents and what needs you, together. "
           "So you can pick up where you left off, in any of them. And use Claude to move your own work forward.")
EXPECT = PASSAGE.replace("vee two", "v2")
F = ["a low, warm, slightly husky alto woman in her late thirties, deep low-pitched chest voice, lower register, relaxed and conversational, smiling, unhurried, with natural rises and falls; like a documentary narrator talking to one person",
     "a deep, low-pitched, warm alto woman in her forties, lower register, calm and friendly, gentle smile, natural intonation, a little breathy and husky, speaking to a friend"]
M = ["a warm, relaxed baritone man in his late thirties, deep low-pitched chest voice, friendly and conversational, slight smile, natural intonation, not a movie-trailer voice, not an advert",
     "a deep, low-pitched, warm baritone man in his forties, lower register, calm and easygoing, gentle smile, natural rises and falls, talking to a friend, not an advert"]
CANDS = {"F1": (F[0], (155, 182)), "F2": (F[1], (155, 182)), "M1": (M[0], (95, 125)), "M2": (M[1], (95, 125))}

def f0_track(x, sr, fmin=70, fmax=400, hop=0.01, win=0.04):
    n, h = int(win * sr), int(hop * sr); lo, hi = int(sr / fmax), int(sr / fmin); f0 = []
    for s in range(0, len(x) - n * 2, h):
        fr = x[s:s + n * 2]; fr = fr - fr.mean()
        if np.sqrt((fr ** 2).mean()) < 0.01: f0.append(np.nan); continue
        ac = np.correlate(fr, fr, "full")[len(fr) - 1:]; ac = ac / (ac[0] + 1e-9)
        seg = ac[lo:hi]; k = int(seg.argmax()); f0.append(sr / (lo + k) if seg[k] > 0.45 else np.nan)
    return np.array(f0)

def stats(x, sr):
    f0 = f0_track(x, sr, fmin=60); v = f0[~np.isnan(f0)]; med = np.median(v); v = v[(v > med / 1.6) & (v < med * 1.6)]
    st = 12 * np.log2(v / np.median(v)); hop = int(0.02 * sr)
    rms = np.array([np.sqrt((x[i:i + hop] ** 2).mean()) for i in range(0, len(x) - hop, hop)]); db = 20 * np.log10(rms + 1e-6)
    return float(np.median(v)), float(st.std()), float(db[db > db.max() - 35].std())

def gen(model, text, seed, **kw):
    import mlx.core as mx
    mx.random.seed(seed)
    return np.concatenate([np.array(r.audio, dtype=np.float32) for r in model.generate(text=text, lang_code="english", **kw)])

def design():
    m = tts.load("design"); log = []
    for cid, (desc, (lo, hi)) in CANDS.items():
        for i, seed in enumerate([3, 7, 11, 21, 42, 5, 77, 101]):
            d = desc if i < 4 else desc.replace("deep low-pitched", "very deep, low-pitched, resonant").replace("deep, low-pitched", "very deep, low-pitched, resonant")
            a = gen(m, REF, seed, instruct=d); f, sd, _ = stats(a, SR); dur = len(a) / SR
            ok = lo <= f <= hi and 8 <= dur <= 15
            print(cid, seed, i, round(f), round(sd, 2), round(dur, 1), "OK" if ok else "", flush=True)
            log.append(dict(cid=cid, seed=seed, f0=f, dur=dur, desc=d))
            if ok:
                sf.write(OUT / f"{cid}-ref.wav", a, SR, subtype="PCM_16")
                json.dump(dict(id=cid, description=d, seed=seed, transcript=REF, f0_med_hz=round(f), duration_s=round(dur, 2)), open(OUT / f"{cid}-ref.json", "w"), indent=1)
                break
    json.dump(log, open(OUT / "design-log.json", "w"), indent=1)

def clone():
    m = tts.load("clone")
    for cid in CANDS:
        if not (OUT / f"{cid}-ref.json").exists(): print("no ref", cid); continue
        r = json.load(open(OUT / f"{cid}-ref.json"))
        a = gen(m, PASSAGE, 11, ref_audio=str(OUT / f"{cid}-ref.wav"), ref_text=REF)
        sf.write(OUT / f"{cid}-clone.wav", a, SR, subtype="PCM_16")
        json.dump(dict(id=f"{cid}-clone", text=PASSAGE, expect=EXPECT, seed=11), open(OUT / f"{cid}-clone.json", "w"), indent=1)
        print(cid, round(len(a) / SR, 1), flush=True)
if __name__ == "__main__": {"design": design, "clone": clone}[sys.argv[1]]()
