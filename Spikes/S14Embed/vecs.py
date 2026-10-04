"""S14: Swift Core ML query vectors vs the POC's ONNX vectors (cosine)."""
import json, pathlib, subprocess, sys, hashlib, numpy as np, onnxruntime as ort
from tokenizers import Tokenizer
POC = pathlib.Path.home() / "repos/smol-sim-search"; sys.path.insert(0, str(POC / "tests"))
from conftest import GOLDEN
HERE = pathlib.Path(__file__).parent; HF = HERE.parent / "S13CoreML/hf/bge-small"
src = POC / "vendor/models/bge-small"
onnx = b"".join(p.read_bytes() for p in sorted(src.glob("model.onnx.part*")))
sess = ort.InferenceSession(onnx, providers=["CPUExecutionProvider"])
tok = Tokenizer.from_file(str(HF / "tokenizer.json")); tok.enable_truncation(512)
prefix = "Represent this sentence for searching relevant passages: "
for model, cu in [("fp32", "cpu"), ("fp32", "all"), ("fp16", "all"), ("fp16", "ane")]:
    cos = []
    for q, _ in GOLDEN:
        e = tok.encode(prefix + q); ids = np.array([e.ids], dtype=np.int64)
        h = sess.run(None, {"input_ids": ids, "attention_mask": np.ones_like(ids), "token_type_ids": np.zeros_like(ids)})[0][:, 0]
        ref = h[0] / np.linalg.norm(h[0])
        out = subprocess.run([str(HERE / ".build/debug/S14Embed"), "query", str(HERE / f"out/bge-small-{model}.mlmodelc"),
                              str(HF / "vocab.txt"), cu, q], capture_output=True, text=True, check=True).stdout.splitlines()
        v = np.array(json.loads(out[-1]), dtype=np.float32)
        cos.append(float(ref @ v))
    print(f"{model}/{cu}: min cosine to ONNX {min(cos):.6f} over {len(cos)} golden queries")
