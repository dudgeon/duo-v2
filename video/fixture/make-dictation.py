#!/usr/bin/env python3
"""The 0.2.22 film's dictation (films/release-0-2-22): what Sam says into the mic, as spoken audio the real recognizer
hears (VideoTargets+Voice.swift feeds it through voice input's file path, at the pace it was spoken).

Spoken by the house voice (voice/house, a designed voice, nobody's real one), a phrase per take with the short pause a
person leaves between phrases, so the recognizer settles them one at a time as it does from a microphone.
  voice/.venv/bin/python -I fixture/make-dictation.py      (from video/)
writes fixture/dictation/<id>.wav (16-bit mono) and dictation.json (the words, for the shots and the report).
"""
import json, os, subprocess, sys, tempfile
import numpy as np, soundfile as sf

HERE = os.path.dirname(os.path.abspath(__file__))
VIDEO = os.path.dirname(HERE)
OUT = os.path.join(HERE, "dictation")
TAKES = {
    "chat": ["Can you check the glare cases against Denise's photos", "and tell me which ones still fail?"],
    "terminal": ["Add a glare warning to the scan screen", "and keep it under ten words."],
}
PAUSE, LEAD, TAIL = 0.7, 0.4, 0.9   # seconds: between phrases, before the first, after the last

house = json.load(open(os.path.join(VIDEO, "voice/house/voice.json")))
lines = [{"id": f"{k}-{i}", "text": t} for k, ts in TAKES.items() for i, t in enumerate(ts)]
with tempfile.TemporaryDirectory() as tmp:
    job = {"lines": lines, "out_dir": tmp,
           "voice": {"mode": "clone", "ref_wav": os.path.join(VIDEO, "voice", house["ref_wav"]), "ref_text": house["ref_text"], "seed": house["seed"]}}
    jp = os.path.join(tmp, "job.json"); json.dump(job, open(jp, "w"))
    subprocess.run([os.path.join(VIDEO, "voice/.venv/bin/python"), "-I", os.path.join(VIDEO, "voice/tts.py"), jp], check=True)
    os.makedirs(OUT, exist_ok=True)
    meta = {}
    for k, ts in TAKES.items():
        parts, sr = [], None
        for i in range(len(ts)):
            a, sr = sf.read(os.path.join(tmp, f"{k}-{i}.wav"))
            parts += [a, np.zeros(int(PAUSE * sr))] if i < len(ts) - 1 else [a]
        audio = np.concatenate([np.zeros(int(LEAD * sr))] + parts + [np.zeros(int(TAIL * sr))])
        sf.write(os.path.join(OUT, f"{k}.wav"), audio, sr, subtype="PCM_16")
        meta[k] = {"phrases": ts, "text": " ".join(ts), "duration_s": round(len(audio) / sr, 3)}
    json.dump(meta, open(os.path.join(OUT, "dictation.json"), "w"), indent=1)
    print(json.dumps(meta, indent=1))
