# Home list: a New session button (study, Q-339)

Geoff, 2026-10-30: "the home list view needs a new session button somewhere; please have a worker think through some options".

Canvas: https://claude.ai/artifact/Ug3zdTyXjRTR5TWzyyMAMN (Duo design system). Boards: 0 today, A, B, C, side by side. Every option is a [P]; Geoff picks.

- `today-light.png`, `today-dark.png`, `today-classic.png`: `list-1440` as built on main 32dada0a, isolated and in the background (F-446).
- **A · Header pill:** DL-253's `+ [robot | shell]` at the end of the list's header. Starts a Home session or shell.
- **B · New session row (recommended):** a dashed 28 pt row first in the list, `New session in [★ home ⌄]`, ⌘T. The popup lists Home, the projects by last activity, then New Project…, and remembers the last pick. Home opens the session in Home's pane; a project jumps in with the new tab selected. `duo2 session new --project <p>`.
- **C · Row hover +:** `+ robot` in a row's wait column under the pointer; a session in that row's project, and in its task (`duo2 task session`).
- For any choice: ⌘T at All projects starts a session (F-446), the empty list gets words, and the header stays put while the list scrolls.

Not a handoff yet: after Geoff's pick, the chosen boards are exported to `docs/design/home-list-new-session-handoff/`.
