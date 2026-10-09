# Duo v2 — Stack recommendation

Status: proposed · 2026-10-03 · **Amended by `decisions.md` (DL-3, DL-8, DL-14, DL-15, DL-29, DL-30); where they differ, the decision log wins. Build findings: `../plan/findings.md`.** · Inputs: `docs/research/stack-terminal-and-claude-hosting.md`, `docs/research/stack-editor-and-webview.md`, `docs/research/claude-code-session-path-binding.md`, and Geoff's answers (below).

## Constraints from Geoff

- Fast, memory-light, native macOS feel. Idle budget **< 300 MB** for Duo itself (the `claude` processes are outside that; each is ~120–230 MB).
- **macOS 26+**, direct download, Developer ID + notarized. Not the App Store.
- **100% built by Claude Code**, Geoff reviewing. Conventional, well-documented choices win.
- Console: **real Claude Code TUI first**, architecture open to a native conversation view later.
- **Every session keeps a live terminal**, hidden when not focused.
- Embedded browser must: view local HTML and localhost; hold logged-in sessions on third-party sites; let the user **select an element and hand it (DOM, selector, screenshot) to the focused session**; let the **agent drive the page** (navigate, click, type, read).
- Editor: edit the rendered markdown, no split view. Native preferred; a web-based editor is acceptable long-term only if it has native menus/shortcuts, macOS spellcheck/dictation/Writing Tools, native-looking selection/caret/scroll/find, and **byte-faithful saves**.

## Decisions

| # | Area | Decision | Fallback |
|---|---|---|---|
| 1 | Language / UI | **Swift 6, SwiftUI app with AppKit where SwiftUI is weak** (terminal, web views, split-view resizing, menus, text finder). | — |
| 2 | Project format | **Decided (DL-30, ADR-0001): a Swift package built with the Command Line Tools; no Xcode required.** Superseded proposal: Xcode project generated from `project.yml` with XcodeGen. | — |
| 3 | Terminal emulator | **SwiftTerm** (MIT, Metal renderer, DEC 2026 sync output, OSC 8/52, SGR mouse, bracketed paste after Sept 2026 — pin a commit on the 2.0 line), wrapped behind a `TerminalHost` protocol. | **libghostty** via `Lakr233/libghostty-spm` behind the same protocol |
| 4 | Claude Code hosting | **Spawn the user's own `claude` in a PTY per session** (`forkpty`), always with `--session-id <duo-uuid>`; reopen with `--resume <uuid>`. Never `-c`, never the picker. | Headless `stream-json` for a later native "review pane", not for v1 |
| 5 | Session state | **Hooks + `claude agents --json`.** Per-session hooks injected with `--settings` post events to Duo's local HTTP endpoint; `claude agents --json` polled as the authoritative state (busy/waiting/idle, `waitingFor`). | Parse terminal output (avoid) |
| 6 | Agent ↔ app tools | **Decided (DL-15): `duo` CLI over loopback TCP, on PATH inside Duo's PTYs only.** Superseded proposal: **Duo runs an MCP server inside the app (HTTP transport, localhost)**, passed to each session via `--mcp-config`. Tools: `browser.*` (get_selected_element, read_page, navigate, click, type, screenshot), `tasks.*`, `project.*`, `sessions.*`. This is how the agent "sees" a selected element and drives the page. | stdio MCP shim that proxies to the app |
| 7 | Browser | **WKWebView** (AppKit, `NSViewRepresentable`). One shared `WKProcessPool`; persistent `WKWebsiteDataStore` for logged-in sites (+ a non-persistent profile for private tabs); `WKURLSchemeHandler` (`duo://`) for local folders; `isInspectable` for Web Inspector; `WKDownload`; `createPDF`. **Element inspector = injected `WKUserScript`** (hover highlight, click to select, computes selector/outerHTML/computed styles/rect) + `takeSnapshot(with:)` for the element screenshot. **Page driving = `callAsyncJavaScript`** + an injected accessibility-tree script. | SwiftUI `WebView`/`WebPage` (macOS 26) if downloads/print gaps close |
| 8 | Markdown editor | **CodeMirror 6 "live preview" in one dedicated WKWebView.** Markdown text is the single source of truth; headings, emphasis, links, images, task lists, code and tables render in place via decorations/widgets; syntax reveals near the caret. **No AST round-trip, so saves are byte-faithful by construction.** Reference implementation: `kenforthewin/atomic-editor` (MIT). | — (the native TextKit 2 successor and its hedge spike are dropped, DL-167: revisit only when a native rendered-markdown library with tables, virtualisation and a maintainer exists) |
| 9 | Editor ↔ native | Native `NSMenu` items → `callAsyncJavaScript` commands with `validateMenuItem`; macOS spellcheck/dictation/Writing Tools via the editable DOM (verify in spike); find via `WKWebView.find(_:configuration:)` or a natively-styled CM6 panel; selection/caret colours from system appearance. | — |
| 10 | Files & state | **Files are the source of truth** (`PROJECT.md`, `tasks/*.md` with frontmatter, `.duo/project.json`, `.duo/sessions.json`). FSEvents watcher with rename-aware debounce; echo suppression by SHA-256 of bytes written. A **derived, rebuildable SQLite index** (GRDB) in Application Support for search and cross-project queries. | — |
| 11 | Claude config isolation | **Decided (DL-14): shared `~/.claude`**, relocate on move the way `/cd` does. Original text: **Decide in a spike**: Duo-managed `CLAUDE_CONFIG_DIR` + `CLAUDE_CODE_PROJECT_DIR_NAME=<projectId>` makes folder moves free but implies a separate login; the alternative is the user's `~/.claude` with Duo's own session index and a migrate-on-move routine. | — |
| 12 | Sandbox | **App Sandbox off.** Child PTYs inherit the sandbox and no entitlement exists; the app also reads `~/.claude`. Hardened Runtime + notarization only. | — |

