What the dark pane says when there's no terminal to show, and the bar under a session that ended.

**Status:** Designed (DB-3); the no-Home message is a stand-in (DL-84, DB-37). **In code:** `Project/ConsoleStates.swift` `ConsoleEmpty`, `ConsoleMessage`, `ConsoleEndedBar`.

**Anatomy:** top-left on `console`, padding `consoleMessagePadding` 24 (20 16 in Home's pane): a title in `bodyEmphasis` `consoleText`, a body in `body` `consoleText2` at most 440 wide, `consoleMessageGap` (6) apart, then console Buttons 8 below.

**Cases:** no session open ("No session open in refunds" · Resume <most recent> · Start Claude here); never run; Claude Code not found (Open Settings… · Look Again); open in another app (Look Again · Resume as a Fork, never end it); folder missing (Start in <nearest> · Locate Folder…); no Home session (Start Claude in Home); no Home folder (Choose Home Folder…).
**Ended bar:** `consoleBarHeight` 40 under the kept output, 1 `consoleRule` above: what happened, Resume (default), Close Tab.
**Trust bar (DL-229):** the same bar under a terminal when `/fork` says "Workspace not trusted": "Claude Code doesn't trust ‹folder› yet, so /fork couldn't start." with Not Now and **Trust This Folder…** (the default: `consoleText` edge, semibold; `ConsoleButtonStyle(bold:)`), changing in place to "Claude Code now trusts ‹folder›." with OK and **Fork Again**, or "Couldn't change Claude Code's settings: ‹why›." with Not Now and **Try Again**. In chat the bar sits over the composer in `NoticeBar`'s look. **In code:** `Project/TrustBar.swift`.

