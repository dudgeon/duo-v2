# Duo — Design brief, slice 2: sessions first, Home, tasks and the lists

Status: ready for the design session · 2026-10-04 · Owner: Geoff · One brief, written once the model was settled (DL-95). It amends `design-brief-2026-10-04.md` (DB-n) and `surfaces-handoff/README.md`'s slice plan; where they disagree, this wins, and `decisions.md` wins over both.

> **Designed (2026-10-05), awaiting review:** https://claude.ai/artifact/JSmkQh1Gsj9uyPSzkcuQFV (Q-29).
>
> **Read first:** the Duo design system: `docs/design/system/`, published at https://claude.ai/artifact/QMapKeLYS3TVV36QKEc6MH. It holds the tokens, every component's guidelines and status, every surface's status, and screens of the app as built.

Slice 1 (DB-1 to DB-4) is built and in review. This slice was going to be DB-5 to DB-9. Geoff has since changed what Duo's objects are (DL-82 to DL-98), which redraws several of those and adds the two places people spend most of their time: the map and a project's session list. Everything below is built today with a plain stand-in look, so the shapes and the copy can be tried in the app; nothing here is a new feature to invent, only a look to give it.

## 1. The model now (read first)

| Object | What it is | Decided |
|---|---|---|
| **Session** | One Claude Code conversation. Duo lists **every** session in Claude's logs on launch, with no setup; sessions outside Home are first-class (open, resume, search). | DL-82 |
| **Folder** | Where a session ran. A folder with sessions and no `PROJECT.md` is shown as a folder ("No project file"). | DL-63 |
| **Project** | A folder with `PROJECT.md`, wherever it is. A session belongs to the deepest project around the folder it ran in. A project inside another project's folder shows as its **sibling** (parenthood isn't shown). | DL-82, DL-89 |
| **Home** | Optional. The folder that holds the projects you track (`HOME.md` at its top), chosen by each user (Geoff's: `~/claude-home/`). Home's own session runs in it. **Move into Home…** brings a project in with its sessions. | DL-84, DL-85, DL-94 |
| **Topic** | A folder that isn't a project but holds projects. Nothing marks it. Inside Home, a project's column is the folder it sits in (none, the unlabelled first column, when it sits directly in Home); outside Home, the parent folder's path (`~/repos`). | DL-83, DL-89 |
| **Task** | A Markdown note in a project's `tasks/` folder. Its frontmatter `sessions:` list links the sessions working on it (`- "[title](duo2://session/<id>)"`). A to-do first; sessions are optional. | DL-87, DL-93 |
| **Group** | Sessions bundled by hand, held only by Duo. Kept beside tasks. | DL-88 |
| **Thread** | A session and its forks, folded into one row. Unchanged. | DL-24 |
| **Session link** | `duo2://session/<id>`. Copy Link on any session; clicking one in a note opens or resumes it. | DL-87 |

Things that no longer exist: "New session" as a name (DL-90), sections by state in the session list (DL-91), a required workspace (DL-82), the single "Elsewhere" column (DL-83).

## 2. Surfaces in this slice

Each: what it is now in the app, what's decided, and what's open for you. **Bold** items are the ones Geoff will look at first.

### S2-1 · **A project's session list** (replaces the state sections in `project.html`; DL-90, DL-91, DL-93, DB-33)
- **Built:** sections **Needs you** · **Open · n** (sessions with a tab open in Duo, whatever Claude is doing; they read "at prompt" or "working" in place of a time) · **Today** · **This week** · an **Earlier · n** fold · the **Archived · n** fold. Open rows carry the provisional active tint (DB-33).
- **Task rows and group rows** sit together in each section by their most urgent session; a pill says `task · n` or `group · n`. A task row opens its note in the right pane; a group row its group tab. Both fold open to their sessions.
- **Untitled sessions:** the first words typed, in quotes (`“Summarise the six buyer…”`), or `Session 4:12 PM` before anything is typed.
- **Open:** the Open section's look against Needs you (both are "live"); whether "at prompt" / "working" is the right wording and weight; how task and group rows differ beyond the pill (a task can have a status: open, in-progress, waiting, review, done); the history labels' rhythm; where "Resume a session" (in `project.html`) goes now.
- Session-list exploration Geoff chose from: `docs/design/explorations/session-list.html`, option A.

### S2-2 · **The map** (amends `overview.html`, DB-38, DB-34; DL-83, DL-89, DL-92)
- **Built:** columns are folders. A label is a folder mark, the folder's own name and a trailing slash (`payments /`, `~/repos /`); projects directly in Home sit in an unlabelled first column; Home's topic folders follow, then folders outside Home by path. Columns side by side while each gets 220, wrapping into rows past that. Folder-only tiles say "No project file" (or "Has CLAUDE.md · no project file"). The Archived rollup sits under the map.
- **Built:** inside a project the toolbar reads `All projects › payments › checkout`.
- **Open:** long path labels (truncated today); a visual break between Home's columns and the outside-Home columns, or none; whether outside-Home folders want a quieter tile; how a column with one tile looks in a wrapped row; whether to call the screen "All projects" still, now that it lists folders too.

### S2-3 · **First launch and no Home** (supersedes DB-5 "choosing a workspace" and DB-6's "none" case; DB-37; DL-82, DL-84)
- **Built:** Duo opens on every session, grouped by folder, with no question asked. Home's dark left pane says "No Home folder yet", one paragraph, and **Choose Home Folder…** (also in File, and `duo2 home set`). No Claude session starts in Home until there is one.
- **Open:** the first-launch moment (is there one, or is the map itself the welcome?); the no-Home pane; the folder picker's prompt and message (today "Make Home" / "Home holds the projects you track. Duo adds a HOME.md to the folder if it has none."); what Home's pane shows the first time after choosing, before its first session.

### S2-4 · Home: several, moved, and Move into Home (DB-6 rest, DB-8, DB-39; DL-42, DL-85)
- **Built:** two `HOME.md` folders: the remembered one wins, the other shows as a project with a note. **Move into Home…** on any project or folder outside Home: a standard confirmation naming the old and new paths and the session count; the move is journaled and undoable.
- **Open:** whether tiles show Home-or-not at all; dragging a tile onto Home's heading as a second way in; the "project folder moved or missing" state (DB-8) now that moving is something Duo does itself.

### S2-5 · Tasks in the right pane and on the menus (DL-87, DL-93)
- **Built:** a task is a note, opened in the editor like any document; its frontmatter shows as raw YAML (DB-16 is later). Session menus have **Copy Link**, **Make a Task**, **Add to Task ▸**; group rows have **Make a Task**; task rows **Open Task Note**. Links in notes are underlined text; a click opens them when the line isn't showing raw Markdown, ⌘-click from anywhere.
- **Open:** how a session link looks in a note (it's a live thing: it could show the session's state glyph); a task note's header (title, status, its sessions) above the text, if anything; the empty task (no sessions yet).

### S2-6 · Needs you and create a project (DB-7, DB-9), as planned
Unchanged by the model; carry over from the original slice 2. Create a project now also means "Make a Project" on a folder tile (DL-63) and a new folder inside Home.

## 3. What to hand back

Same shape as `surfaces-handoff/`: screens (one per state), a README with [G]/[B]/[P] marks, `tokens-additions.json` for anything new, and fixture additions. Please include, at minimum: the session list with all its sections and both row kinds (one target at the fixture's size, one sheet of row states); the map with Home's columns, an outside-Home column and a wrapped row; the no-Home left pane; the first launch; Move into Home's confirmation.

The app's sample world (`build-handoff/fixture.json`) still has topics like Payments; for these screens use folder names as the app now shows them (`payments /`), a Home called `claude-home`, and at least one outside-Home column (`~/repos /`).

## 4. Constraints (unchanged)

The screens are the build target; system chrome is exempt (DL-26). One accent, needs-you only; never colour alone. Plain, sentence-case copy. Every action reachable by keyboard and `duo2`. Questions are sheets on the window. Tokens only. No quick-reply buttons on cards (DL-29).
