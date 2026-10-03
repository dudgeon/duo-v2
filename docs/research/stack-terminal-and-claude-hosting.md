# Hosting Claude Code sessions inside a native macOS app

**Decision doc for Duo v2.** Research date: 2026-10-03. Local environment at time of writing: macOS 27 (Darwin 27.0.0), Claude Code 2.1.288 (`~/.local/bin/claude`, native binary), Claude Desktop bundling Claude Code 2.1.286.

Companion doc (written separately, not covered here): `docs/research/stack-editor-and-webview.md`.

Legend for claims:
- **[verified]** fetched from a primary source on 2026-10-03, URL cited.
- **[observed]** measured or run on this machine on 2026-10-03.
- **[unverified]** plausible but not confirmed; treat as a spike input, not a fact.

---

## 0. TL;DR

**Recommendation: host the real Claude Code TUI.** One PTY per session, spawned from a non-sandboxed Swift app via the user's login shell, rendered by **SwiftTerm** (Metal renderer, SwiftTerm 2.0 line) behind a thin `TerminalHost` protocol. Layer Duo's PM-facing affordances (session list, "needs input" badges, notifications, cost) on top of **`claude agents --json` polling plus per-session hooks injected with `--settings`**, which work regardless of how the session is hosted.

**Fallback (swap behind the same protocol): libghostty** via the `Lakr233/libghostty-spm` Swift package if SwiftTerm shows rendering defects against Claude Code's fullscreen renderer that cannot be fixed upstream within a spike.

