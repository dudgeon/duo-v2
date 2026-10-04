# Send to Claude

Duo can put context into a Claude session's prompt: a file, a selection, an element on a page, a session or a project. It never presses Enter, so you add the request ("make this button yellow") and send it yourself. Decisions: DL-67 to DL-70. How it was built: F-46.

## What you can send, and from where

| What | Where | What Claude gets |
|---|---|---|
| A file or folder | Right-click it in Files, or its document tab | `@docs/prd.md`, an @-reference Claude Code resolves (relative to the session's folder when inside it, else absolute) |
| Text in a Markdown document | Select it, then right-click › Send Selection to Claude, or Edit › Send Selection to Claude | `From docs/prd.md, lines 12–14:` and the text, quoted |
| Text and images in an HTML page | Select, then right-click › Send Selection to Claude; or right-click an image › Send Image to Claude | The page, its title, the text quoted, and each image's file path |
| An element of an HTML page | Right-click the page › Select Element; hover, click to freeze; Send to Claude in the bar below | The element's tag, CSS selector, the headings it sits under, its text, attributes, computed styles and box, its HTML, and a screenshot (Claude Code attaches it as an image) |
| A session | Right-click it in the session list or on the map | Its title, project, id, note and next step, and how to read it (`duo2 session show <id>`, transcript path) |
| A project or folder | Right-click its tile on the map | Its folder, project file, goal, health and next step |

## Which session receives it

- **Send to Claude** goes to the Claude session showing in the console, or Home's at All projects. When it can't, the item says why: no session is showing, the tab is a shell, Claude hasn't started (it's still asking whether to trust the folder), or it's waiting on a question or permission prompt.
- **Send To ▸** lists every other running Claude session, plus **New Session**. That starts one in the current project (Home at All projects) and sends once Claude's prompt is ready.
- After a send, Duo shows the receiving session with the keyboard in its prompt.

## The element picker

- **Start it:** right-click an HTML page › Select Element. Elements outline as you move over them.
- **Choose:** clicking one freezes it; the page doesn't act on that click.
- **The bar under the page** names the element (`<button#pay.cta.primary>`) and offers Send to Claude, Send To ▸, Pick Another and Cancel.
- **Leave it:** Esc or Cancel.
- **Not designed yet:** the look is plain macOS for now, outlined in the system selection colour. A designed version is a design question (Q-21).

## HTML pages

- **Opening:** HTML files open as pages in the right pane, read-only.
- **Live reload:** a page reloads within a second when it, or a stylesheet, script or image next to it, changes. Claude can edit a prototype and you see it update.
- **Links:** links to other sites open in your browser.

## Claude can do it too

Every send has a `duo2` verb, so a session can hand context to another one:
- `duo2 send file <path>`
- `duo2 send selection`
- `duo2 send element`
- `duo2 send session <id>`
- `duo2 send project <name>`
- `duo2 send text "<text>"`

Each takes `--to <session id>` or `--new`. `duo2 selection` tells Claude what you have selected right now, so "make this yellow" works without sending anything.

## Not yet

- **No keyboard shortcut** for Send Selection: legacy Duo used ⌘D, and the shortcut map is locked (Q-22).
- **No sending from the terminal itself:** selecting text in a Claude session doesn't offer Send.
