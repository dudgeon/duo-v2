# Live edits vs changes on disk (DL-77)

2026-10-04. Geoff: "start work on file system collision handling; check how legacy handles this and pick an approach for how to treat conflicting live edit/saves vs simultaneous file system changes." Picked by Claude on Geoff's delegation; Geoff can overrule.

## How legacy Duo does it

Sources are in the legacy repo; the review is summarised in F-49.

- **Saves:** autosave 800 ms after typing stops. Before every write it reads the disk and writes only if the disk still matches the bytes it last saw. Writes go through a temp file and a rename. It doesn't save on quit.
- **Watching:**
  - chokidar watches the file and its parent folder, which catches saves that replace the file by rename.
  - A catch-up read follows attaching, to close the gap between loading and watching.
  - Duo recognises its own writes against a set of bodies it recently wrote, registered before each write. An earlier 2-second time limit missed late events on big files (BUG-099).
- **Outside change, no unsaved edits:** it reloads, with the change highlighted. If more than half the document changed, it shows a "most of this document was replaced" banner instead.
- **Outside change with unsaved edits:** a banner offers Keep mine, Reload from disk, or View diff (the disk text as tracked changes over yours). **There is no merge.** OT and three-way merge were explicitly out of scope.
- **Claude's writes:**
  - `duo doc write` goes into the buffer. If you have unsaved edits it waits behind an Accept/Decline banner, and the CLI waits up to 5 minutes.
  - `duo doc edit` edits the buffer with no gate.
  - The CriticMarkup verbs write to disk, and the watcher brings the change in.
  - A warn-only hook catches raw Edit/Write to open files.
- **History:** a snapshot on every save Duo makes (consecutive saves within 90 s merged; at most 200 per file), restorable from a History modal. Writes from outside Duo are never captured.
- **What went wrong:** about 11 bugs in one stretch (BUG-085 to BUG-166):
  - autosave silently overwrote Claude's writes;
  - Duo's own saves raised false conflicts;
  - each Markdown round-trip quirk added another normalizer rule, and the normalizer then also swallowed real outside edits;
  - "autosave makes the unsaved-edits protection largely illusory": a full overwrite hit a buffer autosave had just left clean, and silently replaced it (ENH-197).

## Where v2 is

v2 has two advantages legacy lacked:
- **Byte-faithful text:** no round-trip normalizer, so no false conflicts from formatting.
- **A three-way merge** of outside changes into your unsaved edits.

Its gaps (the review's list):
1. **No disk read before saving.** An outside write landing in the last 100 ms is overwritten.
2. **The watcher can go deaf.** It can't recover from a delete-and-recreate. It doesn't watch the parent folder (LR-36), doesn't resolve symlinks, and doesn't do a catch-up read.
3. **The merge is one hunk per side.** Two separate edits of yours span everything between them, so false conflicts are likely. Deletions aren't marked.
4. **A conflict has no way out.** There's no bar (Q-20), and switching documents while in conflict drops your unsaved edits.
5. **Edits in the last second before quitting are lost:** nothing saves on quit.
6. **No history** (LR-38), so nothing can be got back.

## The approach

One principle: **neither side's text is ever lost.** Duo prefers merging to asking. When it must ask, it keeps both versions until you choose. Anything it replaces goes to history first.

1. **History first** (LR-38, DL-5's "next"). A local snapshot store per file, content-addressed, in App Support. Duo snapshots:
   - the file as it was on disk when opened;
   - each save Duo makes (consecutive saves within 90 s merged);
   - the buffer before any outside or Claude change is applied to it;
   - both sides of every conflict.

   This is the safety net legacy didn't have for outside writes. It's also what ENH-4's revert and a later History view stand on.
2. **Merge by line, with many hunks.** A diff3 over lines: each side's edits are separate hunks, so non-overlapping changes always merge. Outside changes that merge into your buffer show with the "added" highlight (DL-5), as today. Only hunks that touch the same lines are a conflict.
3. **Never write blind.** Each save:
   - reads the disk first;
   - if the disk changed since the base, merges first (and stops on a conflict);
   - writes through a unique temp file and a rename;
   - records the bytes it wrote, so its own echo is recognised by content, not by timing.
4. **Watch robustly.** Resolve symlinks. Watch the file and its parent folder, so saves that replace the file by rename are seen. Debounce about 150 ms. Do a catch-up read after attaching, and re-attach when the file comes back.
5. **On a conflict**, Duo:
   - keeps your buffer exactly as it is;
   - pauses autosave;
   - snapshots both sides to history;
   - shows a plain bar under the document (system look until Q-20 is designed) with **Keep Mine** (save yours; the disk version stays in history), **Use Theirs** (load the disk; yours stays in history), and **Compare** (later; for now it reveals both snapshots).

   `duo2 doc status` reports the conflict, and `duo2 doc resolve mine|theirs` lets Claude resolve it when you ask.
6. **Nothing is dropped when you look away.** Switching documents, closing a tab or quitting while edits are unsaved:
   - saves if it safely can;
   - in a conflict, keeps that document's buffer and conflict in memory, so it's there when you come back, and snapshots it;
   - flushes saves on quit.
7. **Deleted or moved outside Duo:** the buffer stays, with a bar: removed on disk; save to recreate it. Moves Duo makes itself follow the file, as today.
8. **Claude's own edits go through the editor** (`duo2 doc replace|insert`, F-47). They apply to the buffer like typing, so they merge with yours without a gate; they're snapshotted and highlighted. Raw writes by Claude's Edit tool are just another outside change and go through the merge. Whether to steer Claude away from them more firmly depends on the agent-edit tests (F-49).

### Why not legacy's banner-on-every-dirty-change

With autosave at 1 s the buffer is almost never dirty for long, so legacy's protection was "largely illusory" (its own words). Most real collisions are Claude editing one part while you type in another, and a line merge resolves those without interrupting you. The banner is kept for real overlaps, where a person has to choose.

### Order of work

1. Save-time disk check, robust watcher, save on switch and quit (gaps 1, 2, 5).
2. History store, with snapshots at the points above (gap 6).
3. Line-level diff3 (gap 3).
4. Conflict bar, `duo2 doc resolve`, keeping conflicted buffers across switches (gap 4).
5. Deleted-on-disk bar.

Each step has checks in `DuoChecks`, plus a live test that races Duo's autosave against an outside writer.

## Status (2026-10-04)

Built (F-50):
- all five steps above, minimally: the merge, never writing blind, watching, kept text, saving on quit, history, resolving, and removed-on-disk;
- Claude's edits through the editor (DL-78, F-49).

Next:
- Compare, and browsing and restoring history in the app;
- marking deletions;
- the designed bars (Q-20);
- ENH-4's revert.
