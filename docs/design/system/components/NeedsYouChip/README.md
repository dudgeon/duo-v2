The toolbar chip that counts sessions needing you in other projects and opens the peek.

**Status:** Designed. **In code:** `Shell/DuoToolbar.swift` `NeedsYouChip`.

**Anatomy:** a 9 pt `needsYou` dot and `N need you` in `chip` (12/20 semibold), padding 0 8, 1.5 `needsYou` border, `radiusControl`. When the peek is open it fills with `needsYou` and the text and dot turn `onNeedsYou`. Hidden at zero.

**Behaviour:** click or ⇧⌘P toggles the peek. It counts other projects only, never the one on screen.

**Accessibility:** "2 sessions need you in other projects".
