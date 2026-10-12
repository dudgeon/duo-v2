#!/usr/bin/env python3
"""Python ASR runners for the voice-input benchmark (see ../SPEC.md, Runner interface).

    python -I asrbench.py --engine <name> --manifest m.jsonl --out results.jsonl
                          [--mode batch|stream] [--context terms.txt] [--chunk-ms 100]

Each engine's deps live in its own venv under ~/Library/Caches/duo-voice-input/venv-<family>/
(see README.md). Models download into ~/Library/Caches/duo-voice-input/models/<engine>/
(HF_HUB_CACHE is pointed there before any library import). Audio is read with soundfile,
folded to mono and resampled in memory (soxr); it is never written anywhere.

Timing definitions (SPEC):
  batch : proc_ms = wall time to transcribe the whole in-memory clip (model loaded). final_ms = proc_ms.
  stream: audio is fed in chunk-ms chunks paced at real time. first_partial_ms = start of audio ->
          first non-empty partial. final_ms = end of audio -> final result. proc_ms = time spent
          inside the engine (excludes pacing sleeps), so RTF = sum(proc)/sum(audio) is compute only.
"""
import argparse, json, os, sys, time

CACHE = os.path.expanduser("~/Library/Caches/duo-voice-input")

# engine -> (family, model repo / arch, native sample rate, supports stream)
ENGINES = {
    "mlx-whisper-turbo": dict(fam="whisper", repo="mlx-community/whisper-large-v3-turbo"),
    "mlx-distil-whisper": dict(fam="whisper", repo="mlx-community/distil-whisper-large-v3"),
    "mlx-distil-whisper-v35": dict(fam="whisper", repo="wbell7/distil-whisper-large-v3.5-mlx"),
    "parakeet-mlx-v3": dict(fam="parakeet", repo="mlx-community/parakeet-tdt-0.6b-v3"),
    "parakeet-mlx-v2": dict(fam="parakeet", repo="mlx-community/parakeet-tdt-0.6b-v2"),
    "moonshine": dict(fam="moonshine", arch="MEDIUM_STREAMING"),  # alias of the newest English model
    "moonshine-medium-streaming": dict(fam="moonshine", arch="MEDIUM_STREAMING"),
    "moonshine-small-streaming": dict(fam="moonshine", arch="SMALL_STREAMING"),
    "moonshine-base": dict(fam="moonshine", arch="BASE"),
    "kyutai-stt": dict(fam="kyutai", repo="kyutai/stt-1b-en_fr-mlx"),
    "kyutai-stt-2.6b": dict(fam="kyutai", repo="kyutai/stt-2.6b-en-mlx"),
    "voxtral-mini": dict(fam="voxtral", repo="mzbac/voxtral-mini-3b-4bit-mixed"),
    "voxtral-mini-8bit": dict(fam="voxtral", repo="mzbac/voxtral-mini-3b-8bit"),
    "voxtral-realtime": dict(fam="voxtral_rt", repo="mlx-community/Voxtral-Mini-4B-Realtime-2602-4bit"),
    "granite-speech": dict(fam="granite", repo="mlx-community/granite-4.0-1b-speech-8bit"),
}


def log(*a):
    print(*a, file=sys.stderr, flush=True)


def load_audio(path, sr):
    import numpy as np, soundfile as sf, soxr
    x, in_sr = sf.read(path, dtype="float32", always_2d=True)
    x = x.mean(axis=1) if x.shape[1] > 1 else x[:, 0]
    if in_sr != sr:
        x = soxr.resample(x, in_sr, sr)
    return np.ascontiguousarray(x, dtype="float32")


def paced(audio, sr, chunk_ms, t0, pace=True):
    """Yield chunks, each released when its last sample would have been captured live."""
    step = int(sr * chunk_ms / 1000)
    n = len(audio)
    for i in range(0, n, step):
        j = min(i + step, n)
        if pace:
            d = t0 + j / sr - time.perf_counter()
            if d > 0:
                time.sleep(d)
        yield audio[i:j]


class Timer:
    """Accumulates time spent inside engine calls."""
    def __init__(self):
        self.total = 0.0
        self.first = None
        self.t0 = None
        self.partials = 0
        self.last = ""

    def start(self):
        self.t0 = time.perf_counter()

    def partial(self, text):
        text = (text or "").strip()
        if text:
            if self.first is None:
                self.first = (time.perf_counter() - self.t0) * 1000
            if text != self.last:
                self.partials += 1
            self.last = text


