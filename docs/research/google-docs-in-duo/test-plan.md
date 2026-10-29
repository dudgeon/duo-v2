# Phase 2 test plan: Google Docs in Duo

Phase 1A of [Google Docs in Duo](../../../tasks/google-docs-in-duo.md), 2026-10-29. Phase 2 runs these tests on real Docs in Geoff's account, after Checkpoint 1. The jobs are in [jobs.md](jobs.md), what Duo has today is in [duo-browser-today.md](duo-browser-today.md), and the approaches are in [comparison-frame.md](comparison-frame.md). The landscape survey's ten unknowns ([agent-landscape.md](agent-landscape.md) §"For gdocs-frame's Phase 2 test plan") are folded in, marked **L1** to **L10**.

## Ground rules

- **Docs:** every test Doc lives in one Drive folder in Geoff's account, **"Duo Google Docs tests"**, made by the setup step (S-1). Nothing touches his other Docs.
- **Signing in:**
  - Geoff signs in himself; no agent enters credentials.
  - Google hosts go on his Duo's allow list only: `docs.google.com`, `accounts.google.com`, and `googleusercontent.com` for exports. Never a shipped default.
- **The API:**
  - It's used only after Geoff's one authorization (Checkpoint 1).
  - The token is kept in the Keychain on the Mac mini, never in the repo.
  - The OAuth client is Geoff's own Cloud project, in testing mode.
- **Locks:** timing runs (latency, memory) take the GPU lock exclusive; builds and captures take it shared.
- **Records:** each test writes its numbers into `docs/research/google-docs-in-duo/phase2-results.md`, with captures in `img/`.
- **Visible runs:** a test that needs Duo on screen asks Geoff first, by button, with what appears and for how long.

## Tooling Phase 2 needs

This is scratch work on a Phase 2 branch, not merged without Checkpoint 3.

| Tool | What it is | Needed by |
|---|---|---|
| **W-1** `duo2 browser docs read\|selection\|select <start> <end>\|watch` | A page-world call to `_docs_annotate_getAnnotatedText`: the text, annotations, selection and set-selection. `watch` streams selection changes, polled every 50 ms in the page | T-02, T-03, T-04, T-06, T-08 |
| **W-2** `duo2 browser key <chord>` and `duo2 browser type <text>` | Real NSEvent keys to the web view, as `click` sends mouse events (F-413) | T-06, T-10, T-12 |
| **W-3** `duo2 browser drag <x1,y1> <x2,y2>` and `click --at <x,y>` | Real drags and point clicks | T-02, T-06 |
| **W-4** Inner-scroller support | `scroll` and `screenshot --full-page` follow `.kix-appview-editor` | T-01, T-03 |
| **W-5** A persistent cookie store per support folder | `WKWebsiteDataStore(forIdentifier:)` keyed to the support folder, so a test instance stays signed in apart from Geoff's own Duo (only if Checkpoint 1 picks a test instance) | T-00 onward |
| **W-6** Export downloads | Allow the `docs.googleusercontent.com` redirect, so `export?format=…` downloads | T-13 |
| **W-7** API runner | A small script on the Mac mini: `documents.get`, a `SUGGEST` `batchUpdate`, `insertComment`, `addCommentReply`, Drive export and revisions. Also tried: Google's Docs MCP server in a scratch Claude session (L10) | T-04, T-05, T-09, T-13, T-14 |
| **W-8** Chrome reference | The same Doc, signed in, in Claude in Chrome at the same CSS width and zoom, for captures and timing | T-01, T-08 |

## The test Docs (S-1, made once in the test folder)

- **D1 "Rich":**
  - headings 1–4, normal text, nested bullet and numbered lists, a 4×4 table with merged cells, a footnote
  - links, and person, file, date and dropdown chips
  - an inline image, a drawing and an equation
  - two doc tabs, a header and footer, a page break, an emoji and a non-Latin line
