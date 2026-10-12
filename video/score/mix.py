#!/usr/bin/env python3
"""Sit a score under narration, with an envelope taken from the voice's own loudness.

Job: {"music":"bed.wav", "voice":[{"wav":"line.wav","at":2.0},...], "out":"mix.wav",
      "under_db":-20, "gap_db":-8, "voice_lufs":-16, "attack":0.25, "release":0.7, "hold":0.35}
The music is first set so that, in the gaps, it sits gap_db below the voice's speech loudness; while the voice
speaks it is ducked to under_db below. Speech is found from the voice track's own short-term loudness (frames
within `thresh_db` of its speech level), then smoothed (fast attack, slow release) so the music breathes
rather than pumps. The voice is normalised to voice_lufs and left untouched otherwise.
Run: .venv/bin/python -I mix.py job.json   (from video/score/)
"""
import json, subprocess, sys
import numpy as np
import soundfile as sf
from scipy.signal import resample_poly

SR = 48000


def lufs(x):
    """Integrated loudness (ffmpeg ebur128) of a float array (n, ch) at SR."""
    p = subprocess.run(["ffmpeg", "-nostats", "-f", "f32le", "-ar", str(SR), "-ac", str(x.shape[1]), "-i", "-",
                        "-af", "ebur128", "-f", "null", "-"], input=x.astype("<f4").tobytes(), capture_output=True)
    for ln in p.stderr.decode().splitlines()[::-1]:
        if ln.strip().startswith("I:"):
            return float(ln.split()[1])
    raise RuntimeError("no loudness")


def load(path):
    x, sr = sf.read(path, always_2d=True, dtype="float32")
    if sr != SR:
        x = resample_poly(x, SR, sr, axis=0).astype("float32")
    return x


def smooth(a, attack, release, fps):
    out = np.zeros_like(a); y = 0.0
    ka, kr = np.exp(-1 / (attack * fps)), np.exp(-1 / (release * fps))
    for i, v in enumerate(a):
        k = ka if v > y else kr
        y = k * y + (1 - k) * v
        out[i] = y
    return out


def main(job_path):
    j = json.load(open(job_path))
    under, gap = float(j.get("under_db", -20)), float(j.get("gap_db", -8))
    vl, thresh = float(j.get("voice_lufs", -16)), float(j.get("thresh_db", 22))
    music = load(j["music"])
    n = len(music)
    voice = np.zeros((n, 2), dtype="float32")
    segs = []
    for v in j["voice"]:
        w = load(v["wav"])
        w = np.repeat(w, 2, axis=1) if w.shape[1] == 1 else w[:, :2]
        w = w * 10 ** ((vl - lufs(w)) / 20)
        a = int(v["at"] * SR); b = min(n, a + len(w)); voice[a:b] += w[: b - a]
    # Voice loudness envelope: 20 ms frames of RMS in dB; speech = within thresh_db of the 90th-percentile level.
    hop = SR // 50
    nf = n // hop
    rms = np.sqrt((voice[: nf * hop].mean(axis=1).reshape(nf, hop) ** 2).mean(axis=1) + 1e-12)
    db = 20 * np.log10(rms)
    level = np.percentile(db[db > -70], 90)
    active = (db > level - thresh).astype(float)
    # hold the duck through short pauses between words, then smooth
    k = max(1, int(float(j.get("hold", 0.35)) * 50))
    held = np.convolve(active, np.ones(k), mode="same") > 0
    duck = smooth(held.astype(float), float(j.get("attack", 0.25)), float(j.get("release", 0.7)), 50)
    duck = np.interp(np.arange(n) / SR, (np.arange(nf) + 0.5) * hop / SR, duck)
    # music level: integrated loudness set so the gaps sit gap_db below the voice's loudness
    base = vl + gap - lufs(music)
    gain_db = base + (under - gap) * duck
    out = music * (10 ** (gain_db / 20))[:, None] + voice
    sp = np.repeat(held, hop)[:n] if len(held) * hop >= n else np.pad(np.repeat(held, hop), (0, n - len(held) * hop))
    sp = sp.astype(bool)
    mdb = lambda m: round(float(20 * np.log10(np.sqrt(((music * (10 ** (gain_db / 20))[:, None])[m] ** 2).mean()) + 1e-12)), 1)
    vdb = round(float(20 * np.log10(np.sqrt((voice[sp] ** 2).mean()) + 1e-12)), 1)
    peak = float(np.abs(out).max())
    if peak > 0.97:  # keep headroom without changing the voice/music balance
        out *= 0.97 / peak
    sf.write(j["out"], out, SR, subtype="FLOAT")
    print(json.dumps(dict(out=j["out"], music_gain_gap_db=round(base, 1), voice_lufs=vl, mix_lufs=round(lufs(out), 1),
                          peak=round(float(np.abs(out).max()), 3), speech_frac=round(float(held.mean()), 2),
                          music_rms_db_in_speech=mdb(sp), music_rms_db_in_gaps=mdb(~sp), voice_rms_db_in_speech=vdb)))


if __name__ == "__main__":
    main(sys.argv[1])
