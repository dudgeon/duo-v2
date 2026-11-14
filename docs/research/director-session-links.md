# Clickable session names in what a director says

Research session `director-session-links`, 2026-10-24, for Geoff's request: "whenever it mentions another claude session, the name should be a clickable link; if in claude desktop it opens the session there, if in duo it opens there". Records: F-366 (what the tests showed), F-367 (a blank chat found on the way), Q-236 (the choice), Q-237 (a link to a session that's live elsewhere), ENH-270 (Duo's part).

## The answer in short

One link form can work everywhere: the session's **Remote Control URL**, `[name](https://claude.ai/code/session_…)`. It's the only form that worked when clicked in the Claude desktop app, and it's the form the phone opens. Duo can take the same link and open the session in Duo instead of the browser: it has to recognise `claude.ai/code/session_…`, map it to the Claude session id (the transcript holds both), and route it to the existing session-link code (DL-87). Duo's terminal also needs `FORCE_HYPERLINK=1`, so that Claude Code writes links at all. A session without Remote Control gets no link, only its name: workers that `duo2 director start` starts already have Remote Control.

## What was tested

### Claude Code's terminal UI (in Duo's terminal mode)

Spike: `tui_links.py` (kept in the job's scratch folder, not the repo) writes a two-message transcript into a scratch `CLAUDE_CONFIG_DIR`, starts `claude --resume <id>` in a pseudo-terminal with Duo's terminal environment (`TERM=xterm-256color`, `COLORTERM=truecolor`, no `TERM_PROGRAM`, no `CLAUDE_*`), and reads what the TUI draws. A dummy API key gets past the login screen. No model turn runs.

| CLI | Environment | What the TUI wrote for `[alpha-worker](duo2://session/…)` |
|---|---|---|
| 2.1.310 | Duo's, as today | `alpha-worker (duo2://session/…)`, plain text, no OSC 8 |
| 2.1.310 | plus `FORCE_HYPERLINK=1` | `alpha-worker` wrapped in OSC 8 to `duo2://session/…` |
| 2.1.219 (work Mac's pin, from npm) | Duo's, as today | plain text, as above |
| 2.1.219 | plus `FORCE_HYPERLINK=1` | OSC 8, as above |

With the variable set, all four schemes came out as OSC 8: `duo2://`, `https://`, `claude://` and `#local_…`. The CLI decides by `supportsHyperlink` (a `hyperlinks` setting, then `FORCE_HYPERLINK`, then a list of terminals named by `TERM_PROGRAM`: ghostty, Hyper, kitty, alacritty, iTerm, Warp; plus JetBrains, Windows Terminal, tmux 3.4+). Duo removes `TERM_PROGRAM` (`ChildEnvironment.make`), so Claude Code treats Duo's terminal as one that can't do links.

SwiftTerm, Duo's terminal, already handles OSC 8. A click with ⌘ held calls `requestOpenLink`, which by default opens the link through `NSWorkspace`. Duo doesn't override it (nothing in `Sources/` does), so today a `duo2://` link would go out to Launch Services and back into the Duo that owns the scheme. That works for Geoff's own Duo, but a test build has no scheme (`bundle.sh`: only the main checkout's build registers `duo2`).

Geoff's click in Duo's terminal mode (2026-10-24): links 6 (`duo2://`) and 7 (`https://`) weren't links and couldn't be clicked, as the spike predicts. A bare `https://` URL may still open with ⌘ held, through SwiftTerm's own URL detection, but that wasn't tested.

### Duo's chat mode

`ChatMarkdown.inline` parses with Foundation's Markdown parser. A Swift spike confirmed that all four forms become links: `duo2` and `claude` with their schemes, `https`, and `#local_…` with no scheme. A click goes `ChatView`'s `openURL` → `openChatLink` → `openLink`:
- `duo2://session/<id>` → `openSessionLink`: it focuses the session's tab, resumes it if it's closed, offers explain-and-fork if it's open in another app, and says so if the id is unknown (DL-87, shipped). The same route serves notes.
- `https://…` → a Duo browser tab if the site is allowed, otherwise the default browser.
- `claude://…` → the system, which means the Claude desktop app.
- `#local_…` → read as a file name next to the project; Duo says "local_… isn't there". Harmless, and useless.

Duo lists sessions by their Claude Code session id, including ones the desktop app or `claude --bg` runs (126 in Geoff's list today, with this session among them). So `duo2://session/<id>` resolves for nearly any session the director names.

Geoff's click test in chat mode didn't happen: opening this background session in Duo's chat mode showed a fully blank pane (F-367).

### The Claude desktop app (Code tab)

- The app gives its own sessions ids of the form `local_<uuid>`. That id isn't the Claude Code session id: each record under `~/Library/Application Support/Claude/claude-code-sessions/<account>/<org>/local_*.json` carries `cliSessionId`. The director's record, for one, is `local_634397ac…` → `60d72656…`.
- The app's own system prompt for its sessions says: "Link a session whenever you mention one … `[its title](#local_<id>)`". The `claude://` scheme serves `claude://claude.ai/…`, `claude://code/new`, `claude://code/continue?session=last` and `claude://code/needs-input` (from the app bundle).
- Background workers (`claude --bg`) have no `local_` record. The app shows them from `claude agents`, so there's no `local_` id to link to.

Geoff's clicks, reading this background session in the desktop app (2026-10-24):

| # | Link | Result |
|---|---|---|
| 1 | `#local_<id>` of a desktop session | not drawn as a link |
| 2 | `claude://claude.ai/epitaxy/local_<id>` of the same session | a link; clicking it did nothing |
| 3 | `#local_<cli id>` of a `--bg` worker (a guess) | not a link |
| 4 | `claude://…/epitaxy/local_<cli id>` of the worker (a guess) | a link; clicking it did nothing |
| 5 | the worker's Remote Control URL `https://claude.ai/code/session_…` | a link, and it worked |

These clicks were in a background session's view. `#local_` may still work in a desktop-hosted session's own chat, where the app's prompt asks for it, but it can't name a background worker either way.

### The phone (Claude app, Remote Control)

A Remote Control URL is the address the app itself gives a session with Remote Control on. The director console already sends Geoff to sessions with these URLs on his phone. The click sheet included links 5 and 7 for the phone, and Geoff's phone results are asked in Q-236. A `duo2://` link on the phone has nowhere to go: no app on iOS claims the scheme, so it's dead.

### Can the director tell where it's hosted?

The environment says only part of it:
- **Duo:** `DUO_SESSION_ID` is set, and Duo strips `CLAUDE_*`.
- **Desktop app:** `CLAUDE_CODE_DESKTOP_APP_VERSION` and `CLAUDE_CODE_HOST_SESSION_ID=local_…` are set. But a `--bg` worker started from a desktop session inherits both: this session has the director's `local_634397ac…` and `CLAUDE_CODE_CHILD_SESSION=1`.
- **Remote Control on:** `CLAUDE_CODE_BRIDGE_SESSION_ID=session_…`.

None of this says where Geoff is reading right now. A director with Remote Control is read on the Mac and on the phone at once, so one reply has to work in both. That rules out a form chosen per host.

### A side observation

Geoff couldn't see links that sat in a text block just before an AskUserQuestion while it was open, in the view he was using. Links meant to be clicked should go in a message on their own, not in the lead-up to a question.

## Options (Q-236)

**A, recommended: Remote Control links everywhere, and Duo opens them in Duo.**
- Skill: a session name is `[name](<Remote Control URL>)`, or the plain name when the session has none. `duo2 session link <id>` gains the URL (`--remote`, or a `remote` field in its `--json`), so the director doesn't have to read transcripts. `duo2 director status` lists it per worker.
- Duo (ENH-270): `openLink` maps `https://claude.ai/code/session_<bridge id>` to a session it knows, by the `bridge_status` / `remote_session_change` lines in the transcripts it already reads, and opens it as for `duo2://session/` (F-366's route). An unknown one goes to the browser, as now. The terminal sets `FORCE_HYPERLINK=1` and overrides `requestOpenLink` to send links through the same `openLink`. That's one route for chat, terminal and notes, and it works in a test build without the scheme.
- Works: the desktop app (tested, link 5), the phone, and a browser. In Duo, it opens in Duo once ENH-270 is built.
- Cost: a short skill rule, plus the Duo work. No new surface. Links in the terminal show their title only (OSC 8), the usual look in iTerm or Ghostty.

**B: write the link for the host.** `duo2://session/<id>` when `DUO_SESSION_ID` is set, and the Remote Control URL otherwise. It needs no Duo change beyond `FORCE_HYPERLINK=1` for terminal mode. But a director in Duo with Remote Control then sends dead links to the phone, and the skill text grows.

**C: skill only, now.** Remote Control links, with no Duo change. Links open in the browser from Duo (or in a Duo browser tab if `claude.ai` is an allowed site), and do nothing in Duo's terminal mode. It's a quick first step toward A.

Either way, `#local_` and `claude://` links aren't worth writing: they did nothing in the test, and background workers don't have the id.

## Q-237: a link to a session that's live somewhere else

Most of a director's workers are `--bg` sessions, running outside Duo. Today a Duo session link to a live session gives explain-and-fork (DB-3), not the running session. Should a link to a running worker open its transcript read-only in Duo, or keep explain-and-fork? A read-only view would need a design round first, since it's a new visible state.
