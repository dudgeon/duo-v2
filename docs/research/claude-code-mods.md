# Can Duo bundle its own Claude Code mods?

Research for Geoff's ask of 2026-10-10: *"Claude Code recently shipped “mods”; can a client app like Duo easily and reliably bundle its own mods that would appear in the terminal (or chat?) view in Duo? I don't know how these are pushed to the user's computer and what our pattern would be."* MODS session, branch `research/claude-code-mods`. Docs only; nothing was built. Records: F-279, F-280, C-78, Q-176, ENH-70.

**Short answer.** Yes, easily, and the way Duo already passes hooks fits. Duo can ship a mod inside the app and add `--plugin-dir <folder>` to the sessions it starts, beside the `--settings` file it already passes. That needs no install, no consent and no change to `~/.claude`, and it was proven against the real 2.1.296 TUI. The catches:
- The mod API is early access and "may change between releases without notice".
- Mods need Claude Code 2.1.287 or later, so the work Mac (2.1.219) has none.
- An organization can turn off mods it didn't ship (`allowManagedModsOnly`).
- Anything a mod draws appears only in the terminal view, never in chat.

The real use is not drawing. It is a structured feed of state from inside Claude, which could replace the parts of chat mode that read the screen.

## 1. What mods are (facts)

Sources opened:
- the installed CLI, 2.1.296 (`claude --version`), and its `--help`;
- the official CHANGELOG (`raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md`, fetched 2026-10-10);
- the CLI's built-in `plugin-authoring` skill, loaded in this session: its SKILL.md, `reference.md`, `examples/`, and `types/claude-code.d.ts`, the 21,461-line API declaration the engine writes;
- strings in the CLI binary.

**The name is right.** "Mods" is the product name (changelog 2.1.287: *"Added Claude Mods: plugins may now modify deeper behavior"*). The docs and the code call them *plugins of function hooks*: `functionHooks` in the binary, and "plugin authoring" in the skill. That skill's description: *"Make a mod: a change to Claude's own interface or behaviour, such as a live pane or panel, a band above the prompt, a status line, a toast, a slash command, or a hook on tool calls or prompts."*

**Shipped in 2.1.287.** The first mention of mods anywhere in the changelog is that entry. Releases 2.1.288 to 2.1.296 carry about 60 mod fixes and additions. The first built-in mod is "You should know" (`/plugin enable cc-plugin-you-should-know@builtin`). Installed here: 2.1.288 to 2.1.296.

**What a mod is.** A mod is a plugin folder with three files:
- `.claude-plugin/plugin.json`, the manifest;
- `hooks/hooks.json`, holding `{ "modules": ["./register.tsx"] }`;
- a TypeScript or JavaScript ES module that exports `register(on, options)`.

`on(event, matcher?, ($, e, next) => …)` hooks an event. `next(e)` passes it on to the engine, a rewritten `e` changes it, and an answer without calling `next` replaces it. The module runs in its own sandboxed environment (no DOM, no Node) and reaches everything through `$` (reference.md §"What a plugin of function hooks is").

**What a mod can change.** The events are `tool.call`, `tool.check`, `prompt.submit`, `prompt.fill`, `prompt.compose`, `prompt.autocomplete`, `ui.render` and the other UI events, `command.run`, `session.start`, `session.append`, `session.end`, `turn.start`, `turn.step` and `turn.complete`, `agent.spawn`, `telemetry.*`, and the classic settings hooks as `classic.<Event>`. The nouns on `$` are:
- `ui`: status, toast, notify, log, ask, open a pane, selection, copy;
- `prompt`: fill or submit a prompt;
- `session`: messages, append, version;
- `tool` and `agent`: register a tool or an agent type the model can call;
- `command`: register a slash command;
- `model`: complete, fork;
- `fs`, `process`, `http`, `env`, `store`, `state`, `clock`, `settings`, `audio`.