# ---------------------------------------------------------------- engines
class Engine:
    sr = 16000
    can_stream = False
    can_bias = False
    native_chunk_ms = 100
    info = ""

    def __init__(self, name, cfg, terms):
        self.name, self.cfg, self.terms = name, cfg, terms

    def load(self): ...
    def batch(self, audio): raise NotImplementedError
    def stream(self, audio, chunk_ms, pace): raise NotImplementedError


class Whisper(Engine):
    can_bias = True

    def load(self):
        import mlx_whisper
        from mlx_whisper.transcribe import ModelHolder
        import mlx.core as mx
        self.mw = mlx_whisper
        ModelHolder.get_model(self.cfg["repo"], mx.float16)
        self.prompt = ", ".join(self.terms) if self.terms else None

    def batch(self, audio):
        r = self.mw.transcribe(audio, path_or_hf_repo=self.cfg["repo"], language="en",
                               initial_prompt=self.prompt, condition_on_previous_text=False,
                               verbose=None)
        return r["text"].strip()


class Parakeet(Engine):
    can_stream = True
    native_chunk_ms = 480  # 100 ms chunks give garbled text and RTF > 1 with the local-attention cache

    def load(self):
        import mlx.core as mx
        from parakeet_mlx import from_pretrained
        self.mx = mx
        self.m = from_pretrained(self.cfg["repo"])
        self.sr = self.m.preprocessor_config.sample_rate

    def batch(self, audio):
        from parakeet_mlx.audio import get_logmel
        mx = self.mx
        mel = get_logmel(mx.array(audio), self.m.preprocessor_config)  # float32 required (mx.view trick)
        r = self.m.generate(mel)[0]
        return r.text.strip()

    def stream(self, audio, chunk_ms, pace):
        mx = self.mx
        T = Timer()
        with self.m.transcribe_stream(context_size=(256, 256), depth=1) as s:
            T.start()
            for ch in paced(audio, self.sr, chunk_ms, T.t0, pace):
                a = time.perf_counter()
                s.add_audio(mx.array(ch))
                txt = s.result.text
                T.total += time.perf_counter() - a
                T.partial(txt)
            t_end = T.t0 + len(audio) / self.sr
            a = time.perf_counter()
            txt = s.result.text
            T.total += time.perf_counter() - a
            fin = time.perf_counter()
            T.partial(txt)
        return txt.strip(), T, (fin - t_end) * 1000


class Moonshine(Engine):
    can_stream = True

    def load(self):
        from moonshine_voice import ModelArch
        from moonshine_voice.download import get_model_for_language
        from moonshine_voice.transcriber import Transcriber
        arch = getattr(ModelArch, self.cfg["arch"])
        path, arch = get_model_for_language("en", arch, cache_root=os.path.join(CACHE, "models", self.name_dir))
        self.tr = Transcriber(path, arch, update_interval=0.25)
        self.streaming_arch = "STREAMING" in self.cfg["arch"]
        self.can_bias = self.streaming_arch
        if self.terms and self.streaming_arch:
            self.tr.set_keyterms([t for t in self.terms if "," not in t])
        elif self.terms:
            log("moonshine: biasing needs a streaming architecture; --context ignored")
        self.can_stream = True

    def _text(self, tr):
        return " ".join(l.text.strip() for l in tr.lines if l.text.strip())

    def batch(self, audio):
        return self._text(self.tr.transcribe_without_streaming(audio.tolist(), 16000)).strip()


class MoonshineListener:
    def __init__(self, T):
        self.T = T
        self.lines = {}
        self.order = []

    def __call__(self, ev):
        line = getattr(ev, "line", None)
        if line is None:
            return
        lid = getattr(line, "line_id", id(line))
        if lid not in self.lines:
            self.order.append(lid)
        self.lines[lid] = line.text
        self.T.partial(self.text())

    def text(self):
        return " ".join(self.lines[i].strip() for i in self.order if self.lines[i].strip())


def _moonshine_stream(self, audio, chunk_ms, pace):
    T = Timer()
    st = self.tr.create_stream(update_interval=0.25)
    lis = MoonshineListener(T)
    st.add_listener(lis)
    st.start()
    T.start()
    for ch in paced(audio, 16000, chunk_ms, T.t0, pace):
        a = time.perf_counter()
        st.add_audio(ch.tolist(), 16000)
        T.total += time.perf_counter() - a
    t_end = T.t0 + len(audio) / 16000
    a = time.perf_counter()
    st.stop()
    now = time.perf_counter()
    T.total += now - a
    T.partial(lis.text())
    fin = now
    return lis.text().strip(), T, (fin - t_end) * 1000


