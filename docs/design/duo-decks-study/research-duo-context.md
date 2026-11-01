---
title: "Duo Decks: what Duo already has, and where each piece should live"
status: research
date: 2026-10-31
branch: research/duo-decks (base 4e809942, main)
---

# Duo Decks: Duo's existing context

Research only, for the planned **Duo Decks** feature. In it, PowerPoint templates (project- or user-scoped) define slide types, and a deck is Markdown where each slide names a template and fills its slots. Duo parses it deterministically into a viewer and editor, Claude writes the Markdown, decks live in git, and the deck exports to .pptx for Google Slides.

References are `path:line` in this worktree (= main 4e809942), plus record numbers. "Not built" means a decision exists but no code (see Q-321).

---

## 1. How Duo treats Markdown documents today

**The editor.** CodeMirror 6 live preview, in one `WKWebView` (DL-167 keeps it and drops ProseMirror and native TextKit).
- **The bundle.** `Vendor/codemirror/dist/cm6.js` (690 KB, esbuild) is built from `Vendor/codemirror/src/` by `build.sh` (exact versions are in `package.json`, all MIT).
  - `duo-editor.js` is 2703 lines.
  - `critic.js` (433), `margin.js` (473), `atmenu.js` and `lists.js` are the rest.
- **The Swift host.** `Sources/DuoKit/Editor/DocumentEditor.swift`. Its `EditorMessage` enum (line ~27) is the page↔Swift message list, and DuoChecks pins it (C-81).
- **Preview and source.** There is no separate rendered-HTML preview of Markdown: the live preview *is* the rendering.
  - A Source mode per document is `duo2 doc mode source|preview|toggle` (`Actions.swift:363`; DL-167 Q3; `EditorController+Source.swift`).
  - Markdown in chat is a separate Swift renderer (`Sources/DuoKit/Chat/ChatMarkdown.swift`; DL-188).
  - `Vendor/swift-markdown-engine` is vendored but "Not used by Duo itself" (`VENDORED.md`; F-39 hedge).
- **One editor instance for the whole app** (F-145): one editor, one HTML viewer, one deck viewer. One editor *state* per open document (DL-167 step 3).
- **Claude's edits** go through the editor:
  - A PreToolUse hook on Edit/Write for the document showing.
  - `duo2 doc edit --stdin` as the backup.
  - Highlighted in green (`claudeEdit`).
  - Merged with unsaved typing.
  - DL-78, DL-77 (three-way merge), DL-186.

**Frontmatter.**
- **The parser.** `Sources/DuoKit/Live/Frontmatter.swift` is a read-only, deliberately small YAML reader: flat `key: value`, inline and block lists, nothing nested (header, lines 3-8).
  - Writing frontmatter is separate and surgical (LR-37).
  - Since F-268 there is one writer for task-note properties: Swift writes, and an open note gets the result as a plain change.
- **The properties block** (DB-16, `docs/design/frontmatter-handoff/`, built F-77) draws typed fields in the editor:
  - text, list, number, checkbox, date, datetime and link, with a type icon in the gutter;
  - verbs: `duo2 doc prop list|get|set|remove|type` (`Actions.swift:366`);
  - ENH-1 is the origin; `PropertyCorpus.swift` suggests keys across the vault.

**Review in Markdown** (DL-236, DL-237, DL-248, DL-251; handoff `docs/design/markdown-review-handoff/`; shipped 0.2.21 per Q-318).
- **Syntax.** CriticMarkup with signatures: `{++ ++}`, `{-- --}`, `{~~a~>b~~}`, `{== ==}`, then `{>>@name YYYY-MM-DD #id: …<<}`, inline with no sidecar.
- **The model** is `Sources/DuoControl/ReviewMarkup.swift` (`enum Review`, Foundation only, text in and text out; F-385).
  - The editor scan is `Vendor/codemirror/src/critic.js`, one document scan (F-388).
  - The margin is `margin.js`, and the review bar is `MarkdownReviewSlot` (`ProjectPanes.swift:907`).
- **Suggest Edits** is the frontmatter key `suggest-edits: true`, written only while on (DL-237). This is today's one example of a frontmatter key changing how the editor behaves.
- **Claude learns the convention** from the paragraph `Review.convention` (`ReviewMarkup.swift:496`). The SessionStart hook injects it into Duo's own sessions (`AppModel+TaskContext.swift:31`).
- **Verbs:** `duo2 comment …`, `duo2 suggestion …`, `duo2 doc review on|off`.

**How a file type gets its own viewer: by extension only.**
- **The dispatch** is one `if/else` chain in the right pane, `Sources/DuoKit/Project/ProjectPanes.swift:871-925`:
  - browser tab;
  - `.html`/`.htm` gets `HTMLViewerView` with `PickerBar` (`:879`);
  - `AppModel.isDeck` (`pptx|pptm|ppsx`, `Model/AppModel+Send.swift:303`) gets `DeckView` (`:890`);
  - `isWordViewable` (`docx|doc`, `:300`) gets `DocxView` (`:896`);
  - `FileKind.isBinary` (`Live/FileKind.swift:6`, C-26, F-102) gets `BinaryFileView`, which is Quick Look or the Q-52 notice;
  - everything else with a dot gets `DocumentStateBar` + `TemplateBar` (if the file is in a `templates/` folder) + `MarkdownReviewSlot` + `DocumentEditorView` (`:899-909`).
