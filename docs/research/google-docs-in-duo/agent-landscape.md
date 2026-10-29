---
title: How agents drive Google Docs today
status: research
task: tasks/google-docs-in-duo.md
phase: 1B (gdocs-landscape)
date: 2026-10-29
records: [F-409, F-410]
---

# How agents drive Google Docs today

Phase 1B of [Google Docs in Duo](../../../tasks/google-docs-in-duo.md). This is a survey of how computer-use agents, browser agents, extensions and API tools read, select, suggest and comment in Google Docs, as of 2026-10-29. It covers outside work only. Duo's own browser and Google's technical surface in depth are gdocs-frame's (Phase 1A).

The survey drew on web search and fetches only, with no Google account and no sign-in. The tags work like this:
- **[V] (verified):** a primary source says so, meaning Google's or a vendor's docs, release notes, or the code itself. I re-read the three findings the conclusions hang on myself (the Docs API's suggest mode, Claude's Docs add-on limits, and Harper's bridge code).
- **[R] (reported):** secondary or hands-on reports.
- **[I] (inferred):** my own reasoning.

## The short version

1. **Since 2026-09-30, the Docs API can make real suggestions and anchored comments** [V], so the old rule that the API "can't suggest" no longer holds. The rest of this doc follows from that.
   - Setting `writeControl.writeMode: "SUGGEST"` on `documents.batchUpdate` turns every request in the batch into a tracked change.
   - `insertComment` takes a `range`, and `addCommentReply` can resolve or reopen a thread.
   - `acceptSuggestion`, `rejectSuggestion` and `deleteSuggestion` exist.
   - This is GA in the release notes (preview since 2026-07-07). It covers personal accounts too, with no admin switch. (F-409)
2. **No outside tool knows the user's selection through a sanctioned, live channel.** Apps Script's `getSelection()` works, but only in an Editor add-on or bound script, and by polling. Anthropic's own Docs add-on gets the selection that way [V]. The API and Google's MCP server have no selection or cursor at all [V].
3. **Inside the page, the one route that has lasted is Google's private "annotated canvas"** [V, code]. A page-world script asks `_docs_annotate_getAnnotatedText(id)` for the doc's text and selection, and edits with `setSelection` plus a synthetic paste into the text-event iframe. Chromium's Reading Mode and Harper use it. It is gated by an undocumented extension-ID allowlist, and borrowing an ID is a policy risk. (F-410)
4. **Browser agents (Claude in Chrome, ChatGPT agent and Atlas, Gemini's auto browse, Browser Use and friends) have no Docs special case.**
   - They read from screenshots and whatever accessibility tree Docs exposes, and type with the keyboard.
   - There is no published reliability figure for Docs. Anecdotes run from "typed it fine, then timed out" to "said it was done and wasn't".
   - None documents using Suggesting mode or comments, though the keyboard shortcuts would let them.
5. **No public benchmark scores Google Docs editing.**
   - OSWorld's 8 Drive tasks are optional, and runs usually skip them.
   - The nearest analogues are LibreOffice Writer in OSWorld and Windows Agent Arena, and ownCloud's web Office in TheAgentCompany. They are the weakest areas in all three, with clicks, selection and formatting the common failures.

## Approaches compared

The table's columns:
- **Reads with:** how it reads the doc.
- **Writes with:** how it changes the doc.
- **Suggest:** can it make tracked changes?
- **Comment:** can it add comments?
- **Selection:** does it know the user's selection?
- **Latency and reliability:** how fast it works, and how often.
- **Sources:** numbered in the list below.

| Approach | Who | Reads with | Writes with | Suggest | Comment | Selection | Latency and reliability | Sources |
|---|---|---|---|---|---|---|---|---|
| **Docs API, suggest mode** | Anyone with OAuth: Google's MCP server, a-bonus/google-docs-mcp, Claude_Docs | `documents.get`: a structured tree with UTF-16 indexes, and suggestions shown inline or previewed | `batchUpdate`; `requiredRevisionId` makes an edit fail if the doc changed, and `targetRevisionId` merges with collaborators' changes | **Yes**, GA 2026-09-30 [V]. Not for tabs, named ranges, header or footer deletes, or column widths | **Yes, anchored**: `insertComment` with a range, plus reply, resolve, reopen and delete [V] | **No** [V] | One HTTP round trip; no published figures, so Phase 2 measures it. Quota is 60 writes and 300 reads per user per minute [V]. Reliable and documented [I] | 1, 2, 3, 4 |
| **Google Docs MCP server** (`docsmcp.googleapis.com`) | Google, in developer preview since 2026-07-13 | `read_doc`: "verbalized text" as JSON, with comments optional | `update_doc` passes `batchUpdate` and `writeControl` through | Yes, through `writeMode` [V] | Yes, comment support since 2026-10-01 [V] | No | As the API. From 2026-11-11 the OAuth client must be flagged "AI-powered agent" [V] | 3, 5 |
| **Drive API** (export and comments) | Most MCP servers, connectors, web-capture tools | `files.export` to txt, html, docx, **`text/markdown`** and more [V] | Whole-file update only | No | Comments stay **unanchored** in Docs [V] | No | Fast, but the read is a whole-doc snapshot [I] | 6, 7 |
| **Apps Script Editor add-on or bound script** | Anthropic's "Claude in Google Docs" add-on (beta since 2026-10-06); classic add-ons | `DocumentApp` in the user's session | `DocumentApp` edits are **direct** | Not through DocumentApp; the Advanced Docs service may pass `SUGGEST` through [I, untested] | Through the Docs API from the script [I] | **Yes**: `getSelection()` and `getCursor()`, bound or add-on only, pull only with no change event [V] | A `google.script.run` round trip per poll [R]; Google stops a call after 6 min [V] | 8, 9, 10 |
| **Card-based Workspace add-on** | Newer add-ons | REST APIs with `drive.file` | REST APIs | Via the API | Via the API | **Not documented** [I: none] | — | 11 |
| **Claude in Google Docs** (Anthropic's add-on) | Claude Pro/Max/Team/Enterprise | Open file plus the selection [V] | Direct edits under the user's name, with "ask before edits" [V] | **No**: proposal cards in the sidebar, not Docs suggestions. It can't accept or reject existing ones [V] | **No**: it "cannot read, reply to, or resolve comments" [V] | **Yes** [V] | Up to 6 min per operation; closing the sidebar stops it [V] | 8, 12 |
| **Claude's Google Workspace connector** | claude.ai | Text only [V] | Creates and edits Docs, re-reading before each change [V] | Unclear: says Claude "can see comments and suggestions" [V], not whether it makes them | Unclear | Not documented | — | 13 |
| **ChatGPT Google Drive app** | OpenAI, editing native Docs since about 2026-08 [R] | Connector | API-style "batch update" with approval [R] | No evidence | No evidence | No evidence | — | 14, 15 |
| **Gemini in Docs** | Google, native | Server-side, the whole doc | Edits and "Help me write"; proposed edits are **private to the user until approved** [V] | Private proposals, which no API offers [V] | Summarises threads, inserts comments, drafts replies, edits from feedback (Jul 2026; help page says trusted testers) [V] | **Yes**: select text to focus it [V] | Native | 16, 17 |
| **Annotated-canvas bridge** (in-page JS) | Chromium Reading Mode, Harper, and reportedly Grammarly, LanguageTool and Wordtune | `_docs_annotate_getAnnotatedText(id).getText()`: plain text with offsets [V, code] | `setSelection(start,end)`, then a synthetic `paste` ClipboardEvent into `.docs-texteventtarget-iframe`'s contenteditable, then re-read to confirm [V, code] | **Yes, if the tab is in Suggesting mode** [I]: it's a user paste | Through the UI (⌘⌥M) [I] | **Yes**: `getSelection()` gives offsets [V, code] | In-page and immediate [I]. Gated by an undocumented allowlist; private and could break [V/R] | 18, 19, 20, 21 |
| **Screen-reader mode** (⌘⌥Z) | Screen readers and braille; DL-7 relies on it | A hidden "side DOM" and live regions [R] | Keyboard | Keyboard, in Suggesting mode | Keyboard | Speaks the selection [R]; whether the DOM marks it is unknown | Its current DOM isn't documented anywhere [R] | 22, 23 |
| **Screenshots and keyboard** (computer use, CUA) | Claude computer use, ChatGPT agent and Operator, Gemini auto browse | Screenshot or vision | Clicks and `type` or `key` | Via ⌘⌥⇧X, untested anywhere | Via ⌘⌥M, untested anywhere | Only what it can see highlighted | Slow (seconds per step). Click accuracy is the leading failure in OSWorld [V], and agents "act as if succeeded" [V] | 24, 25, 26 |
| **DOM and accessibility-tree browser agents** | Claude in Chrome, Atlas, Browser Use, Stagehand, Playwright MCP, Nanobrowser | `read_page` or a11y tree; screenshots as fallback; canvas often has "no useful node" [V] | Keyboard to the focused text-event iframe | Not documented | Not documented | No | Browser Use's text "correctly inputs" but timed out [R]; Nanobrowser can't read or scroll Docs [R]; no Docs code in any repo [V] | 27, 28, 29, 30 |
| **Model internals** (`DOCS_modelChunk`, `KX_kixApp`) | web-capture (Rust), old userscripts | Intercepted model chunks [V, code] | — | — | — | `KX_kixApp` gone from global scope since 2025-10 [R] | Read-only and the most brittle | 21, 31 |
| **Agent's own account plus a cloud browser** | interface0 (2025-11) | Browser | Browser in Suggesting mode, as the agent's own Google user | Yes, attributed to the agent | Yes | No | "imperfect and a little brittle" by the author's account [R] | 32 |
| **Old routes, now dead** | `_docs_force_html_by_ext`, `?mode=html`, google-docs-utils | — | — | — | — | — | Retired around 2022 [R] | 21, 33 |

## What works best today

**(a) Reading.**
- **Best: the API's structured read, with Markdown export for a quick look.**
  - `documents.get` gives exact structure, tabs, suggestions and comments with indexes you can write back to, and it's GA [V].
  - Drive `text/markdown` export is the cheapest whole-doc read [V].
- **In the page:** the annotated canvas gives live text in the user's session with no OAuth [V, code].
- **Screen-reader mode is a legitimate fallback** and is what DL-7 bet on. It's undocumented in shape, so Phase 2 must look at it.
- Screenshots work but are slow and lossy.

**(b) Knowing the selection.**
- **Sanctioned:** an Apps Script Editor add-on's `getSelection()`, which Claude's own add-on uses [V]. It is pull only, and it needs an add-on installed or a per-doc bound script.
- **Unsanctioned but proven:** the annotated canvas's `getSelection()` gives offsets into the text, live [V, code].
- **Fallbacks:**
  - Read the selection that screen-reader mode exposes.
  - Copy the selection and match it against the API text. Claude_Docs does this with the user copying [V].
  - In Duo, a page-world script can read the `copy` event's payload without touching the system pasteboard [I].
- Nobody uses any of these over the API, which has no selection [V].

**(c) Suggesting edits.**
- **Best: Docs API `SUGGEST` mode** [V].
  - It's real Docs suggestions that every collaborator sees, made against a revision, and it merges with live edits.
  - The suggestion is credited to the OAuth user [I: the docs imply authorship but don't say; Phase 2 checks]. For Geoff that means his own name, not "Claude".
- **In the page:**
  1. Switch the tab to Suggesting mode (⌘⌥⇧X) [V].
  2. Insert by the annotated-canvas paste, or by typing.
  - This is the user's own suggestion, made in his session. Gemini's private-until-approved proposals have no outside equivalent [V].

**(d) Commenting.**
- **Best: Docs API `insertComment` with a range** [V].
  - It is anchored, which the Drive API never managed, and replies and resolves go with it.
  - Older MCP servers still use Drive comments and warn they "aren't visibly anchored" [V].
- **In the page:** select the text, then ⌘⌥M, then type [V for the shortcut].

## Techniques Duo could borrow

Duo's browser is WKWebView, not Chrome, so Chrome-extension mechanics don't carry over directly [I]. Duo can, though, inject `WKUserScript`s at document start into every frame of an allowed site, in the page's world, which is more access than a content script has.

| Technique | What it gives Duo | Solidity | Policy or ToS |
|---|---|---|---|
| **Docs API through Geoff's own OAuth**: `get`, `SUGGEST` batches, `insertComment`, `requiredRevisionId`; Drive Markdown export | Reads, tracked changes, anchored comments and replies, all documented | **Solid**: public, GA and versioned | Sanctioned. Needs a Google Cloud OAuth client. `documents` is a sensitive scope, so a fleet-wide client needs Google's verification, while `drive.file` (per-file, via the Picker) does not [I; Phase 3]. MCP clients need the "AI-powered agent" flag from 2026-11-11 [V] |
| **Google's Docs MCP server** for Claude in a Duo session | The same reach, without Duo writing API code | Developer preview | Sanctioned. Same OAuth questions |
| **Keyboard shortcuts in the tab**: ⌘⌥⇧X Suggesting, ⌘⌥⇧Z Editing, ⌘⌥M comment, ⌘⇧H find and replace, ⌘⌥Z screen reader | Mode switches and UI-level suggest or comment through `duo2 browser` keys (Duo has no key verb yet; gdocs-frame's inventory) | **Fairly solid**: documented user shortcuts, though keys can collide in WKWebView [I] | None: it's the user's UI |
| **Screen-reader mode plus the WKWebView accessibility tree** (DL-7) | Text without OAuth or private hooks | **Medium**: supported for users, but the DOM is undocumented | None |
| **Annotated canvas**: set `_docs_annotate_canvas_by_ext` at document start, then `getAnnotatedText`, `getSelection`, `setSelection` and a synthetic paste | Live text, the **live selection**, and exact range replacement (as a suggestion in Suggesting mode) | **Fragile**: private, undocumented, keyed to an allowlist. Unknown whether Docs checks the ID's origin (Chrome extension APIs) at all in WebKit | **Real risk.** Using another extension's allowlisted ID looks like impersonation and "bypassing protective measures" under Google's ToS (2026-07-30) [I]. The sanctioned route is to apply to Google's allowlist (a 2021 form, no recorded answers [R]). Don't ship it without Geoff's call |
| **Synthetic paste without the bridge**: focus the text-event iframe, dispatch `paste` with `text/plain` or `text/html` | Inserting at the caret without the system clipboard; possibly with formatting | **Medium** [I]: Harper relies on the paste path. An HTML paste is untested anywhere | None beyond automation of the user's own session |
| **Copy-event capture for the selection**: page-world listener on `copy`, read Docs' own `clipboardData` | The selection's text (and HTML) when the user or Duo copies | **Medium** [I]: uses a standard event | None. Must not overwrite the user's pasteboard |
| **Apps Script Editor add-on** ("Duo for Docs") polling `getSelection()` and posting to Duo | The live selection, sanctioned | **Solid but heavy**: install per user, a Marketplace listing for the fleet, polling latency | Sanctioned. Needs Google review to publish beyond test users |
| **Model chunks or `KX_kixApp`** | — | **Broken or brittle** | Reverse engineering. Don't |

## For gdocs-frame's Phase 2 test plan

These are the unknowns that only a test in Geoff's signed-in Duo answers.

1. **API suggest mode in practice.**
   - Who is credited: Geoff, the OAuth app, or a label?
   - How fast does a `SUGGEST` batch show in an open Duo tab and in a second collaborator's tab?
   - Does `targetRevisionId` merge cleanly while someone is typing?
2. **Anchored comments.** Does `insertComment` show anchored in the editor? Does the anchor survive edits around it?
3. **Mapping the user's selection to API indexes.**
   - Selection text (from the bridge, copy or screen-reader mode), matched against `documents.get` text, gives a UTF-16 range.
   - What does it do with repeated phrases, smart chips, tables, footnotes and tabs?
4. **Annotated canvas in WKWebView.**
   - Does setting the flag at document start make `_docs_annotate_getAnnotatedText` appear?
   - With what ID: none, Chromium Reading Mode's, or a made-up one?
   - Whatever the result, record it, and don't adopt it without Geoff's ToS call.
5. **Screen-reader mode in WKWebView.**
   - What does the side DOM or accessibility tree hold: the whole doc or just the visible page, and the selection?
   - Does `duo2 browser read` see it?
6. **Typing paths into the text-event iframe.** Compare `duo2 browser fill`/type, `Input`-style key events, a synthetic `paste` (plain and HTML) and `execCommand('insertText')`, in Editing and in Suggesting mode, for:
   - correctness and formatting
   - speed per 1,000 characters
   - what the undo stack looks like
7. **Shortcuts in WKWebView.** Do ⌘⌥⇧X, ⌘⌥M, ⌘⌥Z and ⌘⇧H reach Docs, or does Duo or macOS take them?
8. **Markdown round trip.** Drive `text/markdown` export, compared with "Copy as Markdown" (Tools → Preferences), for fidelity on Geoff's real docs.
9. **Apps Script selection latency.** Measure a bound-script sidebar polling `getSelection()` (one test doc, with Geoff's one authorization).
10. **Google's MCP server.** Is a Claude session's `update_doc` with `SUGGEST` and `insertComment` at parity with REST, and how much setup does it take?

## Questions for Geoff (held for Checkpoint 1)

- **Q1.** Annotated canvas: it is the only live, in-page way to get text and selection, but it rides an undocumented allowlist. Is it out of bounds for Duo, out of bounds unless Google allowlists Duo (we'd apply), or acceptable for your local build only? Recommendation: out of bounds unless allowlisted. Test it once for the record (§Phase 2, item 4).
- **Q2.** API suggestions will carry **your** name, not Claude's. Is that acceptable, or should Claude suggest as a separate Google identity (a second account), as interface0 does?
- **Q3.** OAuth for the fleet: should Duo plan for its own verified Google client (scope review), or should the API path stay "bring your own client" or local-only for now?

## Sources

1. Docs API, *Work with comments and suggestions*, updated 2026-09-30: https://developers.google.com/workspace/docs/api/how-tos/suggestions
2. Docs API release notes (2026-07-07 preview; 2026-09-30 GA; MCP 2026-07-13, 2026-10-01, 2026-10-12): https://developers.google.com/workspace/docs/release-notes
3. Workspace Updates, *Programmatic comment and suggestion support*, 2026-09-30: https://workspaceupdates.googleblog.com/2026/09/programmatic-comment-and-suggestion.html
4. Docs API usage limits, updated 2026-09-03: https://developers.google.com/workspace/docs/api/limits
5. Docs MCP server reference (`read_doc`, `update_doc`), 2026: https://developers.google.com/workspace/docs/api/reference/mcp
6. Drive export formats, updated 2026-09-03: https://developers.google.com/workspace/drive/api/guides/ref-export-formats
7. Drive *Manage comments* (Docs treats Drive anchors as unanchored), updated 2026-09-10: https://developers.google.com/workspace/drive/api/guides/manage-comments
8. Claude help, *Use Claude in Google Docs, Sheets and Slides*, about 2026-10: https://support.claude.com/en/articles/16951679-use-claude-in-google-docs-sheets-and-slides
9. Apps Script `Document.getSelection()` and `getCursor()`: https://developers.google.com/apps-script/reference/document/document
10. Editor add-on translate quickstart (reads the selection): https://developers.google.com/workspace/add-ons/editors/docs/quickstart/translate
11. Workspace add-ons for Editors, updated 2026-10-09: https://developers.google.com/workspace/add-ons/editors/gsao
12. Anthropic, *Claude now works in Google Docs, Sheets and Slides*, 2026-10-06: https://claude.com/blog/claude-now-works-in-google-docs-sheets-and-slides
13. Claude help, *Use the Google Workspace connector*, about 2026-10: https://support.claude.com/en/articles/10166901-use-the-google-workspace-connector
14. OpenAI help, *Google Drive app* (HTTP 403; snippets only): https://help.openai.com/en/articles/10929079-google-drive-app-and-setup-in-chatgpt
15. Report on ChatGPT editing native Drive files, 2026-08-14: https://letsdatascience.com/news/chatgpt-adds-direct-editing-for-google-drive-files-503e4d8d
16. Workspace Updates, Gemini comment workflows in Docs, 2026-07-28: https://workspaceupdates.googleblog.com/2026/07/streamline-collaboration-in-google-docs-with-Gemini-powered-comment-workflows.html; help page https://support.google.com/docs/answer/17133843
17. Workspace Updates, Gemini edits "only visible to you until you approve them", 2026-07-16: https://workspaceupdates.googleblog.com/2026/07/expanded-language-support-for-gemini-in-Google-Docs.html
18. Chromium Reading Mode Docs helper (`gdocs_script.js`), main branch: https://chromium.googlesource.com/chromium/src/+/main/chrome/browser/resources/reading_mode_gdocs_helper/gdocs_script.js
19. Harper `google-docs-bridge.js`, master, read 2026-10-29: https://github.com/Automattic/harper/blob/master/packages/chrome-plugin/public/google-docs-bridge.js; Harper contributor notes: https://writewithharper.com/docs/contributors/chrome-extension
20. Yomichan PR #2235 (annotated canvas, allowlist), 2022-09-25: https://github.com/FooSoft/yomichan/pull/2235
21. google-docs-utils #10 (force-HTML, annotated canvas, `KX_kixApp` gone), 2021-05 to 2025-10: https://github.com/Amaimersion/google-docs-utils/issues/10; Chromium extensions thread, 2022-11 to 2023-02: https://groups.google.com/a/chromium.org/g/chromium-extensions/c/dLnxATEOcqg; Google forum, 2023-02 and 2025-01: https://discuss.google.dev/t/annotated-canvas-in-google-docs-for-chrome-extension/102700
22. Workspace Updates, canvas rendering, 2021-05: https://workspaceupdates.googleblog.com/2021/05/Google-Docs-Canvas-Based-Rendering-Update.html; WebAIM, 2021-05: https://webaim.org/blog/seismic-change-to-docs/
23. Docs keyboard shortcuts: https://support.google.com/docs/answer/179738; screen-reader support: https://support.google.com/docs/answer/6282736
24. Anthropic computer-use tool (`computer_toolset_20260801`): https://platform.claude.com/docs/en/agents-and-tools/tool-use/computer-use-tool
25. OpenAI, *Computer-Using Agent*, 2025-01: https://openai.com/index/computer-using-agent/
26. Gemini in Chrome auto browse, 2026-01-28 (secondary): https://9to5google.com/2026/01/28/chrome-gemini-auto-browse/
27. Anthropic browser-use tool (canvas "no useful node"): https://platform.claude.com/docs/en/agents-and-tools/tool-use/browser-use-tool; Claude in Chrome, getting started: https://support.claude.com/en/articles/12012173-get-started-with-claude-in-chrome; `get_page_text` bug, 2026-10-19: https://github.com/anthropics/claude-code/issues/103511
28. Browser Use PR #571 (Docs typing, timeout), 2025-02-12: https://github.com/browser-use/browser-use/pull/571; PR #1101 (Sheets shortcuts), 2025-03-22: https://github.com/browser-use/browser-use/pull/1101
29. Nanobrowser #31 (can't read Docs), 2025-03-12: https://github.com/nanobrowser/nanobrowser/issues/31
30. Atlas: OpenAI publishers FAQ (403; seen through https://adrianroselli.com/2025/10/openai-aria-and-seo-making-the-web-worse.html); hands-on: https://www.makeuseof.com/week-with-chatgpt-atlas-convinced-me-to-uninstall-it/
31. web-capture `gdocs.rs` (model chunks, export URLs): https://docs.rs/web-capture/0.3.10/src/web_capture/gdocs.rs.html
32. Andy Bromberg, *interface0*, 2025-11-11: https://andybromberg.com/interface0-google-docs
33. google-docs-utils README (pre-canvas typing): https://github.com/Amaimersion/google-docs-utils
34. MCP servers: https://github.com/a-bonus/google-docs-mcp (suggest mode merged 2026-10-26; Drive comments unanchored); https://github.com/taylorwilsdon/google_workspace_mcp (no suggestions; `requiredRevisionId`); https://composio.dev/toolkits/googledocs (no comments or suggestions); https://github.com/bzreinhardt/Claude_Docs (copy-and-match selection)
35. Benchmarks: OSWorld https://arxiv.org/html/2404.07972 and https://xlang.ai/blog/osworld-verified (2025-07-28); Windows Agent Arena https://arxiv.org/html/2409.08264; TheAgentCompany https://arxiv.org/html/2412.14161; OfficeBench https://arxiv.org/html/2407.19056
36. Google Terms of Service, effective 2026-07-30: https://policies.google.com/terms; Chrome Web Store impersonation policy: https://developer.chrome.com/docs/webstore/program-policies/impersonation-and-intellectual-property

## Appendix: MCP servers and benchmarks in brief

**MCP servers.** Only Google's own server and a-bonus/google-docs-mcp make suggestions.

| Server | Make suggestions | Comments | Other |
|---|---|---|---|
| Google's own | Yes, via `update_doc`, which passes `writeControl` through | Yes | Developer preview |
| a-bonus/google-docs-mcp (about 680 stars) | Yes, with `suggestMode: true`, plus list, accept and reject | Uses the Drive API, so unanchored | Reads Markdown |
| taylorwilsdon/google_workspace_mcp (about 3.4k stars) | No | Uses the Drive API | Revision-guarded edits |
| Composio | No | No | 46 actions |

None of them knows the selection or cursor.

**Benchmarks.** None scores Google Docs editing.

| Benchmark | Docs coverage | Best result | Failures reported |
|---|---|---|---|
| OSWorld | Its 8 Drive tasks are skippable | Office: 8.55% against 72% for humans (original paper) | Inaccurate clicks, ungrounded formatting |
| Windows Agent Arena | Office means LibreOffice | 0% on Office | Shortcut- and icon-heavy tasks |
| TheAgentCompany | ownCloud web Office | — | Blames "the complexity of the UI of web-based Office software" |

No model card reports a Docs evaluation.
