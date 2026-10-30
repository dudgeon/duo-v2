# Duo's browser and duo2 with a Google Doc, as of 2026-10-29

Phase 1A of [Google Docs in Duo](../../../tasks/google-docs-in-duo.md). The code read is `main` at 6d9d1e8f. The probes ran on a **public** Doc, signed out, in two places:
- **An isolated Duo** built from that commit: its own `DUO_SUPPORT_DIR` (`/tmp/gdf/sup`), a scratch `CLAUDE_CONFIG_DIR`, `DUO_SOCKET` and `DUO_TOKEN` from its own `endpoint.json`, `docs.google.com` on *its* allow list only. Launched with `open -g` and never shown.
- **A bare WKWebView probe** (`probes/main.swift`): configured as Duo's browser tab is (non-persistent store, Safari's user-agent token), in an off-screen window that never activates. It runs script in the page's own world, which duo2 can't.

The Doc was Chromium's "Features to Update for Out-of-Process iframes" (`1dCR2aEoBJj_Yqcs6GuM7lUPr0gag77L5OSgDa8bebsI`): 5,104 characters, headings, nested lists, 22 links, "anyone with the link can view". Raw output: `probes/duo2-verbs.out.txt`. No Google account was used anywhere.

Records: F-411 (duo2 verbs on a Doc), F-412 (the annotated-text hook), F-413 (real input events reach the editor).

## 1. What the code has

| Area | What's there | Where |
|---|---|---|
| **Web view** | One `BrowserWebView` (a `DuoWebView`, a WKWebView subclass) per tab, made in `WebTab.init`. Popups use the configuration WebKit passes, so they keep their opener (F-119). | `Sources/DuoKit/Browser/BrowserTabs.swift:138` |
| **Allow list** (DL-3) | `allowed-sites.txt` in the support folder. Each line is a host, and a host also covers its subdomains. It's checked on main-frame navigations only; frames inside an allowed page load freely. The shipped default is empty: local files (inside the project's folders, DL-178) and localhost only. | `AllowedSites`, `BrowserTabs.swift:8-63` |
| **Adding a host for one user** (DL-178) | Three ways in, and each writes only this Mac's support-folder file, never a shipped default: <br>• `duo2 browser allow <host>` asks on a Duo sheet (`DUO_AUTOCONFIRM=1` answers for scripts)<br>• the blocked tab's **Allow** button<br>• the Settings list's **Edit…**<br>So adding `google.com` or `docs.google.com` for Geoff's Duo only is a line in *his* file. | `AllowedSites.add`, `BrowserTabs.swift:44` |
| **Cookies and site data** | Two cases:<br>• **The real Duo:** `WKWebsiteDataStore.default()`. It belongs to the **bundle id**, not the support folder (C-32), so every `com.dudgeon.duo` Duo on the Mac shares one cookie jar, which is separate from Safari's and Chrome's.<br>• **An isolated Duo** (any `DUO_SUPPORT_DIR` but the real one, including every work-tree build): `.nonPersistent()`, which is empty at launch and gone at quit.<br>So **no test instance can stay signed in today.** `WKWebsiteDataStore(forIdentifier:)` (macOS 14+) would give each support folder its own persistent store; nothing uses it yet. | `BrowserTabs.swift:142-146` |
| **User agent** | Duo adds `Version/<Safari's major.minor> Safari/605.1.15`, so Google treats the tab as Safari (F-117). Without it, Docs says the browser is unsupported. | `WebUserAgent.swift` |
| **Running script** | `callAsyncJavaScript` in **`.defaultClient`**, Duo's isolated world. Pages share the DOM with it but not their JavaScript objects. The comment says it outright: "No arbitrary script: read, click, fill, wait and screenshot are the whole surface." The only page-world script is the `window.print` shim. | `BrowserTabs.swift:731-736` |
| **Mouse** (DL-124) | `click` sends `mouseMoved`, `mouseDown` and then (50 ms later) `mouseUp` straight to the web view at the element's centre. The page sees these as trusted events, even when the window isn't key (F-119). If the tab isn't in a window or the centre isn't in view, it falls back to `element.click()`. No drag, no double-click, no click at a point. | `BrowserTabs.swift:756-797` |
| **Keyboard** | No key verb. `fill` sets `.value` or `textContent` and fires `input`/`change`, which doesn't fit a canvas editor. `BrowserWebView.performKeyEquivalent` takes only ⌘+ ⌘- ⌘0. | `BrowserTabs.swift:816`, `:436` |
| **Duo's chords over a page** | The menu is one table (DL-34). Chords that are always on, or on whenever a browser tab is showing, would compete with Docs:<br>• **⇧⌘H** is Duo's Home and Docs' find and replace<br>• **⌥⌘0** is Duo's collapse right pane and Docs' Normal text<br>• **⌥⌘← →** move between Duo's panes<br>• **⌘P** is Duo's WebKit print, while Docs has its own print<br>• **⌘O** is Duo's open-file<br>• **⌘W**, **⌘T**, **⇧⌘A**, **⌘D** are Duo's when enabled<br>Duo's ⌥⌘M, ⇧⌘E, ⌘B, ⌘I, ⌘K and ⇧⌘X are only on for the Markdown editor, so they reach Docs. Which side wins (the page or the menu) is a Phase 2 test. | `Sources/DuoKit/Navigation/Commands.swift:128-200` |
| **Clipboard** | Plain WKWebView: ⌘C, ⌘X and ⌘V go to the page. No duo2 verb reads or writes the page's clipboard events. | — |
| **Accessibility tree** (DL-7) | Nothing in Duo reads it. WKWebView exposes the page to macOS accessibility, but a Doc's text isn't in the DOM unless Docs' screen-reader or braille mode is on (§3). Another process reading it needs the Accessibility (TCC) permission; Duo reading its own web view in-process may not, but that's untested. | — |
| **Screenshots** | `screenshot` takes WebKit's snapshot of the visible page. `--full-page` scrolls the *document* and joins the pieces. Captures work while the window is covered (F-120). | `WebTab.screenshot*` |
| **Selection to Claude** | Send to Claude (⌘D, LR-44) and the element picker cover Markdown docs and local HTML. For a browser tab the picker sends an element (`SendFormat.Element`), not a text selection, and nothing reads a canvas selection. | `SendFormat.swift`, `HTMLPicker` |
| **Downloads, uploads, print, popups, zoom** (DL-124) | All built (F-118, F-119). Downloads go to ~/Downloads, or to the support folder for an isolated Duo. | `BrowserBasics.swift` |

