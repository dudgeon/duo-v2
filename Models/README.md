# Models

`bge-small-fp16/` is the search model (SRCH L6, L16; DL-40; findings F-35, F-36): `BAAI/bge-small-en-v1.5` at revision `5c38ec7c`, converted to Core ML fp16 by `Spikes/S13CoreML/convert.py`. It arrives with the repo, so nothing is downloaded on anyone's Mac (SRCH FR-7.9.3).

- `model.mlpackage/`: the converted model. Its weights are split into parts under 50 MB (`weight.bin.part00`, `part01`).
- `SHA256SUMS`: checksums of the reassembled weights, the program and the vocabulary.
- `PROVENANCE.json`: source revision and checksums, tool versions, conversion variants.
- `vocab.txt`: the WordPiece vocabulary (identical to the POC's tokenizer).
- `MODEL_CARD.md`: the upstream model card (MIT licence).

`scripts/bundle.sh` reassembles the weights into `Duo.app/Contents/Resources/search/`, checks them against `SHA256SUMS` and fails the build on a mismatch. On first launch the app compiles the model into `~/Library/Application Support/Duo/search/model/`, where `duo2 search` loads it read-only.
