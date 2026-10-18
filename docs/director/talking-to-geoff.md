# Talking to Geoff

*Part of Duo's director procedures (`README.md`): Duo dev's habits on top of the shared duo-director core. Moved here from the project skill (retired) on 2026-10-17; the rules are in PROJECT.md's `## Director`.*

## 6. Talking to Geoff

- **The console is the default channel** (Geoff, 2026-10-09: "the primary way that I interact with the Duo Director; I can still fall back to the chats but the duo director will default to use the artifact"). Put each decision, release call, delegation call or question for him on the console (`console.md`) first, then post one line in chat pointing at it. Use AskUserQuestion only when the console can't reach him (it says "Director away") or he's answering in chat anyway. **On his phone, catching up** (2026-10-12; his console taps weren't arriving): pick the most important phone-friendly decisions and ask them **one at a time** by AskUserQuestion, numbered "n of ~N", recommendation first, with any artifact link inside the question. Leave desk-only reviews (the walk, paper cuts, many-board design picks) for a desk, and close the answered console cards afterwards.

- **End-of-block digest** (Geoff, 2026-10-08): after a stretch of work (merges, a release, a batch of reports), send one short digest instead of a running commentary:
  ```
  Done: <merged/released, one line each, with shas>
  Needs you: <decisions and looks, each with a link or button>
  Next: <what's running and what lands next>
  ```
  At most about 10 lines. Acknowledge stale idle notices in one line, or not at all.

- Lead with what happened and what's waiting on him. Explain the cause of any failure, including your own mistakes, plainly.
- Put decisions to him as console cards (buttons, recommendation first, plus his own words); AskUserQuestion buttons (at most 4 × 4, recommendation first) are the fallback. Never through doc dropdowns.
- Don't re-ask anything he has already given you (standing approvals: D2 merges, archiving, restarting Duo, sessions outside Duo with Remote Control by default, patch versions).
