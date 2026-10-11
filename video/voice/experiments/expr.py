"""Expressiveness experiments (voice2). Usage: .venv/bin/python -I experiments/expr.py <group>
groups: base (A,B,E-clone,G), design (C,D,E-ref), custom (F)
"""
import json, sys, os
from pathlib import Path
import numpy as np, soundfile as sf
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import tts

OUT = Path("/private/tmp/claude-501/-Users-geoff-repos-duo-v2/843380b2-bd65-4948-a0c2-2046c49a0953/scratchpad/voice2")
WAV = OUT / "wav"; WAV.mkdir(parents=True, exist_ok=True)
LINES = ["Duo v2 is built around your projects.",
         "Each one keeps its sessions, its documents and what needs you, together.",
         "So you can pick up where you left off, in any of them.",
         "And use Claude to move your own work forward."]
PASSAGE = " ".join(LINES)
EXPR = ("A warm, calm, mid-pitched woman narrator in her thirties, warm and smiling, conversational, "
        "with natural rises and falls in her pitch, a little enthusiasm on the key words, like explaining something useful to a friend.")
REF_TEXT = ("You know that moment when you sit down and can't remember where you were? "
            "Well, that's exactly what this fixes. Everything is right there, waiting for you, and honestly, it's a pretty nice feeling.")
HOUSE = Path(__file__).resolve().parent.parent / "house"
SR = 24000


def gen(model, text, seed, **kw):
    import mlx.core as mx
    mx.random.seed(seed)
    parts = [np.array(r.audio, dtype=np.float32) for r in model.generate(text=text, lang_code="english", **kw)]
    return np.concatenate(parts)


def save(id_, audio, text, extra=None):
    sf.write(WAV / f"{id_}.wav", audio, SR, subtype="PCM_16")
    json.dump(dict(id=id_, text=text, expect=text, **(extra or {})), open(WAV / f"{id_}.json", "w"), indent=1)
    print(id_, round(len(audio) / SR, 2), "s", flush=True)


def per_line(model, seed, **kw):
    gap = np.zeros(int(0.35 * SR), dtype=np.float32)
    out = []
    for i, l in enumerate(LINES):
        if i: out.append(gap)
        out.append(gen(model, l, seed, **kw))
    return np.concatenate(out)


def main(group):
    if group == "base":
        m = tts.load("clone"); v = json.load(open(HOUSE / "voice.json"))
        ck = dict(ref_audio=str(HOUSE / "reference.wav"), ref_text=v["ref_text"])
        save("A-baseline", per_line(m, 11, **ck), PASSAGE, dict(seed=11))
        save("B-clone-passage", gen(m, PASSAGE, 11, **ck), PASSAGE, dict(seed=11))
        ref = OUT / "E-reference.wav"
        if ref.exists():
            ek = dict(ref_audio=str(ref), ref_text=REF_TEXT)
            save("E-newref-passage", gen(m, PASSAGE, 11, **ek), PASSAGE, dict(seed=11))
            for t, p in [(1.0, 0.95), (1.1, 0.9)]:
                save(f"G-E-t{t}-p{p}", gen(m, PASSAGE, 11, temperature=t, top_p=p, **ek), PASSAGE, dict(seed=11))
                save(f"G-B-t{t}-p{p}", gen(m, PASSAGE, 11, temperature=t, top_p=p, **ck), PASSAGE, dict(seed=11))
    elif group == "design":
        m = tts.load("design")
        save("C-design-perline", per_line(m, 11, instruct=EXPR), PASSAGE, dict(seed=11))
        save("D-design-passage", gen(m, PASSAGE, 11, instruct=EXPR), PASSAGE, dict(seed=11))
        a = gen(m, REF_TEXT, 11, instruct=EXPR)
        sf.write(OUT / "E-reference.wav", a, SR, subtype="PCM_16")
        json.dump(dict(ref_text=REF_TEXT, instruct=EXPR, seed=11, duration_s=len(a) / SR), open(OUT / "E-reference.json", "w"), indent=1)
        print("E-reference", len(a) / SR)
        for t, p in [(1.0, 0.95), (1.1, 0.9)]:
            save(f"G-D-t{t}-p{p}", gen(m, PASSAGE, 11, instruct=EXPR, temperature=t, top_p=p), PASSAGE, dict(seed=11))
    elif group == "custom":
        m = tts.load("clone") if False else __import__("mlx_audio.tts.utils", fromlist=["x"]).load_model(str(tts.MODELS / "Qwen3-TTS-12Hz-1.7B-CustomVoice-bf16"))
        ins = "Warm, friendly and conversational, smiling, natural intonation, a little enthusiasm on the key words."
        for sp in ["serena", "vivian", "sohee"]:
            save(f"F-custom-{sp}", gen(m, PASSAGE, 11, voice=sp, instruct=ins), PASSAGE, dict(seed=11, speaker=sp))


if __name__ == "__main__":
    main(sys.argv[1])
