# ADR-0002 · Fixture mode and the screenshot comparison loop

Status: accepted · 2026-10-03 · Handoff: §0, §15 slice 1 · Findings: F-1, F-3, F-4, F-5, F-7

## Context

The design screens in `docs/design/build-handoff/screens/` are the literal build target (DL-26). Matching them needs a repeatable way to put the app in each target's state and compare pixels, without a human in the loop.

## Decision

- **Fixture mode.** The app loads `fixture.json` (bundled, or `--fixture <path>`) into the same model the live state layer will fill. `--state <target>` puts the window into one of the six target states (`TargetState`).
- **Capture.** `--capture <png>` renders the content area below the toolbar, sized to exactly 1440×862 pt, at 2x, in sRGB, then quits. `--capture-window <png>` captures the whole window (screencapture, or the frame view without Screen Recording).
- **Compare.** `scripts/check-ui.sh [states…]` builds, captures every state, and runs the handoff's `compare.sh --content-only`, writing `build/ui/<state>-compare.png` (TARGET | BUILD | DIFFERENCE).
- **Measure.** `scripts/pixels.py` samples colours and finds edges in a PNG, in design points.
- References are frozen PNGs committed under `screens/png/` (rendered once with `render-references.sh`).

## Consequences

- Every slice closes with comparison images for Geoff's review (DL-26).
- The fixture path is permanent: tests, screenshots and previews depend on it even after live data exists.
- Things the handoff exempts (system toolbar material, terminal content, placeholder bars, document typography, and the reply buttons per DL-29) show up in DIFFERENCE and are ignored by judgement, region by region.
