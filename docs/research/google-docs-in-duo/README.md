# Google Docs in Duo: research

The task is [tasks/google-docs-in-duo.md](../../../tasks/google-docs-in-duo.md). Phase 1 is done; Checkpoint 1 is next.

- [checkpoint-1.md](checkpoint-1.md): what changed the plan, and Geoff's questions (Q-309 to Q-316).
- [jobs.md](jobs.md): the jobs a person, Claude and remote people do on a Doc.
- [duo-browser-today.md](duo-browser-today.md): Duo's browser and duo2 against a public Doc (F-411 to F-413).
- [google-docs-surface.md](google-docs-surface.md): Docs' page, its API, Apps Script and change signals, with sources.
- [comparison-frame.md](comparison-frame.md): browser (A), native (B) and hybrid (C), criterion by criterion.
- [test-plan.md](test-plan.md): Phase 2's tests, in order, with the tools and what Geoff provides.
- `agent-landscape.md`: how other agents drive Docs (Phase 1B, branch `research/gdocs-landscape`).
- `probes/`: the throwaway probes, to re-run:
  - `main.swift`: a bare WKWebView with page-world script. Build it with `swiftc -O main.swift -o probe`, then run `./probe <url> <script.js> [seconds] [png]`. `ACTS="drag x1 y1 x2 y2; key shiftright"` sends real events first.
  - `duo2-verbs.sh`: every duo2 verb against an isolated Duo.
