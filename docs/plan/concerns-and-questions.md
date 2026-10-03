# Duo v2 — Concerns and open questions

A living log for pre-build refinement (DL-32). Claude adds entries as they arise; Geoff reviews in batches. Each entry has an ID that stays stable, a status, and what it blocks.

Status: **open** (needs Geoff or a spike) · **defaulted** (Claude chose a default to keep moving; Geoff can overturn) · **closed**.

---

## Open questions

| ID | Question | Blocks | Status | Notes |
|---|---|---|---|---|
| Q-1 | **CLI name** for v2 (DL-16: a new name that coexists with legacy `duo`). | Phase F | closed | **`duo2`** (DL-37). |
| Q-2 | **Is `⌘K` Jump also search?** The toolbar field jumps to projects, groups and sessions (LR-25); SRCH wants one search reachable from anywhere. One field, two, or one palette with modes? | Design of the palette (v1) and search UI (v1.1) | closed | **`⌘K` = project/group/session picker; `⇧⌘F` = expansive search; shared UI and services; `⌘F` stays find-in-document** (DL-38). |
| Q-3 | **Model weights in git?** SRCH requires the embedding model to arrive with Duo, checksummed (FR-7.9). A Core ML `bge-small` is tens of MB. | Phase M | closed | **Committed to the Duo repo, checksummed** (DL-40). |
| Q-4 | **How is Home marked?** (handoff §11) | Phase E | closed | **`HOME.md` marks Home**; several → use the last used, notice with "Use this one", remembered (DL-42). |
| Q-5 | **Neutralise legacy Duo's global instructions?** Legacy installs a skill, subagent, hooks and a `CLAUDE.md` block into `~/.claude`; with a shared `~/.claude` (DL-14) they load into v2 sessions and describe legacy commands. | Phase F | closed | **Detect and warn; offer removal with a backup** (DL-39). |
| Q-6 | **Which word for sessions not in a project:** *Unfiled* (handoff, CONS) or *Unsorted* (SRCH)? | Copy in v1 | closed | **Unfiled**, matching the approved designs and CONS. PR #2 updated 2026-10-03. Geoff can still overturn. |
| Q-7 | **PR #2 wording (SRCH L5).** Its rationale says "nothing is written inside project folders", which CONS L6 and DL-1/DL-13 superseded. The central-index decision stands. | Nothing | closed | PR #2 updated 2026-10-03. |
| Q-8 | **Chord map.** Handoff proposals `⌘↩` (jump into the selected peek card's project) and `⇧⌘H` (Home) are built. The four unassigned actions now have proposals in `Sources/DuoKit/Navigation/Commands.swift` (one table, menus generated from it): All projects `⌘↑` ("up a level", as Finder), open the peek `⇧⌘P`, collapse the right pane `⌥⌘0` (as Xcode's inspector), cycle panes `⌥⌘→` / `⌥⌘←`. Sidebar uses the macOS standard `⌃⌘S`. | Phase C exit | closed | **Locked as proposed** (DL-34). |
| Q-9 | **`Open project` vs `Jump into project`** on cards (handoff §12). | Phase B | defaulted | Default `Open project` everywhere, per the handoff's suggestion. |
| Q-10 | **CONS owner confirmations:** R1 (pointer first, `/cd`-style relocation), R2 (deterministic migrator, not an agent), R4 (archive means preserve), L3a (deterministic evidence facets for catch-all buckets), SRCH L14 → CONS L3b. | v1.2 consolidation work | closed | **R1, R2, R4, L3a confirmed** (DL-41). |
| Q-11 | **What should `14 idle, resumable ›` open,** and the resume-first list (LR-7)? | v1 | open, design | Both are LR musts and undesigned. |
| Q-13 | **Where Duo's machine-local state lives:** CONS uses `~/.claude/duo/` (registry, journals, archive); the plan defaults to `~/Library/Application Support/Duo/`. | Phase E | defaulted | Default Application Support: keeps Duo's state out of Claude's tree and away from `claude purge`. The archive's location matters most: CONS chose a path Claude's sweep never touches, which Application Support also satisfies. |
| Q-14 | **SF Mono or Menlo for the console chrome?** The handoff specifies SF Mono, but the design canvas's mono stack falls back to Menlo in Chrome, so the reference images (and possibly what Geoff reviewed) show Menlo (findings F-12). | Nothing; build uses SF Mono | closed | **SF Mono** (DL-36). |
| Q-15 | **Go-ahead for the token-spending spikes?** S1's interactive half (typing, permission prompt, AskUserQuestion, `/tui fullscreen`) and S2 (six streaming sessions) both make real model calls in throwaway folders. | Phase D | closed | **Yes, within reason; Haiku for many calls** (DL-33). |
| Q-16 | **Screen Recording permission** for the app that runs Claude Code here, so captures can show terminal pixels (F-17) and the real toolbar (F-7). | Nice to have | closed | **Geoff grants it** (DL-35). |
| Q-17 | **Does the Home folder have `PROJECT.md` as well as `HOME.md`?** Home is a project (goal, sessions) but is marked by `HOME.md` (DL-42). One file that does both, or two? | Phase E, first-run design | open, design | Leaning: `HOME.md` replaces `PROJECT.md` for Home and carries the same frontmatter (`type: home`), so there's one file to read. |
| Q-12 | **Settings for v1:** at least the path to `claude`, the workspace root for new projects, and the retention consent. | v1 | open, design | Minimal native Settings window; needs a design pass. |

## Concerns

| ID | Concern | Severity | Mitigation / where tracked |
|---|---|---|---|
| C-1 | **Duo on the work Mac is untested until after Phase C** (DL-31). If local builds, ad-hoc signing, PTY spawning or loopback TCP are blocked there, distribution and the CLI transport change late. | High | Phases A–C don't depend on any of these. Prepare `scripts/workmac-probe.sh` with the Phase C build so the test is one command. |
| C-2 | ~~Six streaming Claude TUIs in SwiftTerm may burn CPU.~~ **Retired:** S2 with six streaming sessions peaked at 11% of a core in the host, under 1% afterwards (F-18). | — | Closed. libghostty stays the fallback behind `TerminalHost` if a later SwiftTerm regresses. |
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
| C-14 | **Q-9 and Q-13 are still defaults**: Geoff answered the defaults question about Home only. `Open project` everywhere and `~/Library/Application Support/Duo/` for Duo's state stay as defaulted. | Low | Raise again if either matters before Phase E. |
| C-15 | **Home starts a session on launch** in live mode when it has none. Home's empty state isn't designed (§13) and the brief describes Home as always on, so this is a provisional default; starting Claude costs no tokens until you type. | Low | Revisit with the empty-state designs. |
| C-16 | **Partly resolved (F-26):** ready-for-review and the seen mark are built. Still open: **no state for "open and quiet"**: a Claude process at its prompt reports `idle`, which the handoff reserves for sessions that aren't running (§2.2). For now it keeps its tab with the idle glyph, and the `n idle, resumable` count includes it. Hooks only cover sessions Duo started; others fall back to beacons. | Medium | Exclude running sessions from the resumable count; decide with the idle-tier design. |
| C-13 | **Core ML embedding inside Claude's sandbox is unproven** (SRCH Q2). | Medium (v1.1) | S14 before Phase M; CPU-only and precompiled fallbacks. |
