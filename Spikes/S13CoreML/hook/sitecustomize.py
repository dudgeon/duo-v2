# Loaded by Python at startup (PYTHONPATH). With DUO_COREML set, swaps the POC's ONNX model call
# for a Core ML one, so ingest, chunking, tokenising and ranking stay exactly the POC's.
import os

if os.environ.get("DUO_COREML"):
    import numpy as np
    import coremltools as ct
    import sem.embed as E

    _model = ct.models.MLModel(os.environ["DUO_COREML"],
                               compute_units=getattr(ct.ComputeUnit, os.environ.get("DUO_CU", "ALL")))

    def _run(self, batch):
        enc = self.tok.encode_batch(batch)
        ids = np.array([e.ids for e in enc], dtype=np.int32)
        mask = np.array([e.attention_mask for e in enc], dtype=np.int32)
        out = []
        for s in range(0, len(ids), 64):
            out.append(_model.predict({"input_ids": ids[s:s + 64], "attention_mask": mask[s:s + 64]})["embedding"])
        return np.concatenate(out).astype(np.float32)

    E.OnnxEmbedder._run = _run
