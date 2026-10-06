# Duo — Design brief: everything still waiting on design

Version 1 · 2026-10-04 · Owner: Geoff · Written by Claude from the build plan, the handoffs and the code.

> **Since this brief (to 2026-10-05):** most of it is designed and built.
> - DB-1 to DB-4: `surfaces-handoff/`. DB-16: `frontmatter-handoff/`, built (F-77).
> - DB-5, DB-6, DB-7, DB-9, DB-33, DB-37 to DB-39: slice 2 (`slice2-handoff/`, DL-100, F-76). DB-5 ("choosing a workspace") is replaced by the no-Home pane; there is no workspace.
> - DB-8, DB-10, DB-11, DB-12 (confirmations), DB-14, DB-15, DB-27, DB-36: slice 3 (`slice3-handoff/`, DL-101, F-84).
> - The map with many projects (S4-1, not in this brief): `many-projects-handoff/` (DL-104, F-82).
> - Still open: DB-13 (local HTML look), DB-34 (the Archived rollup's look), DB-35 (revert from the highlight itself; Claude's deletions got Show and Revert in S3-5), DB-17 to DB-24 (v1.1 and search follow-ons), DB-26 (the menu bar), DB-28 to DB-32 (later).
> - "Tasks anywhere: parked" no longer holds (DL-87, DL-93).
>
> Current state of every surface: `docs/design/system/surfaces.md`.

