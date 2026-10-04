"""Spike S13: convert BAAI/bge-small-en-v1.5 (pinned revision) to Core ML, reproducibly.

    .venv/bin/python convert.py            # writes out/bge-small-fp32.mlpackage, out/bge-small-fp16.mlpackage

The model embeds exactly like the POC (smol-sim-search): BERT, CLS pooling, L2 normalisation,
max 512 tokens. Inputs are int32 `input_ids` and `attention_mask`, batch 1–64 and sequence
1–512 (flexible). Output `embedding` is float32 [batch, 384], already normalised.
"""
import hashlib
import json
import pathlib
import sys

import coremltools as ct
import numpy as np
import torch
from transformers import AutoModel

HERE = pathlib.Path(__file__).parent
SRC = HERE / "hf" / "bge-small"
OUT = HERE / "out"
REVISION = "5c38ec7c405ec4b44b94cc5a9bb96e735b38267a"


class Embedder(torch.nn.Module):
    def __init__(self, bert):
        super().__init__()
        self.bert = bert
        # transformers masks padding with float32's minimum, which is -inf in fp16 and turns
        # softmax into NaN (F-35). -1e4 is the classic BERT value and masks just as well.
        bert.get_extended_attention_mask = lambda mask, shape, dtype=None: (1.0 - mask[:, None, None, :].float()) * -1e4

    def forward(self, input_ids, attention_mask):
        hidden = self.bert(input_ids=input_ids, attention_mask=attention_mask,
                           token_type_ids=torch.zeros_like(input_ids)).last_hidden_state
        cls = hidden[:, 0]
        return cls / cls.norm(dim=1, keepdim=True).clamp(min=1e-12)


def sha256_tree(path: pathlib.Path) -> dict:
    return {str(f.relative_to(path)): hashlib.sha256(f.read_bytes()).hexdigest()
            for f in sorted(path.rglob("*")) if f.is_file()}


def main():
    torch.manual_seed(0)
    bert = AutoModel.from_pretrained(SRC, torch_dtype=torch.float32, attn_implementation="eager").eval()
    model = Embedder(bert).eval()
    ids = torch.randint(1000, 2000, (2, 128), dtype=torch.int32)
    mask = torch.ones_like(ids)
    with torch.no_grad():
        traced = torch.jit.trace(model, (ids, mask))

    OUT.mkdir(exist_ok=True)
    batch, seq = ct.RangeDim(1, 64, default=1), ct.RangeDim(1, 512, default=128)
    inputs = [ct.TensorType("input_ids", shape=(batch, seq), dtype=np.int32),
              ct.TensorType("attention_mask", shape=(batch, seq), dtype=np.int32)]
    record = {"model": "BAAI/bge-small-en-v1.5", "revision": REVISION,
              "source_sha256": {k: v for k, v in sha256_tree(SRC).items() if not k.startswith(".")},
              "tools": {"torch": torch.__version__, "coremltools": ct.__version__, "python": sys.version.split()[0]},
              "variants": {}}
    for name, precision in [("fp32", ct.precision.FLOAT32), ("fp16", ct.precision.FLOAT16)]:
        ml = ct.convert(traced, inputs=inputs, outputs=[ct.TensorType("embedding", dtype=np.float32)],
                        convert_to="mlprogram", compute_precision=precision,
                        minimum_deployment_target=ct.target.macOS15)
        ml.short_description = f"bge-small-en-v1.5 @ {REVISION[:7]}, CLS + L2 norm, {name}"
        path = OUT / f"bge-small-{name}.mlpackage"
        ml.save(str(path))
        record["variants"][name] = {"path": path.name, "sha256": sha256_tree(path)}
        print(f"saved {path}")

    # The Neural Engine needs fixed or enumerated shapes (S15): batch 32 at three lengths.
    shapes = ct.EnumeratedShapes(shapes=[(32, 128), (32, 256), (32, 512)], default=(32, 256))
    ane_inputs = [ct.TensorType("input_ids", shape=shapes, dtype=np.int32),
                  ct.TensorType("attention_mask", shape=shapes, dtype=np.int32)]
    ml = ct.convert(traced, inputs=ane_inputs, outputs=[ct.TensorType("embedding", dtype=np.float32)],
                    convert_to="mlprogram", compute_precision=ct.precision.FLOAT16,
                    minimum_deployment_target=ct.target.macOS15)
    path = OUT / "bge-small-fp16-ane.mlpackage"
    ml.save(str(path))
    record["variants"]["fp16-ane"] = {"path": path.name, "sha256": sha256_tree(path)}
    print(f"saved {path}")
    (OUT / "PROVENANCE.json").write_text(json.dumps(record, indent=1) + "\n")


if __name__ == "__main__":
    main()
