# Duo: opening a Word document as Markdown — design handoff

Status: approved by Geoff, 2026-10-06 (DL-123), and built (F-116). The boards were drawn on the Design canvas https://claude.ai/artifact/YRWyEm4MHbxYYtnRVr55xp with the Duo design system (every mark a [P]), and are exported here as static HTML with PNGs in `screens/png/`.

## What the boards settle

- `docx-offer` (A): a .docx opens in Quick Look as other binary files do (C-26), with the notice bar offering **Convert to Markdown** (default), Open With and Show in Finder. Nothing pops up.
- `docx-offer-sheet` (A2): **not chosen**. The same offer as a sheet on open.
- `docx-name-taken` (B): when `<name>.md` exists, a Duo question: the path and how long ago it was edited, a **Save new as** field holding a free name (`Report 2.md`; Geoff's canvas comment), and Cancel, Replace, Open Existing, **Convert**.
- `docx-converting` (C): after half a second, a progress bar in the bar, what it's doing, and Cancel.
- `docx-result` (D): the copy takes the .docx's tab with "Converted from Report.docx. The Word document is unchanged.", the summary, and Undo Conversion, Open Original, **OK**.
- `docx-partial` (E): the same, "with gaps", listing what didn't come over, then the rest.
- `docx-failed`, `docx-failed-kinds` (F, F2): why it couldn't (password, damaged, the older format, only pictures), that nothing was written, and what to do; Convert Anyway for a document with only pictures.

## Behaviour a picture can't show

- The .docx is never written. The copy goes beside it as `<name>.md`, its pictures in `<name>-images/` as `image-1.png`… with relative links. Undo (the button, Edit › Undo or `duo2 undo`) moves both to the Trash, and brings back anything Replace moved there. A copy edited since is left, and Duo says why.
- What the converter does, and why: `docs/plan/spikes/docx-to-markdown.md` (F-114, F-115). Comments become endnotes; tracked changes are accepted (Q-62 for more).
- `duo2 file convert <docx> [--as <name.md>] [--replace] [--anyway]` (DL-71).

## Exempt from the comparison

Quick Look's preview (macOS draws it) and the editor's text below the bar. Names and documents are illustrative.