What it can draw (`ui.render` components, `types/claude-code.d.ts` ≈ lines 9771–10340):
- `AbovePrompt`, a band above the input;
- `Pane`, a docked or inline panel;
- `PromptHint`, the dim hint line, with `isDraft` and `isWorking`;
- `SessionMode`, the footer's mode labels;
- `Spinner`, `UserMessage`, `AssistantMessage`, `ToolUse`, `ToolResult`, `ToolGroup`, `CommandOutput`, `AskUserQuestion`, `InfoNotice` and `TurnDuration`.

The drawing surfaces are `terminal`, `desktop`, `vscode` and `mobile`.

**How a mod is installed and found.** These are all the routes, from reference.md, `--help` and the changelog:

| Route | Scope | Notes |
|---|---|---|
| `claude --plugin-dir <folder or .zip>` (repeatable) | that session only | Watched and hot-reloaded in an interactive session (reference.md "Developing one"). The flag itself has been there since 2.1.74 or earlier, for classic plugins. |
| `CLAUDE_CODE_PLUGIN_DIRS` | process env, or the `env` block of `~/.claude/settings.json`; never a project's settings | Same as `--plugin-dir`, for hosts that can't pass flags. |
| `--plugin-url <url>` | that session | Fetches a .zip. |
| Marketplace: `/plugin install <mod> --marketplace <owner>/<repo>`, or `claude plugin marketplace add <folder or git>` then `claude plugin install` | user, project or local scope (`enabledPlugins` in settings) | The person is asked "Add marketplace?" and picks a scope. A folder marketplace is read in place; any other source is a copy updated by `claude plugin update` and `/reload-plugins`. |
| Skills folders: `~/.claude/skills/<name>`, or a project's `.claude/skills/<name>` holding a plugin manifest | user or project | Auto-loaded and watched. |
| A session's dev-mods folder, `~/.claude/dev-mods/<session>/` | that session | Used only while the plugin-authoring skill is writing a mod. The person is asked "Enable hot reloading for this session?". |
| Managed settings | the organization | Its plugins take a "managed seat" ahead of the user's. |

**Updates and trust.**
- *Updates:* an installed plugin updates through its marketplace. A `--plugin-dir` folder simply is the code, re-read on each save.
- *Gates:*
  - *Workspace trust:* a session in an untrusted folder holds hooks modules back (`loadHooksModulesHeldForTrust` in the binary).
  - *The org policy* `allowManagedModsOnly` refuses mods the organization didn't ship. The binary's message is "mods are limited to your organization's by policy (allowManagedModsOnly); … was not loaded".
  - *A guard against overriding deny rules:* `allowModsToOverrideDenyRules` is named in the binary.
  - *A remote switch:* `claude plugin test` can report "installed mods are turned off remotely".
  - *Suppressing flags:* `--safe-mode` and `--bare` turn customizations off.
  - *A crash breaker:* "mods that run in the hooks worker are off for this session: it crashed N times".
- *Stability:* the API is labelled early access in the types' header ("may change between releases without notice"), and reference.md says "the declaration file is the authority".

**How mods relate to the other extension points.** A mod is a kind of plugin. The same `plugin.json` folder can also hold the classic parts: skills, commands, agents, command hooks in `hooks.json`, MCP servers and output styles. A mod hooks the classic settings hooks too (`classic.Stop` and the like), and its `$.ui.status` line is separate from the `statusLine` setting. Today's `statusLine` is a shell command that gets session JSON on stdin and prints one line; it has existed since 1.0.71. Output styles change the system prompt, not the TUI.

## 2. What Duo already does here

- **Launch** (`Sources/DuoKit/Terminal/Terminals.swift`):
  - Every session gets `--session-id`, or `--resume` (with `--fork-session` for a fork).
  - `--settings <support>/events/<id>.settings.json` and `--append-system-prompt <primer>` (lines 189–197).
  - `--remote-control` when the CLI offers it (DL-128).
