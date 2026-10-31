# Home list: New session (DL-262)

Status: approved by Geoff, 2026-10-30 (DL-262, Q-339), through the director. Not built.

Geoff: "the home list view needs a new session button somewhere". The study (`../home-list-new-session-study/`, canvas https://claude.ai/artifact/Ug3zdTyXjRTR5TWzyyMAMN) drew three placements; he picked **B**, then set the default: "defaul to ~/Documents/ if no home folder present; else default to home folder".

## Screens

- `screens/list-1440-new-session.html`: **the target**, 1440 × 900. home-evolution-handoff's approved `list-1440` with B's row added above the needs-you line. Everything else is that screen's.
- `screens/states.html`: the row in every state, in Light, Dark and Classic:
  - with a Home: rest, hover, pressed, the popup, Choose Another Folder…;
  - with no Home: `~/Documents`, the popup, macOS's Documents prompt, and no `~/Documents`.
- `screens/png/`: both screens rendered (`canvas/render.sh`).
- `canvas/`: the canvas boards' sources (`*.dc.html`, `canvas.json`) and `make.py`, which writes `screens/` from the same rules as `ListPane.dc.html` (`dflt="docs"`).

## The row [G] DL-262

- **Where:** the first row of All projects › List, under the header and above the needs-you line.
  - 16 in from the pane's sides, 8 above and 8 below, 28 high.
  - It stays put with the header while the list scrolls; the header then shows a 1 pt `rule` under it [P].
- **Look:**
  - 1 pt dashed `controlEdge` border, radius 6: in this header, dashed means "make something", as on `+ New project`.
  - The robot (DL-253's mark, 12 × 8, filled) in `text2`.
  - `New session` in `text`, then `in` in `text2`.
  - The popup: 20 high, 1 pt `rule` border, radius 5, 12/16 type, with the up-down chevrons.
  - `⌘T` in `text2` at the trailing end.
- **States:**
  - Hover fills `selected` and the robot turns `text`; pressed fills `menuTarget`.
  - The popup is a system menu.
  - The tooltip is the system's: "New Claude session ⌘T · in ‹folder›".
  - Focus with Tab, and Return presses it.
- **The default** [G]:
  - **Duo's Home** (★ home, the `_HOME.md` folder) when there is one;
  - otherwise `~/Documents`;
  - with neither, no default: the popup reads *Choose…* in `text2`, and the row and ⌘T open the popup instead of starting anything.
  - Duo never creates `~/Documents` and never falls back to `~`.
- **The popup**, in order:
  1. the default, ticked;
  2. a rule;
  3. `~/Documents` (when Home is the default), then the projects and the folders chosen before, by last activity;
  4. a rule;
  5. **Choose Another Folder…**, which opens the system folder panel; the folder it gives joins the list;
  6. New Project… (the New project sheet);
  7. with no Home, Choose Home Folder….
- **What it starts:**
  - A Claude session in the chosen folder, in the mode that folder's sessions open in.
  - A project: Duo goes into it with the new tab selected (DL-142 (5)).
  - Home, or a plain folder (`~/Documents` included): the session opens in Home's pane, and lists as a folder row when the folder isn't a project.
  - No shell from the row: ⇧⌘T still opens one in Home.
- **Trust:**
  - Every start goes through the trust check before Claude runs (DL-229, and chat-reliability's trust-before-start sheet).
  - `~/Documents` keeps its trust once given: Claude's home-folder rule is an exact match on `~`, in 2.1.311 and 2.1.284.
- **⌘T at All projects** presses the row (F-446: today it does nothing there).
- **The empty list** shows "No sessions yet" (`text`) and "Start one above, or ⌘T. Sessions show here, newest first." (`control`, `text2`) [P].

## Behaviour a picture can't show

- **macOS asks once for Documents.**
  - `~/Documents` is a protected folder.
  - The first time Duo starts Claude there, or lists its files, macOS asks "“Duo” would like to access files in your Documents folder". Duo spawns Claude, so the prompt is in Duo's name.
  - Reads there wait until it's answered (F-28), so the start must not block the main thread.
  - A managed Mac's profile may grant it or block it. If it's blocked, the session fails to start, and the row's folder must say why (stand-in: the console's folder-missing message).
- **iCloud Desktop & Documents:** the path stays `~/Documents`, but files may be cloud-only, and Claude's reads then download them or fail offline (not tested).
- **A chosen folder that's gone** leaves the popup's list; the default never changes because of it.
- **Open (DL-262):** whether a remembered last pick should override the default. As built: the default every time. A pick lasts only for that start.

## duo2 (DL-71)

- `duo2 session new [--project <p> | --folder <path>]`. `--folder` is new: it starts in a plain folder, which goes through the trust check like the row.
- With neither at All projects, it uses the row's default. With no default, it refuses: "Choose where it starts: --project <name> or --folder <path>".
- The popup is that argument, so it adds no new verb.

## Not drawn (stand-ins)

- The system folder panel (NSOpenPanel, prompt "Start Here").
- The trust sheet (chat-reliability's design).
- A failed start in a blocked Documents folder.

## Exempt from the comparison

- `list-1440-new-session` is home-evolution's approved screen, which predates `+ New project` in the header (Q-158's stand-in): the build keeps that button.
- Names, times and data are illustrative.
