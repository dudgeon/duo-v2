# Google Docs' technical surface, as of 2026-10-29

Phase 1A of [Google Docs in Duo](../../../tasks/google-docs-in-duo.md). This is what Google Docs offers a tool that wants to read and change a Doc: in the page (the live editor in a browser), through the Docs and Drive APIs, and through Apps Script and add-ons. Each fact has its source and date.

Tags:
- **[VERIFIED]** means read in a primary source: Google's docs, release notes or help, or Chromium's code.
- **[INFERRED]** means a secondary source or reasoning.
- **[PROBED]** means measured here, in WebKit, on a public Doc, signed out (see [duo-browser-today.md](duo-browser-today.md)).

Spot checks:
- I re-read the two claims that change the plan most myself, on 2026-10-29: the Docs API's suggest mode, and Google's 2026-09-30 announcement.
- The landscape survey ([agent-landscape.md](agent-landscape.md), F-409, F-410) covers who uses these routes. This doc covers what the routes are.

## What changed the picture

1. **The Docs API can write suggestions and anchored comments (since 2026-09-30).**
   - It writes suggestions with `writeControl.writeMode: SUGGEST`, and accepts and rejects them with `acceptSuggestion`, `rejectSuggestion` and `deleteSuggestion`.
   - It creates anchored comments with `insertComment{range, content, assigneeEmailAddress}`, and replies, resolves and reopens with `addCommentReply`.
   - This covers personal accounts too. The announcement says comment support "remains in developer preview in accordance with the preview status of the MCP servers".
   - [VERIFIED] (https://workspaceupdates.googleblog.com/2026/09/programmatic-comment-and-suggestion.html, 2026-09-30; https://developers.google.com/workspace/docs/api/how-tos/suggestions, "Last updated 2026-09-30"). F-409.
2. **Docs' in-page annotated-text hook answers any caller in WebKit.**
   - `_docs_annotate_getAnnotatedText(id)` is defined by Docs' own boot script.
   - It returned the whole text, the links, the selection and `setSelection` for a made-up id, without the `_docs_annotate_canvas_by_ext` flag, signed out.
   - Every outside source describes it as allowlisted. That may hold for the SVG overlay, or in Chrome, or signed in; the hook itself wasn't gated here.
   - [PROBED] F-412.
3. **Nothing official exposes the live selection except Apps Script in a bound script or editor add-on**, and that only by polling. [VERIFIED]
4. **There is no realtime op stream and no presence API.** Change signals (Drive push, Workspace Events) say "something changed", with no diff. [VERIFIED / INFERRED as marked below]
5. **Google sign-in in an embedded WKWebView is against Google's stated policy.** OAuth refuses it outright (`disallowed_useragent`); plain sign-in "may" be stopped. [VERIFIED for the policy; enforcement INFERRED]

## 1. Canvas rendering and what DOM remains

- **The 2021 announcement.** On 2021-05-11 (updated 2021-05-26), Google said Docs was moving from HTML-based to canvas-based rendering "over the coming months", for performance and cross-platform consistency. [VERIFIED] (https://workspaceupdates.googleblog.com/2021/05/Google-Docs-Canvas-Based-Rendering-Update.html, 2021-05-11/26)
- **What it said about extensions.** Chrome extensions that rely on Docs' HTML "may no longer work as intended". Admins should test them. In-house extensions should migrate to the Google Workspace Add-ons framework, which "uses the supported Workspace APIs and integration points". It gave a feedback form for private extensions that can't migrate, and a canvas test doc. The post itself mentions no allowlist. [VERIFIED] (same)
- **Accessibility claim in the post.** Screen readers, braille devices and magnifiers "will not be impacted". [VERIFIED] (same)
- **`_docs_annotate_canvas_by_ext`.** This is a page-global set to a *Chrome extension ID*. It makes Docs render an "annotated canvas" so that "the a11y tree [can] be built for the document contents". Chromium's own Reading Mode helper sets it (file copyright 2024), injecting it into the page context from the extension. [VERIFIED as present in Chromium source] (https://chromium.googlesource.com/chromium/src/+/main/chrome/browser/resources/reading_mode_gdocs_helper/gdocs_script.js, acc.)
- **What the annotated canvas looks like.** Each canvas tile carries an SVG overlay, `.kix-canvas-tile-content svg > g > rect`, whose `aria-label` holds the text of each run. Tools read text and positions from these rects. Yomichan had to add a fill so the rects show up in `elementsFromPoint`. [INFERRED] (Yomichan commit "Google Docs accessibility update (#2235)", https://git.foosoft.net/alex/yomichan/commit/8240482e9d0b6da7a996bc581c9b5304ebcf22aa, acc.)
- **`_docs_force_html_by_ext`.** Set the same way, it forces the legacy HTML render. If any extension forces HTML, the annotated canvas doesn't render, so they conflict. [INFERRED] (Stack Overflow Q 70996296, 2022-02-05, and answer, 2022-03-02, https://stackoverflow.com/questions/70996296/annotated-canvas-rendering-in-google-docs)
- **Is the flag allowlisted?** Setting the flag with an arbitrary extension ID reportedly has no effect. Developers describe an allowlisting form with no response (2023-02-06; still unanswered 2025-01-29). Grammarly, LanguageTool and Wordtune reportedly use it. Google doesn't document it publicly. Its current status, and whether a non-Chrome host (WKWebView with no extension ID) can trigger it, is unknown. [INFERRED] (https://discuss.google.dev/t/annotated-canvas-in-google-docs-for-chrome-extension/102700, 2023-02-06; SO 70996296)
- **Keyboard input target.** Docs takes keystrokes through a hidden iframe (`.docs-texteventtarget-iframe`) whose body is `contenteditable="true"`, `role="textbox"`. Userscripts dispatch into it, but synthetic key events are often reported not to work. [INFERRED] (https://greasyfork.org/scripts/562026-docskeys-vim-for-google-docs/code, acc.; SO answers in search, various)
- **EditContext.** Chromium's EditContext Intent-to-Ship is reported to mention Docs moving IME input off the hidden contenteditable. EditContext is Chromium-only (Chrome 121, January 2024), and Safari doesn't support it (WebKit bug 269922). In WKWebView, Docs therefore presumably still uses the contenteditable path. [Chrome/Safari support VERIFIED; the Docs usage INFERRED] (https://developer.chrome.com/blog/introducing-editcontext-api, updated 2024-02-02; https://web-platform-dx.github.io/web-features-explorer/features/edit-context, acc.; https://groups.google.com/a/chromium.org/g/blink-dev/c/yOxNDSaviyU, acc.)
- **Screen reader and braille settings.** Tools > Accessibility > "Turn on screen reader support" (Mac shortcut ⌘⌥Z) and "Turn on braille support" (⌘⌥H). Braille support shows content on the display, makes routing keys move the cursor, gives faster typing echo and character navigation, and announces punctuation better. Google recommends "the latest Chrome"; Safari isn't mentioned, though VoiceOver is. [VERIFIED] (https://support.google.com/docs/answer/6282736, acc.; https://support.google.com/docs/answer/6057417, acc.)
- **What those settings change in the DOM.** Screen reader mode adds aria-live announcement regions. Braille mode is widely reported to expose the document text, and the caret/selection, in an accessible DOM so the display can follow. Google doesn't document the DOM. [INFERRED] (my reasoning from the documented behaviour; no primary source)
- **Measured in WebKit (Duo's engine), signed out, view-only, 2026-10-29.** [PROBED]
  - **Rendering:** 3 canvases and 6 tiles; no `.kix-lineview` HTML render; no SVG `rect[aria-label]` overlay.
  - **The DOM:** body text is chrome plus the outline's headings. The keyboard target is the hidden `.docs-texteventtarget-iframe`. Live regions (`aria-live`) exist but were empty.
  - **The hook:** `_docs_annotate_getAnnotatedText` is defined by the page's boot script (`function(id) {return KX_kixApp.getAnnotatedText(id);}`). Called from the page world with any id, it resolves to `{getText, getAnnotations, getSelection, setSelection}`. `getText()` gives the whole doc (5,104 characters, under 1 ms). `getAnnotations()` gives `{link: [...]}`. `getSelection()` follows real drags and Shift+arrow keys. `setSelection()` draws a real selection.
  - The landscape survey reports `KX_kixApp` gone from global scope since 2025-10; it is, but the hook still reaches it through the closure.
  - Signed-in and editable behaviour, and whether suggestions or comments show up in `getAnnotations()`, are Phase 2's to test (T-02, T-03).
- **Is the selection exposed in the DOM?** Not in any documented mode. In canvas mode the selection is drawn (overlay rects). The annotated canvas gives text positions, so the selection can only be inferred geometrically. The supported way to read the selection is Apps Script `getSelection()` in a bound script or editor add-on (§5). [INFERRED]
- **Changes 2023–2026.** I found no official post changing the canvas, annotated-canvas or extension policy since 2021. The 2024 Chromium Reading Mode helper shows Google still relies on the annotated canvas internally. [INFERRED] (absence of evidence; Chromium file above)

## 2. Docs API v1

- **`documents.get` parameters.** `suggestionsViewMode` = `DEFAULT_FOR_CURRENT_ACCESS` (view-only users get `PREVIEW_WITHOUT_SUGGESTIONS`), `SUGGESTIONS_INLINE`, `PREVIEW_SUGGESTIONS_ACCEPTED` or `PREVIEW_WITHOUT_SUGGESTIONS`. "When editing a document, changes must be based on a document with SUGGESTIONS_INLINE." [VERIFIED] (https://developers.google.com/workspace/docs/api/reference/rest/v1/documents, acc.; https://developers.google.com/workspace/docs/api/reference/rest/v1/documents/get, acc.)
- **New `commentsViewMode`.** Values are `COMMENTS_VIEW_MODE_OMITTED`, `COMMENTS_VIEW_MODE_INCLUDED` and `…DEFAULT_FOR_CURRENT_ACCESS`. `INCLUDED` requires `SUGGESTIONS_INLINE` and `includeTabsContent=true`. [VERIFIED] (same; https://developers.google.com/workspace/docs/api/how-tos/suggestions, updated 2026-09-30)
- **`includeTabsContent`.** With `true`, content comes back in `Document.tabs[]` (a tree with `childTabs`, `tabProperties` {tabId, title, parentTabId, index, nestingLevel, iconEmoji}). With `false`, only the first tab fills `body`. [VERIFIED] (https://developers.google.com/workspace/docs/api/how-tos/tabs, updated 2026-09-03)
- **`batchUpdate` requests (53).**
  - Text and styles: replaceAllText, insertText, updateTextStyle, updateParagraphStyle, updateNamedStyle, updateDocumentStyle, updateSectionStyle, deleteContentRange
  - Lists: createParagraphBullets, deleteParagraphBullets
  - Named ranges: createNamedRange, deleteNamedRange, replaceNamedRangeContent
  - Images and objects: insertInlineImage, replaceImage, deletePositionedObject
  - Tables: insertTable, insertTableRow, insertTableColumn, deleteTableRow, deleteTableColumn, updateTableColumnProperties, updateTableCellStyle, updateTableRowStyle, mergeTableCells, unmergeTableCells, pinTableHeaderRows
  - Breaks: insertPageBreak, insertSectionBreak
  - Headers, footers, footnotes: createHeader, createFooter, deleteHeader, deleteFooter, createFootnote
  - Tabs: addDocumentTab, deleteTab, updateDocumentTabProperties
  - Chips: insertPerson, insertRichLink, insertDate
  - Comments: insertComment, addCommentReply, updateCommentPost, deleteComment, deleteCommentReply
  - Suggestions: acceptSuggestion, rejectSuggestion, deleteSuggestion
  - Dropdowns: createDropdownDefinition, updateDropdownDefinitionProperties, insertDropdown, updateDropdownProperties, deleteDropdownDefinition

  [VERIFIED] (https://developers.google.com/workspace/docs/api/reference/rest/v1/documents/request, acc.)
- **Creating suggestions.** Set `writeControl.writeMode: SUGGEST` (values are WRITE_MODE_UNSPECIFIED=EDIT, EDIT, SUGGEST). Suggest mode rejects AddDocumentTab, CreateNamedRange, DeleteFooter, DeleteHeader, DeleteNamedRange, DeleteTab, UpdateDocumentTabProperties and UpdateTableColumnProperties. Document format and header/footer settings can't be suggested. [VERIFIED] (batchUpdate reference, acc.; suggestions how-to, updated 2026-09-30; announcement 2026-09-30)
- **The old feature request.** Until September 2026 the how-to said suggestions "can be retrieved through the API, but not accepted, rejected, or created programmatically". The localized copies still say this. I could not load issuetracker.google.com (it needs JavaScript), so the tracker ID and its status are unconfirmed; the feature itself has now shipped. [VERIFIED for the shipped feature; INFERRED for the tracker] (localized how-to, e.g. https://developers.google.com/workspace/docs/api/how-tos/suggestions?hl=he, acc.)
- **Accepting and rejecting suggestions.** `acceptSuggestion` needs edit access. `rejectSuggestion` needs edit access or authorship. `deleteSuggestion` needs authorship. `SuggestionThread`s "cannot be created directly"; they come from suggest-mode writes. [VERIFIED] (request reference; documents reference, acc.)
- **Smart chips you can read.** ParagraphElement types are textRun, autoText, pageBreak, columnBreak, footnoteReference, horizontalRule, equation, inlineObjectElement, **person**, **richLink** (a link to a Google resource such as a Drive file, YouTube video or Calendar event; properties title, uri, mimeType), **dateElement** and **dropdown**. Place, finance and other chip types are not listed as elements. [VERIFIED for the list; INFERRED that other chips are absent or come through as text] (documents reference, acc.)
- **Smart chips you can insert.** insertPerson, insertRichLink, insertDate and insertDropdown; none can go inside an equation, and dates and rich links must sit inside an existing paragraph. Which URIs insertRichLink accepts is not stated in the reference. [VERIFIED] (request reference, acc.)
- **Named ranges.** Names are 1–256 UTF-16 units and need not be unique. replaceNamedRangeContent replaces only the first range. [VERIFIED] (request reference)
- **Revision control.** `requiredRevisionId` makes the write fail with 400 if the doc changed since the read. `targetRevisionId` makes the server apply the write on top of collaborators' changes ("The Docs server is responsible for merging the content"). It only works against recent revisions: "usually … valid … for several minutes after it's read", shorter for busy docs, and 400 if "too far behind". A batchUpdate is atomic: one invalid request fails the whole batch. [VERIFIED] (batchUpdate reference, acc.; https://developers.google.com/workspace/docs/api/how-tos/best-practices, updated 2026-09-03)
- **Images.** insertInlineImage takes images under 50 MB and up to 25 MP, in PNG, JPEG or GIF. The URI must be public and at most 2 kB. Images can't go in a footnote or equation. [VERIFIED] (request reference)
- **Footnotes, headers, tables, styles.** Covered by the requests above. Some limits: table cell borders can't be transparent; paragraph borders can't be partially updated; dropdown option styles are limited to foreground and background colour. [VERIFIED] (documents reference, acc.)
- **Quotas.** Per project: 3,000 reads and 600 writes per minute. Per user per project: 300 reads and 60 writes per minute. Over quota you get 429 and should back off exponentially. Overage charges are planned for later in 2026. [VERIFIED] (https://developers.google.com/workspace/docs/api/limits, updated 2026-09-03)

## 3. Comments

- **Drive API anchors on Docs files.** "Editor apps … treat these comments as unanchored comments." The anchor is stored but treated as opaque. For anchored comments on these file types, Google says to use the Docs, Sheets or Slides APIs. [VERIFIED] (https://developers.google.com/workspace/drive/api/guides/manage-comments, updated 2026-09-10)
- **Long-standing tracker issue.** The "Drive anchor ignored by Docs" behaviour is tracked as issue 292610078 (since 2016) and 491884714. [INFERRED] (via third-party references found in search; issuetracker not loadable)
- **Anchored comments now go through the Docs API.** `insertComment{range, content, assigneeEmailAddress}`. Both content and assignee are limited to 2,048 UTF-8 units. [VERIFIED] (request reference; suggestions how-to, updated 2026-09-30)
- **Drive Comment fields.** `anchor`, `quotedFileContent{mimeType,value}`, `resolved` (output only), `htmlContent`, `content`, `mentionedEmailAddresses` (output only) and `assigneeEmailAddress` (output only). So through Drive, assignment and mentions are read-only. [VERIFIED] (https://developers.google.com/workspace/drive/api/reference/rest/v3/comments, updated 2025-11-06)
- **Reading the quoted text.** It's readable through the Drive API's `quotedFileContent.value`, and through the Docs API as `CommentThread.plainTextQuote` plus `commentAnchors` per tab. [VERIFIED] (Drive comments reference; Docs documents reference, acc.)
- **Resolving.** Drive: post a reply with `action: resolve`. Docs API: `addCommentReply` with `commentAction` RESOLVE or REOPEN, where content is optional. [VERIFIED] (Drive manage-comments; Docs suggestions how-to)
- **Assigning.** Docs API: `assigneeEmailAddress` on insert, `assigneeEmail` on a reply (400 on a suggestion thread). Assigning by typing "+email" in content via the API is not documented. [VERIFIED for the fields; INFERRED for "+email"] (same)
- **Restrictions.** You can't edit the head post of a suggestion thread. You can delete only your own threads or replies, and not replies that carry actions or assignees. Check `commentUpdateState` in the response, because document edits can commit even when the comment save fails. [VERIFIED] (suggestions how-to, updated 2026-09-30)

## 4. Revisions, export, import

- **Revision history is incomplete.** Drive `revisions.list` "might be incomplete for files with a large revision history, including frequently edited Google Docs". The page doesn't define granularity. [VERIFIED] (https://developers.google.com/workspace/drive/api/guides/manage-revisions, updated 2026-09-03)
- **No naming or pinning via the API.** `keepForever` applies only to binary files, and Docs revisions can't be deleted. The Revision resource has no name or label field, so you can't name versions via the API. Docs files get `published`, `publishAuto`, `publishedLink` and `exportLinks` (per-revision export). [VERIFIED] (https://developers.google.com/workspace/drive/api/reference/rest/v3/revisions, updated 2025-07-23)
- **Named versions in the UI.** "Name this version", up to 40 per doc. Named versions aren't merged, and revisions "may occasionally be merged". [VERIFIED] (https://support.google.com/docs/answer/190843, acc.)
- **Export formats for Docs.** docx, odt, rtf, pdf, txt, html, zipped html, epub, and **Markdown (`text/markdown`)**. [VERIFIED] (https://developers.google.com/workspace/drive/api/guides/ref-export-formats, updated 2026-09-03)
- **Import.** Markdown, Word, ODT, HTML, RTF and plain text all convert to Docs. Check `about.importFormats` for the current list. [VERIFIED] (https://developers.google.com/workspace/drive/api/guides/manage-uploads, updated 2026-09-03)
- **Markdown in the UI.** Markdown import and export arrived on 2024-07-16 (Rapid) and 2024-07-31 (Scheduled), with File > Download and File > Open. Copy-as-Markdown and paste-Markdown are opt-in under Tools > Preferences. [VERIFIED] (https://workspaceupdates.googleblog.com/2024/07/import-and-export-markdown-in-google-docs.html, 2024-07-16)

## 5. Apps Script and add-ons

- **Selection and cursor.** `getSelection()`, `getCursor()`, `setSelection()` and `setCursor()` work only "if the script is bound to the document", and only for the user running it; otherwise they return null. Scope is `documents.currentonly` or `documents`. They work on the active tab. [VERIFIED] (https://developers.google.com/apps-script/reference/document/document, acc.)
- **Editor add-ons can read the selection.** They are HTML sidebars and dialogs via HtmlService, and run desktop only. Google's translate quickstart calls `DocumentApp.getActiveDocument().getSelection()` from an editor add-on sidebar. [VERIFIED] (https://developers.google.com/workspace/add-ons/concepts/types, updated 2026-10-09; https://developers.google.com/workspace/add-ons/editors/docs/quickstart/translate, acc.)
- **Workspace add-ons (cards) don't get the selection.** Their Docs event object carries only `docs.id`, `docs.title`, `addonHasFileScopePermission` and `matchedUrl`: no selection or cursor. [VERIFIED] (https://developers.google.com/workspace/add-ons/concepts/event-objects, updated 2026-10-28)
- **No selection-change event in Docs.** Any live mirroring has to poll from the sidebar with `google.script.run`. [INFERRED] (no such trigger documented; the selection-change trigger exists only in Sheets per common knowledge)
- **`google.script.run` latency.** It's an async server round trip, typically hundreds of ms to more than a second per call. Google publishes no figure. [INFERRED]
- **Quotas, same for consumer and Workspace accounts.** 6-minute script runtime, 30 s custom-function runtime, 30 simultaneous executions per user. Trigger runtime is 90 min/day (consumer) and 6 h/day (Workspace). URL Fetch is 20k/day and 100k/day respectively. [VERIFIED] (https://developers.google.com/apps-script/guides/services/quotas, updated 2026-09-03)
- **Distribution.** Marketplace visibility is public or private, and that choice is permanent; private and unlisted is possible. Admins can allow all apps, only allowlisted apps, or none, and can block apps or limit their scopes through API controls. Internal-only apps (org-owned project, Internal consent screen) skip Google's verification. Public apps using sensitive or restricted scopes need verification. [VERIFIED] (https://developers.google.com/workspace/marketplace/enable-configure-sdk, acc.; https://knowledge.workspace.google.com/admin/apps/manage-the-marketplace-app-allowlist-for-your-organization, acc.; https://support.google.com/cloud/answer/13464323, acc.)

## 6. Change notifications and realtime

- **Drive push channels.** `files.watch` sends `update` with `X-Goog-Changed: content` when content changes. Channels last at most 1 day for files and 1 week for changes (default 1 h) and need manual renewal. Google states no latency. [VERIFIED] (https://developers.google.com/workspace/drive/api/guides/push, updated 2026-09-17)
- **Push delay for Docs edits.** Notifications for Docs edits are widely reported to arrive batched, from seconds to minutes. [INFERRED]
- **Workspace Events API (Drive).** Supports file `contentChanged` plus comment and reply events over Pub/Sub. Subscriptions expire in up to 4 h with resource data or 7 days without. Developer Preview (2025-07-07). It carries no content diff or ops. [VERIFIED] (https://developers.google.com/workspace/events/guides/events-drive, updated 2026-09-03; https://developers.google.com/workspace/events/guides, updated 2026-09-03; release notes, acc.)
- **No realtime ops or OT feed.** The Drive Realtime API was announced for retirement 2017-11-28: new projects blocked then, docs read-only 2018-12-11, shut down 2019-01-15. No third-party op feed has replaced it; a native client must poll `documents.get` and diff. [VERIFIED for the retirement; INFERRED for "no replacement"] (https://workspaceupdates.googleblog.com/2017/11/committed-to-storage-apis-retiring.html, 2017-11-28)

## 7. Gemini in Docs (context only)

- **What it can do.** Select text and use Refine (rephrase, shorten, elaborate, bulletize, summarize, change tone). It can make prompt-based edits to the whole doc without a selection, and shows its suggestions in the doc to accept or reject one by one or all at once. It can reference Drive files via @ or Sources. It needs an eligible Workspace or Google AI plan. [VERIFIED] (https://support.google.com/docs/answer/13951448, acc.)

## 8. Offline

- **Offline needs Chrome or Edge.** "You must use the Google Chrome or Microsoft Edge browser", plus the Google Docs Offline extension, and not in incognito. [VERIFIED] (https://support.google.com/docs/answer/6388102, acc.)
- **Safari has no offline Docs.** Safari "doesn't support: Offline access to Gmail, Calendar, Docs, Sheets, Slides". [VERIFIED] (https://knowledge.workspace.google.com/admin/support/troubleshooting/supported-browsers-for-google-workspace, updated 2026-10-26)

## 9. Browser support and embedded sign-in

- **Supported browsers.** Chrome, Firefox, Safari and Edge, in the two most recent versions. Safari "works well" except for offline and Gmail desktop notifications. Virtual or embedded environments "might not support all … functionality". [VERIFIED] (supported-browsers page, updated 2026-10-26)
- **OAuth in embedded webviews.** The OAuth endpoint blocks embedded webviews: WKWebView and UIWebView on iOS and macOS, and Android WebView. They got `disallowed_useragent` from 2021-09-30. The alternatives are the default browser or SFSafariViewController; ASWebAuthenticationSession is standard practice but not named in the post. [VERIFIED] (https://developers.googleblog.com/en/upcoming-security-changes-to-googles-oauth-20-authorization-endpoint-in-embedded-webviews/, 2021-06-29)
- **Plain Google sign-in.** Google Account sign-ins from "all embedded frameworks" were blocked from 2021-01-04 (CEF named). Browsers must not offer automation features or alter network traffic. The help page says sign-in may be stopped for browsers "embedded in a different application" or "controlled through software automation". It names no WKWebView carve-out. [VERIFIED] (https://developers.googleblog.com/guidance-to-developers-affected-by-our-effort-to-block-less-secure-browsers-and-applications/, 2020-08; https://support.google.com/accounts/answer/7675428, acc.)
- **How strictly WKWebView sign-in is enforced in practice.** Enforcement is risk-based and varies by account. It often trips 2FA or passkey flows, and SSO for Workspace accounts goes through the IdP. Expect breakage, not a guaranteed block. [INFERRED]

## 10. What a native editor (B) must rebuild, and what the API can't express

- **Model to rebuild.**
  - StructuralElements: paragraph, table, sectionBreak, tableOfContents.
  - ParagraphElements: textRun, autoText (page numbers), pageBreak, columnBreak, footnoteReference, horizontalRule, equation, inlineObjectElement (images and drawings), person, richLink, dateElement, dropdown.
  - Positioned objects.
  - Named styles, paragraph and text styles, lists (nesting and glyphs), and section styles (columns, margins, first and even-page headers and footers).
  - Headers, footers and footnotes as separate segments.
  - Tabs (a tree), named ranges, bookmarks and heading links (with tabId).
  - Suggestions: per-element `suggestedInsertionIds`, `suggestedDeletionIds` and suggested style changes.
  - Comment threads and anchors.

  [VERIFIED] (https://developers.google.com/workspace/docs/api/reference/rest/v1/documents, acc.)
- **No requests for equations, drawings or most chips.** No request inserts or edits an equation, a drawing (embedded drawings return only partial details: "extensive details are not supported"), a positioned object (only delete), a table of contents, or chips beyond person, rich link, date and dropdown (place, finance, file-as-chip variants and similar). [VERIFIED for the request list and the drawing note; INFERRED for the chip types that aren't listed]
- **No cursor or presence API.** There's no way to see other editors' cursors or selections, or to publish your own. The only "selection" API is Apps Script for the running user (§5). [INFERRED] (no such endpoint in the Docs or Drive references)
- **No op stream.** The client must re-fetch the whole document (or a field mask) and reconcile index-based edits. `targetRevisionId` lets the server merge only within a window of minutes. [VERIFIED for the window; INFERRED for the design consequence] (§2)
- **Suggest-mode gaps.** Can't suggest tab, named-range, header/footer deletion, column-width or document-format changes. [VERIFIED] (§2)
- **Revision gaps.** Revisions can't be named or pinned, and the history may be incomplete. [VERIFIED] (§4)

## 11. What a native editor would have to re-implement (Phase 1A's summary)

Approach B means drawing and editing a Doc in Duo, and syncing it through the API. The list in §10 is the document model. On top of that model, B must also rebuild:
- **The editor:** layout and pagination (or pageless), fonts as Docs draws them, lists and their glyphs, tables, images, positioned objects, headers and footers, footnotes, the table of contents, equations and drawings (read-only at best), and every chip type (most are read-only or text only).
- **Suggestions and comments:** drawing them inline and in the margin, and accepting or rejecting them. DL-237's margin and inline marks are a start, but they are Duo's design, not Docs'.
- **Sync:** poll or listen, re-fetch, diff and rebase your own pending edits onto a moving document. Index-based writes are only safe within `targetRevisionId`'s window of a few minutes. A batch is atomic. The API has no op feed, so a remote keystroke reaches B seconds to minutes later, not live.
- **Presence:** nothing. B can't show who is here or where their cursors are, and can't show its own user to them.
- **What the API can't do:** name versions, edit equations or drawings, insert most chip types, suggest tab, named-range or header/footer changes, show Gemini, the Explore panel, voice typing, building blocks, e-signatures, pageless mode controls and the many small UI features Docs adds every month.
- **Quota:** 60 writes and 300 reads per user per minute. A live-feeling editor polling every 2 s spends 30 reads a minute on one doc, before any other agent reads.

My verdict: B can't meet J-N1 to J-N4 (live co-editing) or J-A1 (pixel fidelity) at any reasonable cost [INFERRED from the above]. B's real strengths are agent reads and writes, and the API now gives those to approach A as well.
