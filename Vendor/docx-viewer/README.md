# docx-viewer (vendored)

The Word viewer (DL-162, `docs/design/docx-viewer-handoff/`) draws .docx files with **@file-viewer/docx 0.3.33** (Apache-2.0, a maintained fork of docx-preview, https://github.com/flyfish-dev/docxjs) and **JSZip 3.10.1** (MIT), from their npm tarballs:

file-viewer-tarball-sha256: 98ba3050f0d01c48fb866709f0148a812596a2bdff596b165e7dd52d65bdf314
jszip-tarball-sha256: 5117f4a2a645aeb307bf3b829c575ad58135cc97e75291e594532ab5b5b21b23

- `docx-preview.mjs` is the package's ES module (`dist/docx-preview.mjs`, as published). `vendor.sh` changes one thing: its `import "jszip"` is pointed at `./jszip.mjs`, so no import map (inline script) is needed. `jszip.mjs` is the package's `dist/jszip.min.js` (the very file the renderer ships) with a two-line wrapper. The renderer has no `fetch`, XHR or beacon; external images and links are blocked by its options and the page's policy.
- Notices: `LICENSE` (Apache-2.0, the renderer), `LICENSE-jszip.md` (JSZip: MIT or GPLv3, taken as MIT), `NOTICE`. Settings › About lists the Apache-2.0 notice.
- `docx.html` and `docx.js` are Duo's own page around it: the review layer (per-person colours, comment cards, labels, the four markup views), the messages to `DocxViewer` (`Sources/DuoKit/Editor/DocxViewer.swift`).
- `scripts/bundle.sh` copies the folder's page and scripts into `Duo.app/Contents/Resources/docx/`.
- **Why pinned:** a young fork with one maintainer and a no-op licence hook in its bundle (`assertViewerLicense`); a vendored Apache-2.0 copy can't be taken back. If it ever goes commercial the fallback is upstream docx-preview with `Spikes/DocxViewer/patch-paraids.py` (`docs/plan/spikes/docx-viewer.md`).
- To upgrade: change the versions here and in `vendor.sh`, run `./vendor.sh` (it checks the hashes), then `swift run DuoChecks` (it renders the test documents and compares the ids with `Docx.swift`'s outline).
