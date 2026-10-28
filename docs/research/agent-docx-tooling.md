---
title: What agents need from duo2 to make documents well
status: research
task: tasks/agent-docx-tooling.md
date: 2026-10-28
records: [F-377, F-378, Q-258, Q-259, C-115, ENH-274]
---

# What agents need from duo2 to make documents well

## The case

On the work Mac (Claude Code 2.1.219, sandbox on, auto mode), a session in Duo used Anthropic's official docx skill to make a Word document that would be imported into Google Docs for stakeholders to comment on. The material is private and isn't described here.

- It checked the structure first: `duo2 doc outline` for heading levels, styles and list membership, then the skill's XML validator. Built-in styles, native lists, DXA table widths that sum correctly, no text boxes, schema-valid.
- Then it followed the skill's "Verify the output" step, "render it and look". The route was `soffice --headless --convert-to pdf`, then a Duo browser tab on the PDF with `#page=N`, then `duo2 browser screenshot`. LibreOffice exited 1 with no log inside Claude's sandbox. The session guessed that the single-instance socket was blocked.
- It asked for five things, in its own priority order: `duo2 doc screenshot`, `duo2 file convert --as pdf`, `duo2 doc layout`, `browser screenshot --full-page` with `--page N` and a `browser scroll` verb, and a real Google Docs round trip.
- Geoff asked why it needed a PDF. It agreed it didn't: for a Google Docs target, structure is what matters, and a LibreOffice render can mislead because Docs reflows with its own fonts. The skill's generic step sent it the wrong way.

## 1. Why LibreOffice fails in the sandbox (F-377)