- **D2 "Long":** about 100 pages of text with headings (pasted from a public spec).
- **D3 "Review":** five comment threads (one assigned to Geoff, one @mentioning the collaborator, one resolved), six suggestions (Geoff's and the collaborator's), and one named version.
- **D4 "Shared":** shared with the second collaborator, as an editor, for live tests.

## The tests, cheapest and most decisive first

Each test gives:
- **Jobs:** the jobs it covers.
- **Steps:** what to do.
- **Needs:** the tools or verbs it uses.
- **Measure:** what to record.
- **Pass:** the bar it has to clear.
- **From Geoff:** what he has to do or provide.

### T-00 · Sign in to Google in Duo's web view, and stay signed in (decides A and C)
- **Jobs:** all person jobs.
- **Steps:**
  1. Allow `accounts.google.com`.
  2. Open a D-doc.
  3. Geoff signs in: personal account first, then (separately, if he chooses) the work account.
  4. Record each screen: password, passkey, 2FA, any "This browser or app may not be secure".
  5. Relaunch Duo and reopen the Doc.
  6. Repeat a day later.
- **Needs:** W-5 if the test is a test instance.
- **Measure:** success or failure at each step, which screens appear, whether the session survives relaunch and a day.
- **Pass:** signed in, editable, still signed in after relaunch and next day.
- **From Geoff:** the sign-in itself (about 5 min); the choice of instance (Q-312).

### T-02 · The page hook, signed in and editable (L4): text, selection and set-selection
- **Jobs:** J-A4, J-A6, J-B1–B3, J-B6, J-C1.
- **Steps:** in D1 and D4:
  1. Call `browser docs read` and compare with the API text (or with an export).
  2. Geoff selects text 20 times: by drag, double-click, Shift+arrows, ⌘A, inside a table, across a chip and in tab 2. Record each `watch` event.
  3. Run `browser docs select` on 10 ranges and look at each.
- **Needs:** W-1, W-3.
- **Measure:**
  - Text equal to the source: yes/no, and the diff.
  - Lag from mouse-up to the `watch` event, in ms.
  - Whether the hook needs an id or flag when signed in.
  - Behaviour across doc tabs.
- **Pass:**
  - Text exact, apart from known placeholders for chips and images.
  - Selection correct every time.
  - p95 lag under 250 ms.
- **From Geoff:** signed in (T-00); about 10 min selecting.

### T-03 · What the page hook carries in a rich Doc
- **Jobs:** J-A4, J-A6, J-C3, J-F4, J-G3, J-J2.
- **Steps:**
  1. Run `getAnnotations()` on D1 and D3; list every annotation kind (links, and maybe suggestions, comments, chips, headings, lists).
  2. Run `getText()` on D2: time it, and check it holds the whole doc without scrolling.
  3. Compare with the screen-reader DOM (T-07).
- **Needs:** W-1.
- **Measure:** the annotation kinds and their shape; the `getText` time and length on 100 pages.
- **Pass:** recorded; this is a fact-finding test with no bar. If it carries suggestions and comments, A's read is enough without the API.
- **From Geoff:** nothing more.

### T-10 · Keys and chords in a Docs tab (L7)
- **Jobs:** J-R1, J-I1, J-E1 (in-page), J-G1.
- **Steps:** with the Doc focused, use W-2, then Geoff by hand, to send:
  - ⌘⌥⇧X (Suggesting), ⌘⌥⇧Z (Editing), ⌘⌥M (comment)
  - ⇧⌘H (find and replace; also Duo's Home), ⌥⌘0–6 (styles; ⌥⌘0 is also Duo's collapse pane)
  - ⌘F, ⌘K, ⌘P, ⌘O, ⌘D, ⌘/, ⌘⌥Z (screen reader)
  - typing, Return, Tab, ⌘Z