## Why these, briefly

**Terminal over headless.** The TUI is what users already know; every Claude Code feature works on day one (plan mode, permissions, `/resume`, Agent View, Remote Control, Desktop handoff); the headless control protocol's wire format is not officially documented; and the SDK terms forbid offering claude.ai login or "Claude Code" branding in third-party chat surfaces. Headless stays available for a later native review pane. Memory is dominated by the `claude` process under every approach, so hosting choice doesn't move the budget much.

**SwiftTerm over libghostty.** SwiftTerm is a stable, tagged, MIT Swift package with the features Claude Code's fullscreen renderer needs. libghostty's full renderer is explicitly "not yet stabilized for general-purpose embedding", has no tagged version, and the project is moving off GitHub. One real risk on SwiftTerm: an open issue where several streaming agent TUIs on 1.x burned 75–82% of a core; the maintainer says 2.0 is 10–50× faster. That is Duo's exact workload, so it's the first spike, and the `TerminalHost` protocol keeps libghostty one swap away.

**WKWebView over CEF or Tauri.** Everything on the browser list is doable in WKWebView: logged-in sites (persistent data store, OAuth popups via `createWebViewWith`), local files (scheme handler), inspection and driving (injected scripts). CEF adds 150–250 MB and Chromium's memory profile; Tauri is WKWebView underneath plus a Rust toolchain. The one real loss is the Chrome DevTools Protocol, so the legacy `cdp-bridge` approach must be rebuilt on `evaluateJavaScript`; the inspector overlay is a user script we own anyway.

**CM6 live preview over ProseMirror/TipTap.** The legacy app spent roughly a year on TipTap-to-markdown round-trip bugs (escaped HTML comments, rewritten autolinks, shattered table cells, a six-times-grown normalization regex). Document-model editors normalize untouched text on every save; that is structural, not a bug to fix. With CM6 the markdown *is* the buffer, so "byte-faithful saves" and "Claude's edits merge in without clobbering my cursor" both fall out: an external change becomes a CM6 `ChangeSet`, and selection, scroll and folds map across automatically.

**Why not a native editor.** No mature native rendered-markdown editor with tables and task lists exists; the only candidate (`swift-markdown-engine`) is pre-1.0, single-author. A from-scratch TextKit 2 editor is 3–5 engineer-months, with tables alone 4–8 weeks and known TextKit 2 instability, and the size spike failed (F-39). DL-167 (Geoff, 2026-10-09) keeps CodeMirror 6 and drops the native successor and its hedge spike from the plan; the trigger to revisit is a native rendered-markdown library with tables, virtualisation and a maintainer, not a date.

**All sessions live.** SwiftTerm's buffer per session is ~10–30 MB; hidden views stop drawing. Six sessions ≈ 100–180 MB inside Duo, under the 300 MB budget with one editor webview and a couple of browser tabs. The `claude` processes themselves (6 × ~120–230 MB) are the real cost and are the same under any design.

## Expected memory (to be measured in spikes)

