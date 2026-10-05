# Duo slice 2: sessions first, Home, tasks and the lists — design handoff

Status: approved, 2026-10-05 (DL-100) · Owner: Geoff · Answers `docs/design/design-brief-slice-2.md`. Designed by Claude in the build session, on the canvas https://claude.ai/artifact/JSmkQh1Gsj9uyPSzkcuQFV with the Duo design system.

Same shape as `surfaces-handoff/`, and the same rule: the files in `screens/` are the target (`screens/manifest.json` lists them). Every value is a token from `build-handoff/tokens.json`; this slice adds none.

## What the screens settle

- **S2-1 · The session list** (`project-sessions`, `session-rows`).
  - Sections run Needs you · Open · Today · This week, then the folds: Earlier · n, Tasks · n, Archived · n.
  - Open rows sit on `activeTint` and read "working" or "at prompt" in place of a time. An open session that needs you stays under Needs you, still tinted.
  - A task row is `rowGroup` (28): chevron, the state glyph of its most urgent session, a 10 pt task box in `text`, its name in `bodyEmphasis`, then "<status> · <sessions>" in `text2` (`in progress · 2`, or `2 sessions` while it's open).
  - Group rows keep their `group · n` pill.
  - A task line in the Tasks fold is indented under the fold (box in `text2`, title, status past open).
  - Buttons: `+ New session` and `+ New task`. "Resume a session" is gone.
- **S2-2 · The map** (`map-folders`).
  - Home's columns come first: an unlabelled column for projects directly in Home, then its topic folders.
  - Then a full-width `OUTSIDE HOME` section label on a `rule` hairline, then the folders outside Home in columns labelled by path. A long path keeps its first and last parts: `~/Desktop/…/interviews`.
  - The New project tile ends the map.
  - Open tasks list under Ready for review.
- **S2-3 · No Home** (`no-home`). There's no welcome screen: the map is it, listing every folder by path. Home's pane says "Choose a Home folder", explains Home in one paragraph, and offers `Choose Home Folder…` and `Not Now` (console buttons), with a footnote naming File › Choose Home Folder…. In the action column, "Nothing needs you." (with the resolved glyph) replaces an empty Needs you.
- **S2-4 · Move into Home** (`move-into-home`): a sheet from the toolbar, on `ground`, 460 wide, radius 10 at the bottom, `shadowPopover`. It has:
  - a title;
  - the old and new paths in `mono` with the session count;
  - a `text2` warning about other apps;
  - an **Into** popup: Home's top level, or one of its topic folders;
  - Cancel, and Move (default, `text` border, semibold).

  The window behind dims to 55%.
- **S2-5 · A task note** (`task-note`): the properties block (`frontmatter-handoff`), with two changes:
  - `status:` shows a popup ("in progress ⌄").
  - Each `sessions:` entry is a line with its live state glyph, the underlined session name, and its wait at the right in `text2`. `+ Add` sits on the `sessions:` line.

  In the text, a session link shows its state glyph before the underlined name.
- **S2-6 · Needs you** (`needs-you-states`):
  - The reason follows the project on a card's second line: `checkout · permission`, `· question`, `· plan to approve`.
  - A question longer than 6 lines is clamped, with "… more" in `text2` under it.
  - Nothing waiting is the S2-3 line.
- **S2-6 · New project** (`new-project`): a sheet, 520 wide, on `ground`. Fields:
  - Name;
  - Goal (one line, with a hint);
  - In (a folder popup: Home's top level or a topic);
  - the resulting path in `mono` `text2`;
  - a "Start a Claude session in it" checkbox;
  - Cancel, and Create Project (default).

  Move to Project ▸ New Project… opens the same sheet, filing the session in the new project (Q-30).

## Behaviour a picture can't show

- `Not Now` collapses Home's pane at All projects and doesn't ask again. File › Choose Home Folder… stays.
- "… more" opens the question in full on the card; clicking the card again folds it.
- Status ▸ and the status popup write only `status:`, plus `completed:` when done or dropped (F-70).
- A session line in the properties block opens or resumes its session, keeping the note open (DL-87).
