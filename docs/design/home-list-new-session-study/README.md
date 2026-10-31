# Home list: a New session button (study, Q-339)

Geoff, 2026-10-30: "the home list view needs a new session button somewhere; please have a worker think through some options".

Canvas: https://claude.ai/artifact/Ug3zdTyXjRTR5TWzyyMAMN (Duo design system). Boards: 0 today, A, B, C, side by side. Every option is a [P]; Geoff picks.

- `today-light.png`, `today-dark.png`, `today-classic.png`: `list-1440` as built on main 32dada0a, isolated and in the background (F-446).
- **A · Header pill:** DL-253's `+ [robot | shell]` at the end of the list's header. Starts a Home session or shell.
- **B · New session row (recommended):** a dashed 28 pt row first in the list, `New session in [★ home ⌄]`, ⌘T. The popup lists Home, the projects by last activity, then New Project…, and remembers the last pick. Home opens the session in Home's pane; a project jumps in with the new tab selected. `duo2 session new --project <p>`.
- **C · Row hover +:** `+ robot` in a row's wait column under the pointer; a session in that row's project, and in its task (`duo2 task session`).
- **B with no Home** (Geoff's question, board "B · With no Home folder…"): Home is optional (DL-82); there is none before it's chosen or after its folder is moved or deleted (the scan finds no `_HOME.md` and Home's pane says "Choose a Home folder"). The popup then lists the known projects by last activity, New Project… and Choose Home Folder…. The default is the last pick if it still exists, else Home, else none: the row reads *Choose…* and the row and ⌘T open the popup rather than start. If the last pick is gone it falls back to Home and says so once. Every start goes through the trust check (DL-229, the trust-before-start sheet). Code note: when the remembered Home is gone, `ProjectDiscovery.chooseHome` takes the newest other `_HOME.md` folder it has seen, so Home can follow a moved folder that Claude has run in since, or pick up another `_HOME.md` without asking.
- For any choice: ⌘T at All projects starts a session (F-446), the empty list gets words, and the header stays put while the list scrolls.

Not a handoff yet: after Geoff's pick, the chosen boards are exported to `docs/design/home-list-new-session-handoff/`.
