# Acceptance walk: live workspace to organising

- **Status:** open (walk started 2026-10-04; Geoff may defer it)
- **Page:** https://claude.ai/artifact/Wu4bb9tB7C4HH1UEfXgKMa (verdicts in its `verdicts` collection)
- **Covers:** commits up to `5bd86bd` and the F-67 fixes (sessions first, Home, folder columns, the Open-then-past list, tasks and session links, DL-82 to DL-98), and before that the search M-UI (F-56) (Phase E live workspace through DL-66 organising, then Send to Claude, local HTML and the element picker, duo2 parity and the install loop, DL-67–DL-80, Claude's edits and collisions, drag and drop, Set up test and Claude's own runs)
- **Features:** 130 (7 for slice 3 after F-79; 2 for moved and missing folders after F-78; 5 for the properties block after F-77; 8 for the slice 2 build after F-76; 7 for restore, updates, tasks day to day and the browser after F-73; 12 for sessions-first, Home and tasks after DL-98, added at Geoff's request on the decision path page, DL-96; 4 for the home-view round after F-61; 8 for search after F-56, 7 for surfaces slice 1 after F-58, 5 for CONS, click-to-resume and revert after F-60), plus 15 decisions (6 for slice 1, Q-26) (39 on 2026-10-04 morning, the rest added the same day; earlier verdicts kept). 56 have a Set up test button; Claude ran all 65 first and wrote what it did on each card (after the screen-locked reruns, F-55: 63 of the first 65 passed, 2 need Geoff; the 8 search features passed), in [features.json](features.json); page built by `scripts/acceptance/build-page.py`
- **Fixtures:** `~/DuoAcceptance` from `scripts/acceptance/fixtures.py`; open Duo with `scripts/acceptance/open-duo.sh`

## Outcome

Not yet read back. When it is, record here: accepted, rejected (with what was logged where), not now, untested.