Moonshine.stream = _moonshine_stream


class Kyutai(Engine):
    sr = 24000
    can_stream = True
    native_chunk_ms = 80

    def load(self):
        import json as _j
        import mlx.core as mx, mlx.nn as nn, numpy as np, rustymimi, sentencepiece
        from huggingface_hub import hf_hub_download
        from moshi_mlx import models, utils
        self.mx, self.np, self.models, self.utils, self.rustymimi = mx, np, models, utils, rustymimi
        repo = self.cfg["repo"]
        cfg = _j.load(open(hf_hub_download(repo, "config.json")))
        self.stt = cfg.get("stt_config", {})
        mimi_w = hf_hub_download(repo, cfg["mimi_name"])
        lm_w = hf_hub_download(repo, cfg.get("moshi_name", "model.safetensors"))
        tok = hf_hub_download(repo, cfg["tokenizer_name"])
        lc = models.LmConfig.from_config_dict(cfg)
        self.lc = lc
        m = models.Lm(lc)
        m.set_dtype(mx.bfloat16)
        if lm_w.endswith(".q4.safetensors"):
            nn.quantize(m, bits=4, group_size=32)
        elif lm_w.endswith(".q8.safetensors"):
            nn.quantize(m, bits=8, group_size=64)
        m.load_weights(lm_w, strict=True)
        self.model = m
        self.tok = sentencepiece.SentencePieceProcessor(tok)
        self.mimi = rustymimi.Tokenizer(mimi_w, num_codebooks=max(lc.generated_codebooks, lc.other_codebooks))
        m.warmup()

    def _run(self, audio, chunk_ms, pace):
        mx, np, models, utils = self.mx, self.np, self.models, self.utils
        left = int(self.stt.get("audio_silence_prefix_seconds", 0.0) * self.sr)
        right = int((self.stt.get("audio_delay_seconds", 0.0) + 1.0) * self.sr)
        FR = 1920  # 80 ms at 24 kHz
        for c in self.model.transformer_cache:
            c.reset()
        self.mimi.reset()
        n_steps = (left + len(audio) + right + FR - 1) // FR + 2
        gen = models.LmGen(model=self.model, max_steps=n_steps + 4,
                           text_sampler=utils.Sampler(top_k=25, temp=0),
                           audio_sampler=utils.Sampler(top_k=250, temp=0), check=False)
        T = Timer()
        pieces = []
        oc = self.lc.other_codebooks

        def feed(frame):
            if len(frame) < FR:
                frame = np.pad(frame, (0, FR - len(frame)))
            toks = self.mimi.encode_step(frame[None, None, :])
            toks = mx.array(toks).transpose(0, 2, 1)[:, :, :oc]
            t = gen.step(toks[0])[0].item()
            if t not in (0, 3):
                pieces.append(self.tok.id_to_piece(t).replace("▁", " "))
                return True
            return False

        # silence prefix first (not paced; a live app would run it at key-down)
        for i in range(0, left, FR):
            feed(np.zeros(FR, dtype="float32"))
        # real audio in 80 ms frames, paced
        T.start()
        buf = np.zeros(0, dtype="float32")
        for ch in paced(audio, self.sr, 80, T.t0, pace):
            buf = np.concatenate([buf, ch])
            while len(buf) >= FR:
                a = time.perf_counter()
                feed(buf[:FR]); buf = buf[FR:]
                T.total += time.perf_counter() - a
                T.partial("".join(pieces))
        t_end = T.t0 + len(audio) / self.sr
        # flush: remaining samples + delay padding, unpaced (an app injects silence at key release)
        tail = np.concatenate([buf, np.zeros(right, dtype="float32")])
        a = time.perf_counter()
        for i in range(0, len(tail), FR):
            feed(tail[i:i + FR])
            T.partial("".join(pieces))
        T.total += time.perf_counter() - a
        fin = time.perf_counter()
        return "".join(pieces).strip(), T, (fin - t_end) * 1000

    def batch(self, audio):
        return self._run(audio, 80, pace=False)[0]

    def stream(self, audio, chunk_ms, pace):
        return self._run(audio, 80, pace)


class Voxtral(Engine):
    def load(self):
        import mlx.core as mx
        from mlx_audio.stt import load
        self.mx = mx
        self.m = load(self.cfg["repo"])
        # transformers' VoxtralProcessor wants a container format for in-memory arrays
        # (it encodes to a BytesIO, never to disk); mlx-audio does not pass one.
        proc = self.m._processor
        orig = proc.apply_transcription_request
        proc.apply_transcription_request = lambda **kw: orig(format="wav", **kw)

    def batch(self, audio):
        out = self.m.generate([audio], max_tokens=256, language="en")
        return out.text.strip()