**Do not** build a headless chat UI (`--input-format stream-json` + `--output-format stream-json`) as the primary surface. It is viable (Anthropic's own Desktop app does exactly this, observed locally), but it means rebuilding Claude Code's entire UI against a protocol whose wire format is only partly documented, it loses the "users already know the TUI" advantage, and it carries a branding/subscription policy wrinkle. Keep it as a **secondary view** candidate (e.g. a read-only "chat summary" pane) and de-risk it with one spike.

**Do not** use xterm.js in a WKWebView. It re-creates the Electron architecture (JS emulator + bridged PTY) inside WebKit with worse clipboard/IME/bridge ergonomics and no memory advantage. Only consider it if both native emulators fail.

**App Sandbox: off.** A sandboxed app's child processes inherit the sandbox, so Claude Code could not read the user's repos, run `git`, or find `claude` on PATH. Duo v2 is Developer ID signed and notarized, distributed outside the Mac App Store, like Ghostty, iTerm2, Warp and CodeEdit.

---

## 1. Terminal emulator options for Swift/AppKit

### 1.1 What Claude Code's TUI actually needs from an emulator

Claude Code is still React-based, but the renderer is no longer stock Ink: Anthropic rewrote it from scratch in 2.0.72 (Dec 2025) while keeping React as the component model, to fix the "signature flicker" **[verified]** (<https://steipete.me/posts/2025/signature-flicker>). It now ships two renderers **[verified]** (<https://code.claude.com/docs/en/fullscreen>):

| Renderer | Mechanism | Who gets it |
|---|---|---|
| **Classic** | Inline, scrollback-preserving, re-renders only changed regions. Probes the terminal for synchronized output (DEC 2026) at startup and uses it when reported. | Default for users who first used Claude Code before 2026-05-06, screen-reader mode, `tmux -CC`. |
| **Fullscreen** (research preview) | Alternate screen buffer, like vim. Only visible messages in the render tree ("flat memory"). Captures the mouse (click-to-expand, wheel scroll, in-app selection with copy-on-release via `pbcopy`, Cmd+click links). Sends only changed cells per frame; `CLAUDE_CODE_ALT_SCREEN_FULL_REPAINT=1` forces full repaint for terminals that coalesce positioned writes badly. | Default for users who first used Claude Code on/after 2026-05-06; **always** used for `claude attach` to background sessions. |

Capability checklist derived from the docs **[verified]** (fullscreen page; <https://code.claude.com/docs/en/terminal-config>; <https://code.claude.com/docs/en/interactive-mode>):

| Capability | Why Claude Code needs it | Notes |
|---|---|---|
| Truecolor / 256 color | Themes, diffs | Table stakes. |
| Alternate screen + DECSTBM scroll regions | Fullscreen renderer; classic renderer uses scroll regions for the fixed prompt | Scroll-region bugs are exactly what broke SwiftTerm in Dec 2025 (see 1.2). |
| **Synchronized output (DEC mode 2026)** | Flicker-free streaming; Claude Code probes for it (DECRQM) and uses it if reported. `CLAUDE_CODE_FORCE_SYNC_OUTPUT=1` forces it. | tmux ≤3.6 lacks it and flickers; same will apply to any emulator that doesn't report it. |
| **SGR mouse reporting (1006) incl. motion + wheel** | Fullscreen: wheel scroll, click-to-expand, selection, hover highlights. `CLAUDE_CODE_DISABLE_MOUSE=1` opts out. | Wheel multiplier assumptions differ per terminal (`CLAUDE_CODE_SCROLL_SPEED`). |
| **Kitty keyboard protocol (CSI ? u)** | Shift+Enter newline, Cmd+C copy in fullscreen, `Ctrl+[` in vim mode, `modifyOtherKeys` | Claude Code only *queries* kitty protocol support for terminals on a `TERM_PROGRAM` allowlist (Ghostty, Kitty, iTerm2, WezTerm, Warp, Apple Terminal, Windows Terminal) — open bug #97501 says `claude attach` never sends `CSI ? u` for unlisted terminals, and #96526 says `modifyOtherKeys` is likewise gated **[verified]** (<https://github.com/anthropics/claude-code/issues/97501>, <https://github.com/anthropics/claude-code/issues/96526>). **Implication for Duo: whatever `TERM_PROGRAM` Duo advertises decides which key-encoding path Claude Code takes.** Spike this. |
| Bracketed paste | Paste large content → `[Pasted text #N]` chips; invisible-character stripping | |
| **OSC 8 hyperlinks** | `owner/repo#123` clickable refs; `FORCE_HYPERLINK=1` to force on | Claude Code also special-cases Ghostty and Warp so a *plain* click on a link opens it, because the mouse protocol cannot encode Cmd. |
| OSC 52 clipboard | Only used as a fallback over SSH; locally Claude Code runs `pbcopy` itself | Nice-to-have, not required for Duo. |
| OSC 9 / OSC 777 desktop notifications, OSC 9;4 progress | Claude Code sends desktop notifications only in Ghostty, Kitty, iTerm2 (detected by `TERM_PROGRAM`); otherwise `preferredNotifChannel: "terminal_bell"` or a `Notification` hook | Duo should use a hook (section 2.4), not emulator OSC parsing. |
| Image paste (Ctrl+V) | `[Image #N]` chips | Claude Code reads the clipboard itself; not an emulator feature. |
| Terminal title (OSC 0/2) | Session name shown in title | Cheap to support; useful for Duo's tab labels. |
| Option-as-Meta | `Alt+B/F/D/Y/P` shortcuts | Emulator config choice. |

Takeaway: **fullscreen mode is the hard target** (alt screen + mouse + sync output + kitty keys + incremental cell writes). Any emulator Duo picks must pass a soak test in *both* renderers, because `claude attach` forces fullscreen and new users default to it.

### 1.2 SwiftTerm (Miguel de Icaza)

Repo facts **[verified]** via GitHub API on 2026-10-03 (<https://github.com/migueldeicaza/SwiftTerm>):

- 1,717 stars, 497 forks, 91 open issues, **MIT**, last push 2026-10-02 (eight merged PRs that day alone).
- Latest tag **v1.20.0 (2026-08-18)**; `main` is the **SwiftTerm 2.0 API** (migration guide shipped, no 2.0.0 tag yet). `v1.x` branch maintained for 1.x. Package is `swift-tools-version:6.2`.
- Used in shipping products: Secure Shellfish, La Terminal (iOS SSH clients), **CodeEdit** (23k-star macOS editor), Tecolot (Terminal.app replacement), and a fork in "Threading" (macOS/iOS terminal host; see issue #647 where that team offers their downstream fixes upstream).
- Front-ends: AppKit (`MacTerminalView`), UIKit, headless, wasm. UI-agnostic engine.

Feature coverage against the checklist (README **[verified]**, source search **[verified]**):

| Need | SwiftTerm status |
|---|---|
| Truecolor/256 | Yes. |
| **Metal GPU renderer** | Yes, opt-in `try terminalView.setUseMetal(true)`; `metalBufferingMode = .perFrameAggregated` is documented as "best for full-screen TUI apps that repaint most of the screen each frame" (`Documentation.docc/GPURendering.md`). CoreGraphics renderer remains the default. |
| **Synchronized output (2026)** | Implemented. PR #498 (closed 2026-04-02) fixed rendering suppression during sync blocks — the bug report was literally "running Claude Code inside tmux" scroll-through artifacts. Feature issue #203 (2022) is still open as a tracking issue. |
| Mouse | Yes incl. motion, SGR, middle button (#730, 2026-10-02), typed mouse responses (#681). Open: #583 (scrollback in alt screen via trackpad), #705 (Option-drag bypass). |
| Bracketed paste | PR #683 "Bracketed paste" merged **2026-09-03 — after the v1.20.0 tag**. If you pin to a tag you may not have it. **[unverified]** whether 1.x had a partial implementation before. |
| OSC 8 hyperlinks | Yes, with `.explicit` vs implicit link detection and parsed params. Open bug #701 (implicit link regex joins adjacent paths). |
| OSC 52 / Kitty clipboard | Yes (README "Kitty Clipboard"; `ClipboardHost.swift`). |
| **Kitty keyboard protocol** | `KittyKeyboardProtocol.swift` and `KittyKeyboardEncoder.swift` exist in `Sources/SwiftTerm` (32 code-search hits). **[unverified]** how complete (progressive enhancement flags, release events, text-as-codepoints). Spike. |
| Kitty graphics / Sixel / iTerm2 images | Yes. |
| Reflow on resize | Issue #405 "Window Resize on Coding Agents (eg. Claude Code or Gemini CLI)" opened 2025-12-01, closed 2026-02-02. Root cause the maintainer found was window-size propagation to the shell (zsh not receiving the size change), not the buffer reflow itself. **[unverified]** that reflow is fully correct for the classic renderer's inline UI; it is the #1 thing to test. |
| Search, selection, find bar | Yes (built-in macOS find bar). |
| BiDi, grapheme clusters | Yes; README claims stronger Unicode handling than xterm.js. |
| Session recording/playback (termcast) | Yes — useful for Duo's "replay" ideas. |
| Local process / PTY | `LocalProcess` + `Pty.swift` use `forkpty`; `LocalProcessTerminalView` is the ready-made AppKit view. 2.0 adds `directDelivery` and fixes PTY fd leakage into children (#719), reaping (#717/#716). |

Known issues relevant to Duo **[verified]**:

- **#658 (open, 2026-08-25): "High main-thread CPU with multiple streaming TUI terminals: glyph metrics dominate Metal draw."** Reporter runs *six* terminals attached to streaming AI-agent TUIs with Metal on SwiftTerm 1.2.x and sees 75–82% of one core while idle; `CTFontGetBoundingRectsForGlyphs` dominates. Maintainer reply (2026-08-27): v2 "was improved extensively across the board, some 10x to 50x in various places" and asks for a v2 re-test; hidden views already stop rendering. **This is Duo's exact workload. Spike 3 reproduces it on 2.0.**
- #636 (open) Metal row cache across scrolls; #642 (open) retry frames refused by Metal; #603 (open) repaint rows while scrolled back; #449 (open) line layout cache.
- #584 (closed) macOS 26 Tahoe phantom mouseDown during hover — shows the project tracks current macOS quickly.
- Cross-project: anthropics/claude-code #14613 "Scroll region rendering broken in SwiftTerm after recent flickering fix" (opened 2025-12-19, closed 2026-02-27) — the content region scrolled one extra line per update under SwiftTerm (via the Xtro iOS client). Fixed on one side or the other; the point is **SwiftTerm + Claude Code combinations get exercised and bugs get fixed within weeks on both sides.**

Assessment: pure Swift, SPM, MIT, zero extra toolchain, extremely active maintainer, Metal path, and the specific Claude Code/TUI bugs of the last ten months have been fixed. Risks: 2.0 is untagged (pin a commit), per-view Metal CPU cost under six streaming sessions (#658) is unresolved on 1.x and unmeasured on 2.0, and kitty-keyboard completeness is unverified.

### 1.3 libghostty / Ghostty embedding (Mitchell Hashimoto)

Repo facts **[verified]** (<https://github.com/ghostty-org/ghostty>): 61,809 stars, **MIT**, latest tag v1.3.1 (2026-03-13), last push 2026-10-03. The project announced on 2026-04-28 that it is leaving GitHub ("Ghostty Is Leaving GitHub", <https://mitchellh.com/writing/ghostty-leaving-github>): GitHub will remain a **read-only mirror**, destination "in the coming months", no impact statement for embedders. As of 2026-10-03 commits are still landing on GitHub, so the migration is not complete.

There are **two different things** people call "libghostty" **[verified]** (README "Cross-platform libghostty" section; <https://ghostty.org/docs/about>; <https://mitchellh.com/writing/libghostty-is-coming>, 2025-09-22; <https://ghostty-org-ghostty.mintlify.app/api/overview>):

1. **libghostty-vt** (`include/ghostty/vt.h`): the VT parser, terminal state, scrollback, reflow, selection, search, kitty graphics state, key/mouse *encoders*, and render-state readback. **No renderer, no windowing.** Zero dependencies (not even libc). Officially "available and usable today for Zig and C… compatible for macOS, Linux, Windows, WebAssembly… functionality extremely stable… **API signatures still in flux**… **we haven't tagged libghostty with a version yet**." In-tree examples include `example/swift-vt-xcframework` (a Swift consumer of a vt xcframework) and ~30 C examples (`c-vt-render`, `c-vt-search`, `c-vt-encode-key`, …). Doxygen docs at <https://libghostty.tip.ghostty.org/>. `ghostty-org/ghostling` (1,119 stars, MIT, pushed 2026-08-09) is a single-file C terminal on libghostty-vt using Raylib for rendering. Recent in-tree work: "render hold effect for synchronized output" (#14317, 2026-09-20), bulk render-state style readback (#14513, 2026-10-02), memory-usage query (#14499).
2. **Full libghostty / GhosttyKit** (`include/ghostty.h`, `ghostty_app_t` / `ghostty_surface_t`, the Metal renderer, font shaping, PTY, config): what the Ghostty macOS app itself links. The official API overview says: "The libghostty API is currently used primarily by the macOS app and is **not yet stabilized for general-purpose embedding**" and the about page's roadmap lists cross-platform libghostty as "in progress". The 2026 roadmap statement (Superlogical post, 2026-07-29 **[verified via secondary summary, unverified primary]**) predicts libghostty users will exceed Ghostty users by mid-2027.

Third-party Swift paths **[verified]**:

- **`Lakr233/libghostty-spm`** (<https://github.com/Lakr233/libghostty-spm>): 111 stars, MIT, **pushed 2026-10-03**, tags track upstream (`upstream.1.3.1`, `upstream.<sha>`). Ships a prebuilt `GhosttyKit` xcframework binary target (full libghostty, Metal) plus a `GhosttyTerminal` Swift wrapper: `TerminalSurfaceView` for SwiftUI, `AppTerminalView` for AppKit, `sendKey`/`paste(text:)` input paths that honor the program's key mode and bracketed paste, `isSurfaceVisible` to stop rendering hidden tabs while keeping grid/scrollback, prompt-jump via OSC 133, an `.exec` backend that spawns a shell with bundled **MIT** bash/zsh shell integration (upstream's scripts are GPLv3 and are deliberately not shipped). Requires Swift 6.2 / Xcode 26, macOS 13+. Version 2.0.0 of the wrapper removed some APIs — it is young and moving.
- **Enso** (<https://github.com/amanfromsolan/enso>): a SwiftUI macOS terminal "for people who work with AI coding agents", built on `GhosttyKit.xcframework` which you must build yourself from Ghostty source with **Zig 0.16+**. 36 stars, GPL-3.0, pushed 2026-09-02, signed/notarized DMG releases. Proof that a solo dev can ship a Swift app on full libghostty today; also evidence of the toolchain cost.
- Another embedder (issue #12065, April 2026) built a macOS terminal on the C API that detects Claude Code running in a tab — and asked for `ghostty_surface_child_pid()` because they had to scrape viewport text. Closed; **[unverified]** whether the API was added.

Open risk **[verified]**: #14245 (open, 2026-09-29) "libghostty: `ghostty_surface_free` deadlocks the app thread when the surface's reader is blocked pushing into the app mailbox." Exactly the kind of lifecycle bug you hit closing one of six tabs.

Why it is attractive: Claude Code's docs explicitly name Ghostty as a first-class terminal (kitty keyboard, Shift+Enter, desktop notifications, plain-click links, wheel amplification). Setting `TERM_PROGRAM=ghostty` from a libghostty-backed view would be *honest* and would put Duo on Claude Code's best-tested path. Metal renderer, shaping and Unicode are best-in-class.

Why it is not the default: no tagged API, "not stabilized for embedding" per the authors, project mid-migration off GitHub, and the Swift packaging is a one-person third-party wrapper (very active, but the xcframework is a prebuilt binary you must trust or rebuild with Zig). For a solo dev working mostly with Claude Code, a C API with no stability promise is more risk than a Swift library with 90 open issues and a responsive maintainer.

Licensing **[verified]**: Ghostty core and libghostty are MIT. Only the upstream shell-integration scripts are GPLv3 (avoid bundling those; libghostty-spm already does).

### 1.4 xterm.js inside WKWebView

Repo facts **[verified]**: xterm.js 21,250 stars, MIT, **6.0.0 released 2025-12-22** (removed the canvas addon; WebGL addon is the GPU path; added DEC 2026 synchronized output, OSC 52, progress addon, ligature improvements), last push 2026-09-13. The legacy Duo app pins `@xterm/xterm ^5.5.0` + `node-pty ^1.0.0` + `electron ^32` **[observed]** in `~/repos/duo/package.json`.

Viability in a WKWebView:

- Rendering: WebKit supports WebGL2, so `@xterm/addon-webgl` should load **[unverified in WKWebView specifically]**; DOM renderer always works. Claude Code's own docs note that in "the VS Code integrated terminal and similar xterm.js-based terminals" throughput is the bottleneck that motivated fullscreen mode, and `/terminal-setup` *turns off* GPU acceleration in VS Code "to prevent garbled text" **[verified]** (terminal-config page). That is not an endorsement of xterm.js for this workload.
- PTY: there is no node-pty; Duo would `forkpty` in Swift and shuttle bytes to JS via `evaluateJavaScript`/`WKScriptMessageHandler` (base64 or string), i.e. a main-thread JSON bridge on the hot path for six streaming sessions. This is the part of the Electron app that made it heavy, re-created with a worse bridge.
- Memory: each `WKWebView` has a WebContent process (sharable via a `WKProcessPool`, but one crash takes all tabs). Typical idle cost is on the order of 50–150 MB per content process **[unverified; measure if ever pursued]**, before xterm.js buffers.
- IME: works via the DOM (xterm.js has a hidden textarea). Clipboard: `navigator.clipboard` in WKWebView is permission-gated; copy/paste and OSC 52 must be bridged to `NSPasteboard`. Links: OSC 8 via `@xterm/addon-web-links` plus a message handler to `NSWorkspace.open`. All doable, all plumbing.
- Fidelity: xterm.js is the emulator behind VS Code's terminal, which Claude Code supports but with known glitches (#51828, #84247 scrollback duplication on resize; #61562 sliced glyphs on macOS 26.2 — all **[verified]** open/closed issues in anthropics/claude-code).

Verdict: only as a last-resort fallback. It gives up native feel, keeps a JS runtime per view, and buys nothing the native options lack.

### 1.5 Others considered

- **`alacritty_terminal` (Rust crate)** — the engine behind Alacritty (65.9k stars, Apache-2.0, last push 2026-08-31 **[verified]**) and **Zed's terminal** (`crates/terminal/Cargo.toml` depends on `alacritty_terminal` **[verified]**). It is a VT/grid library with no renderer; using it means Rust FFI from Swift plus writing a Metal renderer. Same shape of work as libghostty-vt, with a less active-for-embedding community. Not pursued.
- **Warp** open-sourced its client in April 2026 (AGPL; `warpui`/`warpui_core` crates MIT) **[verified via secondary sources]** (<https://blog.kilo.ai/p/warp-finally-went-open-source>, <https://en.wikipedia.org/wiki/Warp_(terminal)>). It is a whole Rust app with a block-based model, not an embeddable emulator. AGPL on the client is a non-starter for a proprietary Mac app anyway. Not pursued.
- **Terminal.app via `NSTask`/AppleScript** — not an emulator; and Claude Code has a known regression when launched via AppleScript `do script` (#33676 **[verified]**). Not applicable.
- **Claude Code's own `claude attach` in a terminal pane** — not an emulator either, but see 2.3: it is a legitimate *process model* that any of the above emulators can host.

### 1.6 PTY spawning in Swift and the App Sandbox

**Spawning** (all **[verified]** by reading SwiftTerm `Pty.swift`/`LocalProcess.swift` references and Apple docs discussion):

- `forkpty(3)` / `posix_openpt` + `fork`/`exec` is the standard path; SwiftTerm's `LocalProcess` wraps it and handles `SIGWINCH` via `ioctl(TIOCSWINSZ)` on resize, child reaping, and EOF. `Process` (NSTask) cannot allocate a controlling TTY; you can hand it the slave fd as stdin/stdout, but `forkpty` is simpler and what every Mac terminal uses.
- **Environment.** Duo must launch `claude` the way the user's shell would: run the login shell once (`/bin/zsh -lic 'echo $PATH'` or spawn `zsh -l -c 'exec claude …'`) so Homebrew, `~/.local/bin` (the native installer location, `claude install`), npm global, nvm and `CLAUDE_CONFIG_DIR` are all respected. Set `TERM=xterm-256color`, `COLORTERM=truecolor`, `LANG`, and a deliberate `TERM_PROGRAM` (see 1.1 — this value changes Claude Code's key-protocol and notification behavior).
- **SIGINT/Ctrl-C** goes through the PTY line discipline as usual; SwiftTerm has tests for foreground-pgrp ownership (#723).

**App Sandbox** **[verified]** (Apple DTS "Quinn", July 2021, <https://developer.apple.com/forums/thread/685544>): `forkpty` works in a sandboxed app, but "child processes… always inherit the parent's sandbox," so the shell sees only the container (`ls /Users` → "Operation not permitted", `zsh: can't set tty pgrp`). "App Review requires that all code within your app be sandboxed. So you can't include a non-sandboxed helper app within your app." There is no entitlement that exempts PTY children. The only MAS-compatible pattern is an external, non-MAS helper over a socket — which App Review is "very wary of."

For Duo this is decisive: Claude Code must read/write arbitrary repos, run `git`, `node`, `pytest`, open sockets for MCP and cross-session messaging, and find its own binary on PATH. **Duo v2 runs unsandboxed, Developer ID signed, notarized, distributed via DMG/Sparkle, not the Mac App Store.** Hardened Runtime stays on. Note macOS TCC still gates Desktop/Documents/Downloads and Local Network — Claude Code's docs call this out for background sessions too — so Duo should request those on first use with clear copy.

---

## 2. Alternative: drive Claude Code headlessly

### 2.1 What the CLI offers today **[verified]**

Sources: <https://code.claude.com/docs/en/cli-reference>, <https://code.claude.com/docs/en/headless>, <https://code.claude.com/docs/en/agent-sdk/overview>, <https://code.claude.com/docs/en/agent-sdk/typescript>, <https://code.claude.com/docs/en/agent-sdk/user-input>, <https://code.claude.com/docs/en/agent-sdk/streaming-vs-single-mode>, <https://code.claude.com/docs/en/hooks>, <https://code.claude.com/docs/en/sessions>.

- `claude -p --output-format stream-json --input-format stream-json --verbose` gives newline-delimited JSON both ways. Add `--include-partial-messages` for token deltas (`stream_event` with `event.delta.type == "text_delta"`), `--replay-user-messages` for echo/ack, `--include-hook-events` for `hook_started/progress/response`, `--forward-subagent-text` for subagent transcripts (`parent_tool_use_id` links them), `--prompt-suggestions`, `--json-schema` for structured final output. Stdin is capped at 10 MB. Exit codes are meaningful; SIGTERM → 143 with `SessionEnd` hooks run; SIGINT ends the turn.
- First event is `system/init` carrying `session_id`, model, tools, `mcp_servers`, plugins, and a **`capabilities` array** ("interrupt_receipt_v1", "interrupt_cancel_queued_v1", "mcp_read_resource_v1", "async_agent_v1", …) meant for feature detection instead of version sniffing. Other message types the TS reference lists: `assistant`, `user`, `result`, `stream_event`, `tool_progress`, `status`, `task_*`, `permission_denied`, `api_retry`, `rate_limit_event`, `auth_status`, `session_state_changed`, `worker_shutting_down`, `compact_boundary`, `prompt_suggestion`, `elicitation_complete`, `informational`, `conversation_reset`, and the hook lifecycle events. Roughly 35 variants, and the docs say the list grows.
- **Sessions:** `--session-id <uuid>` to choose the ID up front; `--resume <id|name|path>`; `--continue`; `--fork-session`; `--no-session-persistence`. `-p` sessions are hidden from the interactive `/resume` picker and `claude --continue` by default (but `claude -p --continue` sees them). Transcripts live at `~/.claude/projects/<slug>/<session-id>.jsonl`; the docs warn the line format "is internal to Claude Code and changes between versions."
- **Permissions and questions:** both tool approvals and `AskUserQuestion` arrive through the same channel — the SDK's `canUseTool` callback, or for a raw CLI consumer, `--permission-prompt-tool <mcp-tool>`. `AskUserQuestion` input is `{questions:[{question, header, options:[{label, description, preview?}], multiSelect}]}` (1–4 questions, 2–4 options); you answer by returning `behavior:"allow"` with `updatedInput:{questions, answers:{"<question text>":"<label>"}}`, optional free-text `response`. Approve-with-changes (`updatedInput`), approve-and-remember (`updatedPermissions` echoing `suggestions`, with `destination: "localSettings"` persisting to `.claude/settings.local.json`), deny-with-message, deny-with-`interrupt`, and `PreToolUse` → `defer` (so the process can exit and resume later) are all supported. `--permission-prompts none` denies everything that would prompt and removes `AskUserQuestion`. Plan mode exists in `-p` (`--permission-mode plan`), and resuming into plan mode with `-p` requires `--permission-prompt-tool`.
- **Streaming input** (an async iterable of `{type:"user", message:{role:"user", content}}`) is required for interrupts, queued messages, mid-session `setModel`/`setPermissionMode`/`applyFlagSettings`, image attachments (base64 blocks), and `canUseTool`. Single-shot `-p "prompt"` is the limited mode.
- **Wire format of the control channel.** The official docs describe the semantics via the SDKs but **do not publish the raw JSON** for `control_request`/`control_response`. Third-party reverse-engineering (Runloop's "Claude protocol" page, <https://docs.runloop.ai/docs/axons/broker/claude-protocol>, **[verified secondary]**) documents: an `initialize` handshake (`{"type":"control_request","request_id":…,"request":{"subtype":"initialize","protocolVersion":"1.0"…}}`); Claude → host `control_request` with `request.subtype` ∈ `can_use_tool` (`tool_name`, `tool_use_id`, `input`), `hook_callback`, `mcp_message`; host → Claude `control_response` `{"type":"control_response","response":{"subtype":"success","request_id":…,"response":{"behavior":"allow"|"deny",…}}}`; host → Claude `{"subtype":"interrupt"}`. Runloop's own caveat: "The protocol is unstable. Current tested version: 2.1.52." Treat as **[unverified]** until Spike 6 logs it against 2.1.288.
- **What Anthropic's own Desktop app does** **[observed]**: Claude Desktop 1.x (Code tab) runs its bundled CLI as
  `claude --output-format stream-json --verbose --input-format stream-json --effort <x> --model <m> --permission-prompt-tool stdio --allowedTools mcp__…`
  — stream-json both ways, **no `-p`**, and `--permission-prompt-tool stdio`. The `stdio` value is **not in the public CLI reference** (community write-ups describe it as "the bidirectional control channel") → **[unverified/undocumented]**. The docs also state Desktop "is interactive only; `--print`/`--output-format` not available" from the user's perspective and that Desktop does not implement `Shift+Tab` mode cycling or other TUI shortcuts — i.e. Anthropic's native chat UI is a *re-implementation*, with its own session list, diff viewer, terminal pane, etc.

### 2.2 Agent SDK: TypeScript/Python only; Swift options

- The Agent SDK is **Python and TypeScript** only; each "runs the Claude Code binary" (the TS package bundles `@anthropic-ai/claude-agent-sdk-darwin-arm64` or honors `pathToClaudeCodeExecutable`). The docs' answer for other languages: "run the CLI as a subprocess with the `-p` flag." **[verified]**
- **Policy note [verified]:** the SDK overview says "Unless previously approved, Anthropic does not allow third party developers to offer claude.ai login or rate limits for their products, including agents built on the Claude Agent SDK. Use the API key authentication methods instead," and the branding section forbids calling a product "Claude Code" or mimicking its visuals. `--bare` mode "never reads OAuth credentials." Hosting the user's *own* `claude` TUI in a terminal is clearly the user using their own tool; a Duo-branded chat UI that drives the user's subscription through stream-json is closer to the line. **Not legal advice; confirm before shipping a headless chat surface.**
- Swift community wrappers: `jamesrochabrun/ClaudeCodeSDK` (99 stars, MIT, **last push 2025-12-27**, macOS 13+, spawns the CLI with `Process`, optional Node Agent-SDK backend) **[verified]**. Nine months stale against a protocol that changes monthly; usable as reference, not as a dependency.
- **Node sidecar cost [observed]:** an idle `node` process is ~38 MB RSS on this machine; a sidecar running the TS SDK would add that plus the SDK, on top of the `claude` process it spawns anyway. Since `claude` is now a native binary and speaks stream-json directly, a sidecar buys nothing but typed message definitions. Skip it; parse NDJSON in Swift with `Codable` and an "unknown type → ignore" policy.

### 2.3 `claude agents --json`, the supervisor, and background sessions **[verified + observed]**

Source: <https://code.claude.com/docs/en/agent-view> (agent view requires v2.1.257+; research preview).

- `claude agents --json` prints a JSON array of live sessions **including interactive ones started from any terminal** — on this machine it listed four interactive sessions with `pid`, `cwd`, `kind`, `startedAt` (ms), `sessionId`, `name`, `status` (`busy|waiting|idle`), and `waitingFor` ("input needed", "permission prompt", "sandbox request", "worker request", "dialog open") **[observed]**. Background sessions add `id` (short), `state` (`working|blocked|done|failed|stopped`). `--all` includes completed, `--cwd` filters. This is the officially preferred state source ("read via `claude agents --json`, not the files").
- The **supervisor** (`claude daemon status|stop`) hosts `--bg` sessions, **one Claude Code process per session** ("~50–150 MB base" per docs), stops an idle unattached process after ~1 h and restarts it on demand (state in `~/.claude/jobs/<id>/state.json`), restarts crashed sessions, and migrates after auto-update. `claude attach <id>` takes over a terminal **in fullscreen rendering regardless of the `tui` setting**; `←`/`Ctrl+Z` detaches; Claude posts a recap of what happened while unattached. `claude --bg` cannot be combined with `-p`. On this machine the daemon was not running (`claude daemon status` → "not running", socket dir `/tmp/cc-daemon-501/…`) **[observed]**.
- Other state sources: **hooks** (`SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PermissionRequest`, `Notification`, `Stop`, `SessionEnd`, `SubagentStart/Stop`, `TaskCreated/Completed`, `PreCompact/PostCompact`, `CwdChanged`, …) with `command`, **`http`** (POST to a local URL), `mcp_tool`, `prompt`, `agent` handler types, every payload carrying `session_id`, `cwd`, `transcript_path`, `permission_mode`, `effort`; the **statusline command** (receives JSON with cost/context/model); **cross-session messaging** (per-session Unix socket at `/tmp/cc-socks-<uid>`, `CLAUDE_CODE_MESSAGING_SOCKET`, `/list-agents`; works for `-p` sessions unless `--bare`). Hooks can be injected per session via `--settings '<json>'` so Duo never edits the user's `~/.claude/settings.json`.

### 2.4 Hybrid: TUI for the console + `agents --json` + hooks for state

This is the shape Duo should take whichever emulator wins:

```
Duo.app (Swift)
 ├─ SessionManager ── polls `claude agents --json` (1–2 s, or on hook events) ── sidebar: status/needs-input badges
 ├─ HookServer (localhost HTTP) ◄─ hooks injected via --settings on each spawn ── notifications, cost, PR links, timeline
 ├─ TerminalHost protocol
 │    ├─ SwiftTermHost (default)        ── PTY ── zsh -l -c 'exec claude [--resume id] [--name …]'
 │    └─ GhosttyHost (fallback)
 └─ (optional, later) HeadlessHost ── stream-json ── native "chat summary"/review pane
```

Assessment: everything in the state layer is **officially supported, version-tolerant** (JSON with documented fields, `capabilities` for feature detection), and independent of the hosting choice. It gives Duo the PM affordances (who needs me, what is each session doing, cost, done/failed) without touching rendering. The only brittle piece is reading `.jsonl` transcripts directly — avoid, or treat as best-effort for previews. Remote Control, Agent View, plan mode, `/resume`, Desktop handoff (`/desktop`, `claude --desktop --resume <id>`), and future features all keep working because the real TUI is running.

What the hybrid cannot do that headless can: render Claude's output in native typography, inline diff review with native controls, structured permission sheets, or synthesize across sessions. Those are candidates for a **second, read-mostly pane** fed by hooks + `claude -p --resume <id> --output-format json "summarize…"` (a documented pattern on the sessions page), not for replacing the console.

---

## 3. Comparison

Memory baseline **[observed, 2026-10-03, Apple Silicon]** — the dominant cost is the Claude Code process itself, which every approach pays:

| Process | RSS |
|---|---|
| `claude` interactive TUI, idle | 228 MB |
| Claude Desktop-hosted headless session (stream-json), light/idle | 118 MB |
| Claude Desktop-hosted headless session, long session with large context | 467 MB |
| `claude rc` (Remote Control server) | 110 MB |
| `claude --print --sdk-url …` bridge worker | 174 MB |
| Claude Desktop Electron renderer helper (whole app, for scale) | 995 MB |
| `node` idle (sidecar baseline) | 38 MB |

Docs' figure for a background session: ~50–150 MB base. So the hosting choice moves the *per-session* number by tens of MB (emulator buffers, glyph atlases, or WebContent processes), not hundreds — except xterm.js/WKWebView, which adds a browser content process.

| Criterion | A. TUI in SwiftTerm | B. TUI in libghostty (via libghostty-spm) | C. xterm.js in WKWebView | D. Headless stream-json + native UI |
|---|---|---|---|---|
| **Responsiveness** | Native; Metal path available. Unknown: v2 CPU under 6 streaming TUIs (#658 on 1.x showed 75–82% of a core). | Best-in-class renderer; Claude Code tunes for Ghostty (wheel, links, kitty keys). | Worst: JS emulator + main-thread bridge for PTY bytes; Anthropic's own fullscreen-mode rationale cites xterm.js-based terminals as the bottleneck. | Excellent for text (SwiftUI/AppKit text), but you must re-implement streaming, diffs, tool cards, permission sheets, question cards. |
| **Memory / session** (host side, excluding the claude process) | Low: grid + scrollback + glyph cache; Metal atlas per view (sharing TBD). | Low; `isSurfaceVisible=false` stops rendering hidden tabs; libghostty-vt has a memory-usage query. | High: WebContent process (shared pool possible) + xterm.js buffers. | Lowest: only model objects + views; transcript can be virtualized. |
| **Fidelity to Claude Code UX** | 100% by construction, *if* the emulator is correct (classic + fullscreen renderers). Risk areas: reflow on resize, kitty keyboard, mouse in fullscreen. | 100% by construction; emulator correctness is Ghostty's (xterm-audited, fuzzed). Can honestly set `TERM_PROGRAM=ghostty`. | 100% by construction, with VS Code-terminal-class glitches (resize duplication, glyph slicing). | Divergent by construction: no slash-command UI, no `/resume` picker, no `/tui`, no transcript viewer, no Agent View, no Remote Control for `-p` sessions (requires an interactive session **[verified]**), no Desktop handoff. Hooks, plan mode, AskUserQuestion, images, interrupts, cross-session messaging do work. |
| **Implementation risk (solo dev + Claude Code)** | **Low–medium.** Pure Swift SPM, MIT, `LocalProcessTerminalView` is a drop-in; one abstraction protocol to write. Risks: untagged 2.0, per-view Metal CPU. | **Medium.** Prebuilt binary from a third party *or* Zig 0.16 toolchain; C API "not stabilized"; project migrating off GitHub; known `surface_free` deadlock. Swift wrapper is good but moving. | **Medium.** All plumbing (PTY bridge, clipboard, links, IME, process pool); nothing hard, but it is the Electron design again. | **High.** ~35 message types, undocumented control wire format, monthly protocol drift (`capabilities` helps), and the whole UI to build and keep at parity. Policy wrinkle on claude.ai login/branding. |
| **6+ sessions** | 6 PTYs + 6 `claude` processes (or `--bg` + daemon with `attach` per visible pane). Hidden views stop rendering. Suspend = kill + `--resume` later (classic renderer reprints history; fullscreen rebuilds). | Same as A; plus a cleaner hidden-surface story. | 6 WebViews (one pool) + 6 PTYs; heaviest. | 6 `claude` processes; cheapest to suspend (kill, `--resume <id>`, replay transcript from your own store). Could also drive `--bg` sessions via `claude -p --resume` for one-off queries. |
| **Keeps up with Claude Code releases** | Automatically (it is the real TUI). | Automatically. | Automatically. | Every release is potential UI work. |

---

## 4. Recommendation

### 4.1 Primary: TUI in SwiftTerm, plus the hybrid state layer

1. **Process model, v1:** one `forkpty` per session from Duo's own process, `zsh -l -c 'exec claude --name <duo-name> [--resume <id>] --settings <duo-hooks.json>'`. Set `TERM=xterm-256color`, `COLORTERM=truecolor`. Pick `TERM_PROGRAM` deliberately after Spike 1 (either Duo's own value, accepting classic key handling, or a value on Claude Code's allowlist *only if* the emulator truly implements that terminal's key protocol).
2. **Emulator:** SwiftTerm 2.0 line pinned to a commit (not `from: "1.20.0"`, which predates bracketed paste #683 and the 2.0 I/O rewrite), `setUseMetal(true)` with `.perFrameAggregated`, Option-as-Meta on, hyperlinks on, OSC title → tab name. Wrap in a `TerminalHost` protocol (`spawn`, `write`, `resize`, `title`, `bell`, `linkOpened`, `visible`) so B can be swapped in.
3. **State layer:** poll `claude agents --json` (plus `--all` on demand) for the sidebar; inject `http` hooks (`SessionStart`, `UserPromptSubmit`, `PermissionRequest`, `Notification`, `Stop`, `SessionEnd`, `TaskCompleted`) pointing at a localhost listener via `--settings`; statusline command for cost/context. Do not parse `.jsonl` except for best-effort previews.
4. **Persistence:** on app relaunch, re-spawn visible sessions with `--resume <sessionId>` (IDs captured from `SessionStart` hook / `agents --json`). Evaluate `--bg` + `claude attach` in Spike 7 as the way to let idle sessions sleep without Duo managing it.
5. **Distribution:** non-sandboxed, Hardened Runtime, Developer ID, notarized, Sparkle.

### 4.2 Fallback: libghostty via `Lakr233/libghostty-spm`

Trigger: Spike 1 finds rendering defects in SwiftTerm against Claude Code's fullscreen renderer (scroll regions, incremental cell writes, mouse selection, kitty keys) that are not fixed upstream within ~2 weeks of filing, **or** Spike 3 shows SwiftTerm 2.0 cannot keep 6 streaming sessions under ~15% of a core. Keep the `TerminalHost` boundary strict so the swap is a week, not a rewrite. Accept the Zig/prebuilt-binary dependency and track `upstream.<tag>` releases of the SPM package.

### 4.3 Later / secondary: headless "review" pane

Do not block v1 on it. After the console works, prototype a native read-mostly pane fed by hooks and `claude -p --resume <id> --output-format json`, and only then decide whether a full stream-json chat surface is worth owning. Confirm the branding/login policy question first.

### 4.4 Spikes to run first (ordered)

1. **SwiftTerm soak, 30 min × 2 renderers.** Build a 50-line AppKit app with `LocalProcessTerminalView` + Metal, run `claude` in classic and `/tui fullscreen`. Script: resize narrower/wider mid-stream, Shift+Enter, Option+Enter, Ctrl+O transcript, mouse-wheel scroll, click-to-expand, drag-select + copy, Cmd+click a link, paste 1,000 lines, `/model` picker, a permission prompt, an `AskUserQuestion`, `/resume` picker, `/diff` panel, `Ctrl+L`. Log every defect with a screenshot; try `CLAUDE_CODE_ALT_SCREEN_FULL_REPAINT=1` and `CLAUDE_CODE_FORCE_SYNC_OUTPUT=1` as diagnostics. Repeat with `TERM_PROGRAM` unset vs `ghostty`/`iTerm.app` to see which key path Claude Code takes.
2. **Same soak on `GhosttyTerminal` from libghostty-spm** (prebuilt xcframework; no Zig). Also close/reopen six surfaces repeatedly to probe #14245.
3. **Six-session load test** on both: six sessions streaming (e.g. `claude -p "write a 5,000-word essay" --include-partial-messages` is not a TUI; use six real TUIs each running a long tool-heavy prompt). Record RSS per process and app, main-thread CPU via `sample`, frame time. Compare `.perRowPersistent` vs `.perFrameAggregated`. Decide whether hidden tabs must be detached from the PTY reader.
4. **PTY/env spike:** from a non-sandboxed Swift app, resolve PATH via login shell, spawn `claude --version` and a full session; verify `~/.local/bin`, Homebrew and nvm layouts; verify SIGWINCH, Ctrl-C, EOF handling, and that `CLAUDE_CONFIG_DIR` and `~/.claude/settings.json` are honored. Confirm what breaks if the app *is* sandboxed (expect "Operation not permitted").
5. **State-layer spike:** poll `claude agents --json` while driving a session; confirm `status`/`waitingFor` transitions on a permission prompt and an AskUserQuestion within ≤2 s. Inject `http` hooks via `--settings` and confirm they fire without touching user settings. Measure the polling cost.
6. **Headless probe (de-risk only):** spawn `claude --output-format stream-json --input-format stream-json --verbose --permission-prompt-tool stdio` (Desktop's invocation) and the documented `-p` form; log the raw `system/init.capabilities`, a `can_use_tool` for Bash, an `AskUserQuestion`, an interrupt. Note which parts are undocumented. Measure RSS. This tells us how costly the "review pane" would be and whether `stdio` is safe to rely on.
7. **Persistence spike:** kill a session's process, `--resume` it in a new PTY, and compare restored state (classic reprints, fullscreen rebuilds) vs `claude --bg` + `claude attach` (forces fullscreen, recap on attach, daemon lifecycle). Decide the v1 suspend strategy.
8. **Packaging spike:** Developer ID + notarization + Sparkle pipeline with a Hardened-Runtime, non-sandboxed build, so distribution is not a late surprise.

---

## 5. Sources (all accessed 2026-10-03)

Terminal emulators
- SwiftTerm repo/README/GPU doc/migration guide: <https://github.com/migueldeicaza/SwiftTerm>, `README.md`, `Sources/SwiftTerm/Documentation.docc/GPURendering.md`, `…/MigratingFrom1To2.md`; issues #203, #405, #498, #583, #636, #647, #658, #683, #701, #717, #719, #730.
- Ghostty: <https://github.com/ghostty-org/ghostty> (README "Cross-platform libghostty"), <https://ghostty.org/docs/about>, <https://mitchellh.com/writing/libghostty-is-coming> (2025-09-22), <https://mitchellh.com/writing/ghostty-leaving-github> (2026-04-28), <https://ghostty-org-ghostty.mintlify.app/api/overview>, <https://libghostty.tip.ghostty.org/>, issues #12065, #14245, #14317; <https://github.com/ghostty-org/ghostling>; <https://github.com/Lakr233/libghostty-spm>; <https://github.com/amanfromsolan/enso>.
- xterm.js: <https://github.com/xtermjs/xterm.js/releases> (6.0.0, 2025-12-22).
- Alacritty / Zed: <https://github.com/alacritty/alacritty>, <https://github.com/zed-industries/zed/blob/main/crates/terminal/Cargo.toml>.
- Warp open source (secondary): <https://blog.kilo.ai/p/warp-finally-went-open-source>, <https://en.wikipedia.org/wiki/Warp_(terminal)>.
- App Sandbox + PTY: <https://developer.apple.com/forums/thread/685544>.
- Claude Code renderer history: <https://steipete.me/posts/2025/signature-flicker>.

Claude Code / Agent SDK
- <https://code.claude.com/docs/en/cli-reference>, <https://code.claude.com/docs/en/headless>, <https://code.claude.com/docs/en/fullscreen>, <https://code.claude.com/docs/en/terminal-config>, <https://code.claude.com/docs/en/interactive-mode>, <https://code.claude.com/docs/en/agent-view>, <https://code.claude.com/docs/en/sessions>, <https://code.claude.com/docs/en/hooks>, <https://code.claude.com/docs/en/cross-session-messaging>, <https://code.claude.com/docs/en/remote-control>, <https://code.claude.com/docs/en/desktop>, <https://code.claude.com/docs/en/agent-sdk/overview>, <https://code.claude.com/docs/en/agent-sdk/typescript>, <https://code.claude.com/docs/en/agent-sdk/user-input>, <https://code.claude.com/docs/en/agent-sdk/streaming-vs-single-mode>.
- anthropics/claude-code issues: #14613, #33676, #51828, #61562, #84247, #96526, #97501.
- Third-party protocol write-up (unofficial): <https://docs.runloop.ai/docs/axons/broker/claude-protocol>.
- Swift wrapper (stale): <https://github.com/jamesrochabrun/ClaudeCodeSDK>.

Local observations: `claude agents --json`, `claude daemon status`, `ps -axo rss,command`, `~/repos/duo/package.json`, `~/.claude/projects/…/*.jsonl` on 2026-10-03.
