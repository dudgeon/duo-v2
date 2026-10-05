The one button style in light chrome, plus its dark twin on the console.

**Status:** Designed (handoff §5). **In code:** `Design/Components.swift` `DuoButtonStyle` (`.buttonStyle(.duo)`); on the console `Project/ConsoleStates.swift` `ConsoleButtonStyle`.

**Anatomy:** `buttonHeight` 26: `control` label (12/16), padding 4 10, 1 `controlEdge` border, `radiusControl`, `pane` fill (`selected` while pressed). On the console: `consoleText` label, 1 `consoleText2` border, no fill.

**Copy:** a verb in sentence case: `Start Claude here`, `+ New session`, `Resume Reading note 1`. An ellipsis when a sheet or picker follows: `Choose Home Folder…`.

**Do:** put the default action first and give it Return. Use `gapButtonToButton` (6) between buttons.
**Don't:** invent primary or filled variants: Duo has one button. Never colour a button with `needsYou`.
