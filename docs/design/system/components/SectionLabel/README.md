A section heading in capitals, with an optional `· n` count; in `needsYou` for the needs-you section.

**Status:** Designed. **In code:** `Design/Components.swift` `SectionLabel(text:count:needsYou:)`.

**Anatomy:** `sectionLabel` style (11/16 semibold, capitals, +0.66 tracking), `text2`; `needsYou` for NEEDS YOU. A count follows a middle dot: `NEEDS YOU · 2`. Map columns use it with a folder mark and a trailing slash (`payments /`, see MapColumn).

**Consumer provides:** the text, an optional count, and whether it's the needs-you section.

**Don't:** use it for anything but section headings; don't add icons except the map's folder mark.
