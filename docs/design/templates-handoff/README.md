# Templates handoff (DL-146)

Approved by Geoff, 2026-10-07, by buttons: **option A** (a template is a document), and the **base templates as drawn**. The source is the canvas https://claude.ai/artifact/S2u648a8UTGxcj8uL7r4Td. Boards B1, B2 and C1 there are the options not chosen, and they were not exported.

| Screen | Board | What |
|---|---|---|
| `screens/base-templates.html` | T0 | Duo's base `PROJECT.md` and task templates, and what Duo does when it makes a file |
| `screens/template-task.html` | A1 | Home's task template open in the right pane, with the template bar |
| `screens/template-preview.html` | A2 | Preview: the file a new task would get |
| `screens/template-project-own.html` | A3 | A project's own task template |
| `screens/template-entry.html` | A4 | Where it's reached: Settings › Templates, the TASKS fold's menu, any opening of the file |

## The files

- Base templates are in `Sources/DuoKit/Live/Templates.swift`, exactly as T0 draws them.
- A user's own templates are `templates/new-project.md` and `templates/new-task.md`: a project's own (tasks only), else Home's. **The boards say `templates/task.md`**. The files are named `new-…` so that `templates/project.md` never reads as `PROJECT.md` on a case-insensitive disk (F-186). Only that path text differs from the boards.
- Placeholders are Obsidian's own: `{{title}}`, `{{date}}`, `{{time}}`, `{{date:FORMAT}}`. Templater's `<% %>` is kept as written. Values a flow knows are set by key after the fill. A template never writes over a file.
- Neither DL-150 key, `lanes:` (PROJECT.md) or `references:` (tasks), is in a template: both are written only when first used.

## The template bar (A1 to A3)

The bar sits under the tab strip, over the document. It shows for `templates/new-task.md` and `templates/new-project.md` in Home or a project, however the file was opened.

- **Box:** `ground`, padding 10 16, 1 `rule` under it. Two lines, 2 apart.
- **Line 1:**
  - `Template for new tasks` (or `projects`) in `bodyEmphasis`, then `· Home` or `· <project>` in `text2`;
  - then, at the right, `Insert ▾`, `Preview` and `Reset…` as Duo buttons, 6 apart. On a project's own template, `Use Home's…` replaces `Reset…`.
- **Line 2:** 12/16 `text2`, ending in the file's path in mono 11:
  - Home's template: `Used by + New task in every project without its own · <path>`;
  - a project's own: `This project's own: Home's template isn't used here · <path>`.
- **Preview** (A2):
  - the button is pressed (`selected` fill, semibold), and `Insert ▾` is disabled (`rule` border, `text2`);
  - line 2 reads `A new task named “Draft PRD v2”, made today. Nothing is saved; Preview again to edit.`;
  - the document shows the filled file, read-only, with no + on PROPERTIES.
- **The tab** is titled `Task template` (or `Project template`).

## In the document

- **Placeholders** are chips: a 1 `rule` border, radius 4, padding 0 4.
  - In the properties block they're on `pane`.
  - In a heading they're on `ground`, mono at 16 in a 20 heading, regular weight.
- **Templater code** has a dashed 1 `controlEdge` border. A3's note under it ("Templater code stays as written…") is text the user wrote in the template, not something Duo draws.
- **The task look is off in a template:**
  - no status popup and no session lines;
  - the properties heading has its fold chevron, as on any document;
  - a value that is a placeholder takes the type it becomes (`created: "{{date}}"` shows the date icon), with no date control.
- **`set by Duo`** (11 `text2`) sits at the right of the task template's `sessions:` line.
- **The hint** sits under the properties block (12/16 `text2`, 8 above): `When a task is made, {{title}} becomes its name and {{date}} today's date, as in Obsidian's Templates.`, with the placeholders in mono 11.

## Where it's reached (A4)

- **Settings › TEMPLATES**, after HOME:
  - rows `New projects` and `New tasks`, each saying whose template is in use, with `Edit…`;
  - then the line `Plain Markdown in Home's templates folder. Obsidian's Templates plugin can use the same files.`
- **The TASKS fold's right-click menu** in a project:
  - `New Task`, a separator, `Edit Task Template`, `Make a Template for <project>`;
  - once the project has its own, the last item is `Use Home's Template…`.
- **duo2:** `template show|edit|copy|reset|preview` (DL-71).

## Not drawn (stand-ins, Q-111)

- **The Reset… and Use Home's… questions.** They're Duo questions in the usual look, worded by the build.
- **The Insert ▾ menu.** It's the system's own menu: `{{title}}`, `{{date}}`, `{{time}}`.
- **The project template's bar.** Its line 2 reads `Used by New Project and Make a Project · <path>`, and its `goal:` line has no `set by Duo`.