- **`BrowserTabs.swift:511-512`** repeats the extension tests to find the active `PageHost`.
- **The pptx viewer** (DL-121, DL-125, F-121, handoff `docs/design/pptx-handoff/`): `Sources/DuoKit/Editor/DeckViewer.swift` hosts `Vendor/pptx-renderer/deck.html`+`deck.js`.
  - It is served through a custom `duo-deck:` scheme, with nothing from the network and a CSP (C-33).
  - It is read-only and redrawn when the file changes.
  - It knows the slide on screen, and runs the shape picker keyed by OOXML `p:cNvPr` id.
  - Bar: ‹ › Slide n of N, Select Shape, Open With.
  - Stand-ins are Q-68 and DL-132 j ("Drawing slides…" with empty 16:9 frames from `Pptx.slideCount`, F-145).
- **The docx viewer** (DL-162, DL-233, DL-243; F-235, F-236): `Editor/DocxViewer.swift` with `Vendor/docx-viewer/`, which is `@file-viewer/docx` 0.3.33 (Apache-2.0) and JSZip 3.10.1 (MIT). It has a review layer and Select Text.
- **The HTML viewer** (DL-67, DL-70, DL-175): `Editor/HTMLViewer.swift`.
  - It is a read-only local page, reloaded when the file or its neighbours change (watches html, css, js, svg, images, json; `:113`).
  - It loads nothing remote (a `WKContentRuleList`).
  - The picker script is `Editor/HTMLPicker.swift`: right-click › Select Element; hover outline, click freezes, a native bar with Send to Claude / Send To / Pick Another / Cancel.
  - `PageHost` (`Editor/PageHost.swift`) is the shared protocol: HTML viewer, browser tabs, and since F-236 the deck and Word pickers.
  - It gives selection, picker and element screenshots to `duo2 html …`, `send element` and `duo2 selection`.

**Dispatch on frontmatter `type:`: none in code today.**
- **What `type:` does do:**
  - Duo *writes* `type: project` and `type: task` (`Live/Templates.swift:35,68`; DL-146) and `type: note` (DL-152, not built).
  - `type == "task"` appears only in the Obsidian `.base` filter Duo writes (`Live/TaskBoard.swift:320`).
- **Tasks are recognised by folder, not type.** `TaskNotes.load` reads every `.md` in `tasks/` with no `type` check (F-203).
  - DL-152 (7) decided "`tasks/` notes only with `type: task` or no type". The code has no `type` read.
- **`_sources.md` with `type: sources`** (DL-163) is decided but not built. Nothing in `Sources/` writes it, and `duo2 file source` isn't in the registry (Q-321).
- **The template bar** keys on path (`templates/new-*.md`, `Model/AppModel+Templates.swift:22-29`), not on type.
- **So a `type: deck` view would be the first content-keyed viewer.** It would be a new branch in `ProjectPanes.swift`'s chain, before the Markdown editor branch, with a matching `PageHost` lookup in `BrowserTabs.swift`.

---

## 2. Scope, conventions, user config, and how Claude learns Duo

**Project and Home files** (DL-259, 2026-10-30).
- **One name, with the underscore.** `_PROJECT.md` marks a project and `_HOME.md` marks Home. Duo still reads `PROJECT.md`/`HOME.md`, and renames them quietly by `git mv` (Q-330).
- **Only those two files take the underscore.** Duo's other files are named for what they hold: `tasks/*.md`, `tasks.base`, `templates/new-*.md`, `.duo/`.
- **They're ordinary files, in git** (DL-259 (1)). Duo never writes `.git/info/exclude`. `.duo/` holds machine state (`<project>/.duo/sessions.json`), and DL-50's one-time `.gitignore` offer for it stays.
- **What a project is.** A folder with `_PROJECT.md`. A topic is a project's parent folder (CONTRIBUTING). Home is a folder the user picks (DL-85, DL-94). Projects inside it are tracked, and outside ones are first-class.

**Project vs user scope.** The precedent is templates (DL-146; `Live/Templates.swift:4-18`):
- the lookup is the project's `templates/new-<kind>.md`, else Home's `templates/`, else Duo's built-in base;
- `duo2 file template <template>` makes "a file from a template (the project's templates/, then Home's)" (`Actions.swift:~297`, DL-61);
- `duo2 template show|edit|copy|reset|preview` (DL-146, `Actions.swift:280-285`);
- a template opens as a document with a `TemplateBar` (handoff `docs/design/templates-handoff/`).

So **"user scope" in Duo means Home's folder**, a user-visible, git-able folder. It does not mean the support dir.

**User-level config and state.**
- **Where.** `~/Library/Application Support/Duo/` (DL-53; `Sources/DuoControl/SupportFolder.swift:3-12`, overridable by `DUO_SUPPORT_DIR`).
- **What's there.** `state.json`, `allowed-sites.txt`, `installed.json` (the install manifest), `chat.json`, `context/`, `archive/`, `search/`, `logs/`, `mods/`, and so on. It is machine state, not user-authored content.
- **Machine-only marks stay out of the folder.** DL-152 (2) keeps the knowledge-base mark as Duo's own state, with nothing written in the folder.

