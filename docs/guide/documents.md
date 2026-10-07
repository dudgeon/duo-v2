# Documents: what Claude makes, beside the conversation

**The PRDs, notes, one-pagers, decks and prototypes Claude makes open right beside the conversation.**

## The problem

Claude writes a file and tells you its name. You go and find it in Finder, open it in another app, and then try to work out what changed since last time.

## In Duo

Inside a project, documents open as tabs on the right.

- **Markdown** opens in an editor that looks like a document, not code. Text Claude just added is highlighted, and tables can be edited from Format › Table or the bar that shows while your cursor is in one.
- **HTML** opens as a live page that updates as Claude edits it.
- **PowerPoint** decks open in a viewer: you see each slide, and can pick a shape on it to send to Claude.
- **Word** documents offer to make a clean Markdown copy beside the original, which is never changed. A summary says what was tidied.
- **Other files**, like PDFs and images, open in Quick Look.

The file list marks what Claude changed. When a session finishes and has made something you haven't looked at, it shows as **Ready for review** until you do.

To point Claude at part of a document, select it and press <kbd>⌘D</kbd> (Send Selection to Claude). It lands in Claude's prompt with where it came from; you add what you want and press Return. You can send more than text: a file, an element of a page, a shape on a slide, a whole session or a project.

![A project with a Markdown document open on the right, beside the Claude session.](images/project.png)

*A document open beside the session that's working on it.*

## Web pages

Duo can open web pages in tabs too (<kbd>⌥⌘T</kbd>), but only for sites you allow; everything else opens in your usual browser. Google Docs, Sheets and Google sign-in work in these tabs, as do uploads, downloads, printing and zoom. Claude can read and work a page you have open there.

## Good to know

- Your typing and Claude's edits never overwrite each other. Duo merges them, and only asks when you both changed the same line.
- Didn't want what Claude changed? Right-click it: **Revert This Change**, or revert all of Claude's changes since your last edit.
- A file from outside the project opens as a tab too: File › Open File…, or drag it in from Finder.
- Short of room? The button at the right end of the toolbar (or <kbd>⌥⌘0</kbd>) hides the documents pane and brings it back.

## For power users

Claude's edits to a document open in Duo go through Duo's editor, not straight to disk, so they're highlighted and merged with your unsaved typing. `duo2 doc open <path>`, `duo2 send selection`, `duo2 doc revert`, `duo2 slide` (read a deck's slides, shapes and notes), `duo2 browser allow <site>`, `duo2 browser read`.

Next: [What needs you](what-needs-you.md)
