# Duo v2 — notes for Claude

Read `README.md` first for build commands and layout.

## Precedence

1. `docs/design/decisions.md` (DL-n) wins over every other doc.
2. The design screens in `docs/design/build-handoff/screens/` are the literal target for anything visible (DL-26). Where the handoff README's prose and a screen disagree about looks, the screen wins.
3. Then `docs/design/build-handoff/README.md` (§n), `docs/plan/build-plan.md`, `docs/design/legacy-requirements.md` (LR-n), `docs/design/stack-recommendation.md`.

## Rules

- **Build to the screens, then prove it.** Every visible change ends with `scripts/check-ui.sh <states>` and a look at `build/ui/<state>-compare.png`, region by region. Measure with `scripts/pixels.py`. Keep the last comparison image for Geoff to review (DL-26: he reviews designs slice by slice).
- **Never invent a design.** Anything in handoff §13 or the plan's design queue gets a stub and a question, logged in `docs/plan/concerns-and-questions.md`. Don't build the quick-reply buttons (DL-29).
- **Stay Xcode-free** (DL-30, ADR-0001): no `@State`, `@Entry`, `#Preview` or other SwiftUI macros; no XCTest or Swift Testing. App state is `@Observable` classes. Logic checks go in `Sources/DuoChecks`.
- **Tokens are generated.** Edit `docs/design/build-handoff/tokens.json`, run `python3 scripts/gen-tokens.py`; never edit `Tokens.swift` by hand, never use raw hex in views.
- **Don't edit `docs/design/build-handoff/screens/`.** They are a snapshot of the design canvas.
- **Record as you go.** Facts learned while building go in `docs/plan/findings.md` (F-n); risks and questions in `docs/plan/concerns-and-questions.md` (C-n, Q-n); Geoff's decisions in `decisions.md`.
- **Duo never types into a running Claude session** (LR-15). The harness's `type:` action is for test sessions under `.build/` only; never use `claude -c` or the resume picker programmatically; always mint `--session-id` (DL-14).
- **v1 scope is in the build plan §3a.** Don't pull later features into v1 without logging why.

## Running the app from a Claude session

`scripts/check-ui.sh` and `build/Duo.app/Contents/MacOS/Duo --state … --capture …` open a window briefly and quit. Captures need no permissions; `--capture-window` uses Screen Recording if granted, otherwise draws the frame view (terminals then show as blank panes: their text is in the layer, F-25). With the screen locked, computer-use can't capture either; add `dump` to `--then` and pass `open --stderr <file>` to read each terminal's text. `--workspace <root>` runs on real folders and starts real Claude sessions (Home starts one on launch); quit with `osascript -e 'tell application id "com.dudgeon.duo" to quit'` so terminals are cleaned up, never `pkill`. Prefer `scripts/run-live.sh <ws> <png> <actions> [stderr]`, which never hangs (F-26); `type:<text>` and `enter` drive the visible terminal; set `DUO_MODEL=claude-haiku-4-5-20251001` for test turns (DL-33). Test sandbox behaviour with `scripts/check-sandbox.sh` (Seatbelt, no tokens) before spending a Claude turn on it.