- **Hooks are per session and touch nothing global** (`Sources/DuoKit/Live/HookEvents.swift`, LR-55):
  - A perl one-liner logs `SessionStart`, `UserPromptSubmit`, `PermissionRequest`, `PostToolUse`, `Notification`, `Stop` and `SessionEnd`, plus chat's extra events on 2.1.152 and later (DL-118).
  - `PreToolUse Edit|MultiEdit|Write` runs `duo2 hook pre-edit` (DL-78), and `duo2 hook context` adds context (DL-116).
  - The settings also allow the control socket in the sandbox (DL-43).
- **Environment:**
  - Duo strips every `CLAUDE_*` variable except `CLAUDE_CONFIG_DIR` (line 93, F-17). So a `CLAUDE_CODE_PLUGIN_DIRS` exported in the user's shell does not reach Duo's sessions; one in `~/.claude/settings.json` does.
  - `EDITOR` and `VISUAL` are `duo2 compose`, the Ctrl+G bridge (F-104, F-112).
- **The install step** (`Sources/DuoControl/Installer.swift`, DL-74/75, with consent through one sheet) writes three things outside Duo's folders:
  - a block in `~/.claude/CLAUDE.md`;
  - `~/.claude/skills/duo2/SKILL.md`;
  - the `~/.local/bin/duo2` link.

  It never edits `settings.json`.
- **Chat reads the screen as well as the transcript** (DL-118, DL-143, DL-168; `Sources/DuoKit/Chat/ChatScreen.swift`):
  - From the screen it finds the input box between the last two full-width rules, and takes **the two rows under the last rule** as the footer, where it reads the mode (`auto mode on`, …) and busy (`esc to interrupt`) (line 323).
  - It recognises dialogs by their titles and numbered rows.
  - From the transcript it takes text, tools and `local_command` rows.

**How a mod breaks chat's screen reading, and the guard.** A mod's `$.ui.status` line is drawn *under the input box, above the mode row*. With two of them, the row holding `esc to interrupt` moves to the third row under the rule, outside Duo's two-row window (F-280, screens `busy0` vs `busy2`). Chat would then read busy as false and the mode as unknown while Claude works.

This is true **today, for any user who installs mods**, whether or not Duo ever ships one (C-78). The other ways a mod changes the screen:
- An `AbovePrompt` band adds rows between the transcript and the input box, with a `[-]` mark.
- A `UserMessage`, `AssistantMessage` or `ToolUse` hook can redraw transcript rows. Chat takes content from the transcript file, so it isn't fooled, but the terminal and chat then show different things.
- A `PromptHint` or `SessionMode` hook can reword the very lines chat matches on.

The guards:
1. Find the mode and busy rows by their content anywhere below the input box, not by a fixed offset.
2. Once Duo has a mod of its own, take busy, the mode, the draft state and open dialogs from it as structured data, and keep the screen as the check DL-118 asks for.
3. Fall back as today when the two disagree.

## 3. Options for shipping Duo's mods

The table compares the routes. Rows with ✔ or ✘ are the main claims; the notes say why.

