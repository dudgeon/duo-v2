# Duo v2 — Build plan

Status: draft v2 · 2026-10-03 · Owner: Geoff

Inputs, and how they're cited here:

| Short | Document |
|---|---|
| §n | `docs/design/build-handoff/README.md` (design handoff; `screens/` are the literal target) |
| DL-n | `docs/design/decisions.md` |
| LR-n | `docs/design/legacy-requirements.md` |
| stack #n, S1–S10 | `docs/design/stack-recommendation.md` (amended by DL-14, DL-15) |
| CONS | `docs/prd/legacy-session-consolidation.md`, PR #1 (goals binding per DL-4; UI not binding) |
| SRCH | `docs/prd/cross-project-search.md`, PR #2 (L1–L18 locked by Geoff) |

The handoff's screens are the target for every visible surface. The spikes de-risk the engines. The two PRDs add two capabilities that sit on a shared foundation (inventory + registry). This plan orders all of it so UI work never waits on a spike it doesn't need, and each spike lands just before the phase that depends on it.

---

## 0. Ground rules

1. **The screens win.** Every visible surface is built against `screens/*.html` and closed with the §0.2 loop: fixture state → capture → `compare.sh` → fix → keep the last comparison image with the change.
2. **No invented design.** Anything in §13 ("not designed yet") gets a stub and a question, never a guessed UI. Marked **⛔ design**.
3. **Decisions are logged first.** A behaviour needing Geoff's call is marked **❓ decision** and goes into `decisions.md` before it's built.
4. **Fixture first, then live.** Every view reads a model that the fixture or the live state layer can fill. Fixture mode stays forever: it is how screenshots and checks are made.
5. **One source each** for chords (LR-60), tokens (§4), and the CLI command list (LR-52).
6. **Two PRDs, one foundation.** CONS and SRCH both depend on the same session inventory and project registry. Build that once (Phase E), not per feature.

---

## 1. What we learned scaffolding slice 1

The running record is `docs/plan/findings.md` (F-n); architecture choices are in `docs/adr/`. Summary:

A slice-1 prototype exists on branch `build/slice-1-foundations` (uncommitted, paused at Geoff's request so the plan comes first). It established these facts, which the plan relies on:

- **No Xcode on this Mac; the Command Line Tools are enough to build.** A Swift package builds and runs a SwiftUI/AppKit app with `swift build`, wrapped into `Duo.app` by a script. WebKit is in the CLT SDK.
- **But the CLT lack Xcode's macro plugins.** `@State` (now a macro in this SDK), Swift Testing's `@Test`, and XCTest are unavailable. Workarounds: `@Observable` classes held by `let` (Observation's macros do ship with the toolchain); checks as an executable (`swift run DuoChecks`). No asset catalogs (no `actool`): colours are generated Swift from `tokens.json`.
- **The comparison loop works.** Fixture flags put the window in each §0.2 state; a content capture at 1440×862 pt in sRGB matches the targets' pane edges to the point and token colours exactly. The system toolbar is 40 pt here, not 38 (§0.4: the system wins).
- **Whole-window capture needs Screen Recording**; without it the app draws its frame view instead, which shows toolbar contents.
- **The handoff's `tools/lib.sh` hung** on Chrome 154 (it never exits after writing output). Fixed by watching for the output and stopping Chrome; committed with the reference PNGs on `design/build-handoff`.

**Why this matters beyond convenience:** SRCH records that the delivery pattern proven on Geoff's company Mac is "vendored files arrive through `git clone`, then a local build; nothing downloaded at runtime" (SRCH §4, mini-meeting-minutes). A CLT-only Swift package build is that pattern. Keeping the build Xcode-free may be the thing that lets Duo run on the work Mac at all (SRCH Q1). See ❓ G1.

---

## 2. Gate zero: does Duo run on the work Mac?

SRCH lists this as its top risk; it is the top risk for the whole app. Run it before Phase B, with the slice-1 shell:

| Check on the work Mac | Pass |
|---|---|
| `git clone` + `scripts/bundle.sh` builds with whatever toolchain is there | App launches |
| Ad-hoc-signed local build opens without an admin override | No Gatekeeper block, or a documented one-time allow |
| The app can spawn the user's `claude` in a PTY (no App Sandbox, per stack #12) | `claude --version` runs from inside the app |
| Loopback TCP between a sandboxed Claude session and the app (DL-15) | A CLI round-trip works |

Outcome decides Phase L's distribution path (Developer ID DMG vs clone-and-build vs both). ❓ G1.

---

## 3. Phases

Each phase: what it builds, what it needs first, exit check, gates.

### Phase A — Foundations · handoff slice 1 · *done 2026-10-03*

| | |
|---|---|
| Builds | Swift package (`DuoKit` + `Duo` app + `DuoChecks`), `scripts/bundle.sh`, tokens codegen from `tokens.json`, type styles, `StateGlyph`, window + compact toolbar with per-altitude contents, a three-pane split per altitude (token-coloured 1 pt dividers, collapsible left pane, both altitudes kept alive), fixture model + loader, launch flags for each §0.2 state, content and window capture, `scripts/check-ui.sh`, `scripts/pixels.py`. Reference PNGs (done). |
| Exit | Every state launches from one flag; `check-ui.sh` captures and compares all six; pane edges and colours exact; toolbar contents and order match; left-pane collapse verified at both altitudes (F-5, F-9). Review images: `docs/plan/review/phase-a/`. |
| Gates | ❓ G1 (toolchain/distribution), gate zero. |

### Phase B — Static UI from the fixture · slices 2–3 · *done 2026-10-03, except the `look` gallery (moved to Phase C)*

| | |
|---|---|
| Builds | **All projects:** map (topic columns, tiles, focus outline, `+ New project` as an inert tile), idle footer, action column (needs-you cards, Home pointer card, review cards; no quick-reply buttons per DL-29, ignored when comparing), Home pane chrome (header, session tabs) over a placeholder. **Inside a project:** session list (state sections; group / thread / session rows; pills; selection shape), Resume / New buttons, file tree rooted on a real folder, console tab strip over a placeholder, right-pane tabs with a plain text view and the "added by Claude" block. `look.html` as a debug component gallery. |
| Needs | Phase A. |
| Exit | `overview`, `flow-zoom-1`, `project`, `flow-zoom-2`, `flow-zoom-4` meet §0.3, ignoring the targets' reply buttons (DL-29), the document body (placeholder until Phase I) and the mono font difference (F-12, Q-14). Review images: `docs/plan/review/phase-b/`. |
| Gates | ⛔ design: Project tab and group page (stub tabs, §3.5). ❓ `Open project` vs `Jump into project` (§12). |

### Phase C — Navigation · slice 4 · *built 2026-10-03; exit pending Geoff's chord review (Q-8) and the undesigned ⌘K palette, resume list and idle tier*

| | |
|---|---|
| Builds | Zoom in/out (cross-fade, Reduce Motion), tile focus + Enter, shared selection map ↔ action column, breadcrumb, chip with count-elsewhere, native peek popover, `⌘↩` / `⇧⌘H` / esc, focus restore, chord registry generating menu items, VoiceOver labels (§10). |
| Needs | Phase B. |
| Exit | The four-step zoom flow runs on the fixture; `flow-zoom-3` meets §0.3; every §6.2 action reachable by keyboard. |
| Gates | ❓ confirm DL-21–DL-28 (§14) and the chords (§6.3). ⛔ design: `⌘K` palette, `14 idle, resumable ›`, the resume-first list (LR-7). See also ❓ G4 (jump vs search). |

### Spike track (alongside A–C)

Each is a throwaway target or branch with pass/fail written before it starts. New or changed since the stack rec are marked.

| # | Spike | Unblocks |
|---|---|---|
| S1 | **Passed (F-17, F-18).** SwiftTerm soak with the real `claude` TUI; `TERM_PROGRAM` variants; 8×1 resize floor (LR-14); env scrub of `CLAUDE_CODE_*` / `CLAUDECODE` (CONS §5.6) | D |
| S2 | **Passed (F-18).** Six-session CPU/RSS load (Instruments needs Xcode; otherwise `ps`/`top` sampling) | D |
| S3 | libghostty-spm soak, only if S1/S2 fail | D |
| S9 | **Passed (F-23).** Hooks + `claude agents --json` + `~/.claude/sessions/<pid>.json` beacons → the five states; actionable `Notification` types only (LR-2) | E |
| S10 | **Encoder passed (F-24); relocation and retention still to test.** *Changed:* shared `~/.claude` mechanics (DL-14): full path encoder incl. >200-char rule and self-calibration, `--session-id`, `--resume <id>` from any cwd, the `relocated` record, retention read | E, J |
| S11 | *New:* fork lineage detection for threads (§11) | G |
| S12 | *New:* an answer channel for a waiting interactive session (§12 Q1 option C; Agent View's inline reply) | H |
| S8 | *Changed:* CLI transport from a sandboxed session (DL-15): loopback TCP + token, name TBD (DL-16) | F |
| S13 | *New (SRCH P0):* Core ML conversion of `bge-small-en-v1.5`, reproducible, checksummed; ranking parity with the POC's golden set (SRCH Q3) | M |
| S14 | *New (SRCH P0):* Core ML query embedding inside Claude Code's sandbox with no writes outside allowed paths; CPU-only and precompiled-model fallbacks (SRCH Q2). Includes whether model compilation works without Xcode (`MLModel.compileModel` at runtime vs `coremlc`) | M |
| S15 | *New (SRCH P0):* indexing throughput on the slowest supported Apple silicon; corpus size on the reference machine (SRCH NFR-1, NFR-3) | M |
| S4–S6 | CM6 live preview on a 1.2 MB file; external-edit merge; `swift-markdown-engine` hedge | I |
| S7 | WKWebView: local-only default + allow list (DL-3); inspector on an allowed site | K |

### Phase D — Terminals · slice 5 · *core built 2026-10-03 (F-22); open: shell tabs and auto-promote (DL-8), ANSI palette and empty console (design), ⌘W close*

| | |
|---|---|
| Builds | `TerminalHost` + SwiftTerm. Resolve the user's `claude` (LR-19). Spawn with Duo-minted `--session-id`, `DUO_SESSION_ID` (LR-20), scrubbed env. Console and Home tabs host real terminals; hidden tabs keep their PTY and stop drawing (LR-13); 8×1 floor (LR-14); paste/drop rules (LR-15); Shift+Enter only (LR-16); missing-cwd fallback (LR-18). Plain shell tabs that auto-promote via a Duo-only `claude` wrapper on `PATH` (DL-8). |
| Needs | S1, S2. |
| Exit | Six live sessions, five hidden, within S2's budget; dark panes still meet §0.3 down to their tab strips. |
| Gates | ⛔ design: terminal ANSI palette (pick in S1, show Geoff), shell-tab look, LR-11 empty console. |

### Phase E — Foundation: inventory, registry, live state · slice 6

Shared by everything after it, including both PRDs.

| | |
|---|---|
| Builds | **Registry** (Duo-owned, Application Support): projectId → path + bookmark, Home marker, archive map, triage state (CONS §8, minus anything superseded by DL-1/DL-13). **Project discovery:** folders with `PROJECT.md` + `.duo/project.json`; topic = parent folder. **Inventory** of `~/.claude/projects` (CONS FR-7.1: head/tail reads, collision/orphan/duplicate/live flags, beacons for liveness). **Session model:** `.duo/sessions.json` for Duo-owned facts (DL-1), rebuildable cache for Claude-derived facts (title ladder LR-6, digest LR-4, bounded reads LR-9), task ↔ session links read from task frontmatter (DL-13). **Attention** from hooks + `agents --json` (LR-1–LR-3). Resume rules and never-two-writers (LR-7, LR-8, CONS FR-7.7). Atomic writes, watcher hygiene (LR-35, LR-36). The fixture becomes one source among others. |
| Needs | S9, S10, Phase D. |
| Exit | Delete the cache → identical UI (DL-1). Fixture mode still reproduces every screenshot. |
| Gates | ⛔ design: folder moved/missing banner (LR-23); first run, no projects, no Home, nothing-needs-you empty states (§8, §13). ❓ how Home is marked (§11). ❓ G3 (vocabulary). |

### Phase F — The CLI · slices 6–7

| | |
|---|---|
| Builds | Two parts with one name (DL-16) and one command table generating help and docs (LR-52): **app commands** over loopback TCP + per-launch token (list needs-you, open project, open/resume session, group/ungroup, open file, session note/next, orientation reads LR-53); **read-only commands** that work with the app closed and inside Claude's sandbox: `search` and `similar` (SRCH L10, FR-7.7), later inventory reads. Installed for Duo terminals and plain Terminal, coexisting with legacy `duo` (DL-15, DL-16). `doctor`. Consent for irreversible actions (LR-57). Detect legacy Duo's global skill/hooks/`CLAUDE.md` block and warn (DL-16). Claude-facing guidance (skill) that prefers Duo search over grep for cross-project questions (SRCH FR-7.7.6). |
| Needs | S8; S14 for the search half. |
| Gates | ❓ CLI name (DL-16). ❓ neutralise legacy global instructions (DL-16). |

### Phase G — Groups and threads · slice 7

| | |
|---|---|
| Builds | Thread folding from fork lineage; groups by hand and by CLI verb; stored in `.duo/sessions.json`; group page tab. |
| Needs | S11, Phase F. |
| Gates | ⛔ design: grouping and the group page in the final look (§3.5). |

### Phase H — Replying from the chrome · slice 8 · *backlogged to v1.2 (DL-29)*

| | |
|---|---|
| Builds | Per §12 Q1: option A (the live terminal re-parented into the card or popover) at minimum; B or C only with a log entry. Reason chips (LR-1). |
| Needs | S12, Phase D. |
| Gates | ❓ §12 Q1 (DL-29). |

### Phase I — Documents and the editor

| | |
|---|---|
| Builds | CM6 live-preview editor in one WKWebView (stack #8–9): byte-faithful saves (LR-30), one reconciliation primitive and its state machine (LR-31, LR-32), "added by Claude" highlight (LR-33, DL-5), agent edits through the buffer (LR-34), frontmatter panel (LR-37), Obsidian-compatible writes (DL-6, DL-17–DL-20), images (LR-39), trash/rename/reveal (LR-40). Version history next (DL-5). |
| Needs | S4, S5 (S6 decides native vs web). |
| Gates | ⛔ design: editor internals, conflict banners (§13). |

### Phase J — Bringing existing work in (CONS)

| | |
|---|---|
| Builds | On Phase E's inventory: convert a working folder into a project; file sessions into projects by pointer; relocate the way `/cd` does, journaled and undoable; tandem folder moves; archive by move; retention consent; catch-all ("junk drawer") splitting with deterministic evidence facets. Follows CONS phasing P1–P4 for mechanics. |
| Needs | S10, Phase E. Search (Phase M) makes the curation view much better (SRCH L14) but isn't required for it. |
| Gates | ⛔ design: the whole curation surface (DL-4; §13). ❓ CONS R1, R2, R4 and L3a (owner confirmation pending in PR #1). ❓ SRCH Q9: add L3b ("user-initiated search in curation is allowed") to CONS. |

### Phase K — Browser

| | |
|---|---|
| Builds | WKWebView tab kind in the right pane; local-only default with an in-app allow list (DL-3); inspector (LR-44) and page-driving commands via the CLI (LR-45); Google Docs reading as a should (DL-7). |
| Needs | S7, Phase F. |
| Gates | ⛔ design: browser, inspector, allow list (§13). |

### Phase M — Cross-project search (SRCH)

| | |
|---|---|
| Builds | Follows SRCH's own phasing on Phase E's foundation. **M1 (SRCH P1):** central Duo-owned index (Application Support; content-hash keyed; one writer, many readers; crash-safe), file source across all registry projects, hybrid semantic + lexical retrieval, the read-only `search` CLI (Phase F), coverage reporting, a basic search UI. **M2 (SRCH P2):** session, memory and `CLAUDE.md` sources; Unsorted/Unfiled and archived handling; facets; open and resume actions; secret exclusion and redaction (SRCH L15). **M3 (SRCH P3):** find similar, send to Claude, curation-view integration (L14), replacing the curation title filter. Background throttled indexing with recent-first backfill (L8). Model delivered with Duo, checksummed, never downloaded (SRCH FR-7.9). |
| Needs | S13, S14, S15; Phase E (inventory, registry, attribution); Phase F (CLI). |
| Gates | ⛔ design: the search UI, and where it lives relative to the `⌘K` jump field (❓ G4). ❓ SRCH Q4–Q7 (storage engine, merge/boost tuning, deny-list, record columns). ❓ G2 (model weights in git). |

### Phase L — Ship

| | |
|---|---|
| Builds | Per gate zero: Developer ID + notarization + Sparkle, and/or the clone-and-build path; a launch validator in the release script (LR-61); restore on relaunch (LR-58); MIT `LICENSE` (DL-12); settings and menus. |
| Gates | ⛔ design: settings, menus, notifications (§13). ❓ G1. |

Later, by decision: version history (DL-5, right after I), tracked suggestions (DL-5), scheduled sessions (DL-9), side-by-side documents (DL-11), dark appearance (§12 Q4), similarity analysis (SRCH L12).

---

## 3a. Roadmap: what v1 is (DL-32)

Geoff delegated scoping. The test for v1: **Geoff can use Duo all day instead of Terminal plus legacy Duo, on this Mac and then the work Mac, and it never loses a session.** Everything that doesn't serve that test waits, however good it is.

### v1 — in

| Area | In v1 | From |
|---|---|---|
| Shell and look | Both altitudes as designed, zoom, shared selection, needs-you chip, peek (questions shown, no replies), chord registry, restore on relaunch (LR-58), light appearance only | A, B, C, DL-21–DL-28 |
| Sessions | Real terminals for every session and Home; hidden tabs stay alive; plain shell tabs with auto-promote (DL-8); resume-first list (LR-7); never two writers (LR-8) | D, E |
| Live state | Registry, project discovery, read-only inventory of `~/.claude`, attention from hooks + `agents --json`, title ladder, digest, `.duo/sessions.json`, cache rebuildable (DL-1) | E |
| Not losing sessions | Duo-minted `--session-id` always; project move/rename **detected** and sessions keep resuming by ID (CONS FR-7.5.9 pointer behaviour, LR-23); one-time **retention consent** (C-4) | E |
| Existing work | **Convert a working folder into a project; file Unfiled sessions into a project by pointer.** No physical moves. (DL-4's goal, minimum viable) | J (minimal) |
| Groups | Display as designed; group and ungroup by CLI verb; thread rows for forks Duo starts itself | G (minimal) |
| Documents | CM6 live-preview markdown editing with byte-faithful saves, the reconciliation primitive, the "added by Claude" highlight (DL-5); **local HTML viewing** in the right pane (read-only WKWebView, auto-reload on change) | I, part of K |
| CLI | New name (Q-1), app commands over loopback: status, needs-you list, open project / session / file, group / ungroup, session note / next; `doctor`; legacy-instructions notice (Q-5) | F (minimal) |
| Delivery | Clone-and-build (DL-30) with a launch validator; work-Mac probe passes (gate zero); MIT licence | L |
| Undesigned but required | `⌘K` jump palette, Project tab, empty states (first run, no Home, nothing needs you, empty console), create-project flow, project-moved notice, idle tier / resume list, minimal Settings, terminal ANSI palette | design queue below |

### v1.1 — next

- **Search M1:** files across all projects, hybrid retrieval, read-only `search` CLI usable by Claude in the sandbox, coverage reporting, basic UI (after S13–S15).
- **Browser:** third-party sites via the allow list (DL-3), element inspector (LR-44), page-driving commands.
- **Version history** for files (DL-5).
- **Groups by hand** and the group page (after design).
- **Reconcile a moved project:** relocate transcripts the way `/cd` does, journaled and undoable.
- Developer ID signing, notarization and auto-update, if gate zero shows the work Mac accepts them.

### v1.2 and later

- Search M2–M3: sessions, memory and `CLAUDE.md` sources, secret redaction, facets, find similar, send to Claude, curation integration.
- Full consolidation (CONS): archive by move, delete, tandem folder moves, catch-all splitting, duplicate and collision repair.
- **Replying from the chrome** (DL-29; S12 first).
- Thread detection for forks made inside the TUI (S11).
- Google Docs reading (DL-7), tracked suggestions (DL-5), scheduled sessions (DL-9), side-by-side documents (DL-11), dark appearance (§12 Q4), similarity analysis (SRCH L12), frontmatter panel beyond plain editing (LR-37), multi-window.

### Design queue, in build order

Batch these into design passes; each is a ⛔ in its phase.

1. Before Phase C ends: `⌘K` jump palette (with Q-2's answer), resume-first list and idle tier (Q-11).
2. Before Phase D: terminal ANSI palette (pick in S1), shell tab appearance, empty console (LR-11).
3. Before Phase E ends: empty states (first run, no projects, no Home, nothing needs you), project-moved notice (LR-23), create-project flow, "Use as Home" (Q-4), retention consent, minimal Settings (Q-12).
4. Before v1 docs: Project tab (focused-project card), convert-folder and file-session interactions (DL-4, minimal), local HTML tab.
5. v1.1: search UI, browser and inspector, version history, groups by hand and group page.

## 4. Dependency order at a glance

```
A ─► B ─► C
│              S1,S2 ─► D ─┬─► H (S12)
gate zero                  │
                 S9,S10 ─► E ─┬─► F (S8) ─┬─► G (S11)
                              │           ├─► K (S7)
                              │           └─► M (S13–S15)
                              ├─► J (S10)
                              └─► I (S4–S6)
                                              └──► L
```

Suggested sequencing for one builder: A → gate zero → B → C, with S1/S2/S9/S10/S13–S15 run in between; then D → E → F; then whichever of I, J, M Geoff wants first; G, H, K as their designs and decisions land.

---

## 5. Conflicts and gates collected

**Superseded on 2026-10-03:** G1 → DL-30 (Xcode-free). Gate zero timing → DL-31 (after Phase C). §14 → DL-21–DL-28 (logged; designs still reviewed slice by slice). §12 Q1 → DL-29 (replies backlogged; Phase H and S12 move to v1.2). Everything still open now lives in `docs/plan/concerns-and-questions.md`, which is the live list; the table below is the original snapshot.

### New ❓ decisions raised by this plan (snapshot)

| # | Question | Why |
|---|---|---|
| G1 | **Keep the build Xcode-free (Swift package + CLT) as policy, not a stopgap?** And ship as Developer ID DMG, clone-and-build, or both? | Matches the delivery pattern proven on the work Mac (SRCH §4); gate zero decides. Cost: no SwiftUI macro plugins (`@State`, previews), no Swift Testing/XCTest, no asset catalogs, no Instruments without installing Xcode separately. |
| G2 | **Model weights in git?** SRCH FR-7.9 requires the model to arrive through Duo's own channel with checksums; the MMM pattern committed models to git. A Core ML `bge-small` is tens of MB. | Repo size; git LFS may not be allowed on the work Mac. |
| G3 | **One word for sessions not in a project.** CONS and the handoff say *Unfiled*; SRCH says *Unsorted*. | User-facing vocabulary. |
| G4 | **Is the `⌘K` Jump field also search?** The handoff's toolbar field jumps to projects, groups and sessions (LR-25); SRCH wants one search "reachable from anywhere". One field, two, or one palette with modes? | Both are undesigned (§13); deciding now avoids two competing surfaces. |
| G5 | **SRCH L5's rationale is stale.** It says the central index is "consistent with consolidation R3: nothing is written inside project folders", but CONS L6 superseded R3 and DL-1/DL-13 write `.duo/` and task frontmatter into projects. The decision (central index) stands; only the wording needs a fix in PR #2. | Keeps the PRDs consistent. |

### Carried from the handoff and earlier docs

- §14 log entries DL-21 to DL-28, and DL-29 = §12 Q1.
- `Open project` vs `Jump into project`; chord proposals (§6.3).
- CLI name; neutralise legacy global instructions (DL-16). How Home is marked (§11).
- CONS R1, R2, R4, L3a; SRCH Q2–Q9.

### Designs needed, in the order phases reach them

`⌘K` palette and search UI (C, M) → resume-first list, idle tier target (C) → Project tab, group page (B, G) → terminal palette, shell tabs, empty console (D) → empty states, folder-moved banner (E) → grouping in the final look (G) → editor internals, conflict banners (I) → curation surface (J) → browser, inspector, allow list (K) → settings, menus, notifications (L).