**What Duo installs** (DL-74 approach C, `docs/design/cli-teaching.md`; consent DL-75; `Sources/DuoControl/Installer.swift`). All of it is generated from the action registry, rewritten at every launch unless the user edited it (by hash), listed in a manifest, and removed by `duo2 uninstall`:
1. **A CLAUDE.md block.** `~/.claude/CLAUDE.md` gets a ~60-word block between `<!-- duo2:begin … -->` and `<!-- duo2:end -->` (`Installer.swift:50-66`).
2. **The duo2 skill.** `~/.claude/skills/duo2/SKILL.md` (`:36`, text at `:70-112`).
   - It has fixed sections: "When to reach for it", "Tasks", "Checking documents" (pptx-relevant: it says use `duo2 doc outline/layout/screenshot`, and "Don't start `soffice`"), and "Families" (generated).
3. **The director skill.** `~/.claude/skills/director/SKILL.md`, plus a `duo-director` stub (DL-193, DL-222). Its source is `skills/duo-director/` in the repo.
4. **The duo2 link.** `~/.local/bin/duo2` is linked to `Duo.app/Contents/Helpers/duo2`.
5. **For Duo's own sessions only:**
   - The **primer** (`DuoAction.primer()`, `Actions.swift:657-675`, passed as `--append-system-prompt`, `Terminal/Terminals.swift:247`).
   - Per-session `--settings` with hooks and the sandbox socket rule (`Live/HookEvents.swift:65-67`; DL-51).
   - The **SessionStart context hook**: the project brief, the task and `Review.convention` (`AppModel+TaskContext.swift:31`; `Live/ProjectContext.swift`).
- **The primer's wording is pinned.** DuoChecks checks its phrases, so it may name only real verbs (`DuoChecks/main.swift:~1526, ~1768`).
- **Nothing goes in the project's `.claude/`.**
- **Adding a "Decks" section** means editing `Installer.skill()` and/or `Review`-style convention text. The consent list (`plannedChanges`, `:150`) changes only if a *new file* is installed.
  - A change to the list re-asks consent, by design (DL-75, DL-213 accepted re-asking).

**Obsidian and OKF compatibility.**
- **The rule.** Geoff, 2026-10-07: "For everything we build, I want to maximize backwards compatibility with existing obsidian handling and/or OKF." It is in memory `feedback-obsidian-okf-compat.md`.
  - It is restated in `docs/research/editor-approach-review.md:18`, `second-brains.md:107` and `markdown-review.md:168`.
  - The base reference is `docs/research/obsidian-compatible-task-format.md`.
- **What OKF is here.** Google Cloud's **Open Knowledge Format** (`GoogleCloudPlatform/open-knowledge-format`, v0.1 2026-06-12, v0.2 2026-07-24; `second-brains.md:67`).
  - It is folders of Markdown with YAML frontmatter, and `type` is its only required key.
  - Producers may add keys, and consumers must keep them.
  - `index.md` and `log.md` are reserved. Links are standard Markdown; wikilinks are not OKF.
  - Legacy Duo's "vault" shipped an OKF dialect (`docs/research/legacy-okf.md` under second-brain-sources; `legacy-duo-architecture-review.md:253`).
- **What it implies for a deck file:**
  - plain `.md`;
  - flat YAML with `type:` first (e.g. `type: deck`);
  - quoted relative Markdown links (DL-17: never write wikilinks);
  - no nested YAML in keys Duo owns (Obsidian shows nested maps as raw JSON; format doc lines 54-60);
  - tables one line per row (DL-113 guard);
  - no Duo-only syntax in places other readers render oddly;
  - no `.obsidian/` writes (DL-20).
- **Per-slide slot data belongs in the body**, not the frontmatter, so that Obsidian's Properties panel stays clean.

---

## 3. The pptx stack: renderer, reader, verbs, writer

**`Vendor/pptx-renderer/`** (README; DL-121; F-102, F-121; spike `docs/plan/spikes/pptx-viewer.md`).
- **What it is.** `@aiden0z/pptx-renderer` **1.3.0**, **Apache-2.0**, from the npm tarball, hash-pinned (`tarball-sha256: f867ce7e…`). `vendor.sh` re-fetches it, checks the hash and patches it.
  - `pptx-renderer.js` (1.8 MB) is the standalone browser ES build. It bundles **JSZip** (MIT) and **ECharts** (Apache-2.0).
  - Notices are in `LICENSE`, `THIRD_PARTY_NOTICES.md` and `licenses/` (an MPL-2.0 font decompressor, an ECMA notice).
- **Patches** (`patch.py`):
  1. The node dispatcher is wrapped so every shape, picture, table, chart and group carries `data-duo-shape-id` (`p:cNvPr`), `-name` and `-type`.
  2. Charts draw without `requestAnimationFrame` (`duoFrame` timer, no first-draw animation; F-102, F-122).
  - Both fail loudly if an upgrade moves the code (C-33).
