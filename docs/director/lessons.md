# Lessons, and where things are

*Part of Duo's director procedures (`README.md`): Duo dev's habits on top of the shared duo-director core. Moved here from the project skill (retired) on 2026-10-17; the rules are in PROJECT.md's `## Director`.*

## Lessons (2026-10-07/08: the 0.2.5–0.2.7 work-Mac freeze and a long night)

- **Field evidence first.** For a problem on a machine you can't reach (Geoff's work Mac), get Duo's own `~/Library/Application Support/Duo/logs/hangs.jsonl` (or a sample) before theorising. Check each record's `"version"` field. Read the START of the record (the innermost frames and `"ongoing"`). Symbolicate `Duo@0x…` against the exact release binary: `atos -o build/release/<v>/Duo.app/Contents/MacOS/Duo -arch arm64 -l 0x100000000 0x100<offset>`. 0.2.6 shipped a fix for a cause guessed from a sample; the hang log named the real loop (a lazy-stack re-anchor) at once.
- **A record with no Duo frames** means a SwiftUI-internal loop: look for modifiers that make SwiftUI act on its own (defaultScrollAnchor for sizeChanges, animations, lazy stacks' estimates), not Duo code.
- **"Can't reproduce" is a finding.** Say what the fix rests on (record and code, or a reproduction), add belt and braces when the user gets one try a day, and ship with the hang log as the safety net.
- **Work Mac rules:** no scripts or manual steps there, ever (fixes ship as releases that cope with the state the broken one left); its Claude Code is pinned months old, so test against that version too; a frozen app can't self-update, so the notes say "download the DMG".
- **Urgent fix releases stay minimal.** Hold feature merges; park a checked merge on a `staging/…` branch and reset main; merge the held work right after the cut.
- **Release gate:** build the release in a temporary work tree (never overwrite build/Duo.app) and run check-scale there. The release launch check registers copies with Launch Services, so run `check-launch-services.sh --clean` after every release and merge.
- **Caret differences** in chat captures: check the log's `trace capture … active=` before calling a regression. The caret only draws while Duo is the active app.
- **The first check-chat-perf after the heavy checks** often reads one over budget (machine load). Re-run it twice before acting. Exception: "replies at the bottom" in a **visible** run fails about one run in three on main itself (C-85, F-295). Judge a chat change on three visible runs against that baseline, not on one.
- **After a usage-limit reset,** read every session's last message: sessions stop mid-task silently (the test-model session sat stopped for hours).
- **Before archiving or stopping a session,** check its transcript for Geoff's own messages; if there are any, keep it.
- **Background sessions have no Design canvas:** design rounds run in Duo. **Test launches run in the background;** visible runs need Geoff's OK. **Models:** Opus plans, Sonnet executes scoped work, Haiku tests (CLAUDE.md).
- **Duo carries no dev logic:** test-model and similar rules live in scripts and agent instructions, never in the app.
- **When Geoff answers a button question with a question,** answer it and wait. Don't take it as a choice.
- **Record-table merges:** keep both sides; where both edited a row, prefer the newer content (usually the branch for rows it closed, main for rows others updated); regenerate generated files (Tokens.swift, duo2.md) instead of hand-merging them; union lists like Actions' switches.

## Where things are

| What | Where |
|---|---|
| Director console | https://claude.ai/artifact/MMmJ9BjomsKq9f9HpHK1ka (source `docs/director/console.html`) |
| Acceptance walk page | https://claude.ai/artifact/DfQ1rfxcxHuf3Zshy6UmXX (`docs/acceptance/2026-10-09-since-0-2-4/`); the old one, Wu4bb9tB7C4HH1UEfXgKMa, is superseded |
| Session phone links | `docs/director/session-links.py [id-prefix…]` |
| Design system artifact | https://claude.ai/artifact/QMapKeLYS3TVV36QKEc6MH |
| Records | `docs/design/decisions.md`, `docs/plan/findings.md`, `docs/plan/concerns-and-questions.md`, `docs/plan/enhancements.md` |
| Geoff's voice (a dependency, `voice-repo.md`) | private repo `dudgeon/geoff-voice`; its local checkout is in memory `reference-geoff-voice.md` |
| Checks | `scripts/check-records.sh`, `check-ui.sh`, `check-chat.sh`, `check-context.sh`, `check-reap.sh`, `check-motion.sh`, `check-*.mjs` |
