A plain bar under the editor when the file on disk conflicts with unsaved edits, or was removed.

**Status:** Designed (DL-101, slice3 `editor-notices.html`). A bar under the tabs on `ground`, padding 10 20 (`size.notice`), a `rule` below: the message, a `text2` line, the buttons (default as on sheets). Conflict (lines also outlined in the text), removed, renamed (Duo follows it), read only (why). A document waiting in conflict shows "· conflict" on its tab. **In code:** `Project/ProjectPanes.swift` `DocumentStateBar`, `NoticeBar`.

**Cases:** a conflict ("Changed on disk while you were editing", Use Theirs / Keep Mine); removed on disk (Save to Recreate); a file that can't round-trip opens read-only with a notice. Outside changes that don't conflict merge in silently, highlighted. Open for design (DB-14).
