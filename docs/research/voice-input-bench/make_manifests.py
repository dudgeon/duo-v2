#!/usr/bin/env python3
"""Builds the synthetic test set with macOS `say`, and the manifests (see SPEC.md).

Synthetic audio and its manifest go to ~/Library/Caches/duo-voice-input/. With --takes, the manifest of a private
set of recorded takes (read in place from $TAKES_DIR, never copied) goes to $CLAUDE_JOB_DIR/tmp/private/.
"""
import argparse, json, os, subprocess
from pathlib import Path

BENCH = Path(__file__).resolve().parent
CACHE = Path.home() / "Library/Caches/duo-voice-input"
VOICES = ["Samantha", "Daniel", "Karen", "Rishi"]


def synth():
    out = CACHE / "audio/synth"
    out.mkdir(parents=True, exist_ok=True)
    rows = []
    for line in (BENCH / "utterances.jsonl").read_text().splitlines():
        u = json.loads(line)
        for voice in VOICES:
            wav = out / f"{u['id']}_{voice}.wav"
            if not wav.exists():
                subprocess.run(["say", "-v", voice, "--file-format=WAVE", "--data-format=LEI16@16000",
                                "-o", str(wav), u["spoken"]], check=True)
            rows.append({"id": f"{u['id']}_{voice}", "wav": str(wav), "ref": u["spoken"],
                         "written": u.get("written", u["spoken"]), "terms": u["terms"]})
    (CACHE / "manifests").mkdir(exist_ok=True)
    path = CACHE / "manifests/synth.jsonl"
    path.write_text("".join(json.dumps(r) + "\n" for r in rows))
    print(f"{len(rows)} clips -> {path}")


def takes():
    private = Path(os.environ["CLAUDE_JOB_DIR"]) / "tmp/private"
    private.mkdir(parents=True, exist_ok=True)
    rows = []
    # TAKES_DIR: a private folder outside this repo, with <name>.wav and <name>.json {"text": …} pairs.
    for wav in sorted(Path(os.environ["TAKES_DIR"]).glob("**/*.wav")):
        text = json.loads(wav.with_suffix(".json").read_text())["text"]
        rows.append({"id": wav.stem, "wav": str(wav), "ref": text, "written": text, "terms": []})
    path = private / "takes.jsonl"
    path.write_text("".join(json.dumps(r) + "\n" for r in rows))
    print(f"{len(rows)} takes -> {path}")


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--takes", action="store_true")
    a = p.parse_args()
    takes() if a.takes else synth()
