---
name: triage-feedback
description: Sort tester feedback into the backlog by eval cause
---

# Triage feedback

For each piece of tester feedback (a pasted email, or a file under `research/feedback/`):

1. **Who:** the tester's id and name from `research/interviews/` (P1–P8) and their box.
2. **What happened**, in one line, naming the book if there is one.
3. **The cause:** the eval cause it matches (`tilted`, `glare`, `thin`, `stacked`, `other`; see
   `eval/spine-eval-2026-09-28.md`), or `trust` when the harm is a wrong book in someone's catalog.
4. **Append one line** to `research/feedback/triage.md`:
   `- YYYY-MM-DD · Pn Name · box · cause · what happened`
5. If it bears on an open question in `docs/prd-v2.md`, say which one. Don't edit the PRD.

Answer in one or two lines: the cause, and the line you added.
