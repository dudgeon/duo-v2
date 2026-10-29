# Brief: write Duo's feature catalogue (one-time, Opus)

*For the director to start, as a background Opus session with Remote Control (`delegating.md`). DL-240, job C. The task note's `## Brief` is this file plus the reserved record numbers and the branch.*

## Geoff's words

Geoff, 2026-10-28: "a feature documentation agent, which makes sure that we always have an up-to-date articulation of the full feature intent of the application. We don't always formally make PRDs, and we are much more agile in terms of doing artifact-based review, but I do think that we should have a canonical articulation of the major features and how they should work."

He picked this on 2026-10-29: write the catalogue once, then keep it current through a rule on each feature merge rather than a recurring agent (DL-240).

`done_when`: "`docs/product/features.md` is on main and Geoff has reviewed it on a page; the brief template and the merge checklist name its upkeep; the design-system artifact carries it."

## What to write

**Where:** `docs/product/features.md`, one file. Split it into `docs/product/features/<area>.md` only if it grows past about 1,500 lines. Make it Obsidian- and OKF-compatible: plain Markdown, frontmatter `type: catalogue`, no HTML. Branch `docs/feature-catalogue`, in work tree `.claude/worktrees/feature-catalogue`.

**What counts as a major feature:** something a user would name and expect to keep working, for example:
- chat mode;
- the map;
- tasks and the task board;
- the director;
- review in Markdown;
- the Word viewer;
- forks;
- search;
- `duo2`;
- updates;
- parking;
- templates;
- GitHub issue links;
- the trust notice.

Expect 25 to 35. Group them by area, in the order the README and `docs/guide/` use. Paper cuts, keys and visual polish go inside their feature's rules, not as rows of their own.

**Each feature, in this shape:**

```markdown
## FEAT-07 · Chat mode
- **Intent:** two or three sentences on what it's for and who it serves, in plain words.
- **How it works:** the rules a user can see and rely on, as a short list. Each rule cites what decides it (DL-n, an LR Must, a handoff screen). For example: "Duo falls back to the terminal, with a bar, when it can't read the screen; it never returns to chat by itself (DL-235)."
- **Not:** what it deliberately doesn't do, citing the DL that ruled it out (for example, the quick-reply buttons, DL-29).
- **Governed by:** DL-n…, `docs/design/<x>-handoff/`, LR-n.
- **Status:** shipped in <first release>; changed in <releases>; open questions Q-n.
- **duo2:** the verbs (from `Sources/DuoControl/Actions.swift`).
- **Shown in:** the intro film scene, its own film, the guide page.
```

The FEAT-n numbers are stable and never reused. A retired feature keeps its row, marked `Status: retired (DL-n)`.

**Precedence:** the catalogue restates. Where it disagrees with a DL or an approved screen, they win (CLAUDE.md, Precedence). Say so in its first paragraph, and log each disagreement you find as a Q record, not a silent fix.

## How to find the intent

Read these, and hand the bulk to Sonnet subagents by area:

- `docs/design/decisions.md`, every DL (the main source);
- the handoff READMEs and `docs/design/system/surfaces.md`;
- `README.md`, `docs/guide/` and `docs/cli/duo2.md`;
- the release notes (`gh release list`, then `gh release view`);
- the intent pages and research docs in `docs/research/`, such as `markdown-review.md` and `github-issues.md`;
- `docs/design/legacy-requirements.md` (LR Musts);
- the build plan's v1 scope (§3a).

Write the intent in Geoff's terms where he stated it; quote him with a date when it's his. Don't invent intent: where the records don't say why a feature exists, write "Intent: not recorded" and add a Q.

## Review with Geoff

Publish the catalogue as a private page (an Artifact, after loading `artifact-design`), one card per feature, with a Comment and a "Looks right / Needs a change" Send on each (`db` answers plus `sendToClaude`, as on his earlier decision pages). Then ask him by AskUserQuestion whether it's ready. This session runs in the background, so it may have no Artifact tools (F-259). If it can't publish, hand the page source to the director to publish.

## Keeping it current (the merge rule)

On the same branch:

1. `docs/director/delegating.md`, "The brief is the job": add "the feature catalogue rows (FEAT-n) this changes, or 'none'".
2. `docs/director/merging-and-records.md` §2 already has the line "update the catalogue" (DL-240). Make sure it names the file.
3. `.claude/skills/release/SKILL.md` §3's release brief reads the catalogue for tiers. Check that its wording matches the file you wrote.
4. `docs/design/system/README.md`: add a pointer to the catalogue, so Claude Design reads intent beside looks. The director republishes the design system after the merge.

`scripts/check-hygiene.py` warns when a branch changes `Sources/` without touching `docs/product/features.md` (ENH-285; it switches on once the file exists). The weekly tidy-up lists such merges.

## Proof and report

- `scripts/check-records.sh`;
- every DL cited exists (grep);
- every `duo2` verb cited is in `Actions.swift`;
- `python3 -I scripts/check-hygiene.py --summary` runs.

Then report as CLAUDE.md says: branch, full shas, records, the page link, the number of features, and the number of "Intent: not recorded" rows.