I reproduced it here with LibreOffice 26 (installed with Geoff's OK) under `@anthropic-ai/sandbox-runtime` 0.0.81, the runtime Claude Code's sandbox is built on, and under plain `sandbox-exec` profiles to bisect. The session's guess was half right. `soffice` needs three things the sandbox withholds, and any one missing kills the conversion:

| Needs | Why | Without it |
|---|---|---|
| Write access to `/tmp` | Its single-instance pipe is `/tmp/OSL_PIPE_<uid>_SingleOfficeIPC_<hash>`, hard-wired to `/tmp`; `TMPDIR` doesn't move it | exit 1, no output |
| Binding a Unix socket there | The same pipe is a listening `AF_UNIX` socket; the sandbox denies `network-bind` | exit 1, no output |
| A writable user profile | Default is `~/Library/Application Support/LibreOffice`, outside the writable folders | hangs on an invisible "user installation" dialog, or exits 77 |

- Proven fix: `sandbox.filesystem.allowWrite: ["/tmp"]`, `sandbox.network.allowUnixSockets: ["/tmp"]`, and `-env:UserInstallation=file://<work folder>/lo-profile` on the command line. Allowing only the `OSL_PIPE_*` names did not work in a hand-written profile; Claude's settings take path prefixes anyway.
- Claude Code 2.1.219 (the work Mac's version) has all three settings (`allowWrite`, `allowUnixSockets` and `allowAllUnixSockets`, `excludedCommands`), checked in its binary. Duo already adds a sandbox rule to every session's `--settings` (`HookEvents.swift:67`, duo2's socket), so Duo could have shipped the allowance in a release.
- The skill's helper, `scripts/office/soffice.py`, wouldn't help on a Mac. It calls `soffice` from `PATH` (on macOS it lives inside the app bundle), and its workaround is an `LD_PRELOAD` shim for Linux sandboxes where `socket(AF_UNIX)` itself fails. On macOS `socket()` succeeds and `bind()` is what fails, so the shim never loads. It does set `-env:UserInstallation` to a temporary folder, which covers the third row only.
- **Geoff's call (2026-10-28): drop LibreOffice entirely.** No sandbox allowances, no `file convert --as pdf`, and no page breaks ("I don't care about page breaks at all"; "I want to be very careful to avoid sandbox circumvention"). This finding exists so the next session doesn't guess.

## 2. What duo2 has, and what each ask costs (F-378)

| Ask | What exists | What's missing | Size |
|---|---|---|---|
| `doc screenshot` | `PageHost.screenshot` (`Editor/PageHost.swift:90`) snapshots HTML viewers. `WindowCapture.withWebSnapshots` draws covered or background web views (F-120, F-227). The Word viewer is a WKWebView (`DocxViewer.swift`). | DocxViewer and Markdown preview aren't PageHosts. A tab that isn't showing is dormant (no window, so no snapshot: F-118). `takeSnapshot` clamps to the view's bounds, so a whole document needs a resize or scroll-and-stitch. | M |
| `file convert --as pdf` | `file convert` is Markdown-only (`Actions.swift:299`). `browser print --pdf` prints a web view. | Everything; true pages only via LibreOffice. **Dropped.** | — |
| `doc layout` | `doc outline` reads the docx zip directly (`DuoSearch/DocxOutline.swift`, `AppModel+Docx.swift:107`): paragraphs, styles, levels, changes, comments. | `sectPr` page size and margins, tables as objects (declared widths, vs the text width), image extents (`wp:extent`), overflow warnings. No page numbers (no layout engine, and Geoff doesn't want them). | M |
| `browser screenshot --full-page`, `browser scroll` | `browser screenshot` captures the visible viewport (`BrowserTabs.swift:899`); `click` runs JS by selector. | Full height needs a resize or `createPDF`; scroll is a small JS verb. `--page N` for PDFs is dropped with LibreOffice. | S–M |
| Google Docs round trip | Nothing in Duo. | Sign-in, upload, convert: see below. | L |

Two facts about the Word viewer matter for `doc screenshot`:
- It is one continuous flow at the pane's width, never paginated (DL-162), and nothing in Duo reads page geometry.
- It already lays tables out at the docx's own column widths: `<colgroup>` from `w:gridCol` plus `table-layout: fixed` (`Vendor/docx-viewer/docx-preview.mjs`). Only `#host table { max-width: 100% }` (`Vendor/docx-viewer/docx.html:23`) squeezes a wide table into a narrow pane. Lifting that makes tables wrap as Google Docs wraps them while text still flows at the pane.

## 3. What the docx skill does, and what Duo should tell a session

- The skill's "Verify the output" section says, for every document: convert to PDF with `soffice`, `pdftoppm` to JPEGs, read the images. It has no idea of the file's destination. Its only Google Docs notes are gotchas: DXA widths, not percentages ("PERCENTAGE breaks in Google Docs"), and `ShadingType.CLEAR`.
- Its description already sends sessions to Claude's own Docs when the user didn't name Word. That doesn't apply here: a docx was asked for.
- We don't edit Anthropic's skill. Duo writes its own duo2 skill (`Installer.skill()`, `Sources/DuoControl/Installer.swift:70`) and a primer appended to every session (`DuoAction.primer()`, `Actions.swift:598`). **Geoff's pick: a short "Checking documents" note in the skill and one line in the primer.** The gist:
  - Fit the check to where the file goes. For a docx headed to Google Docs, check structure (`duo2 doc outline` and `doc layout`, built-in styles, native lists, table widths within the text width); a render is a proxy, since Docs reflows with its own fonts.
  - To see a document, use `duo2 doc screenshot`; don't start `soffice` inside the sandbox (it can't run there, F-377).
- The primer's DuoChecks phrase checks (`DuoChecks/main.swift:1526`, `:1768`) cover what the primer may name, so the line must name only real verbs.

## 4. The work Mac's limits

| Proposal | 2.1.219 | No scripts there | Ships as a release |
|---|---|---|---|
| Skill and primer guidance | yes (skill files and `--append-system-prompt` already work there) | yes, Duo writes the skill at launch | yes |
| `doc layout` | yes, reads the file in Duo | yes | yes |
| `doc screenshot` | yes, the capture runs in Duo, outside the session | yes | yes |
| `browser screenshot --full-page`, `browser scroll` | yes | yes | yes |
| Sandbox allowances (not pursued) | settings exist; managed policy could still override | yes | yes |

Every picked item runs inside Duo and reaches the session over duo2's existing socket, so it needs no settings change on the work Mac.

## 5. Not circumventing the sandbox (C-115)

A duo2 verb runs in Duo, outside the session's sandbox. That is what makes `doc screenshot` work, and it is also how a verb could become a way around the sandbox. Geoff set the limit (2026-10-28):
- `doc screenshot` captures only a document open in a Duo tab or a file inside the session's project folder, and refuses any other path.
- The PNGs go to the session's working folder, which the sandbox already lets it read.
- `doc layout` gets the same path rule.
- The same test applies to any later verb: does it let a session read, write or run something its sandbox would deny? If yes, it doesn't ship.

## 6. Google Docs round trip (research only)

Geoff allowed round trips for research; customers can't have one yet (ENH-274). I made a sample docx with docx-js the way the skill does: landscape, Title and headings, native bullets, a six-column table with bullets in narrow cells, CLEAR shading, an image with a caption. I imported it into Geoff's Drive as a Google Doc through the Drive connector, read it back, and trashed it.
- Survived: headings, native lists (also inside table cells), the bold header row, all six columns and rows, the caption's italics.
- Can't see through the connector: the image (text-only read), shading, and table widths. The connector returns text, or a file as inline base64, which is too big for an agent to look at. Seeing Google's own layout needs a browser window on docs.google.com, which is a visible run, so I didn't do it.
- Takeaway for the guidance: the structural checks predicted the import correctly. A round trip adds proof that the structure survived, not a look at pixels.
- How agents author Google Docs well (comments, suggestions, smart chips) belongs to the google-docs-native research (`tasks/google-docs-native-research.md`), which has started but hasn't written up yet. Markdown review conventions are in `docs/research/markdown-review.md`.

## Geoff's picks (2026-10-28), and the build tasks

| Pick | Becomes |
|---|---|
| Guidance in the duo2 skill and a primer line | `tasks/build-doc-check-guidance.md` |
| `doc layout`: facts from the file, no page numbers | same task |
| `doc screenshot`: open tabs and project files only, PNGs to the working folder | `tasks/build-doc-screenshot.md` |
| Tables at their declared widths, text at the pane's width, in the viewer as well as screenshots | same task; the viewer change is visible, so it starts with a design question (Q-258) |
| `browser screenshot --full-page` and `browser scroll` | same task (shared capture code) |
| LibreOffice, `file convert --as pdf`, sandbox allowances, page breaks | dropped |
| Google Docs round trip | research only now; for customers later (ENH-274) |

Order: the guidance task first (small, and it fixes the behaviour that caused this case), then the screenshot task.
