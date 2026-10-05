A small rounded tag with a kind and a count: `group · 3`, `task · 2`, `thread · 2`.

**Status:** Designed for group and thread; `task` added by DL-93 (stand-in, S2-1). **In code:** `Project/ProjectPanes.swift` `CountPill(text:emphasised:)`; search's own pill is `SearchView.swift` `Pill`.

**Anatomy:** `pill` style (11/16), padding 0 8, `radiusPill` (fully rounded), 1 border: `controlEdge` on a `pane` fill when emphasised (group and task rows), `rule` with no fill otherwise (threads).

**Consumer provides:** the kind and the count.

**Don't:** use it as a button or a status colour; a task's status sits beside it as plain `text2` words.
