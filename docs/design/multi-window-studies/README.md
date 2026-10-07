# Multi-window studies (DL-141)

**Status: in study. Nothing here is approved to build.**

Geoff's direction (DL-141, 2026-10-07): independent windows, each optionally pinned to a project, with an optional whole-window tint. New Window is ⌥⌘N. The analysis is `docs/research/multi-window.md`.

- **Canvas:** https://claude.ai/artifact/46yWPpDZn16Qtfrfhbuaw1, drawn with the Duo design system. It has eleven boards.
  - Board 0 is the model.
  - Boards 1 to 10 are decisions, each with 2–3 options and one marked recommended.
  - `Win.dc.html` is the mini window the boards share.
  - `canvas/` is a copy of the canvas's files as of this commit.
- **Spec:** https://claude.ai/artifact/GaK5hPxTAxphXEZJSoXaYA (`spec.html`). It covers what changes, the tradeoffs, the size in slices, and twelve decisions, D1 to D12.
  - Geoff picks an option on each decision and presses Send to Claude.
  - Picks are kept in the page's store, in the `picks` and `submissions` collections, which a session reads with `ArtifactData`.

| Decision | Board | Record |
|---|---|---|
| D1 How a new window opens | 1 | Q-95 |
| D2 Pinning a window | 2 | Q-95 |
| D3 Leaving a pinned window's project | 3 | Q-95 |
| D4 How much a tint covers | 4 | Q-96 |
| D5 What a tint belongs to | 5 | Q-96 |
| D6 A session in two windows | 6 | Q-97 |
| D7 A document in two windows | 7 | Q-97 |
| D8 Needs-you across windows | 8 | Q-98 |
| D9 The Window menu | 9 | Q-98 |
| D10 Home | 10 | Q-98 |
| D11 The tint palette | 5 | Q-96 |
| D12 When to build | — | Q-99 |

Once Geoff decides:
- export the chosen boards to `screens/`, rendered to static markup, with a `manifest.json`, as in the other handoffs;
- add the tints as `windowTint*` tokens in `build-handoff/tokens.json`;
- record the choices in DL-141's follow-up.