- **Fidelity** (spike). Best of the renderers tried: theme colours and gradients, rotation, nested groups, table styles, charts. Calibri falls back on a Mac without Office.
  - Unsupported: EMF/WMF and video.
  - About 20 ms per deck.
- **Shipping.** `scripts/bundle.sh:61-62` copies it to `Duo.app/Contents/Resources/deck/`.
- **Can it draw a pptx Duo generates? Yes.** It renders any valid OOXML from bytes, and DuoChecks already renders synthetic decks made by python-pptx (`Spikes/PptxViewer/make_decks.py`, `video/fixture/docs/make-docs.py`).
  - A deck made by copying a template's master, layouts and theme and filling placeholders is exactly what it was tested on.
  - The same ids would round-trip: the picker's id equals `slide shapes`'s id.

**The OOXML reader** (`Sources/DuoSearch/Pptx.swift`, ported from `Spikes/PptxViewer/pptx_outline.py`).
- **What it reads.** `Pptx.outline(url, slide:)` (`:50`) gives each slide's shapes: id, name, type, groups, text, box in 96-dpi px, tables as TSV rows, chart series, and notes. `Pptx.slideCount` (`:45`) reads only the slide list.
  - It has its own minimal XML `Node` parser and `rels` resolution (`:114-170`).
- **`Pptx.Zip`** (`:176-235`) is a **read-only** zip reader: central directory, stored or deflated through Compression's `COMPRESSION_ZLIB` (raw DEFLATE). No zip64, no encryption, 64 MB per entry.
  - The docx converter and outline reuse it (`DuoSearch/Docx.swift`, `DocxOutline.swift`, `DocxLayout.swift`; DL-123, F-115, F-116).
- **It lives in DuoSearch, which `duo2` links** (`Package.swift:25,29`). So the CLI could use it without the app.
  - Today, though, every `slide` verb goes through the app (`DuoKit/Control/AppModel+Slides.swift`; `AppModel+Control.swift:837`).

**duo2 slide verbs** (family `slides`, "PowerPoint decks"; `Actions.swift:91, 460-467`; F-121):
- `slide`: the deck showing, the slide on screen, and its outline.
- `slide go <n>|next|previous`.
- `slide shapes [<file.pptx>] [<n>]`: from the file, showing or not.
- `slide notes [<file>] [<n>]`.
- `slide pick [<slide>/<id>]`.
- `slide element`.
- `send element` sends the picked shape (`:475`).
- `duo2 doc read` on a deck refuses and points to `slide shapes` (`AppModel+Control.swift:703`).
- A shape sent to Claude (DL-125 D) carries file, slide, name and id, groups, text, box, the `duo2 slide shapes` command and a screenshot.

**Is there a pptx writer anywhere? No.**
- **No production code writes OOXML or zips.** Grepping for `pptxgen`, `python-pptx`, writers, `zip`, `ditto` and CRC32 in `Sources/` finds nothing; the only Compression call is the decode in `Pptx.swift:225`.
- **python-pptx is used only by dev scripts and fixtures:**
  - `Spikes/PptxViewer/make_decks.py`;
  - `video/fixture/docs/make-docs.py` (`uv run --with python-pptx`);
  - `video/fixture/make-tasks.py:89`.
- **Writing a zip would mean writing the format.** Foundation can't zip. Compression can *encode* raw DEFLATE (`compression_encode_buffer`, `COMPRESSION_ZLIB`).
  - CRC-32 would need a small table implementation, or zlib's `crc32` (libz ships with macOS).
  - Stored (method 0) entries are valid OOXML too.
  - It is about 100 lines beside `Pptx.Zip`.
- **Determinism matters for git and checks** (F-238, findings ~3204). python-pptx/docx and Google exports stamp zip times and `docProps/core.xml` dates, so bytes change every run.
  - A Duo writer should fix timestamps and part order.

**docx → Markdown converter** (DL-123, amended by DL-236 (12) and DL-162; F-114 to F-116, F-387).
- **What it is.** Duo's own Swift converter (`DuoSearch/Docx.swift`) on `Pptx.Zip`, with clean-up heuristics.
  - GFM with no raw HTML: the subset Google Docs imports cleanly (F-114).
  - Since F-387 it keeps tracked changes as signed CriticMarkup suggestions and comments as threads.
- **Its verb** is `duo2 file convert <docx> [--as] [--replace] [--anyway] [--yes]` (`Actions.swift:308`). The app side is `Model/AppModel+Convert.swift`.
- **pandoc was rejected**: 192 MB, GPL, and it infers nothing (F-115).

**Google export and import code paths.** None exist in the app.
- **"Copy for Google Docs"** is **ENH-14 part 2**, wanted and unbuilt: a copy with images inlined as data URIs, because Docs can't follow relative image paths (F-114).
- **ENH-274** (a Google Docs round trip for users) is wanted and unscheduled. It needs a sign-in model.
- **Source links** (DL-163) read Chrome's `kMDItemWhereFroms` to offer a Google `/edit` link for a downloaded .pptx or .docx (F-238, F-239). Slice 1 is not confirmed built (Q-321).
- **ENH-55** extends this to Sheets. **ENH-56** writes the source into the file's `docProps/custom.xml`: an explicit action, because it changes the file.
- **Facts about Google's exports** (F-238): a Slides deck exported as pptx has 76 parts and no `docProps`.
  - Shapes are named `Google Shape;<n>;<pageId>`.
  - Two downloads of the same deck differ byte for byte.

