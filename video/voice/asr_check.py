#!/usr/bin/env python3
"""Check TTS WAVs against expected text with parakeet-mlx.
Usage (from video/voice/): .venv/bin/python -I asr_check.py <dir-with-wavs-and-json> [id ...]
Reads <id>.json (needs "text"), writes <id>.asr.json. Exit 1 if any line fails.
Pass: WER <= 0.05, no content word missing/added, 2 <= words/sec <= 3.5, no internal gap > 1.5 s.
"""
import json, os, re, sys
from pathlib import Path

os.environ["PATH"] = "/opt/homebrew/bin:" + os.environ.get("PATH", "")  # parakeet shells out to ffmpeg
MODEL = Path(os.environ.get("DUO_VIDEO_MODELS", Path.home() / "Library/Caches/duo-video/models")) / "parakeet-tdt-0.6b-v3"
STOP = set("a an the of to in on at for and or but is are was were be it its this that with as by from so".split())
ONES = "zero one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen nineteen".split()
TENS = "_ _ twenty thirty forty fifty sixty seventy eighty ninety".split()


def num_words(n):
    if n < 20: return ONES[n]
    if n < 100: return TENS[n // 10] + ("" if n % 10 == 0 else " " + ONES[n % 10])
    if n < 1000: return ONES[n // 100] + " hundred" + ("" if n % 100 == 0 else " " + num_words(n % 100))
    if n < 10000 and n % 1000 == 0: return ONES[n // 1000] + " thousand"
    return " ".join(ONES[int(c)] for c in str(n))


def norm(text):
    t = text.lower().replace("&", " and ").replace("%", " percent")
    t = re.sub(r"(\d+)", lambda m: " " + num_words(int(m.group(1))) + " ", t)
    t = re.sub(r"[^a-z' ]", " ", t.replace("-", " ")).replace("'", "")
    return t.split()


HEARD_AS = {w: name for name, heard in json.load(open(Path(__file__).with_name("heard-as.json"))).items()
            if not name.startswith("$") for w in heard if " " not in w}


def canon(words):
    return [HEARD_AS.get(w, w) for w in words]


def edit_ops(ref, hyp):
    n, m = len(ref), len(hyp)
    d = [[0] * (m + 1) for _ in range(n + 1)]
    for i in range(n + 1): d[i][0] = i
    for j in range(m + 1): d[0][j] = j
    for i in range(1, n + 1):
        for j in range(1, m + 1):
            d[i][j] = min(d[i-1][j] + 1, d[i][j-1] + 1, d[i-1][j-1] + (ref[i-1] != hyp[j-1]))
    i, j, miss, extra = n, m, [], []
    while i or j:
        if i and j and d[i][j] == d[i-1][j-1] + (ref[i-1] != hyp[j-1]):
            if ref[i-1] != hyp[j-1]: miss.append(ref[i-1]); extra.append(hyp[j-1])
            i, j = i - 1, j - 1
        elif i and d[i][j] == d[i-1][j] + 1: miss.append(ref[i-1]); i -= 1
        else: extra.append(hyp[j-1]); j -= 1
    return d[n][m], miss, extra


def words_from(result):
    words = []
    for s in result.sentences:
        for tk in s.tokens:
            if tk.text.startswith(" ") or not words:
                words.append({"word": tk.text.strip(), "start": tk.start, "end": tk.end})
            else:
                words[-1]["word"] += tk.text; words[-1]["end"] = tk.end
    return words


def main(d, ids):
    import soundfile as sf
    from parakeet_mlx import from_pretrained
    model = from_pretrained(str(MODEL))
    d = Path(d); bad = 0
    for jp in sorted(d.glob("*.json")) if not ids else [d / f"{i}.json" for i in ids]:
        if jp.name.endswith(".asr.json"): continue
        meta = json.load(open(jp)); wav = jp.with_suffix(".wav")
        dur = sf.info(wav).duration
        words = words_from(model.transcribe(wav))
        ref, hyp = norm(meta["text"]), canon(norm(" ".join(w["word"] for w in words)))
        errs, miss, extra = edit_ops(ref, hyp)
        wer = errs / max(1, len(ref))
        cmiss = [w for w in miss if w not in STOP]; cextra = [w for w in extra if w not in STOP]
        lead = words[0]["start"] if words else dur
        trail = dur - words[-1]["end"] if words else dur
        gaps = [round(b["start"] - a["end"], 2) for a, b in zip(words, words[1:])]
        spoken = (words[-1]["end"] - words[0]["start"]) if words else dur
        wps = len(words) / spoken if spoken > 0 else 0
        reasons = []
        if wer > 0.05: reasons.append(f"WER {wer:.3f}")
        if cmiss or cextra: reasons.append(f"content words missing {cmiss} / added {cextra}")
        if not 2 <= wps <= 3.5: reasons.append(f"words/sec {wps:.2f} outside 2-3.5")
        if gaps and max(gaps) > 1.5: reasons.append(f"internal silence {max(gaps)}s")
        out = dict(id=meta["id"], expected=meta["text"], heard=" ".join(w["word"] for w in words), wer=round(wer, 4),
                   words_per_sec=round(wps, 2), leading_silence_s=round(lead, 2), trailing_silence_s=round(trail, 2),
                   max_internal_gap_s=max(gaps) if gaps else 0, missing_content=cmiss, added_content=cextra,
                   duration_s=round(dur, 2), words=words, passed=not reasons, fail_reasons=reasons)
        json.dump(out, open(jp.with_suffix(".asr.json"), "w"), indent=2)
        bad += bool(reasons)
        print(f"{'PASS' if not reasons else 'FAIL'} {meta['id']}: WER {wer:.3f} wps {wps:.2f} lead {lead:.2f} trail {trail:.2f} {reasons}")
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2:])