| Component | Estimate |
|---|---|
| App shell (SwiftUI/AppKit, index, watchers) | 60–80 MB |
| Editor WKWebView (one instance, documents swap in) | 40–60 MB |
| Browser tabs | 30–200 MB each, WebKit suspends past its process limit |
| Terminal per session (SwiftTerm buffer + scrollback) | 10–30 MB |
| **Duo idle, 6 sessions, 1 editor, 1 tab** | **~200–280 MB** |
| `claude` processes (not Duo's) | ~120–230 MB each |

## Architecture sketch

```
DuoApp (SwiftUI lifecycle, menus, windows)
├─ DuoCore        models · file store (PROJECT.md, tasks/*.md, .duo/) · FSEvents · SQLite index (GRDB)
├─ DuoClaude      PTY spawn · session registry · hooks endpoint · `claude agents --json` poller · config-dir strategy
├─ DuoTerminal    TerminalHost protocol · SwiftTerm impl · (libghostty impl)
├─ DuoWeb         WKWebView host · profiles · scheme handler · inspector user script · page-driver script
├─ DuoEditor      WKWebView host · CM6 live-preview bundle (esbuild, checked-in dist) · native command bridge · external-change merge
└─ DuoMCP         MCP server (official Swift SDK, HTTP transport on localhost) exposing browser/tasks/project/session tools
```

Three-pane window: `NavigationSplitView` (sidebar = projects/tasks, content = console, detail = view/edit) or an AppKit `NSSplitViewController` if SwiftUI's column sizing fights us.

## Spikes, in order

Each is a throwaway Xcode project or a branch; each has a pass/fail written down before it starts.

1. **SwiftTerm soak (1 day).** Run the real `claude` TUI in SwiftTerm for 30 min on the 2.0 line: classic and fullscreen renderers, resize/reflow, Shift+Enter, mouse, selection/copy, permission prompt, AskUserQuestion, `/tui fullscreen`, `TERM_PROGRAM` variants (Claude Code only enables kitty keys for allow-listed values). Log every rendering defect. *Pass:* no defects a user would notice; typing latency imperceptible.
2. **Six-session load (½ day).** Six streaming sessions, five hidden. Measure CPU and RSS. *Pass:* < 15% of a core total when idle-streaming, hidden views not drawing.
3. **libghostty-spm same soak (½ day)** only if 1 or 2 fail.
4. **CM6 live preview on the legacy 1.2 MB `tasks.md` (2 days).** Byte-identical save, keystroke latency, RSS, spellcheck/dictation/Writing Tools in the editable DOM, native menu → `callAsyncJavaScript` with `validateMenuItem`, find. *Pass:* Geoff's four editor criteria.
5. **External edit merge (1 day).** Claude edits the open file mid-typing; verify cursor/undo preservation and the dirty-buffer diff3 path.
6. ~~**`swift-markdown-engine` hedge (2 days).**~~ Dropped (DL-167); it ran on 2026-10-03 and failed on size (F-39).
7. **WKWebView browser (2 days).** Persistent login across launches, OAuth popup, localhost, local folder via scheme handler, download, PDF, per-tab memory; **inspector overlay** producing selector + outerHTML + computed styles + element screenshot on a logged-in Linear page; a page-driver script that clicks and types.
8. **MCP in-app server (1 day).** Official Swift SDK over HTTP, `--mcp-config` into a session, call `browser.get_selected_element` from the TUI and see it land in the conversation.
9. **Hooks + `agents --json` state (½ day).** Inject hooks with `--settings`, receive events at a local endpoint, correlate with `claude agents --json` by `sessionId`.
10. **Config-dir strategy (1 day).** Duo-managed `CLAUDE_CONFIG_DIR` + pinned project dir name: does login carry over, do memory/trust/`/resume` follow a folder move, does Remote Control work. Decide #11.

Total: ~12 working days of spikes before committing to the skeleton. Spikes 1, 4 and 7 are the ones that could change a decision.

## Open items

- Whether `claude` sessions launched by Duo are exempt from the 30-day transcript cleanup (Desktop-launched ones are). Set `cleanupPeriodDays` in Duo's settings regardless and archive transcripts.
- Policy: confirm with Anthropic's terms before any headless conversation surface; the TUI route avoids the issue because the user runs their own `claude`.
- Editable tables in CM6 live preview are the biggest editor UX item (1–2 weeks); decide after spike 4 whether v1 ships with read-only rendered tables that open to source on click.