---

## 4. duo2 verbs: conventions, parity, file-type examples

- **One registry** (DL-71 parity, DL-72): `Sources/DuoControl/Actions.swift`.
  - `ActionFamily` (`:9-29`; families: app, view, projects, sessions, director, files, repo, docs, review, html, slides, send, search, setup).
  - `ActionID` raw values are the verbs (`:32-95`; a multi-word verb is `"slide shapes"`).
  - `DuoAction(id, family, args, summary, ui:, local:, everyday:, timeout:)` (`:100-125`).
- **What the flags mean:**
  - `ui:` lists the labels of the buttons and menu items that perform the action. The parity check matches them.
  - `local: true` means the verb runs in the CLI with no app (e.g. `install`, `uninstall`, `doctor`, `help`, `update probe`, `hangs`).
  - `everyday: true` puts it in the primer.
  - `timeout` is longer for verbs that wait on a sheet.
- **The parity check.** `Parity.uiOnly` (`:526-…`) lists UI with no verb, and why.
  - DuoChecks `parityGaps()` (`DuoChecks/main.swift:1563-1567`, impl `:3085`) fails when "a button, menu item, click or drag" names neither an action nor a `uiOnly` entry.
  - Views name their action (`ActionButton(.fileRename)`, `.onActivate(.sessionOpen)`).
- **Output** (DL-73): readable text by default, `--json` on every verb, errors on stderr with a non-zero exit.
- **Generated docs.** `docs/cli/duo2.md` comes from `build/Duo.app/Contents/Helpers/duo2 help --markdown` (`Actions.swift:630-650` writes the families tables and the "In the app only" table).
- **App vs offline.**
  - The CLI asks the app over the control socket. With the app unreachable it tries `runOffline` (`Sources/duo2/main.swift:189,201`; `Sources/duo2/Director.swift:21-32`). Only the director verbs and `session show` work offline (DL-231).
  - `duo2 search` runs in the CLI on DuoSearch (`Sources/duo2/Search.swift`; "so the read-only CLI can use it in Claude's sandbox", `Package.swift:23-25`).
- **The sandbox boundary** (C-115, Geoff 2026-10-28). An app verb runs *outside* the session's sandbox.
  - So document verbs act only on a document open in a Duo tab or a file inside the session's project folder, and write only into the session's working folder (`AppModel.documentFile`, `Control/AppModel+DocLayout.swift`; F-386).
  - Every new verb gets the test: "does it let a session read, write or run what its sandbox would deny?"
  - A `local` verb runs *inside* the sandbox, as the session's own process.
- **File-type verb examples:**
  - `file convert` (docx→md);
  - `doc outline|layout|screenshot` (docx; F-378, F-386, F-394; screenshots in `<session>/.duo/screenshots/`);
  - `slide …` (above);
  - `html pick|element|selection|reload|stop`;
  - `doc prop`, `doc mode`, `doc table` (DL-113), `doc format strikethrough` (DL-189);
  - `template …`, `file template`.
- **Off-screen capture exists for Word only.** `OffscreenShot` in `Control/AppModel+DocShot.swift` (F-394) uses a borderless window at (-30000, -30000) and never takes focus.
  - **ENH-289**: no off-screen copy yet for a Markdown preview or a **slide deck**. Today a deck is captured only while showing.

---

## 5. Google Docs work: decided vs pending

