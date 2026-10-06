# pptx-renderer (vendored)

The PowerPoint viewer (ENH-12, DL-121, DL-125) draws decks with **@aiden0z/pptx-renderer 1.3.0** (Apache-2.0, https://github.com/aiden0z/pptx-renderer), from its npm tarball:

tarball-sha256: f867ce7e814454ac048c3857b0db689f884dea633a66e73648860a44cacf0422

- `pptx-renderer.js` is the package's standalone browser build (`dist/aiden0z-pptx-renderer.browser.es.js`), which bundles JSZip (MIT) and ECharts (Apache-2.0); it loads nothing from the network. Notices: `LICENSE`, `THIRD_PARTY_NOTICES.md`, `licenses/` (the MPL-2.0 font decompressor among them).
- **Patched** by `patch.py`: its node dispatcher is wrapped so every shape, picture, table, chart and group element carries `data-duo-shape-id` (the OOXML `p:cNvPr` id), `-name` and `-type`. `duo2 slide shapes` reads the same ids from the file (`Sources/DuoSearch/Pptx.swift`). The patch fails loudly if an upgrade moves the dispatcher.
- `deck.html` and `deck.js` are Duo's own page around it: the slides top to bottom with their numbers, the slide on screen, the shape picker, and the messages to `DeckViewer` (`Sources/DuoKit/Editor/DeckViewer.swift`).
- `scripts/bundle.sh` copies the folder's page and scripts into `Duo.app/Contents/Resources/deck/`.
- To upgrade: change the version and hash in `vendor.sh` and here, run `./vendor.sh`, then `swift run DuoChecks` (it renders the test decks and compares the ids with the outline).
