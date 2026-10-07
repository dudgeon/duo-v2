The bar over a template open in the right pane: what the template makes, whose it is (Home's or a project's own), and Insert ▾, Preview and Reset… (DL-146).

**Status:** Designed (DL-146, templates-handoff `template-task.html`, `template-preview.html`, `template-project-own.html`).
- **Look:** a bar under the tabs on `ground`, padding 10 16, a `rule` below. Line 1: `Template for new tasks` (`bodyEmphasis`) and `· Home` (`text2`), then the buttons. Line 2: a `control` `text2` line saying what uses it and where it is, the path in mono 11.
- **Preview:** shows the file the template would make, read-only. The button is pressed (`selected`, semibold), Insert is disabled, and line 2 says what's shown.
- **A project's own template:** Use Home's… in place of Reset….
- **In the document:**
  - placeholders are chips (1 `rule`, radius 4), on `ground` in a heading;
  - Templater code has a dashed `controlEdge` border;
  - `set by Duo` sits at the right of the task template's `sessions:` line;
  - a hint sits under the properties block;
  - the task look (status popup, session lines) is off.
- **In code:** `Project/TemplateBar.swift`; `Vendor/codemirror/src/duo-editor.js` (`setTemplate`, `preview`, `placeholderField`); `Model/AppModel+Templates.swift`; `Live/Templates.swift`.

**Reached from:** Settings › Templates (Edit…), the Tasks fold's right-click menu (Edit Task Template, Make a Template for <project>, Use Home's Template…), opening `templates/new-task.md` or `templates/new-project.md` anywhere, and `duo2 template edit`.

**Not drawn (Q-111):**
- the Reset and Use Home's questions, which use the usual Duo question;
- the Insert menu, which is the system's;
- the project template's line 2.
