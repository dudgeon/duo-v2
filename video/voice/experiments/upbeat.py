"""Upbeat voice samples. .venv/bin/python -I experiments/upbeat.py refs|clone <variant...>
refs: design B/C(/E) references into the out dir. clone: clone the 3 sample lines from a variant's ref."""
import json, sys
from pathlib import Path
import numpy as np, soundfile as sf
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
sys.path.insert(0, str(Path(__file__).resolve().parent))
import tts
from low import gen, stats, REF
SR = 24000
OUT = Path(__file__).resolve().parents[2] / "out/voice-samples"
HOUSE = Path(__file__).resolve().parents[1] / "house"
BASE = "a deep, low-pitched, warm baritone man in his forties, lower register, {mood}, natural rises and falls, talking to a friend, not an advert"
BASE_L = "a warm, medium-low baritone man in his forties, {mood}, natural rises and falls, talking to a friend, not an advert"
MOODS = {
  "L": "friendly and upbeat, bright and engaged, smiling as he speaks, a little more energy",
  "B": "friendly and upbeat, bright and engaged, smiling as he speaks, a little more energy",
  "B2": "friendly and upbeat but still deep and low, bright and engaged, smiling as he speaks, a little more energy, relaxed low register",
  "B3": "warm, friendly and a little upbeat, engaged, smiling as he speaks, a touch more energy, keeping his deep low baritone",
  "C": "cheerful, lively, enthusiastic but natural, smiling as he speaks, bright and engaged",
}
LINES = ["Duo. A complete workspace for your Claude Code sessions, projects, and files.",
         "The first time you open Duo, you'll see all of your previous Claude Code sessions, and you can resume any of them.",
         "Writing is easier in chat mode too: click and drag to select, use the Mac shortcuts you already know, and see a preview of any image or text you paste."]

def refs(args):
    # args: variant seed [variant seed ...] with optional "name=mood" overrides via env-less json file
    m = tts.load("design")
    for var, seed in zip(args[::2], args[1::2]):
        mood = MOODS[var]
        desc = (BASE_L if var.startswith("L") else BASE).format(mood=mood)
        a = gen(m, REF, int(seed), instruct=desc); f, sd, _ = stats(a, SR)
        name = f"{var}-s{seed}"
        sf.write(OUT / "refs" / f"{name}.wav", a, SR, subtype="PCM_16")
        json.dump(dict(variant=var, description=desc, seed=int(seed), f0_med_hz=round(f), f0_sd_st=round(sd, 2), duration_s=round(len(a)/SR, 2)), open(OUT / "refs" / f"{name}.json", "w"), indent=1)
        print(name, round(f), round(sd, 2), round(len(a)/SR, 1), flush=True)

def clone(args):
    # args: variant refwav [seed]
    var, refwav = args[0], args[1]; seed = int(args[2]) if len(args) > 2 else 11; only = [int(x) for x in args[3].split(',')] if len(args) > 3 else []
    m = tts.load("clone"); d = OUT / "work" / var; d.mkdir(parents=True, exist_ok=True)
    for i, t in enumerate(LINES, 1):
        if only and i not in only: continue
        a = gen(m, t, seed, ref_audio=refwav, ref_text=REF)
        sf.write(d / f"{var}-{i}.wav", a, SR, subtype="PCM_16")
        json.dump(dict(id=f"{var}-{i}", text=t, seed=seed), open(d / f"{var}-{i}.json", "w"), indent=1)
        print(var, i, round(len(a)/SR, 1), "F0", round(stats(a, SR)[0]), flush=True)

if __name__ == "__main__": {"refs": refs, "clone": clone}[sys.argv[1]](sys.argv[2:])
