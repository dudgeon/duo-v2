# Duo v2 — Concerns and open questions

A living log for pre-build refinement (DL-32). Claude adds entries as they arise; Geoff reviews in batches. Each entry has an ID that stays stable, a status, and what it blocks.

Status: **open** (needs Geoff or a spike) · **defaulted** (Claude chose a default to keep moving; Geoff can overturn) · **closed**.

---

## Open questions

| ID | Question | Blocks | Status | Notes |
|---|---|---|---|---|
| Q-1 | **CLI name** for v2 (DL-16: a new name that coexists with legacy `duo`). | Phase F | open | Needed before any CLI command ships or appears in agent guidance. Tie to the v2 product name if that changes. |
| Q-2 | **Is `⌘K` Jump also search?** The toolbar field jumps to projects, groups and sessions (LR-25); SRCH wants one search reachable from anywhere. One field, two, or one palette with modes? | Design of the palette (v1) and search UI (v1.1) | open, for the next design pass | Both surfaces are undesigned (handoff §13). Recommendation: one palette; jump results first, a "search everything" row that becomes full search once Phase M exists. |
| Q-3 | **Model weights in git?** SRCH requires the embedding model to arrive with Duo, checksummed (FR-7.9). A Core ML `bge-small` is tens of MB. | Phase M | open | Git LFS may not work on the work Mac. Alternatives: a separate repo cloned beside Duo, or a release asset fetched by the build script (but SRCH forbids runtime downloads, not build-time ones; confirm). |
| Q-4 | **How is Home marked?** (handoff §11) | Phase E | defaulted | Default: a registry flag set from a project's context menu ("Use as Home"); exactly one project can hold it. Needs a small design. |
| Q-5 | **Neutralise legacy Duo's global instructions?** Legacy installs a skill, subagent, hooks and a `CLAUDE.md` block into `~/.claude`; with a shared `~/.claude` (DL-14) they load into v2 sessions and describe legacy commands. | Phase F | open | v1 minimum: detect and show a one-line notice with what was found. Removal or disabling only with consent, and only if Geoff wants it. |
| Q-6 | **Which word for sessions not in a project:** *Unfiled* (handoff, CONS) or *Unsorted* (SRCH)? | Copy in v1 | closed | **Unfiled**, matching the approved designs and CONS. PR #2 updated 2026-10-03. Geoff can still overturn. |
| Q-7 | **PR #2 wording (SRCH L5).** Its rationale says "nothing is written inside project folders", which CONS L6 and DL-1/DL-13 superseded. The central-index decision stands. | Nothing | closed | PR #2 updated 2026-10-03. |
| Q-8 | **Chord map.** Handoff proposals `⌘↩` (jump into the selected peek card's project) and `⇧⌘H` (Home); four actions have no chord (open the peek, zoom out with the map focused, cycle panes, collapse the right pane). | Phase C | defaulted | Default: adopt both proposals. The four unassigned actions get chords in a full proposed map at the start of Phase C, checked against Claude Code's own bindings and LR-60's avoid list, for one review (LR-60: lock it once). |
| Q-9 | **`Open project` vs `Jump into project`** on cards (handoff §12). | Phase B | defaulted | Default `Open project` everywhere, per the handoff's suggestion. |
| Q-10 | **CONS owner confirmations:** R1 (pointer first, `/cd`-style relocation), R2 (deterministic migrator, not an agent), R4 (archive means preserve), L3a (deterministic evidence facets for catch-all buckets), SRCH L14 → CONS L3b. | v1.2 consolidation work | open | v1 only uses pointer filing and move detection, which hold under any answer. L3b added to CONS 2026-10-03. |
| Q-11 | **What should `14 idle, resumable ›` open,** and the resume-first list (LR-7)? | v1 | open, design | Both are LR musts and undesigned. |
| Q-13 | **Where Duo's machine-local state lives:** CONS uses `~/.claude/duo/` (registry, journals, archive); the plan defaults to `~/Library/Application Support/Duo/`. | Phase E | defaulted | Default Application Support: keeps Duo's state out of Claude's tree and away from `claude purge`. The archive's location matters most: CONS chose a path Claude's sweep never touches, which Application Support also satisfies. |
| Q-14 | **SF Mono or Menlo for the console chrome?** The handoff specifies SF Mono, but the design canvas's mono stack falls back to Menlo in Chrome, so the reference images (and possibly what Geoff reviewed) show Menlo (findings F-12). | Nothing; build uses SF Mono | defaulted | Default SF Mono, per §4.2 and "system faces". Visible difference: mono labels about 2.7% wider. |
| Q-12 | **Settings for v1:** at least the path to `claude`, the workspace root for new projects, and the retention consent. | v1 | open, design | Minimal native Settings window; needs a design pass. |

## Concerns

| ID | Concern | Severity | Mitigation / where tracked |
|---|---|---|---|
| C-1 | **Duo on the work Mac is untested until after Phase C** (DL-31). If local builds, ad-hoc signing, PTY spawning or loopback TCP are blocked there, distribution and the CLI transport change late. | High | Phases A–C don't depend on any of these. Prepare `scripts/workmac-probe.sh` with the Phase C build so the test is one command. |
| C-2 | **Six streaming Claude TUIs in SwiftTerm** may burn CPU (an open SwiftTerm issue reports 75–82% of a core on 1.x). | High | S1/S2 before Phase D; libghostty fallback (S3) behind `TerminalHost`. |
| C-3 | **Claude Code's internals move fast.** Transcript format, `agents --json`, beacons, the `relocated` record and path encoding are internal and changed seven times in recent releases (CONS §5). | High | Version gates, encoder self-calibration, tolerant parsing, fixtures per CLI version (CONS §11); fail toward "unknown" states, never crash. |
| C-4 | **Transcripts deleted after 30 days** by Claude Code's default retention. Without consent to raise it, sessions Duo files under projects disappear. | High | v1 must include the one-time retention consent (CONS FR-7.6.3) in onboarding. |
| C-5 | **Design throughput is now the bottleneck.** Twelve v1 surfaces are undesigned (see the plan's design queue). | Medium | Batch design requests: the plan lists the v1 design queue in build order so a design pass can take several at once. |
| C-6 | **No real test framework** without Xcode (DL-30). The checks executable is fine for model logic but weak for UI. | Medium | The screenshot loop is the UI test; keep model logic in `DuoKit` so checks reach it. Revisit if a CLT release ships the Testing macros. |
| C-7 | **Duo writes into project folders** (`.duo/`, task frontmatter `sessions:`). In GitHub repos shared with engineers this is noise in diffs and PRs. | Medium | v1: document it and show the files in the Project tab; consider suggesting `.duo/` in `.gitignore` on first write (with consent, never silently). |
| C-8 | **Legacy global instructions leak into v2 sessions** (Q-5). | Medium | Detection in v1. |
| C-9 | **Cards without replies may feel unfinished** (DL-29). The action column shows the question but you must open the session to answer. | Low | `Open project` lands on the session's console with the prompt visible, so answering is one click plus a key. Revisit with S12. |
| C-10 | **System toolbar is 40 pt on macOS 27**, not the targets' 38. | Low | Handoff §0.4: the system wins; content captures compare below it. |
| C-11 | ~~The slice-1 prototype has a quick-reply switch, which DL-29 makes moot.~~ Removed 2026-10-03. | — | Closed. |
| C-12 | **WKWebView editor vs the native bar** (Geoff's criteria: native menus, spellcheck, dictation, Writing Tools, native selection and find, byte-faithful saves). | Medium | S4 decides; native TextKit 2 editor stays the tracked successor. |
| C-13 | **Core ML embedding inside Claude's sandbox is unproven** (SRCH Q2). | Medium (v1.1) | S14 before Phase M; CPU-only and precompiled fallbacks. |