## 2. Every `duo2 browser` verb on the Doc (isolated Duo)

Timings are wall-clock for the duo2 command, socket round trip included.

| Verb | Result on the Doc | ms | What it means |
|---|---|---|---|
| `browser open <doc>` | Opened; the tab's URL picks up `?tab=t.0#heading=…` | 50 | Docs loads in Duo with no "unsupported browser" banner (F-117 holds) |
| `browser wait .kix-canvas-tile-content` | There after 0.87 s | 869 | Canvas tiles are a usable "doc is drawn" signal |
| `browser tabs` | id, project, title, address | 45 | Fine |
| `browser read` | **Only Docs' chrome:** title, "Request edit access", "Sign in", the tab list, the *outline's* headings ("In progress:", "Not yet started:") and the screen-reader banner. **None of the body text.** | 57 | A Doc's text isn't in the DOM; `read` can't read a Doc |
| `browser read .kix-canvas-tile-content` | Empty | 47 | The tiles are canvases |
| `browser read .navigation-widget-content` | The outline (tab title + headings) | 55 | Headings are the only document text in the DOM |
| `browser screenshot` | A PNG of the pane (918×1578 px at 2×, a 459 pt pane). Docs' own Chrome promo and its outline panel cover most of it; the page sits off to the right (`img/duo-pane-459.png`) | 83 | At Duo's pane width Docs needs its outline collapsed (and maybe zoom) to show the page |
| `browser screenshot --full-page` | Same picture as the visible one | 92 | Docs scrolls an inner element, not the document, so full-page sees one screen |
| `browser scroll down` / `2000` / `top` | "Scrolled to 0 of 789 px" every time | 37–39 | Scrolling the document does nothing; a Doc scrolls `.kix-appview-editor` |
| `browser click .kix-canvas-tile-content` | "Clicked <div>": a real click at the tile's centre | 39 | Real clicks land on the canvas |
| `browser click #docs-file-menu` | Clicked "File" | 98 | Menus respond to real clicks |
| `browser read [role=menu]` | Matched the **viewers list**: "7 total viewers: Anonymous Camel, … Join chat" | 73 | Presence works signed out; other people's live presence is in the DOM as text |
| `browser click .docs-texteventtarget-iframe` | Fell back to synthetic: "the page isn't on screen" | 64 | Docs parks its keyboard iframe off screen, so a centre click can't reach it |
| `browser fill .docs-texteventtarget-iframe hello` | "nothing matches" | 112 | `fill` can't reach into the iframe's document; it's no way to type into a Doc |
| `browser zoom 125` / `reset` | Zoomed, remembered for docs.google.com | 49–57 | Works; Docs redraws its canvas at the new size |
| `browser print --pdf` | A 4-page PDF with **8 images and no fonts**, so no text layer | 2,059 | WebKit prints the canvas as pictures; Docs' own File › Print or Download PDF is the one to use |
| `browser go …/export?format=md` | Navigated, then nothing downloaded | 55 | The export redirects to `doc-…-docstext.googleusercontent.com`, which isn't allowed. The tab blocks the redirect, and `back` then failed with "isn't on the allow list". Allowing `googleusercontent.com` too (or handing exports to the downloader) would fix it |
| `browser downloads` | "No downloads since Duo started" | 32 | As above |
| `browser go …/mobilebasic` | The "basic" HTML view: `read` gets the **whole text** | 27 | A read-only, HTML route to a Doc's text through the same session; no comments, suggestions or selection |
| `browser go https://accounts.google.com/` | Blocked: not on the allow list | 35 | Signing in needs `accounts.google.com` allowed too |
| `browser allow accounts.google.com` | Allowed (autoconfirmed in the test instance) | 42 | DL-178's path works per user |
| `browser upload`, `back`, `forward`, `close` | Not meaningful on a view-only Doc. `back` was tried and failed as above | — | Phase 2, in an editable Doc (Insert › Image › Upload) |