This brief collects, in one place, every Duo surface that the build has reached but no design covers yet, so one design pass can take several at once (C-5). It states needs, not solutions: what each surface must show, its states, its actions and the decisions that bind it. There are no layouts or colours in it on purpose. The design system, the two altitudes and the components are settled (`docs/design/build-handoff/`, `docs/design/search-handoff/`); everything here must look like it always belonged there. Items are grouped in the order the build reaches them (the build plan's design queue). Each has a short id (DB-n). Where something is built today, it is a plain stub in the system look, and the design replaces it. Use the fixture's world for sample content (`docs/design/build-handoff/fixture.json`): topics Payments, Growth, Platform; projects `checkout-redesign`, `refunds-api-spec`, `fraud-rules-review`, `onboarding-v3`, `pricing-experiment-q4`, `api-deprecations`, and Home (`~/work/home`).

**What we want back:** the same shape as `build-handoff/` and `search-handoff/` (target screens at 1440×900 in the light appearance, a manifest, any token additions, fixture additions, and a README covering what a picture can't show), with [G] / [P] marks so Geoff's decisions and the designer's proposals stay apart.

## Summary

Priority: **v1** blocks Geoff using Duo all day (build plan §3a). **v1 look** is built from decisions in a plain look and needs a design to match the rest. **v1.1**, **later**: by the roadmap.

| Id | Surface | Blocks | Priority |
|---|---|---|---|
| DB-1 | What `14 idle, resumable ›` opens | C exit | v1 |
| DB-2 | Terminal colour palette | D | v1 |
| DB-3 | Console with no running session | D | v1 |
| DB-4 | Plain shell tabs | D | v1 |
| DB-5 | First run: choosing a workspace, no projects | E | v1 |
| DB-6 | Home: none, or several | E | v1 |
| DB-7 | Needs you: nothing waiting, the reason, long questions | E | v1 |
| DB-8 | Project folder moved or missing | E | v1 |
| DB-9 | Create a project | E | v1 |
| DB-10 | Settings | L (and E) | v1 |
| DB-11 | Legacy Duo notice | F | v1 |
| DB-12 | Folders, moving and merging | J (minimal) | v1 look |
| DB-13 | Local HTML tab and the element picker | K (part) | v1 look |
| DB-14 | Editor notices: conflict, removed, read-only | I | v1 |
| DB-15 | How the editor draws a document | I | v1 |
| DB-16 | Properties (frontmatter), and the Project tab | I | later |
| DB-17 | Group page | G | v1.1 |
| DB-18 | Grouping by hand | G | v1.1 |
| DB-19 | Version history, compare, revert Claude's change | I follow-on | v1.1 |
| DB-20 | Browser tab for allowed sites, and the allow list | K | v1.1 |
| DB-21 | Search filter menus opened, date range | M | with search UI |
| DB-22 | Memory result row in search | M | with search UI |
| DB-23 | Find similar, started outside search | M (P3) | later |
| DB-24 | Search's "Go to" rows: actions and recents | M | with search UI |
| DB-25 | Narrow windows, right-pane collapse, motion | L | v1 look |
| DB-26 | Menu bar | L | v1 |
| DB-27 | Notifications and the Dock badge | L | v1 (to confirm) |
| DB-28 | Split view: a document beside a document | later | later |
| DB-29 | Dark appearance | later | later |
| DB-30 | Routing an ask from Home to a project | later | later |
| DB-31 | Full consolidation (curation) | J (full) | later (v1.2) |
| DB-32 | Component sheet at all states | — | with each pass |

**Left out on purpose:**

- The search modal and the ⌘K palette: designed (`search-handoff/`). DL-80 merged Jump into Search and freed ⌘K, so there is no ⌘K palette to design.
- Quick-reply buttons on cards: backlogged (DL-29).
- The resume-first list (LR-7): replaced by history in place, with older sessions folded under `Older · N` (DL-59). Built.
- The Project tab as a card: it opens `PROJECT.md` in the editor (DL-60). What remains is DB-16.
- Retention consent: dropped. Duo never changes Claude's global setting (DL-57).
- Tasks anywhere: parked (DL-25).
- What a sent reference looks like in the terminal: that is Claude Code's output, not Duo's.
- `@` file completion in a session (ENH-3): on hold until Geoff tries Claude Code's own (G-5).

---

## 1. Navigation (design queue 1, Phase C)

### DB-1 · What `14 idle, resumable ›` opens

- **Where, when:** the footer under the project map at All projects. The user meets it when they want something they worked on days ago and can't see it in a tile (tiles list only running sessions).
- **Shows:** every idle, resumable session across all projects. Fixture: 14 (`Interview synth` 2d and `quick q about tax rules` 3d in `checkout-redesign`, plus 12 others). Per session: title (LR-6's title ladder), project (or **Unfiled**), last activity ("ages by last activity", already built), and whether it is in a group (`PRD v2`). Purged-but-archived sessions are listed too, under their archived title (DL-47, DL-49).
- **States:** none idle (footer at 0); a few; hundreds over months; very long titles; sessions from folders that aren't projects (DL-63); a session running outside Duo (Terminal, the Desktop app) that must not be resumed twice (LR-8); narrow window (map about 600 wide at 1280×800).
- **Actions:** resume a session (opens its project with that session in the console, as clicking a row in the project's list does today). Probably also: go to its project, move it to a project (DL-64, DL-66 sheet). Menu labels for those already exist: `Move to Project`, `Send to Claude`, `Send To ▸` (DL-69).
- **Constraints:** a running-but-quiet session shows the idle glyph and is not counted as resumable (DL-55). Never `claude -c` or the picker (DL-14). Must work by keyboard (§10).
- **Today:** the footer is drawn and counts correctly; clicking it does nothing (`ProjectMapPane` in `Sources/DuoKit/AllProjects/AllProjectsPanes.swift`). Inside a project, idle sessions already list under `Older · N` (DL-59).
- **Questions:** Is this a popover, a sheet, a tab, or a filter on the map? Should it sort by recency or by project? Does it need its own search now search exists (DL-80), or is "search for it" the answer and the footer just a count? (Q-11)

---

## 2. Terminals (design queue 2, Phase D)

### DB-2 · Terminal colour palette

- **Where, when:** every terminal: the Home pane and the console. Always on screen.
- **Shows:** the 16 ANSI colours (normal and bright), plus cursor and selection, on the `console` background with `consoleText` as the default foreground. Claude Code's TUI uses colour for diffs (added/removed lines), its prompt box, permission prompts, spinners and links.
- **States:** a diff in a permission prompt; a long tool output; a selection; a plain shell with `ls --color` (DB-4); Increase Contrast on.
- **Constraints:** two-tone look, one accent for needs-you (DL-26). The accent must not become an ordinary terminal colour that reads as "needs you". Contrast on `console` checked like §10's table. SF Mono 12 (DL-36). Duo draws nothing inside the terminal (DL-27).
- **Today:** SwiftTerm's default ANSI palette, with background and foreground from the tokens (`Sources/DuoKit/Terminal/Terminals.swift`, "until one is designed").
- **Questions:** Should red and green in diffs be muted to sit with the two-tone look, or kept loud? Should the selection colour match the editor's?

### DB-3 · Console with no running session

- **Where, when:** the console (middle pane inside a project) and the Home pane, whenever there is no live terminal to show.
- **States to cover:**
  - **No session in this project** (LR-11: "No session in ‹project› · Start Claude here"). Example: `api-deprecations`, nothing running.
  - **Claude Code not installed or not found** (LR-19). Today the terminal prints "Claude Code isn't installed, or Duo couldn't find it."
  - **Running elsewhere:** the session is live in Terminal or the Desktop app, so Duo won't start a second writer (LR-8). Today the pane is blank.
  - **Session ended:** the process exited (the user typed `/exit`, or it crashed).
  - **Folder gone:** the session's working folder is missing (LR-18 falls back; see DB-8).
  - Home with no session: rare, since Duo starts one at launch (DL-54), but possible after closing the last tab.
- **Actions:** start a session here (`+ New session`), resume the last one, open Settings to set the `claude` path (DB-10), and for "running elsewhere" a way to see where. Labels not decided.
- **Constraints:** dark pane, Duo's own chrome (not drawn inside a terminal, DL-27). Never resize a terminal below 8×1 (LR-14).
- **Today:** a blank dark pane (`ConsolePane` in `Sources/DuoKit/Project/ProjectPanes.swift`, `HomePane` in `AllProjectsPanes.swift`); the missing-Claude text is fed into the terminal (`showMissingClaude`).
- **Questions:** One empty-state layout with different messages, or distinct treatments? Should "running elsewhere" offer to take over (end the other process), or only explain?

### DB-4 · Plain shell tabs

- **Where, when:** console tab strip, beside Claude session tabs (DL-8). The user opens one to run `git`, `npm` or a script in the project folder.
- **Shows:** a tab for a shell (title: the shell, or its running command, or the folder), distinct from a Claude session tab, which carries a state glyph. Typing `claude` in it promotes the tab to a tracked session (DL-8): the tab changes kind in place.
- **States:** one shell; several shells and sessions mixed; a long-running command; promotion happening; the shell exited; narrow console (about 520 wide at 1280×800).
- **Actions:** open a new shell tab, close it (`⌘W` closes a tab, DL-34 / F-38). Today the console's `+` makes a Claude session.
- **Constraints:** the chrome strip is the existing console tab strip (36 high, mono 12). Tab roles for VoiceOver (LR-63).
- **Today:** the terminal kind exists (`TerminalCommand.shell`) but nothing opens one, and auto-promotion isn't built.
- **Questions:** How does the user ask for a shell rather than a session: a menu on `+`, a second button, a chord? Does a shell tab need any glyph? Does a promoted tab announce the change?

---

## 3. First run, Home and the workspace (design queue 3, Phases E and F)

### DB-5 · First run: choosing a workspace, no projects

- **Where, when:** the first launch, and any launch where the workspace has no projects.
- **Shows:** what Duo needs to get going: a workspace folder (today only a `--workspace` launch flag; Q-12 lists "the workspace root for new projects"), what Duo found in it (projects with `PROJECT.md`, a `HOME.md`, folders that only have Claude history, DL-63), and the install question (DL-75), which today is a system alert listing every file change.
- **States:** brand-new Mac with no Claude history; lots of Claude history but no `PROJECT.md` anywhere (everything shows as folders, DL-63); a workspace with projects but no Home (DB-6); Claude Code missing (DB-3); scanning in progress (lists render from what is known, never a spinner, §8); a protected folder skipped (F-53).
- **Actions:** choose the workspace folder; make a project (DB-9); make Home (DB-6); the install question's `Install` / `Not Now` (built, DL-75).
- **Constraints:** never trigger macOS privacy prompts by scanning Music, Photos and so on (F-53). Questions are sheets, never app-modal (F-54). Plain, short copy (§8).
- **Today:** without `--workspace` the app shows the design fixture. No first-run screen.
- **Questions:** Is first run a dedicated screen, or All projects in an empty state with guidance? Should Duo propose a workspace (for example the parent of the most active Claude folders), or always ask?

### DB-6 · Home: none, or several

- **Where, when:** Home is the folder with `HOME.md` (DL-42, DL-52). The user meets this when there's no Home yet, or more than one folder has a `HOME.md`.
- **Shows:**
  - **No Home:** the left pane of All projects has nothing to show. §8 suggested it starts collapsed. Duo "helps create it" (DL-42).
  - **Several:** Duo uses the last used one and shows "a quiet notice naming them with Use this one on each"; the others appear as normal projects with an "also has HOME.md" note (DL-42).
- **States:** no Home; two candidates (fixture: `~/work/home` and, say, `~/work/growth/home-old`); Home's folder moved (DB-8).
- **Actions:** make this folder Home (writes `HOME.md`; Duo never edits or deletes one it didn't just create, DL-42); `Use this one` (label decided, DL-42).
- **Constraints:** Home is a project (goal, sessions) pinned to the left pane at All projects, not on the map (§2.3). Live mode starts a Home session when Home has none (DL-54).
- **Today:** the choice is made and flagged as contested (`ProjectDiscovery.chooseHome`), but no notice is shown and nothing helps create Home.
- **Questions:** Where does the "several" notice live (map, Home pane header, a sheet)? With no Home, does the pane disappear or invite?

### DB-7 · Needs you: nothing waiting, the reason, long questions

- **Where, when:** the action column at All projects, and the peek popover (cards are shared).
- **Shows, beyond the targets:**
  - **Nothing needs you:** the column today shows only `Ready for review`, or nothing at all when that is empty too. §8 suggested "a single quiet line".
  - **The reason** a session needs you: permission, question, plan to approve, blocked (LR-1). Not drawn; §8 suggested appending it to the project line (`onboarding-v3 · permission`).
  - **Long questions:** shown verbatim, never summarised (brief §7). §8 suggested a 6-line cap with "more" on unselected cards. The fixture's `PRD v2 edits` question is the long case.
- **States:** zero needs-you and zero review; many (10+) needs-you; a question with a code block or a long path; a Home session needing you (the pointer card, built); a session whose question is unknown (fails toward needs-you, LR-2).
- **Constraints:** the accent is only for needs-you (DL-26); never colour alone (LR-63). No reply buttons (DL-29); `Open project` is the action (DL-58).
- **Today:** `ActionColumnPane` in `AllProjectsPanes.swift` draws the targets' cards; no reason, no cap, nothing for the empty case.
- **Questions:** What should the empty column say, if anything? Does the reason need its own shape, or is a word enough?

### DB-8 · Project folder moved or missing

- **Where, when:** when a project's folder is renamed, moved or deleted outside Duo (LR-23, brief C5). Seen on the map tile, inside the project, and on open documents.
- **Shows:** what is gone (`~/work/payments/refunds-api-spec`), where Duo thinks it went (if found), that the sessions are safe and still resume by id (DL-14), and what the user can do.
- **States:** renamed in place; moved within the workspace; moved outside it; deleted (in the Trash); on an unmounted disk; an open document's file removed (DB-14 covers the editor's side).
- **Actions:** point Duo at the new place, remove the project from Duo, reveal in Finder. Labels not decided. Moving transcripts (`/cd`-style relocation) is v1.1 (§3a); in v1 sessions keep resuming by id.
- **Constraints:** a banner and a revert to a valid state, never a crash (LR-23). Questions are sheets (F-54).
- **Today:** no notice. Projects are found by scanning the workspace, so a moved folder simply shows up at its new place or drops off the map. The registry that would notice a move (Phase E4) isn't built yet.
- **Questions:** Banner on the tile, inside the project, or both? Does a missing project stay on the map greyed, or move to a separate place?

### DB-9 · Create a project

- **Where, when:** `+ New project` on the map (brief C4); `New project "…"` at the end of search results (LR-25, DL-80); `Make a Project` on a folder tile (DL-63, built).
- **Shows:** the name, where it will live (which topic folder; DL-63 says the button "creates a folder under Home" and "open its PROJECT.md"), and the starting `PROJECT.md`: Geoff's template (G-1, not yet written), with goal, health and next milestone as frontmatter (§11, DL-60).
- **States:** a name that already exists; a name with characters a folder can't take; a topic that doesn't exist yet (a new parent folder); no workspace chosen (DB-5); the folder is inside a git repo (the `.gitignore` offer follows, DL-50).
- **Actions:** create, then open the project with `PROJECT.md` in the right pane. Naming new items is inline like Finder (DL-62), with `Untitled` selected; whether that applies to projects too is open.
- **Constraints:** Obsidian-compatible files (DL-6, DL-17, DL-18). No `.base` or `.obsidian/` written (DL-20).
- **Today:** `NewProjectTile` is inert ("The create-project flow is not designed"). Waits for the template (G-1).
- **Questions:** Inline on the map (a tile that takes a name) or a sheet? Is "under Home" in DL-63 the Home project folder or the workspace root? Can the user pick the topic?

### DB-10 · Settings

- **Where, when:** Duo › Settings… (`⌘,`). Rarely visited.
- **Shows, v1 minimum (Q-12):**
  - The path to `claude` (found automatically; LR-19 wants an override).
  - The workspace folder (DB-5).
  - The archive's size on disk, with no limit (DL-56).
- **Shows, later or optional:** console type size and line height (LR-21); whether the `duo2` install is on, with its file list (DL-74, DL-75); legacy Duo's instructions, disabled or not (DL-39, DB-11); the templates folder for New from Template (DL-61); the browser allow list (DL-3, a user-editable file; DB-20).
- **States:** `claude` not found; a custom path that isn't executable; archive empty or very large; install declined.
- **Constraints:** a native Settings window. Retention consent is gone (DL-57). Everything here also needs a `duo2` verb (DL-71) unless listed as a deliberate exception.
- **Today:** `Settings { EmptyView() }` in `Sources/Duo/DuoApp.swift`. Nothing.
- **Questions:** One pane or tabs? Which of the "later" items belong in v1?

### DB-11 · Legacy Duo notice

- **Where, when:** at launch, when legacy Duo has left a skill, subagent, hooks or a `CLAUDE.md` block in `~/.claude` that loads into every session (DL-16, DL-39).
- **Shows:** what legacy installed (each item, by path), that it describes legacy commands to Claude, and that disabling backs everything up and can be undone (DL-39).
- **States:** nothing found (no notice); some found; disabled (with Restore); a partial disable that failed.
- **Actions:** disable (backed up, reversible), restore, not now. `duo2 legacy detect | disable | restore` already does this (F-37).
- **Constraints:** never silent (DL-39). A sheet, not an app-modal alert (F-54). The two other launch questions are system alerts today (install, DL-75; `.gitignore`, DL-50); the design can say whether they stay that way.
- **Today:** CLI only. "The in-app notice waits for a design" (F-37).
- **Questions:** A sheet at launch, a quiet banner, or a line in Settings? Should all three launch questions share one form?

---

## 4. Before v1 documentation (design queue 4; Phases I, J minimal, K part)

### DB-12 · Folders, moving and merging

- **Where, when:** All projects. Built from decisions DL-63 to DL-66 in the targets' parts, without a design. Needs a look pass, not new behaviour.
- **Shows:**
  - **Folder tiles:** a folder with Claude history but no `PROJECT.md`, in its topic or an `Elsewhere` column outside the workspace, marked `No project file` or `Has CLAUDE.md · no project file`, its path and `n past sessions` (DL-63).
  - **Move and merge confirmation:** a sheet saying exactly what moves (which sessions, from where, to where, and that files stay), then Edit › Undo (DL-66).
  - **Drag feel:** a white card with the popover shadow follows the pointer; the source sinks; the target rises; the target says `2 sessions moved in` (F-51, Geoff asked for this).
- **States:** many folder tiles (people have dozens of stray folders); a folder path too long for a tile; a merge of 40 sessions in the sheet; undo; dropping onto Home (allowed) or onto itself (not).
- **Actions (labels built):** `Make a Project`, `Merge Into`, `Merge Sessions Into`, `Move to Project`, `Send to Claude`, `Send To ▸`.
- **Today:** all of the above in `AllProjectsPanes.swift` (`ProjectTile`, `SessionOrganizeMenu`, `ProjectOrganizeMenu`, `DragCard`, `DropTarget`) and `AppModel+Organize.swift`.
- **Questions:** Should folder tiles look different from project tiles beyond their text? Is `Elsewhere` the right name and place? Edit › Undo shows "Undo" without the action's name (F-51): should it name it?

### DB-13 · Local HTML tab and the element picker

- **Where, when:** the right pane, when the user opens an `.html` file from the tree (DL-67). The picker starts from right-click › Select Element (DL-70) to send a page element to Claude.
- **Shows:**
  - **The tab:** the page alone, read-only, reloading when the file or its styles, scripts and images change (LR-49). Links to other sites open in the system browser (DL-3).
  - **Picking:** a hover outline, a frozen outline on click, and a bar naming the element (`<tag#id.class>`) with `Send to Claude`, `Send To ▸`, `Pick Another`, `Cancel`; Esc exits (DL-70, Q-21). Before a click the bar says "Click an element to select it. Esc to stop."
- **States:** page loading; file deleted while open; a page with errors (blank); a tiny element, a full-page element, an element under a fixed header; no Claude session to send to (the plain item says why, DL-69); a page wider than the pane (460 wide); find in page (LR-49).
- **Constraints:** the outline must never use the needs-you accent (DL-70). Native bars, sheets and popovers over web views, never DOM overlays (LR-59). Sending is inline text, Enter never pressed (DL-67, DL-68). `⌘D` sends a selection (DL-79).
- **Today:** `PickerBar` in `Sources/DuoKit/Project/ProjectPanes.swift`, outline in the system Highlight colour (`Sources/DuoKit/Editor/HTMLPicker.swift`), viewer in `Sources/DuoKit/Editor/HTMLViewer.swift`. No chrome on the tab.
- **Questions:** Does the HTML tab need any chrome (path, reload, open in browser)? Should the picker bar sit at the bottom, at the top, or by the element?

### DB-14 · Editor notices: conflict, removed, read-only

- **Where, when:** under or over the document in the right pane, when it needs a decision (DL-77, Q-20).
- **States to cover:**
  - **Conflict:** the file changed on disk on the same lines the user is editing, so the merge can't settle it. Autosave pauses and both versions are kept (DL-77). Example: "Changed on disk where you're editing (lines 40–58). Both versions are kept." Actions `Keep Mine` (default) and `Use Theirs` (DL-77; also `duo2 doc resolve`).
  - **Removed on disk:** the text stays; `Save to Recreate` (DL-77).
  - **Read-only:** a file Duo won't edit safely, such as mixed line endings or not UTF-8 (Q-20). Shows why.
  - **Moved on disk** (a rename the watcher saw): today it reads as removed.
  - Several conflicts in one file; a conflict in a document that isn't the visible tab (it shows on return).
- **Constraints:** never lose either side (DL-77). Claude's edits arrive through the editor (DL-78), so most outside changes merge silently and no notice shows.
- **Today:** `DocumentStateBar` in `ProjectPanes.swift`, a plain system bar with the text and buttons above; nothing for read-only (the editor shows the type only).
- **Questions:** Should a conflict show where it is in the text (the lines), not only in the bar? Is a Compare view needed in v1 (F-50 lists it as not yet), or is that DB-19?

### DB-15 · How the editor draws a document

- **Where, when:** the right pane's CodeMirror live-preview editor, all the time (Phase I).
- **Shows:** Markdown as it reads, not as raw syntax: headings, lists and task lists, tables, images (LR-39, pasted images are saved beside the doc), code blocks, block quotes, links (relative Markdown links, DL-17), frontmatter (until DB-16), and Claude's changes (`added by Claude` with the selected fill, cleared on the user's next edit, DL-5, LR-33). Deleted text isn't marked today (F-50).
- **States:** a 1.2 MB file (S4/S6); a very long line; a wide table in a 460 wide pane; a missing image; a code block in a language with no highlighting; a document Claude is editing as the user types; find (`⌘F`, CodeMirror's own, F-43).
- **Constraints:** the target's type (headings 14 semibold, body 13/20, padding 22 28) is a placeholder for this (§3.3). Byte-faithful saves (LR-30): the drawing never changes the file. Native menus, spellcheck, dictation and Writing Tools (C-12). Tokens injected as CSS variables, no raw hex (F-40).
- **Today:** token-styled CodeMirror (`Sources/DuoKit/Editor/DocumentEditor.swift`); fixture mode shows a placeholder (`DocumentPlaceholder`).
- **Questions:** Should Claude's deletions be shown, and how long does a change stay marked? How much does live preview hide (for example, do `**` markers disappear away from the cursor)?

### DB-16 · Properties (frontmatter), and the Project tab

- **Where, when:** the top of any Markdown document with frontmatter, and the Project tab, which is `PROJECT.md` (DL-60). Tasks use it too when they return (`tasks/*.md`, DL-6).
- **Shows:** properties as typed fields: text, list, date, checkbox, link (ENH-1, LR-37). For a project: `title`, `aliases` (DL-18), goal, health, next milestone. For Home: the same fields in `HOME.md` (DL-52).
- **States:** no frontmatter; malformed YAML (shown, not thrown away); unknown keys; a long list; Obsidian keys Duo reads but never writes (`scheduled`, `priority`); a property Claude just changed.
- **Constraints:** expanded by default; one-click edits with undo; the body untouched by property edits; the YAML stays byte-faithful and Obsidian-readable (LR-37, DL-6). No nested `duo.*` keys.
- **Today:** frontmatter is raw text in the editor.
- **Questions:** Does the Project tab need anything beyond `PROJECT.md` with properties (for example, the project's sessions or key files, LR-29), or is DL-60's plain file enough?

---

## 5. v1.1 (design queue 5)

### DB-17 · Group page

- **Where, when:** a right-pane tab, opened by selecting a group row in the project's session list (fixture: `PRD v2` in `checkout-redesign`, 3 sessions).
- **Shows (from the wireframe, `build-handoff/screens/wireframes/group-page.html`):** title and `Group · 3 sessions`; sessions oldest first, each with state, age and a one-line summary; forks indented under their parent with `Fork of ‹name›` (`PRD v2 edits` is a fork of `Interview synth`); `Resume ‹most recent›` and `+ New session here`; `DOCUMENTS` the sessions touched (`docs/prd-v2.md`); a reserved `TASKS` slot.
- **States:** a group of 1; of 20; a session needing you inside the group; sessions in different states; a group whose documents were deleted; narrow right pane (360 minimum).
- **Constraints:** a group shows the state of its most urgent session (DL-24). Groups are Duo-owned, in `.duo/sessions.json` (DL-1). Tasks parked (DL-25).
- **Today:** the tab appears with an empty body (`RightPane` in `ProjectPanes.swift`).
- **Questions:** Does the group page earn its place in v1.1, or does the expanded group row cover it?

### DB-18 · Grouping by hand

- **Where, when:** the project's session list. The user puts related threads together (DL-24).
- **Shows (wireframe `grouping.html`):** select rows, name the group, press Group; or drag one row onto another. A session can do the same with `duo2` (DL-71 requires a verb).
- **States:** naming (inline, DL-62); grouping a session that's already in a group (a session is in at most one, §11); ungrouping; renaming; grouping across states.
- **Constraints:** drag feel should match the map's (DB-12, F-51).
- **Today:** groups are displayed; there is no way to make one in the app.
- **Questions:** Is drag enough, or is a multi-select plus menu needed too? What does ungroup look like?

### DB-19 · Version history, compare, revert Claude's change

- **Where, when:** from a document. History is kept already (DL-77: the file as opened, both sides of a conflict, what a resolution replaced, text before a removal; at most 200 per file).
- **Shows:** a list of versions (when, and why: opened, conflict, Claude's change, restore); a compare view between any version and now; restore through the normal write path (LR-38). ENH-4: undo one of Claude's changes from its highlight, and revert all of Claude's changes since the user last looked.
- **States:** no history; hundreds of versions; a version from before a rename; a binary or huge file; a restore while Claude is editing.
- **Constraints:** version history is DL-5's next step; tracked suggestions (CriticMarkup) come later.
- **Today:** history on disk and `duo2 doc history`; no UI.
- **Questions:** Is compare side by side or inline? Where does "revert all of Claude's changes" live?

### DB-20 · Browser tab for allowed sites, and the allow list

- **Where, when:** the right pane, when the user opens a web page from a site on the allow list (DL-3). Other sites open in the system browser.
- **Shows:** the page; where you are (URL or title); back, forward, reload; that a link was "sent to your browser" (LR-50); the element inspector (as DB-13) on allowed sites (LR-44); when Claude is driving the page (LR-45, LR-46: Claude never steals the user's tab or focus).
- **Allow list:** a user-editable file (`host`, `*.suffix`, `{host, reason}`, LR-50); a way to add the current site.
- **States:** logged in and kept across relaunch (LR-43); a sign-in redirect to a site not on the list; a page Claude opened in a new tab; an error page; several web tabs among documents.
- **Constraints:** local-only by default (DL-3); native chrome over the web view (LR-59); `⌘R` never reloads the app (LR-60).
- **Today:** only local HTML (DB-13). Spike S7 passed.
- **Questions:** How does the user add a site: from the "sent to your browser" notice, from Settings, or both?

---

## 6. Left by the search design (design queue 6, Phase M; search-handoff §9)

### DB-21 · Search filter menus opened, and a date range

- **Where, when:** the search modal's filter row (project, kind, date, Include archived), opened by click or `⇧tab` (DL-79).
- **Shows:** the project list (with **Unfiled**, and folders, DL-63), kinds (file, session, memory), date presets and a custom range.
- **States:** 40 projects; a filter that hides every result (`search-none` is designed); keyboard only.
- **Today:** the modal is being built from `search-handoff/` (M-UI); the menus aren't drawn there.
- **Questions:** Which date presets?

### DB-22 · Memory result row in search

- **Where, when:** a search result that is Claude's own memory note for a project (indexed already, F-38).
- **Shows:** what the row, its kind icon and its preview show for a memory note (project, file, passage), next to file and session rows.
- **Questions:** What does Return do on a memory result: open the file, or something else?

### DB-23 · Find similar, started outside search

- **Where, when:** right-click on a file in the tree or a session row, or a document tab (search-handoff §9). The search modal has its own `search-similar` state designed.
- **Shows:** probably that same state, opened with the source as its chip. Needs confirming.
- **Questions:** Is it a menu item that opens the modal in `Similar to` mode, or something in place?

### DB-24 · Search's "Go to" rows: actions and recents

- **Where, when:** DL-80 merged Jump into Search: name matches (projects, groups, sessions) come first as a "Go to" block, reusing `search-jump`'s rows, then content results, then `New project "…"`. No new row design is needed. Two gaps remain.
- **Gaps:** what Tab shows on a "Go to" row (search-handoff left Jump's action menu undesigned); whether the empty state, designed as recent searches plus help (DL-79), should also show recent and starred projects and sessions (LR-25 asked for recents and starred).
- **Questions:** Both of the above. Possibly answerable by Geoff without a design pass.

---

## 7. Cross-cutting, Phase L and later

### DB-25 · Narrow windows, right-pane collapse, motion

> Designed and built: DL-129, `narrow-handoff/`, F-128 to F-130.

- **Where, when:** everywhere. Only 1440×900 was drawn; the window must hold at 1280×800 (§3.1, §7).
- **Shows:**
  - The search modal below 1440×900 (search-handoff §9 suggests a rule).
  - The map with more than three topics (§7 suggests an adaptive grid, 220 minimum); a project not under a topic (§8).
  - A visible control to collapse the right pane (`⌥⌘0`, DL-34, has no button).
  - Motion beyond §9's proposals: the scrim, panes collapsing, tiles appearing.
- **States:** 1280×800 at both altitudes; the minimums in §7 (console 480, right pane 360); Reduce Motion on.
- **Today:** §7 and §8's proposals are built where they apply; no right-pane button.

### DB-26 · Menu bar

- **Where, when:** the macOS menu bar. Every action is in a menu and also a `duo2` verb (DL-71, DL-72).
- **Shows:** the full menu structure and labels: the Go menu (All Projects `⌘↑`, Home `⇧⌘H`, Needs You Elsewhere `⇧⌘P`, panes `⌥⌘←`/`⌥⌘→`), Format, file verbs (DL-61), Send Selection to Claude `⌘D` (DL-79), Search `⇧⌘A` (DL-46), Close Tab `⌘W`, Close Window `⇧⌘W`.
- **Constraints:** one chord registry; a chord change needs a log entry (DL-34, LR-60); avoid `⌘\` and `⌘⌥L/;/'` (LR-60). ⌘K is free (DL-80).
- **Today:** menus generated from `Sources/DuoKit/Navigation/Commands.swift`; arranged ad hoc.
- **Questions:** Which top-level menus (Session? Project? View?) and in what order? Should ⌘K be given to something?

### DB-27 · Notifications and the Dock badge

- **Where, when:** when Duo is in the background and a session starts needing you.
- **Shows:** possibly a macOS notification (session, project, the question) and a Dock badge count.
- **Constraints:** actionable events only (LR-2); never for the focused session; announce politely to VoiceOver (§10). macOS asks permission for notifications, which must not block unattended runs (F-54).
- **Today:** nothing.
- **Questions:** Does v1 want notifications at all, or only the badge? Which events: needs you only, or also ready for review?

### DB-28 · Split view: a document beside a document

- **Where, when:** side-by-side documents are later (DL-11). Search's `Open in split view ⌥⌘↩` (DL-79) depends on it.
- **Questions:** Is split view two right-pane documents, or a document beside the console? Until it exists, should the search action be hidden?

### DB-29 · Dark appearance

- **Where, when:** later (§12 Q4). Light only in v1. `tokens.json` carries a provisional dark set Geoff passed over, with a control border short of 3:1.
- **Shows:** a dark chrome that keeps the two-tone idea (DL-26), every token, and the search scrim.

### DB-30 · Routing an ask from Home to a project

- **Where, when:** Home's inbox suggests where asks go (fixture `homeInbox`: "Legal wants a call re: saved cards", suggested → `checkout-redesign`). Today those suggestions are terminal text, so any control must live in Duo's chrome (§13; brief prompts C2, D).
- **Questions:** Is this still wanted, given Home is a Claude session that can run `duo2` itself? Needs rethinking, not only drawing.

### DB-31 · Full consolidation (curation)

- **Where, when:** v1.2 (Phase J full): archive by move, delete, tandem folder moves, splitting catch-all folders with deterministic evidence facets (DL-41 L3a), duplicate and collision repair. The v1 minimum is DB-12.
- **Constraints:** pointers first; a journaled, undoable migrator; agents may propose, never execute (DL-41). Search may help (SRCH L14).
- **Questions:** Is this its own view, or more actions on the map's folder tiles?

### DB-32 · Component sheet at all states

- **Where, when:** brief prompt E, beyond what `look.html` shows: hover, pressed, focus rings, disabled, Increase Contrast, for every component in §5. Best done alongside each pass above.

---

## Constraints that apply to everything

- The screens are the build target; system-drawn chrome is exempt (DL-26).
- One accent, for needs-you only; never colour alone (DL-26, LR-63).
- Plain, short, sentence-case copy, no exclamation marks (§8).
- Every action reachable by keyboard and by `duo2` (§10, DL-71).
- Questions are sheets on the window, never app-modal alerts (F-54).
- Native menus, sheets and popovers above web views (LR-59).
- Tokens only; any new colour or size goes in a tokens addition, as search did.


---

## Added after the brief (2026-10-04, from Geoff's requests)

| Id | Surface | Blocks | Priority |
|---|---|---|---|
| DB-33 | Active sessions: a session with a terminal open in Duo, on tiles and in the project's session list (ENH-7). Built with a provisional tint distinct from `selected`; needs its own treatment that still reads when the row is also selected. | — | v1 look |
| DB-34 | The Archived rollup at the bottom of the project map (ENH-6): folded and open, how archived tiles look, how Unarchive is offered. Built as a section label with a chevron and plain rows. Today it sits at the end of the map's scroll; decide whether it stays visible above the footer. | — | v1 look |
| DB-35 | Revert Claude's change from the highlight itself (ENH-4). Built as menu items (right-click, Edit); the highlight has no affordance of its own yet. | — | v1 look |
| DB-36 | Delete Session… confirmation: today a standard sheet listing the paths and bytes. Whether a typed confirmation is wanted for many at once (CONS FR-7.6.2) when bulk delete arrives. | — | later |
| DB-37 | Home's pane with no Home folder (DL-84): today the console message layout ("No Home folder yet", Choose Home Folder…) under an empty tab strip. Also the first launch, now that Duo opens on every session with no setup (DL-82). | — | v1 look |
| DB-38 | Map columns by folder (DL-83): an unlabelled first column for projects directly in Home; columns outside Home labelled by path (`~/repos`), which can be long and are truncated today; columns wrap into rows when more than fit at 220 each. Whether outside-Home columns need a visual break from Home's. | — | v1 look |
| DB-39 | Move into Home… (DL-85): today a standard confirmation naming the old and new paths and the session count. Whether Home-or-not shows on tiles at all, and a drag onto Home's heading as another way in. | — | v1 look |
