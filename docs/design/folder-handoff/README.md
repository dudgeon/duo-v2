# Duo: inside a folder that isn't a project — design handoff

Status: approved by Geoff, 2026-10-05 (DL-110), and built (F-90). Answers Q-44. The board is `screens/folder-not-project.html`, a sheet drawn with the design system's tokens in the S3-2 notice's look (the Design canvas tool wasn't available in that session).

## What the sheet settles

- Inside a folder with no `PROJECT.md`, the line under its name reads `Folder · no project file` (`Has CLAUDE.md · no project file` when it has one), where a project shows its health and next step.
- A notice on `ground` over the session list: “This folder isn’t a project yet.”, a `text2` line, **Make a Project** (default) and **Not Now**.
- The Project tab, blank before, says “No project file”, what a `PROJECT.md` holds, **Make a Project**, and **Open CLAUDE.md** when the folder has one.

## Behaviour a picture can't show

- Make a Project writes the starter `PROJECT.md` and opens it (DL-63); Undo removes it.
- Not Now hides the notice for that folder only, remembered in Duo's state (`notNowFolders`), never in the folder; Undo brings it back. The line under the name and the Project tab keep the offer. `duo2 project make <folder> --not-now`.
- The console's empty state says “Nothing has run in this folder yet.” for a folder.
- A folder's Files tree lists like a project's (F-88).

## Exempt from the comparison

The sheet's session rows and file names are illustrative; the live captures use scratch data.