## 3. Inside the page: the bare WebKit probe

These run script in the page's own world (`WKContentWorld.page`), which no duo2 verb does.

- **Docs draws on canvas in WebKit.** The page has 3 `<canvas>`, 6 `.kix-canvas-tile-content` tiles and 2 pages. There are no `.kix-lineview` or `.kix-paragraphrenderer` elements (the pre-2021 HTML render), and no SVG `rect[aria-label]` overlay (the "annotated canvas", which needs `_docs_annotate_canvas_by_ext`). `document.body.innerText` is 381 characters, all chrome. The native `window.getSelection()` is empty. The rendering looks like Chrome's: see `img/webkit-1200.png`.
- **The keyboard goes to a hidden iframe.** `.docs-texteventtarget-iframe` (classes `docs-offscreen-z-index docs-texteventtarget-iframe-negative-top`) holds a `contenteditable` body. After a click on the canvas it is `document.activeElement`.
- **Docs exposes its annotated text to any caller in WebKit (F-412).**
  - Docs' own boot script defines `_docs_annotate_getAnnotatedText = function(id) {return KX_kixApp.getAnnotatedText(id);}` in every Doc. It's in the HTML served to a plain `curl` too.
  - In the page world, `await _docs_annotate_getAnnotatedText('duo-probe')` returned an object with `getText()`, `getAnnotations()`, `getSelection()` and `setSelection(start, end)`. It did so for a made-up id and for an empty string, **without** setting `_docs_annotate_canvas_by_ext`, signed out.
  - **`getText()`:** the whole document, 5,104 characters (it starts with `\u0003` at offset 0 and ends at the last line), in under 1 ms, including parts never scrolled into view.
  - **`getAnnotations()`:** `{link: [{range: {start, end}, value: url}, …]}`, all 22 links. This Doc had no other kinds; suggestions, comments and chips are Phase 2's to look for.
  - **`getSelection()`:** `[{start, end}]` in the same offsets. The caret alone is `{start: 1, end: 1}`.
  - **`setSelection(381, 396)`:** Docs drew a real selection over "Session History" (`img/setselection.png`), and `getSelection()` then returned it.
  - **Timing:** the hook is there about 450 ms after navigation starts.
  - It's undefined in Duo's isolated world (`.defaultClient`), so duo2 would need a page-world call.
- **Real input events reach the editor (F-413).** These NSEvents were sent straight to the web view, as `duo2 browser click` does, in an app that never activated and a window that was never key:
  - A mouse **drag** across "Session History" selected it, and `getSelection()` returned 381–396.
  - **Shift+→ three times, then Shift+↓**, extended the selection to 381–419. So keys reach Docs' editor too.
  - The probe had to switch off WebKit's window-occlusion detection (`_setWindowOcclusionDetectionEnabled:`) for its off-screen window; Duo's own hidden test window already draws (F-227).
- **Other routes to the text, signed out:**
  - `…/export?format=md` (6.6 KB, links kept as Markdown), `txt`, `html` and `docx` all answered 200 to `curl` for this public Doc.
  - `…/mobilebasic` returned the whole text as HTML.
  - The boot HTML carries `DOCS_modelChunk` JSON (the model), which is private and the most brittle route of all.

## 4. What this means

1. **Rendering:** Docs in Duo is WebKit's Docs: the same engine and look as Safari, which Google supports (offline aside). The pane is the problem, not the engine. At 459 pt, Docs' outline panel and its "Use Chrome" promo cover the page.
2. **duo2 today reads nothing of a Doc's body.** `read`, `scroll`, `fill` and `screenshot --full-page` all assume the text is in the DOM and the document scrolls. A Doc breaks every one of those assumptions.
3. **The live session is reachable.** In WebKit, Docs gives a page-world caller its text, links, the user's selection (as offsets) and a way to set the selection, and real mouse and key events drive it. That covers J-B2, J-B3 and J-B6 and most of J-A6, at in-page speed, in the user's own session, with no OAuth. The catches are policy and fragility: it's private and undocumented (comparison-frame.md, Q-309).
4. **Missing verbs:**
   - a page-world Docs read (text, selection, annotations)
   - a key and text verb (keys, chords, typing)
   - drag and click-at-point
   - scrolling the Doc's own scroller
   - an export download
   - a cookie store per support folder, for a test instance that stays signed in
   - room on Docs' side for Duo's chords
5. **DL-7's accessibility-tree read** has nothing to read unless Docs' screen-reader or braille mode is on. The annotated-text hook gives more, faster, without that mode. Phase 2 compares the two (T-07).