| | **A. In Duo.app, `--plugin-dir` per session** (recommended) | B. Install into `~/.claude` (local marketplace, user scope) | C. A public Duo marketplace on GitHub | D. Project files (`.claude/skills/<mod>`) | E. `CLAUDE_CODE_PLUGIN_DIRS` set by Duo |
|---|---|---|---|---|---|
| How | The app bundle carries `Resources/mods/<mod>/`. At launch Duo copies it to `<support>/mods/<build>/`, and `hookArgs` adds `--plugin-dir`. | `claude plugin marketplace add <support>/mods`, then `claude plugin install duo-…@duo`, from the install sheet | Users type `/plugin install` | Duo writes a plugin into each project | Duo sets the variable in its child environment |
| Reliability | ✔ Proven (F-280); the same pattern as `--settings` | ✔ Works, but passes the user's plugin policy checks | Same as B | Watched and auto-loaded, but lives in the user's repo | ✔ Same loader as A; Claude processes started inside the session inherit it too |
| Updates with Sparkle | ✔ The new build copies new mods. A versioned folder keeps a running session on the version it started with (the folder is watched; reference.md) | A folder marketplace is read in place, but sessions need `/reload-plugins` | ✘ Separate from Duo's version | On the next write | Same as A |
| Uninstall | ✔ Nothing to remove: deleting Duo removes it | `duo2 uninstall` must run `claude plugin uninstall` | The user does it | Leaves files in repos | Same as A |
| The user's own mods | ✔ Load side by side (two `--plugin-dir`s, proven); installed plugins load too, since `~/.claude` is shared | Side by side | Side by side | Side by side | Side by side |
| Sessions started outside Duo | Not reached, by design, like Duo's hooks | ✔ Reached, but no Duo socket there, so the mod must do nothing | Same as B | Reached in that repo | Not reached |
| Consent (DL-75) | None needed: nothing global changes (LR-55) | A new line on the install sheet | Not ours | ✘ Writes into user folders | None |
| Work Mac (2.1.219, managed) | Inert: no mods before 2.1.287; gate on the version, as chat gates its events. `allowManagedModsOnly` would refuse it, so detect that (no `session.start` line) and go on as today | Same, plus `strictKnownMarketplaces` may block the marketplace | Likely blocked | Same as A | Same as A |
| Terminal view vs chat | Drawing shows only in the terminal. Slash-command replies reach chat as `local_command` rows (proven). Data reaches Duo through files or `duo2` | Same | Same | Same | Same |

**Why A.**
- It is the pattern Duo already uses for hooks: per session, by flag, nothing global.
- It needs no question, and it updates and uninstalls with the app.
- It can't affect sessions outside Duo.

Two details came out of testing:
- **Never point `--plugin-dir` inside the signed app.** An interactive session writes `tsconfig.json` and `.claude-plugin/types/` into the folder at each load (F-280). That would break Duo.app's seal. A read-only folder loads fine and gets nothing written. A copy in Duo's support folder avoids both problems.
- **Gate on the CLI.** Pass the mod only to 2.1.287 and later. Version detection already exists for chat (`.v2_1_291`) and for `--remote-control`. Whether 2.1.219 rejects or ignores a plugin whose `hooks.json` holds only `modules` was not tested (Q-176), so don't find out on the work Mac.

**Rejected.**
- **B** is only worth it for a mod that is useful outside Duo, and none of the candidates below is.
- **C** cuts mod versions loose from Duo's.
- **D** puts Duo's code in users' repos.
- **E** works, but leaks into nested `claude` runs. A flag is explicit.

## 4. Is there a real use?

Yes: one mod, used as a sensor rather than a decoration. Duo has its own UI, and anything a mod draws shows only in the terminal and changes the screen chat reads. The value is what a mod can *tell* Duo, from inside the engine, in structured form, without screen-scraping.