Sources:
- `tasks/google-docs-in-duo.md` (the main checkout, not in git; status in-progress);
- `docs/research/google-docs-in-duo/` (README, checkpoint-1.md, comparison-frame.md, narrative.html published at https://claude.ai/artifact/UgxMcFsUf512DRDkHXJmVz, jobs.md, google-docs-surface.md, test-plan.md, agent-landscape.md);
- the earlier `research/google-docs-native` branch (`docs/research/google-docs-native.md`, not merged; its Q-251 to Q-255 aren't on main).

**Decided.** No DL records yet, only standing permissions and Geoff's stated positions:
- Google hosts may go on the allow list in **Geoff's local Duo only**, never as a shipped default. Test Docs may be made in his account. No agent enters credentials.
- **No per-user Google Cloud project.** Geoff: it "sounds absolutely horrendous". The revised recommendation (Q-314, checkpoint-1 §4, narrative):
  - **Duo registers one Google app**;
  - scope **`drive.file`** (non-sensitive, basic verification);
  - desktop OAuth with a loopback redirect and PKCE, through **Google's sign-in kit for Mac apps** (OAuth inside a WKWebView is refused by Google);
  - the **Picker** pointed at the open doc;
  - one "Allow" per doc;
  - testing mode with Geoff as the only user (T-16);
  - apply for the basic app check after Checkpoint 2.
  - This is still a recommendation awaiting the Checkpoint 1 buttons.
- **LibreOffice is dropped** entirely, with no sandbox allowances and no PDF pages (2026-10-28; F-377; `agent-docx-tooling.md`).
- **Google round trips** are allowed for research, not for customers yet (ENH-274).

**Pending** (Checkpoint 1, all open on main):
- Q-309: Docs' in-page hook `_docs_annotate_getAnnotatedText`.
- Q-310: the job priorities.
- Q-311: the work Google account (managed Workspace may block unapproved OAuth apps, or require Chrome).
- Q-312: where the tests run.
- Q-313: the second collaborator.
- Q-314: API access, as above.
- Q-315: whose name is on Claude's suggestions.
- Q-316: chord collisions.
- After that come Phase 2 tests, then Checkpoint 2 (browser A / native B / **hybrid C** recommended), then Phase 3.

**Import and export paths found** (google-docs-surface §4, google-docs-native §2):
- Drive `files.create` with conversion imports docx, odt, html, rtf, txt and **Markdown** to Docs. An upload is always a **new** file with a new URL (no push into an existing Doc without the API).
- Docs export: docx, pdf, Markdown and others.
- The claude.ai Google Drive connector's `create_file` uploads with conversion (used in research). Whether Duo may lean on it is Q-254 (branch only).
- The no-setup route is a manual upload in drive.google.com with "Convert uploads" on.

**What this implies for a Duo-made pptx going to Google Slides:**
- **Manual upload works today with no Duo code.** The user opens Drive › New › File upload, or Slides › File › Open › Upload. It converts on the way in, it's a new presentation every time, and it works on the work Mac wherever Drive in a browser works.
- **An in-app "Send to Google Slides" would ride the same one-Google-app / `drive.file` model** (Drive `files.create` with target mimeType `application/vnd.google-apps.presentation`).
  - `drive.file` covers files the app creates, so no Picker is needed for a fresh upload.
  - *Updating* an existing Slides deck from a re-export isn't possible by upload. It would need the Slides API: sensitive scopes, or `drive.file` plus a file the app created.
  - Not verified here; pptx-in-`importFormats` is Google's documented behaviour but not tested in this repo.
- **It gates on the same pending decisions:** Q-314, Q-311 (work account), app verification. So the export should stop at a `.pptx` on disk in v1 of Decks, with "upload it yourself" as the path, and Google upload as a later slice on the shared Google-auth work.
- **Google's export renames shapes** (`Google Shape;n;pageId`, F-238). A deck that comes back from Slides as pptx won't keep Duo's shape names or ids. The round trip is one-way unless Duo matches on content.

---

## 6. Bundled JS and web constraints

**How vendored web bundles are built and pinned.** Every runtime web asset is committed and offline. Each bundle has a README with versions and tarball sha256s, plus a `vendor.sh`/`build.sh` that re-fetches, checks the hash, copies and patches.
- `Vendor/codemirror/`: npm lockfile, esbuild, `dist/cm6.js` committed, `dist/THIRD-PARTY-LICENSES.md`.
- `Vendor/pptx-renderer/`: npm tarball and hash, `patch.py`.
- `Vendor/docx-viewer/`: two tarballs and hashes, the import rewritten to the vendored `jszip.mjs`, and a check that the renderer's JSZip *is* JSZip 3.10.1.
- `scripts/bundle.sh:61-65` copies the pages into `Contents/Resources/{deck,docx}/`.
- **Upgrades** are checked by DuoChecks: rendered ids against the Swift outline.
- **Pages load nothing remote** (DL-175, the deck's CSP).

**Licences.**
- **Duo is MIT** (DL-12). Accepted in the app so far: MIT, Apache-2.0, MPL-2.0 (the font decompressor), and JSZip taken as MIT from its MIT/GPLv3 dual licence.
- **Notices.** About Duo's credits plus `THIRD-PARTY-NOTICES.md` in Resources (DL-176, C-82), generated by `scripts/gen-notices.py` from `Vendor/` (findings ~3280).
- **pandoc was rejected partly for GPL plus 192 MB** (F-115).
- The "NC licences OK" memory (DL-246 era) is for **videos and voice only**, not app code.
- There's no DL that lists permitted licences. The practice is permissive-only, with notices.

**App size.**
- `build/Duo.app` is **117 MB**: Resources 68 MB (mostly the search model), MacOS 45 MB, `Helpers/duo2` 2.4 MB.
- F-115 cites 94 MB at the time.
- The idle-memory budget is under 300 MB (`stack-recommendation.md:7`).
- Each web bundle is small next to that: pptx-renderer 1.8 MB, cm6 0.7 MB.

**Could a JS pptx writer be bundled? Technically yes, like pptx-renderer.**
- **What it would need.**
  - **pptxgenjs is MIT** and depends on JSZip, which Duo already ships twice: in pptx-renderer's bundle and as `docx-viewer/jszip.mjs`.
  - It would need a vendored browser build, hash-pinned, plus a page in an off-screen or hidden `WKWebView` (the `OffscreenShot` pattern, F-394).
  - The bytes would go back to Swift through a message handler or a scheme.
- **The trade-offs:**
  - It runs **only inside the app**, so the export needs Duo running. A `duo2` verb would be an app verb (outside the sandbox; C-115 path rules apply).
  - pptxgenjs *creates* decks from scratch through its own object model. **Filling a user's own .pptx template** (its master, layouts, theme, placeholders) is not its strength.
  - Template-faithful output is better done by copying the template package and rewriting slide XML. That is string and XML work Swift can do on top of `Pptx.Zip` plus a writer.
- **Swift zip writing: none today** (above). A small `Zip.write` (local headers, central directory, CRC-32, stored or deflate through `compression_encode_buffer`) next to `Pptx.Zip` would give a writer that:
  - is **in DuoSearch**, so it's usable as a `local` duo2 verb with **no app, no Node, no Python**;
  - works inside the sandbox (writing into the project folder is allowed there);
  - is deterministic for git.

---

## 7. Constraints: CLI login only, the work Mac, "no scripts"

- **CLI login only** (memory `project-users-cli-login-only.md`; DL-118): users have the interactive Claude Code CLI on a subscription. No `ANTHROPIC_API_KEY`, no SDK, no `-p`. Hooks go through per-session `--settings`, never global settings.
- **The work Mac's Claude Code is pinned** to 2.1.284 since 2026-10-28 (was 2.1.219), and is "always months behind" (memory `work-mac-claude-version.md`; DL-155, DL-164).
  - Skills and `--append-system-prompt` work on 2.1.219 and later (`agent-docx-tooling.md` §4).
  - The sandbox is on, in auto mode (`agent-docx-tooling.md`, "The case").
- **What "no scripts" means** (memory `feedback-no-scripts-on-work-mac.md`, Geoff 2026-10-07): "it is not practical and likely against policy for me to run random scripts from my home machine at work".
  - It binds **Geoff and the fixes we ship**: no terminal commands, file edits or `defaults` writes for him to run there. Every remedy is a normal release that copes with existing state.
  - It is **not** a rule about what Claude sessions run. Work-Mac sessions do run tools: one ran Anthropic's docx skill and tried `soffice` (`agent-docx-tooling.md`).
- **Does `duo2` count as allowed? Yes, by record.**
  - `agent-docx-tooling.md` §4's table rates each proposal on "No scripts there". It marks duo2 verbs "yes, the capture runs in Duo", and concludes: "Every picked item runs inside Duo and reaches the session over duo2's existing socket, so it needs no settings change on the work Mac."
  - duo2 ships inside the signed app (`Contents/Helpers/duo2`).
  - The primer tells sessions it "is on PATH and needs no approval" (`Actions.swift:658`).
  - The sandbox socket rule is DL-51.
  - The test that still applies is C-115's: a verb mustn't widen what the sandbox allows.
- **What sessions can't count on:**
  - **Python.** The Mac's system Python 3.9 can't run the docx skill's scripts; a Homebrew 3.12 venv did (`google-docs-native.md` §1.3).
  - **Node.** Not recorded as present on the work Mac; Duo's own dev tooling needs it only for builds and checks.
  - **LibreOffice.** It doesn't run in the sandbox (F-377), and is dropped.
  - So a Decks skill that tells Claude to run python-pptx, pptxgenjs/Node or `soffice` is fragile at work.
  - A skill that tells Claude to **write Markdown and call `duo2 deck …`** is consistent with the records, and is the pattern of "Checking documents" in the duo2 skill (`Installer.swift:~96`).
- **The two kinds of verb differ on the work Mac:**
  - A **`local`** duo2 verb (Swift in DuoSearch) also works with Duo closed, and inside the sandbox.
  - An **app** verb needs Duo running, and is bounded by C-115's path rule.

---

## 8. Prior related records

Search terms: slide, deck, pptx, PowerPoint, presentation, Marp, template, Google Slides.

**Decisions:**
- **DL-121**: PowerPoint viewer with `@aiden0z/pptx-renderer` in a web view, patched for OOXML ids, with duo2 reading slides from XML.
- **DL-125**: the viewer's look as drawn (A to E): the scrolling slides, the ‹ › bar, Select Shape, the picker bar, what Claude receives, the Quick Look fallback.
- **DL-132 j**: the deck's stand-ins ("Drawing slides…", empty numbered frames).
- **DL-130**: motion for the deck (`motion.slide` 250 ms scroll; F-140).
- **DL-123**: our own Swift docx→Markdown converter on `Pptx.swift`'s zip reader, GFM for Google import; Copy for Google Docs deferred.
- **DL-162**: .docx opens in a view-only viewer, with Convert to Markdown on request.
- **DL-163**: the source bar on every .pptx and .docx, and `_sources.md` (`type: sources`). Not confirmed built (Q-321).
- **DL-146**: base templates for project and task. Lookup: project `templates/`, then Home, then base. The template editor; `duo2 template` verbs. Obsidian placeholders only.
- **DL-61**: file actions, including "new from template".
- **DL-152**: knowledge bases; a `note` template kind; `tasks/` only with `type: task` or no type.
- **DL-236, DL-237**: Review in Markdown (CriticMarkup, the margin, `suggest-edits:` frontmatter).
- **DL-259**: `_PROJECT.md`/`_HOME.md`; Duo's files are ordinary git files.
- **DL-17, DL-18, DL-20, DL-113**: Markdown links only; title and aliases; no `.base` unasked; tables safe for other renderers.
- **DL-74, DL-75**: what Duo installs and the consent.
- **DL-71, DL-72, DL-73**: CLI parity, one registry, output format.
- **DL-175**: local pages load nothing remote.
- **DL-176**: notices in About.
- **DL-12**: MIT.
- **DL-53**: the support folder.
- **DL-233**: the Word viewer takes Google Docs' defaults (a precedent for "look like Google" defaults as tokens).

**Findings:**
- **F-102**: binary files and the pptx viewer spike; `Pptx.outline` "so duo2 can use it without the app"; Quick Look gives no preview for a python-pptx deck with notes.
- **F-121**: the PowerPoint viewer as built: `duo-deck:` scheme, CSP, the slides verbs.
- **F-122**: scripted deck runs; charts blank off screen.
- **F-140**: the deck's slide scroll and outline motion; `scripts/check-deck-motion.mjs` (needs playwright-core).
- **F-145**: the deck's stand-ins; one deck viewer for the app.
- **F-114**: what Google Docs' Markdown import keeps.
- **F-115**: pandoc vs mammoth vs our own converter.
- **F-116**: the docx→md converter as built.
- **F-387**: Convert keeps a Word review as CriticMarkup.
- **F-185, F-186, F-187, F-205**: the templates audit and build, and the template engine's gaps.
- **F-203**: `tasks/` claimed by folder name.
- **F-238, F-239**: what Google's pptx and docx exports carry; Chrome's Where-from link.
- **F-377**: LibreOffice can't run in the sandbox.
- **F-378, F-386, F-394**: `doc outline`, `doc layout` and `doc screenshot`; off-screen capture for Word only.
- **F-385, F-388**: the review model and the editor scan.
- **F-77**: the properties block.
- **F-48**: the install loop.
- **F-411, F-412, F-413**: duo2 vs a Google Doc; the page hook; real events.
- **F-409, F-410**: the Docs API's SUGGEST mode and comments (GA 2026-09-30); on the `research/gdocs-landscape` branch.

**Enhancements:**
- **ENH-12**: PowerPoint viewer (built).
- **ENH-14**: docx as Markdown; part 2, Copy/Export for Google Docs, unbuilt.
- **ENH-1**: frontmatter editing (built as the properties block).
- **ENH-55**: source links for Sheets.
- **ENH-56**: Write Link into File (docProps in pptx and docx).
- **ENH-274**: a Google Docs round trip for users.
- **ENH-289**: off-screen `doc screenshot` of a Markdown preview or **slide deck**.
- **ENH-40 to ENH-44**: knowledge-base follow-ons.

**Concerns and questions:**
- **C-26**: binary opened as text (fixed).
- **C-33**: the patched renderer and untrusted decks.
- **C-82**: third-party notices.
- **C-115**: the duo2 sandbox boundary.
- **Q-52**: a file Duo can't show.
- **Q-68**: deck viewer stand-ins.
- **Q-154**: where a file's source link is kept.
- **Q-186**: notices.
- **Q-222**: a deck keeps its author's colours in dark mode (DL-224).
- **C-104**: the deck bars weren't checked dark.
- **Q-309 to Q-316**: Google Docs Checkpoint 1.
- **Q-321**: is DL-163 built?

**Marp.**
- No record. It is mentioned only in `docs/research/second-brain-sources/llm-wiki.md:23,25,46,58`: Karpathy renders "slide shows (Marp format)" from his LLM wiki.
- No decision on Marp syntax. Relevant if the deck Markdown wants `---` slide separators: Marp, and Obsidian's own Slides core plugin, use them. A `---` line also collides with frontmatter fences and thematic breaks, so the parser must define it.

**Google Slides.**
- No record of its own. It appears in F-238 (pptx export), DL-163 (source links) and `agent-landscape.md` (Claude in Slides, 2026-10-06 blog).

**Naming collision.** `DeckViewer`, `DeckView`, `DeckChromeCheck`, the `deck/` resources, and `isDeck` all mean **PowerPoint** today. A Markdown "Duo deck" needs a distinct internal name, or a careful split.

---

## Record numbers

- **Highest on main 4e809942** (`git fetch --all` 2026-10-31): **F-456, Q-343, C-127, ENH-292, DL-265**.
- **On open branches:** `design/markdown-toolbar-voice` uses **DL-266, C-129, Q-345, Q-346, Q-347**. No other open branch in the list I checked goes higher.
  - Checked: build/copy-and-tab-reorder, research/director-session-links, research/google-docs-native, research/voice-input, integrate/2026-10-30l, build/session-multiselect, review/director-dogfood.
  - research/google-docs-native's Q-251 to Q-255 are below main's high.
- **This study's reserved ranges are clear**, with no clash: F-460 to F-466, Q-348 to Q-356, C-130 to C-132, ENH-296 to ENH-299, DL-267 to DL-270.
  - F-457 to F-459, Q-344, ENH-293 to ENH-295 and C-128 are unclaimed on the branches checked, and presumably held by other sessions.