- **Needs:** W-2.
- **Measure:** for each chord, whether Docs or Duo takes it.
- **Pass:** every Docs chord a person uses daily reaches Docs, or Duo has a carve-out plan (a DL to change DL-34's map for browser tabs).
- **From Geoff:** about 5 min by hand; the run needs Duo on screen (ask first).

### T-01 · Rendering fidelity against Chrome
- **Jobs:** J-A1, J-A2, J-A3, J-K1, J-J1.
- **Steps:**
  1. Open D1, D3 and D2's first pages in Duo's tab at pane widths 460, 700 and 900 pt, at 100% and at Docs' fit zoom.
  2. Capture with `browser screenshot`.
  3. Open the same Docs in Chrome at the same CSS width (W-8) and capture.
  4. Compare with `docs/design/build-handoff/tools/compare.sh` and measure with `scripts/pixels.py`.
  5. Repeat with Docs' outline collapsed and with the "Use Chrome" promo dismissed.
- **Needs:** W-4, W-8.
- **Measure:** differing pixels by region (text, chips, images, comments margin); readability at 460.
- **Pass:**
  - Text, tables, chips and images match apart from antialiasing.
  - At 460 pt the page is readable without sideways scrolling, after one remembered setting (outline closed, zoom).
- **From Geoff:** signed in; a glance at the comparison images.

### T-06 · Claude suggests in the page (L6)
- **Jobs:** J-E1, J-E2, J-E3, J-D1, J-D4.
- **Steps:** in D4:
  1. Switch to Suggesting with W-2.
  2. Replace a selected sentence five ways: `setSelection` plus synthetic `paste` (text/plain, then text/html), `type` by W-2, `execCommand('insertText')` in the text-event iframe, and a real ⌘V of a Duo-set pasteboard (only with Geoff's OK, since it touches his clipboard).
  3. Repeat in Editing mode.
  4. Repeat while Geoff's caret is elsewhere in the doc.
- **Needs:** W-1, W-2.
- **Measure:**
  - The result is exact, with formatting kept for the HTML paste.
  - Speed per 1,000 characters.
  - What the undo stack holds.
  - Whether Geoff's own caret or selection moved.
  - How the suggestion is credited.
- **Pass:** an exact suggestion in under 2 s for a paragraph, and Geoff's caret undisturbed (or restored).
- **From Geoff:** signed in; nothing during the run.

### T-05 · Claude suggests and comments through the API (L1, L2, L10)
- **Jobs:** J-E1–E6, J-F3, J-G3, J-G4, J-H1, J-H3, J-H4, J-D1, J-D2, J-I1–I3, J-J1, J-R2, J-S1.
- **Steps:** in D4, with W-7:
  1. Run `documents.get` (SUGGESTIONS_INLINE, comments included).
  2. Send a `SUGGEST` batch: replace a sentence, insert a heading and a list item, add a table row, change a heading's style, apply a replaceAllText.
  3. Run `insertComment` on a range with an assignee, then `addCommentReply` with RESOLVE.
  4. Run `acceptSuggestion` on one of the collaborator's suggestions.
  5. Do all of the above with `targetRevisionId` while the collaborator types in the same paragraph, and again with `requiredRevisionId`.
  6. Repeat one batch through Google's Docs MCP server from a scratch Claude session.
- **Needs:** W-7, Duo's tab open on D4, and the collaborator in Chrome.
- **Measure:**
  - From the API call returning to the change showing in Duo's tab and in the collaborator's, in ms (watched by W-1 on Duo's side).
  - How each suggestion is credited.
  - Whether comments are anchored.
  - Merge results: lost text or not.
  - Quota used.
- **Pass:**
  - The suggestion shows under 2 s, anchored comments show, and no text is lost in 10 concurrent runs.
  - Attribution is recorded for Geoff's call (landscape Q2).
- **From Geoff:** the one API authorization; the collaborator for 20 min.

### T-04 · From the page's offsets to the API's indexes
- **Jobs:** J-B2 (acting on it), J-E2, J-H3.
- **Steps:**
  1. For the 20 selections of T-02, map page offsets to `documents.get` indexes. Try both a direct offset (both appear to start at 1) and a text match.
  2. Cover tables, chips, footnotes, emoji (UTF-16 surrogates), tab 2 and repeated phrases.
  3. Then send a `SUGGEST` replace at the mapped range and check it hit exactly.
- **Needs:** W-1, W-7.
- **Measure:** exact hits out of 20 for each mapping.
- **Pass:** 20/20 with one mapping, or a mapping plus a verify step that refuses ambiguity.
- **From Geoff:** the API authorization.

### T-08 · Live collaboration latency, Duo against Chrome
- **Jobs:** J-N1–N5.
- **Steps:**
  1. The collaborator types a marker string every 5 s for 2 minutes in D4.
  2. Duo's tab (W-1 `watch` on the text) and a Chrome tab on the same Mac (W-8, the same script) time-stamp each marker's arrival.
  3. Geoff types in Duo while the collaborator types in the same paragraph.
  4. Watch presence avatars and remote cursors.
  5. Do T-05's API batch during the session.
- **Needs:** W-1, W-8; the exclusive lock.
- **Measure:**
  - Arrival time in Duo minus in Chrome (median and p95).
  - Characters lost: should be 0.
  - Whether cursors and avatars show.
  - Whether the API batch disturbs anyone.
- **Pass:** median within 100 ms of Chrome; nothing lost; cursors and avatars present.
- **From Geoff:** the collaborator (a second account or person) for 15 min; a visible run (ask first).

### T-09 · Noticing comments and @claude (L2)
- **Jobs:** J-H1, J-H2, J-T2, J-G5.
- **Steps:** the collaborator posts a comment containing "@claude" (and one mentioning Geoff) in D4. Time how fast each route sees it:
  - (a) the open tab: the DOM or hook
  - (b) API polling every 15 s
  - (c) a Drive `files.watch` channel
  - (d) a Workspace Events subscription (developer preview)

  Then Claude replies with `addCommentReply`, and in the page with ⌘⌥M.
- **Needs:** W-1, W-7.
- **Measure:** detection latency for each route; whether the reply threads correctly; who is credited.
- **Pass:** detected in under 10 s with Duo open and under 1 min with it closed; the reply lands in the thread.
- **From Geoff:** the collaborator; any Pub/Sub setup approval for (d).

### T-07 · Screen-reader and braille modes, and the accessibility tree (L5, DL-7)
- **Jobs:** J-A4, J-B2.
- **Steps:**
  1. Turn on ⌘⌥Z (screen reader), then ⌘⌥H (braille).
  2. Run `browser read` and dump the DOM and live regions.
  3. Read Duo's own web view's accessibility tree in-process.
  4. Move the selection and look for it.
- **Needs:** a scratch AX dump.
- **Measure:** whether the text and the selection are exposed; how much of the doc (visible page or whole); what it costs.
- **Pass:** recorded against T-02. It is the fallback if the hook closes.
- **From Geoff:** nothing.

### T-11 · An Apps Script sidebar reports the selection (C′, L9)
- **Jobs:** J-B2, J-B3.
- **Steps:**
  1. Bind a script to one test Doc. Its sidebar polls `getSelection()` every 250 ms and posts each change to a local listener.
  2. Geoff selects 20 times.
- **Needs:** a bound script in one test Doc.
- **Measure:** lag from mouse-up to the post; the failure rate; the install friction.
- **Pass:** recorded, as the sanctioned fallback.
- **From Geoff:** the script authorization (the same session as the API).

### T-12 · Feature sweep for people in Duo's tab
- **Jobs:** J-A2, J-A7, J-A8, J-F1–F2, J-G1–G2, J-L1–L2, J-M1, J-M3, J-R1, J-K1, J-J1, J-J3, J-P1, J-P4, J-Q1, J-I1–I3.
- **Steps:** Geoff (or W-2 with him watching) runs through these in Duo's tab, about 25 actions:
  - outline, tabs
  - accept/reject one and all
  - comment, @mention, assign
  - version history, name a version, restore
  - Share dialog, copy link, request access
  - find and replace
  - insert a chip, image upload, drag and drop an image, rich paste from Duo's Markdown editor and back
  - download docx, PDF and Markdown, print
  - template gallery, Docs' own spellcheck, the right-click menu
  - Gemini side panel (if his account has it)
  - links to other Docs and to non-allowed sites
- **Measure:** works / works with a duo2 addition / blocked, for each action.
- **Pass:** every H and M person job works.
- **From Geoff:** about 20 min of his time in Duo; a visible run.

### T-13 · Markdown and docx round trips (L8)
- **Jobs:** J-P1, J-P2, J-P3, J-O2.
- **Steps:**
  1. Export D1 and D3 as Markdown (Drive export through W-6 and through the API), and with Docs' Copy as Markdown.
  2. Import a Duo Markdown doc with CriticMarkup into a Doc.
  3. Run DL-236's Convert on a docx export with comments.
- **Needs:** W-6, W-7.
- **Measure:** what's kept (headings, lists, tables, links, chips, comments, suggestions), by diff.
- **Pass:** recorded, for the project-copy feature.
- **From Geoff:** nothing.

### T-14 · "What changed since I last looked"
- **Jobs:** J-T1, J-T3, J-L3, J-L4, J-C4.
- **Steps:**
  1. Snapshot D4 (hook text plus API `documents.get` with comments and suggestions).
  2. Let the collaborator edit, comment and suggest.
  3. Diff the snapshots, and compare with Drive revisions' exports.
- **Needs:** W-1, W-7.
- **Measure:** whether the diff is complete and attributed; how fresh `revisions.list` is.
- **Pass:** every change found, with who made it.
- **From Geoff:** the collaborator (folded into T-08's session).

### T-15 · Many Docs open: restore and memory
- **Jobs:** J-A8.
- **Steps:**
  1. Open three Docs in two projects, quit, relaunch.
  2. Measure WebContent memory for each Doc (`measure-web-lifetimes.sh`-style).
- **Needs:** the exclusive lock.
- **Measure:** whether the restored tabs come back signed in and in place; MB per Doc.
- **Pass:** they restore; memory recorded against C-83.
- **From Geoff:** nothing.

## Which test covers each job (H and M jobs)

| Job | Tests |
|---|---|
| J-A1, J-A2, J-A3 | T-01, T-12 |
| J-A4, J-A5, J-A6 | T-02, T-03, T-05 |
| J-A7, J-A8 | T-12, T-15 |
| J-B1–B6 | T-02, T-04, T-11; J-B5's UX is Phase 3 |
| J-C1–C4 | T-02, T-03, T-14 |
| J-D1–D4 | T-05, T-06 |
| J-E1–E6 | T-05, T-06, T-08 |
| J-F1–F4 | T-12, T-05, T-03 |
| J-G1–G5 | T-12, T-05, T-09, T-03 |
| J-H1–H4 | T-09, T-05 |
| J-I1–I3 | T-05, T-12 |
| J-J1–J3 | T-01, T-03, T-12 |
| J-K1, J-K2 | T-01, T-12; J-K2 uses `browser screenshot` |
| J-L1–L4 | T-12, T-14 |
| J-M1–M3 | T-12; J-M2 is a rule, not a test |
| J-N1–N5 | T-08 |
| J-P1–P3 | T-13, T-12 |
| J-Q1, J-R1, J-R2, J-S1 | T-12, T-05 |
| J-T1–T3 | T-14, T-09 |

## Order and what Geoff gives

1. **Without anyone, before T-00 (a day):** build W-1 to W-6 on a scratch branch. Re-run T-02 and T-03 signed out on public Docs, as a regression baseline.
2. **Geoff's first sitting (about 20 min):** T-00 (sign in), then T-10 and T-12's quick half on screen.
3. **Signed in, no one else:** T-02, T-03, T-01, T-06, T-07, T-15.
4. **After the API authorization:** T-04, T-05 (single-user half), T-11, T-13.
5. **One session with the collaborator (about 30 min):** T-08, T-05's concurrent half, T-09, T-14.

If T-00 fails (Google refuses sign-in in Duo's web view), stop. A and C then need another way in, and Checkpoint 2 comes early.
