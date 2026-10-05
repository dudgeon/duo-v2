A plain bar under the editor when the file on disk conflicts with unsaved edits, or was removed.

**Status:** Stand-in (Q-20; DB-14). **In code:** `Project/ProjectPanes.swift` `DocumentStateBar`; `Editor/DocumentEditor.swift`.

**Cases:** a conflict ("Changed on disk while you were editing", Use Theirs / Keep Mine); removed on disk (Save to Recreate); a file that can't round-trip opens read-only with a notice. Outside changes that don't conflict merge in silently, highlighted. Open for design (DB-14).
