# Comparing the approaches: Google Docs in Duo's browser, a Duo-native surface, or a hybrid

Phase 1A of [Google Docs in Duo](../../../tasks/google-docs-in-duo.md), 2026-10-29. This frames the choice at Checkpoint 2. Each cell says what's known (with its source doc) and what Phase 2 must measure (**→ T-nn**, from [test-plan.md](test-plan.md)).

## The approaches

- **(A) Docs live in Duo's browser, plus in-page agent tooling.** People use Google's own editor in a Duo tab. Claude reads and acts through that same tab, with new duo2 verbs:
  - a page-world Docs read (text, links, selection)
  - real keys and drags
  - Suggesting mode by shortcut
  - comments through the UI

  No OAuth app is involved.
- **(B) A Duo-native surface synced through the Docs and Drive APIs.** Duo draws and edits the Doc itself (like its Markdown editor, or the Word viewer of DL-233) and syncs by API.
- **(C) Hybrid: the browser for people, the API for Claude's durable changes, the page for live context.**
  - People use Google's editor in a Duo tab, as in A.
  - Claude reads the live tab (the selection, what's on screen, the text) through the page.
  - Claude **writes** through the Docs API: `SUGGEST`-mode `batchUpdate`, `insertComment`, `addCommentReply`.
  - Claude reads structure from `documents.get`, and Duo maps between the page's offsets and the API's indexes.
  - Variant **C′** swaps the page reads for an Apps Script editor add-on that reports the selection: sanctioned, but polled and installed per user.

## The criteria

| Criterion | (A) Browser + page tooling | (B) Native + API | (C) Browser for people, API for Claude's writes |
|---|---|---|---|
| **Rendering fidelity** (J-A1, J-K1) | Google's own renderer on WebKit. It looks like Chrome's (`img/webkit-1200.png`), and Safari is a supported browser. Duo's narrow pane needs the outline collapsed and zoom → **T-01** (capture vs Chrome at 460, 700 and 900 pt) | Duo's re-implementation. DL-233's Word viewer shows how far "Google's look" takes work, and chips, drawings, equations and pageless mode stay approximate. **Poor by construction** | As A |
| **Feature coverage** (all person jobs) | Everything Docs offers in Safari, offline excepted (Chrome or Edge only) → **T-12** (feature sweep) | Only what the API can express (google-docs-surface §10–11). No version naming, no presence, no Gemini, most chips read-only | As A for people. Claude gets the API's set plus what the page offers |
| **Remote collaboration latency** (J-N1–N4) | Docs' own channel: live cursors, presence (seen signed out: "7 total viewers"), OT. Should equal Safari → **T-08** (keystroke-to-screen, Duo vs Chrome, two accounts) | **No op feed.** Remote edits arrive by poll or Drive/Workspace Events, seconds to minutes late. No cursors or presence. **Fails J-N1–N3** | As A |
| **Claude's read: granularity and latency** (J-A4–A6) | Page hook: the whole text plus link ranges in under 1 ms, live as people type, with nothing missing (F-412). Structure (headings, tables, chips, suggestions, comments) unknown → **T-02, T-03**. `read` today gets none of it (F-411) | `documents.get`: a full structured tree with suggestions and comments, by request. Quota is 300 reads per user per minute. Lags the screen by seconds → **T-05** | Both: the page for what's on screen *now*, the API for structure and threads. Needs offset↔index mapping → **T-04** |
| **Selection awareness** (J-B2, J-B3) | `getSelection()` offsets, read in under 1 ms, following real drags and keys (F-412, F-413). Needs a page-world verb and a watcher → **T-02** (lag from mouse-up to Claude) | Duo owns the editor, so the selection is free | Page hook as A. C′: Apps Script `getSelection()` by polling, hundreds of ms per call → **T-11** |
| **Claude's edits as suggestions** (J-E1–E6) | Switch the tab to Suggesting (⌘⌥⇧X), then `setSelection` plus paste or typing. It's the person's own suggestion, made in their session and **credited to them**. It also moves their selection and caret while they work → **T-06** | `SUGGEST` mode, on Duo's copy | **`SUGGEST` mode on the real Doc (GA 2026-09-30):** a real Docs suggestion that every collaborator sees, merged against `targetRevisionId`, never touching the person's caret. Credited to the OAuth user (Geoff), not "Claude" (landscape Q2) → **T-05** |
| **Comments and @claude** (J-G3–G4, J-H1–H4) | Read: the page hook may carry comment ranges (→ T-03); otherwise the visible margin. Write: ⌘⌥M through the UI. Noticing an @claude: watch the page → **T-09** | Drive or Docs API comments, drawn by Duo | `insertComment` with a range, plus `addCommentReply` (GA). Noticing: Workspace Events comment events (developer preview) or polling, plus the open tab → **T-09** |
| **Auth and security** | The person signs in to Google **in Duo's web view**. Google's policy says embedded browsers "may" be blocked, and OAuth inside a WKWebView is refused (surface §9) → **T-00, the first test**. The real Duo's cookies are in one store shared by every Duo on the Mac (C-32); test instances keep none. Page-world script is new for Duo, whose isolated world was a deliberate line (BrowserTabs.swift:731) | An OAuth client for Duo. The `documents` scope is sensitive, so a fleet-wide client needs Google's verification, while `drive.file` with the Picker does not. Tokens sign in through the system browser, never a web view, and live in the Keychain | Both: the person's web sign-in **and** an OAuth grant |
| **Fleet constraints** (the work Mac: pinned Claude Code 2.1.284, no scripts, management) | Works with Claude Code as is (duo2 verbs only). A managed Workspace account may require Chrome with endpoint verification (context-aware access) and block other browsers → **Q-311**. Nothing to install on Google's side | Needs the work account's admin to allow Duo's OAuth app (or allow unverified apps). Admins can block or limit scopes | Needs both the sign-in (A) and the admin's OK for the OAuth app (B). If the app is blocked, C falls back to A |
| **Policy and fragility** | Relies on a private, undocumented hook. It's stable enough that Chromium's own Reading Mode uses its sibling, but Google can change it any day. It isn't impersonation (no id is borrowed, F-412), but it's still "undocumented internals" → **Q-309** | All documented, versioned APIs | Writes are on documented APIs; only live reads touch the page, and C′ avoids even that |
| **Build cost** | Small to medium: a page-world `browser docs` verb (read, selection, set selection), `browser key`/`type`, drag, inner scroll, export downloads, a per-folder cookie store, and a chord carve-out. Plus a Send Selection for Docs tabs | **Very large**: a Docs-class editor, sync and conflict handling, and a renderer that keeps up with Google | Medium: A's read verbs, plus an OAuth client, an API client (or Google's Docs MCP server in a Claude session), offset↔index mapping, and Duo's identity and attribution UX |
| **Maintenance cost** | Watch for Docs changes to the hook and the DOM; a nightly probe (`probes/`) catches breakage | Constant: every Docs feature is a gap | API is stable; page reads as A |

## Where it leans now (before Phase 2)

- **B is out on Geoff's own terms.** It can't meet "low latency synchronous collaboration with other people" or "nearly perfect rendering" (§10–11 of the surface doc). Its one advantage, writing suggestions and comments, the API now gives to A and C as well.
- **The choice is A versus C,** and it turns on four tests:
  1. **T-00:** can Geoff sign in to Google in Duo's web view, and stay signed in? If not, A and C both need another way in, and B's case comes back.
  2. **T-02 and T-03:** does the page hook work signed in, in an editable Doc, and does it carry suggestions and comments?
  3. **T-05 and T-06:** API suggestions versus in-page suggestions, on attribution, latency and not disturbing the person.
  4. **Q-309:** Geoff's call on using an undocumented page hook at all.
- **My working recommendation is C.**
  - People use Docs itself in Duo's tab.
  - Claude reads the live tab for selection and context.
  - Claude writes suggestions and comments through the API.
  - The page-hook dependency stays read-only and small, so if Google closes it, Duo loses selection awareness (falling back to C′'s add-on, or copy-to-Claude), not editing.
