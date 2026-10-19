# GitHub issues triage, 2026-10-19

Nine open issues on `dudgeon/duo-v2`: three from Geoff (#12, #13, #14) and six from IOGamesUS (#4, #5, #6, #8, #9, #11). #7 (Windows) is closed: Geoff answered it. Nothing on GitHub was touched. Code facts were checked against `origin/main` 8bf73fd (0.2.17).

## 1. Top: what I'd do next

1. **#12, tell agents that Duo tasks exist.** Every new project hits this: Claude writes a `TASKS.md` that Duo can't see. The fix is agent-facing text plus one CLI flag, with no visible design. Size S–M, Sonnet.
2. **#5 and #6 may be one bug, already fixed.** Both were filed on 2026-10-15. 0.2.13 (2026-10-13) started terminals through `duo-exec`, so each shell and each Claude became its own privacy (TCC) subject (DL-185, F-302). A shell in a project under Documents, Desktop or iCloud then can't read its parent folders. That gives exactly `getcwd: cannot access parent directories: Operation not permitted`. A Claude session in that state couldn't read other repos on disk either. 0.2.14 put Duo back as the responsible process (DL-190, F-306), 14 hours later. **Field evidence first:** ask the reporter for their Duo version (About Duo, or `duo2 doctor`), the project's path, and the exact error Claude got in #6. If they run 0.2.14 or later, it's a different bug and needs a real root-cause (Opus).
3. **Shift+Return on the work Mac (ENH-67, part of #4).** Shift+Return works on current Claude Code only because it turns on the kitty keyboard protocol (2.1.288+). On the work Mac's pinned 2.1.219 it probably sends the prompt instead. LR-16 marks this a Must. Size S, Sonnet. Needs one real keypress on 2.1.219.
4. **#14, `/branch` and `/fork` replace the open tab.** Today Duo follows the new session id in the same tab, so the original disappears from the console (F-174). Geoff wants both kept. This needs a short design round (how a fork shows in the sidebar), then a build. Size M.
5. **#13, per-turn actions in chat.** Nothing is drawn yet. It needs a design canvas first, and its Fork action depends on #14.

**Hurting users now:** #12 (every new project), and #5/#6 if the reporter is on 0.2.14 or later. ENH-67 hurts Geoff on the work Mac if the guess about 2.1.219 holds.

## 2. Geoff's issues, prioritised

### P1: #12, agents can't tell Duo tasks exist

- **Ask:** when asked to "create tasks", Claude should make Duo task notes, not `TASKS.md`.
- **State: not built.** The issue's diagnosis matches the code:
  - The primer (`DuoAction.primer()`, `Sources/DuoControl/Actions.swift:584`) lists only the `everyday: true` verbs. No task verb is everyday (`taskNew`, `Actions.swift:237`).
  - The CLAUDE.md block (`Installer.block()`, `Installer.swift:50`) never says "task".
  - The skill's trigger description (`Installer.swift:70`) never says "task". Task verbs appear only in the generated Families line.
  - The hook (`duo2 hook context`) speaks of tasks only when the session is already linked to one (DL-116, `TaskContext.swift:69`).
  - `duo2 task new` always switches to the project and opens the note (`AppModel+Tasks.swift:57`). An agent making 17 tasks would open 17 notes, so it writes the files by hand. It has no `--no-open`, `--status` or batch mode.
  - The project template (`Templates.swift:33`) doesn't mention tasks.
  - The `productivity:task-management` plugin advertises `TASKS.md`, and nothing from Duo competes with it.
- **Decided:** DL-87/DL-93 (tasks are notes; `sessions:` is membership), DL-116 (a linked session knows its task), DL-71 (verbs). There is no record about unlinked agents.
- **Design round:** no for the agent text. The flag changes nothing visible. A "Tasks" line in the PROJECT.md template, or a `tasks/` stub, is visible to people and would need Geoff's OK.
- **Size:** S–M. **Model:** Sonnet to build. The wording is short, and Geoff should see it.
- **Next step, suggested scope:**
  1. Make `tasks` and `task new` everyday verbs, so the primer lists them, with "use this, not a TASKS.md file".
  2. Put tasks in the skill's trigger and give it a short Tasks section.
  3. Make the hook say "Open tasks: n (`duo2 tasks`)" even when there are none.
  4. Add `duo2 task new --no-open` and `--status`, with batch creation as a stretch.
  5. Add a DuoChecks check that the primer and the skill mention tasks.
- **Side items from the same report:**
  - **Write intercept reads as "hook error".** F-55 already found that Claude reads the "Done:" reason correctly and doesn't retry. The label belongs to Claude Code. Low priority. A wording tweak ("Not an error: …") is cheap if Geoff wants it.
  - **`/fork` said "Workspace not trusted"** in a folder Duo had worked in for hours. There is no record of this. Needs an Opus root-cause. Did Duo's launch skip writing `hasTrustDialogAccepted`, or does `/fork` check trust differently? It belongs with #14.

### P2: #14, session fork handling

- **Ask:** a fork opens in a new tab, the original tab stays, and forks are obvious in the left pane.
- **State: partly built.**
  - Built: Duo's own forks (`duo2 session fork`, Resume as a Fork, DL-98/DL-109). `ForkLineage` folds forks into one thread row (DL-24). The group page shows "Fork of ‹name›".
  - Not built: a fork made inside the TUI (`/branch`, `/fork`). `followSessionChanges` (`AppModel.swift:~595`) re-keys the same tab to the new id, as it does for `/clear` (F-173, F-174). The original loses its tab, and its task links aren't copied (`continueTasks` only runs for `source == "clear"`).
  - The build plan puts "Thread detection for forks made inside the TUI (S11)" in v1.2. Geoff filing this may pull it forward. That needs a line in the build plan saying why.
- **Hard part:** the TUI keeps one process. After `/branch` that process **is** the fork. To keep the original "open", Duo has to start a second terminal that resumes the original id. That's a real Claude process. Never two writers (LR-8) holds, because each id gets one writer.
- **Design round:** yes, a small one. How a fork row looks in the sidebar, and which tab gets focus. DL-24's thread row may already cover the sidebar.
- **Size:** M. **Model:** Opus for the design note and the trust question, then Sonnet to build.
- **Next step:** Opus checks what `/fork` and `/branch` do on 2.1.219 and current Claude Code (do they exist, and do they emit a new SessionStart?), then puts 2–3 options to Geoff.

### P3: #13, per-turn buttons in chat

- **Ask:** each turn in chat gets Copy (the turn as Markdown) and Fork, plus other proposed actions.
- **State: not built.**
  - Chat's only copy is on code blocks (`ChatMarkdownView.swift:160`, drawn in the chat-mode handoff). DL-220's Copy is the editor's code blocks, not chat.
  - No handoff draws turn hover actions.
- **Decided:** no record. Limits that apply:
  - DL-29: don't build quick-reply buttons. "Retry" or "answer" style buttons would come close to that.
  - DL-118: chat is an overlay on the real TUI. A "Fork from this turn" would need `--resume-session-at`-style support, and on 2.1.219 that may not exist. Fork of the whole session already exists (`duo2 session fork`).
  - DL-71: every button needs a `duo2` verb.
- **Candidate actions to put on the canvas:** Copy turn as Markdown. Copy as plain text. Fork the session here (whole-session fork first). Reveal in terminal (scroll the TUI to the turn). Send to another session (it exists as a verb). Quote in reply (inserts `> …` in the composer). I would leave out Retry and Edit: they rewrite history and sit close to DL-29.
- **Design round:** yes, a Design canvas with the Duo design system (CLAUDE.md "Never invent a design").
- **Size:** S for Copy, M with Fork. **Model:** Opus to design, Sonnet to build.
- **Next step:** after #14's direction is set, a canvas with 2–3 placements (hover strip, ⋯ menu, right-click). Copy could ship first on its own.

## 3. Other authors' issues (IOGamesUS, unreviewed by Geoff)

These are proposals. Geoff hasn't read or agreed to them. Conflicts first.

### #8, light/dark toggle, or follow the system: conflicts with decisions

- **Ask:** bring back dark mode or follow macOS appearance.
- **Conflicts:**
  - DL-26: "Two-tone: light chrome, dark console."
  - Build plan §3a: v1 is "light appearance only". Dark is "v1.2 and later … dark appearance (§12 Q4)".
  - DL-165: "Light only is approved (DB-29)".
  - The app pins `.aqua` (`Sources/Duo/DuoApp.swift:25`).
- **Feasibility:** good later. The views use semantic tokens, and `tokens.json` has a `darkProvisional` set marked NOT APPROVED (contrast gaps noted). A dark chrome must be designed and approved before it ships (§12 Q4).
- **Duplicates:** none. LR-63 says v1 had both themes ("both themes first-class").
- **Risk:** medium. Every screen needs a second capture and contrast check.
- **Recommendation: needs Geoff's view.** My suggestion: keep v1 light-only, and answer that dark is planned after v1. If Geoff wants it sooner, it's a design round (Opus), then an L-sized build.

### #9, rearrange panes (terminal under the editor): conflicts with decisions

- **Ask:** user-arranged layout, for example terminal docked at the bottom and editor above.
- **Conflicts:**
  - DL-23 fixes the project layout: sessions and files left, console middle, right-pane tabs.
  - DL-22 fixes the All projects layout.
  - DL-26: the screens are the literal target.
  - DL-11 defers side-by-side documents.
- **Feasibility:** possible in AppKit, but every surface, chord (DL-165 pane focus), narrow-window rule (DL-129) and capture assumes three columns. Tab reorder within a strip just shipped (DL-220). Moving tabs across panes is an open gap (Q-210 item 4).
- **Duplicates:** partly ENH-26 (drag tabs out to new windows).
- **Risk:** high. It touches the whole shell.
- **Recommendation: decline for v1, needs Geoff's view.** A cheaper middle ground for a later design round: a vertical split option for the right pane only.

### #11, terminal theming, or "noise cancellation": mostly built; theming conflicts

- **Ask:**
  - Hide commands like Cowork does, in layers: output first, then actions, then script detail.
  - Or let the user theme the terminal.
- **State: the layered view exists as chat mode.**
  - DL-118 and DL-119 define it, with a Terminal/Chat pill per tab.
  - DL-135 folds tool runs to one line, for example "Ran 4 shell commands, read 3 files". It opens per step, and output and diffs show on click.
  - The reporter may not know chat mode exists.
- **Conflicts (theming):** DL-27, "Claude Code's TUI, unmodified. Duo draws nothing inside the terminal". DL-86 (muted palette) and DL-36 (SF Mono) fix the terminal's look.
- **Duplicates:** chat mode (ENH-13, DL-135).
- **Recommendation:** point them to chat mode, and **decline** terminal theming under DL-27/DL-86. Let Geoff see this first. A third "script detail" layer is already one click (a step opens to its output). Not worth more.
- **Possible gap:** chat mode isn't easy to find. Making it the default for new sessions would be Geoff's call; today it's "the mode you used last" (DL-119), and Home opens in chat (DL-142).

### #5, new shell can't read its folder (`getcwd … Operation not permitted`): take up, evidence first

- **Ask:** the shell button should open in the project folder and work.
- **What the code does:** `newShell()` (`Shells.swift:20`) starts `$SHELL -l` in the project's live folder, or home. It isn't sandboxed, and the app isn't App Sandboxed.
- **Likely cause:** 0.2.13's `duo-exec` (DL-185, F-302). It made the shell its own TCC subject, so a shell inside a protected folder can't read its parents. Fixed in 0.2.14 by DL-190. The timing fits: filed 2026-10-15, two days after.
- **Feasibility:** fine. If it's still there on 0.2.14 or later, suspect a project under Documents, Desktop or iCloud where Duo itself was denied Files and Folders access.
- **Evidence to ask for:** the Duo version; the project path; System Settings › Privacy & Security › Files and Folders for Duo; whether Claude sessions in the same project can run `ls ..`.
- **Recommendation: take up**, starting with a version check. Opus root-causes only if they're past 0.2.14.

### #6, Claude can't look at other repositories: needs information

- **Ask:** as in v1, Claude should be able to read and explore other GitHub repos.
- **What the code does:** Duo adds no host or folder limits. The only `sandbox` key it sets is the socket allowance (`HookEvents.swift:65`, DL-43/DL-51). It removes `CLAUDE_*` env vars except `CLAUDE_CONFIG_DIR`.
- **Likely cause:** "Other repositories" could mean local clones (the #5 TCC cause, if on 0.2.13) or remote repos via `gh` or WebFetch. For remote repos, the cause is the user's own Claude sandbox or permission settings, not Duo.
- **Duplicates:** probably #5's cause, if local.
- **Recommendation: needs information** before any work. Ask for the version, the exact prompt and error, and whether `/sandbox` is on. Don't build anything yet.

### #4, keyboard shortcuts: split it

- **Shift+Return for a new line.** LR-16 (Must) and ENH-67.
  - It works on current Claude Code through the kitty protocol.
  - The chat composer already does it (`ChatComposerView.swift:634`).
  - It's likely broken on older Claude Code, the work Mac's 2.1.219 included.
  - **Take up** (top item 3).
- **Ctrl+C to interrupt.**
  - The terminal passes ^C through (SwiftTerm default). What it does is up to Claude Code, not Duo. Check on 2.1.219 whether it interrupts a turn.
  - In the chat composer only Esc interrupts.
  - Mapping Ctrl+C to interrupt in chat is small, but it changes a chord (DL-34 registry). **Needs Geoff's view.**
- **⌘+ / ⌘- text size.**
  - Not built anywhere except browser tabs (DL-124).
  - The sizes come from tokens. The screens are the target (DL-26), and zoom changes every capture.
  - **Needs Geoff's view.** It's an accessibility ask, so I'd lean yes for the terminal and editor. It needs a decision and a stand-in design.
- **⌥⌫ / ⌘⌫ to delete a word or line.**
  - Duo maps neither (no `keyDown` override). SwiftTerm's Option-as-Meta default should make ⌥⌫ delete a word; I haven't checked it with a keypress.
  - ⌘⌫ (delete line) would need a mapping to ^U.
  - **Take up as a check**, S, Haiku to test and Sonnet to map.
- **Duplicates:** LR-16, ENH-67, LR-60 (one chord registry).

## Records and branches checked

DL-11, 22–24, 26, 27, 29, 34, 36, 43, 51, 71, 86, 87, 93, 98, 109, 116, 118–120, 124, 129, 135, 142, 165, 185, 190, 220; F-31, 55, 173, 174, 302, 306, 333; ENH-13, 26, 67; LR-8, 16, 60, 63; Q-210. No open branch works on any of these issues. The highest records on main today are DL-220 and ENH-232; this doc takes none.

## Geoff's answers, 2026-10-19 (by button)

- **#12:** build it, plus a Tasks line in PROJECT.md. Suggested task: `tasks/agents-know-duo-tasks.md`.
- **#5, #6:** reply with the assessment, ask them to try the current build and reopen if it's not fixed. Done: both replied to and closed as likely fixed.
- **#14:** Opus design note first. Suggested task: `tasks/fork-handling-design-note.md`.
- **#8:** dark mode sooner, starting with a design round. Suggested task: `tasks/dark-appearance-design-round.md`. The decision record (proposed DL-221) is not written yet.
- **Still open:** #9, #11, #13, and #4's Ctrl+C and text-size parts.