class VoxtralRT(Engine):
    can_stream = True

    def load(self):
        import mlx.core as mx
        from mlx_audio.stt import load
        self.mx = mx
        self.m = load(self.cfg["repo"])

    def batch(self, audio):
        return self.m.generate(audio).text.strip()

    def stream(self, audio, chunk_ms, pace):
        T = Timer()
        sess = self.m.create_streaming_session(max_tokens=512, temperature=0.0)
        txt = ""
        T.start()
        for ch in paced(audio, 16000, chunk_ms, T.t0, pace):
            a = time.perf_counter()
            sess.feed(ch)
            for d in sess.step(max_decode_tokens=16):
                txt += d
            T.total += time.perf_counter() - a
            T.partial(txt)
        t_end = T.t0 + len(audio) / 16000
        a = time.perf_counter()
        sess.close()
        while not sess.done:
            for d in sess.step(max_decode_tokens=16):
                txt += d
            T.partial(txt)
        T.total += time.perf_counter() - a
        fin = time.perf_counter()
        return txt.strip(), T, (fin - t_end) * 1000


class Granite(Engine):
    def load(self):
        from mlx_audio.stt import load
        self.m = load(self.cfg["repo"])

    def batch(self, audio):
        import mlx.core as mx
        return self.m.generate(mx.array(audio), max_tokens=256).text.strip()


FAMILIES = dict(whisper=Whisper, parakeet=Parakeet, moonshine=Moonshine, kyutai=Kyutai,
                voxtral=Voxtral, voxtral_rt=VoxtralRT, granite=Granite)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--engine", required=True, choices=sorted(ENGINES))
    ap.add_argument("--manifest", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--mode", default="batch", choices=["batch", "stream"])
    ap.add_argument("--context", default=None)
    ap.add_argument("--chunk-ms", type=int, default=None, help="stream chunk (default: 100, parakeet 480, kyutai 80)")
    ap.add_argument("--no-pace", action="store_true", help="stream without real-time pacing (debug only)")
    a = ap.parse_args()

    cfg = ENGINES[a.engine]
    name_dir = a.engine if a.engine != "moonshine" else "moonshine-medium-streaming"
    mdir = os.path.join(CACHE, "models", name_dir)
    os.makedirs(mdir, exist_ok=True)
    os.environ["HF_HUB_CACHE"] = os.path.join(mdir, "hub")
    os.environ.setdefault("HF_HUB_DISABLE_TELEMETRY", "1")

    terms = []
    if a.context:
        terms = [l.strip() for l in open(a.context) if l.strip()]
    clips = [json.loads(l) for l in open(a.manifest) if l.strip()]

    eng = FAMILIES[cfg["fam"]](a.engine, cfg, terms)
    eng.name_dir = name_dir
    if terms and not (eng.can_bias or cfg["fam"] == "moonshine"):
        log(f"{a.engine}: no biasing support; --context ignored")
    t = time.perf_counter()
    eng.load()
    load_ms = (time.perf_counter() - t) * 1000
    if a.mode == "stream" and not eng.can_stream:
        sys.exit(f"{a.engine}: no stream mode")

    pace = not a.no_pace

    def run_clip(audio, warm=False):
        if a.mode == "batch":
            t = time.perf_counter()
            hyp = eng.batch(audio)
            ms = (time.perf_counter() - t) * 1000
            return dict(hyp=hyp, proc_ms=ms, first_partial_ms=None, final_ms=ms, partials=None)
        hyp, T, fin = eng.stream(audio, a.chunk_ms or eng.native_chunk_ms, pace and not warm)
        return dict(hyp=hyp, proc_ms=T.total * 1000, first_partial_ms=T.first, final_ms=fin, partials=T.partials)

    # warm-up on the first clip, not scored
    run_clip(load_audio(clips[0]["wav"], eng.sr), warm=True)

    with open(a.out, "w") as out:
        for i, c in enumerate(clips):
            audio = load_audio(c["wav"], eng.sr)
            r = run_clip(audio)
            row = dict(id=c["id"], hyp=r["hyp"], audio_ms=len(audio) / eng.sr * 1000)
            if i == 0:
                row["load_ms"] = load_ms
            row.update(proc_ms=r["proc_ms"], first_partial_ms=r["first_partial_ms"],
                       final_ms=r["final_ms"], partials=r["partials"])
            out.write(json.dumps(row) + "\n")
            out.flush()


if __name__ == "__main__":
    main()