1. **`duo-signal`: a state feed for chat (ENH-70).**
   - *What it does:* on each event it writes a JSON line to Duo's events file (`$.fs.write`), or reports through `duo2` (`$.process.run`). The events:
     - `session.start` (the version);
     - `turn.start` and `turn.complete`, and `turn.step` for streaming;
     - `tool.check`, the permission question and its `ceiling`;
     - the `AskUserQuestion` render props;
     - `PromptHint.isWorking` and `isDraft`;
     - the `SessionMode` labels.
   - *What it buys over today:*
     - busy, mode and "is the input empty?" without reading the footer, which is C-78's break and part of C-75's guard;
     - one process instead of a perl fork per event (F-23's interleaving);
     - dialog structure straight from the engine.
   - The probe already does the first half. Its `events.jsonl` held `session.start`, `turn.start` and `turn.complete` lines.
2. **Prompt delivery without Ctrl+G.** `$.prompt.fill({ text, mode })` and `$.prompt.submit` put words into Claude's prompt from inside the engine. That could replace the `EDITOR` shim and paste-on-send (F-104, C-75).
   - *Open:* how Duo tells the mod to do it. Options are a `$.clock.every` read of the compose file, or a `/duo-send` command typed by Duo.
   - It needs its own spike before anyone counts on it.
3. **The DL-78 edit guard as a `tool.call` hook.** Today it is a `PreToolUse` command that starts `duo2` on every edit. A mod hook is lighter and can say why it refused. But the command hook must stay for older CLIs and for policies that block mods, so it is a second path, not a replacement. Low value.
4. **A Duo status line or band in the terminal.** It is possible (proven), but it is new visible design (CLAUDE.md: never invent a design) and it adds rows chat must read past. **Not recommended** unless Geoff wants the terminal view to show Duo's context. If he does, it is designed on the canvas first.

## 5. Proof (F-280)

The probe was:
- the real `claude` 2.1.296 TUI on a PTY with a headless xterm mirror (the chat spike's `drive.mjs`);
- the spike's mock Messages API with a dummy key;
- a scratch `CLAUDE_CONFIG_DIR` and workspace;
- `--model claude-haiku-5-5`.

No credentials and no tokens were used. `~/.claude` and Geoff's Duo were not touched, and everything ran in the background. The probe mod `duo-probe` (status line, band, `/duo-ping`, and an events file through `$.fs.write` to `$DUO_PROBE_OUT`) passed `claude plugin validate`.

| Run | What it showed |
|---|---|
| `--plugin-dir duo-probe` | Loaded with no install and no question. The band `duo-probe band [-]` sits above the input box. The status line `⚠ duo-probe: duo-probe: ready` sits under the box, above `⏵⏵ auto mode on`. `/duo-ping` answered `⎿ duo-probe: pong from duo-probe`. The events file had `session.start` (2.1.296), `turn.start` and `turn.complete`. |
| The transcript | The command and its reply are `type: system, subtype: local_command` rows (`<local-command-stdout>duo-probe: pong from duo-probe</local-command-stdout>`). The band and the status line are not in it. |
| `CLAUDE_CODE_PLUGIN_DIRS=<mod>` and no flag | The same result. |
| Two `--plugin-dir`s, the probe plus a stand-in user mod, during a turn | Two status rows, then `⏵⏵ auto mode on … · esc to interrupt …` on the **third** row under the rule. With no mods it is the first row. This is C-78. |
| The mod folder after an interactive load | The engine wrote `tsconfig.json` and `.claude-plugin/types/{claude-code,claude-code-tools,claude-code-mcp}/index.d.ts` into it. |
| A read-only copy of the mod (`chmod -R a-w`) | Loaded and worked the same, and nothing was written. |

Not proven:
- 2.1.219 given such a folder (Q-176);
- a managed `allowManagedModsOnly` machine; the policy text comes from the binary;
- behaviour under the real CLI login rather than an API key. The 2.1.290-era fix "mods staying off for people who reach Claude through a gateway" suggests login type matters to availability, and the mock run shows an API-key session gets them.

The scratch harness (`run-probe.sh`, the steps files and the probe mods) was kept in the session's job folder. It was not committed, because nothing was to be built.

## 6. Decisions for Geoff (Q-176)

1. **Pursue a Duo mod at all, now?** The API is early access and moves every release, and the work Mac has none.
   - *Recommendation:* yes, as one small post-v1 spike, `duo-signal` (ENH-70). It must be optional: Duo works exactly as today when it is missing, refused or broken.
   - *Either way:* fix C-78 (chat's fixed two-row footer). Users' own mods break it today.
2. **How to ship it.**
   - *Recommendation:* option A. It lives in Duo.app, is copied to Duo's support folder, is passed by `--plugin-dir` to sessions on 2.1.287 and later, and needs no install question.
   - *Alternative:* B. It installs into `~/.claude` through the install sheet, and only if a mod should also run in sessions outside Duo.
3. **Should a Duo mod ever draw in the terminal** (a status line, a band)?
   - *Recommendation:* no for now. It stays an invisible sensor. Anything visible goes through the design canvas first.
