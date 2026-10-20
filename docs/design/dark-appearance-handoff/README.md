# Dark appearance handoff (DL-224)

Canvas: https://claude.ai/artifact/C5VkwLWwUPpEuVA23waNJG, drawn with the Duo design system. Geoff chose on 2026-10-19, by button: **Dark B, "Ink"** (Q-220), **both a toggle and following the system** (Q-221), and **the scope as proposed** (Q-222). DL-221 started the round. Until this is built, Duo stays light only.

## Screens

Each dark screen is an approved light target with every token at its Ink value. **It settles colour only.** Layout, type and copy are the base target's, as later decisions amended it (some bases are older targets, for example the search field's label from before DL-80). Compare a dark capture with `compare.sh dark-appearance-handoff/<screen> <png>`, region by region, for colour.

| Screen | Base target | Shows |
|---|---|---|
| `allprojects-dark` | `pane-focus-handoff/pane-home` | All projects: the chrome on Ink, Home's console a step deeper |
| `project-dark` | `pane-focus-handoff/pane-console` | A project's three panes |
| `chat-dark` | `chat-mode-handoff/window` | Chat: the transcript on the console colour, Claude's card on `pane`, your bubble `chatYou` |
| `chattools-dark` | `chat-mode-handoff/tools` | Tool steps: diff fills and text, a failed step, the output box |
| `editor-dark` | `frontmatter-handoff/frontmatter-claude` | The editor after Claude changed it: `claudeEdit` |
| `sheet-dark` | `project-task-cx/03-new-a-fresh` | A sheet over the window |
| `search-dark` | `search-handoff/search-overview` | Search over the dark scrim |
| `settings-dark`, `settings-light` | `slice3-handoff/settings` | Settings with the new Appearance row, in both appearances |
| `tokens` | — | Reference: every token in light, A (not chosen) and B, and the contrast pairs |

The canvas also has every surface in Dark A, "Graphite" (not chosen), and the board for the three appearance options.

## Tokens [G]

`tokens-additions.json` gives every light token a dark value. The build replaces `color.darkProvisional` with it as `color.dark` in `build-handoff/tokens.json` (gen-tokens.py already emits `duoDynamic(light:dark:)`), then regenerates `Tokens.swift` and the design system's tokens.

- **The chrome:** `ground` #131518, `pane` #181A1E, `selected` #262A30, `rule` #2B2F36, `controlEdge` #6E7681 (3.8:1 on `pane`, 4.0:1 on `ground`, 3.1:1 on `selected`; answers §12 Q4), `text` #E6E8EB, `text2` #9AA1AB.
- **The accent:** `needsYou` #F97316, the console's orange, everywhere in dark. `onNeedsYou` is dark (#0C0D10), 6.9:1: white on that orange is 2.8:1.
- **The console sinks in dark:** `console` #0C0D10, `consoleRule` #24272D, `consoleHover` #17191D, `consoleMenuTarget` #262A30, `placeholderBarOnConsole` #24272D, `tuiInputBorder` #3F444C. **This changes the rule that console tokens are the same in every appearance:** in light they stay as they are. The terminal's background follows `console`; the ANSI palette is unchanged and every colour gains contrast on it (brightBlack 5.2:1, red 6.8:1).
- **Chat:** `chatGround` is the console colour in dark (#0C0D10), so the conversation is the deepest pane in both its modes. In light it stays `ground`. `chatYou` #22344F (text 10.2:1).
- **The rest:** `activeTint` #18222E, `menuTarget` #2E3238, `claudeEdit` #1F3A28 (a step stronger than `diffAddFill` #15291C, as in light; DL-186's provisional value, now chosen), diff, error, review-author and comment colours as listed; all text pairs are 4.5:1 or more (the `tokens` screen).
- **Overlays:** `scrim` black at 55%; Duo-drawn popover shadow black at 50%.
- Every pair Ink needs passes. Light's own gaps (`needsYou` on `selected` 4.4:1, `controlEdge` on `ground` 2.8:1) stay as approved.

## Behaviour [G]

- **Settings › General › Appearance**, the first row, above Explanations: a native pop-up, the same control as Home opens in, with **Match System** (the default), **Light** and **Dark**. Sub-line: "Light or dark, as macOS is set. Light and Dark keep Duo one way whatever macOS does." General is itself a stand-in placement (Q-177).
- Match System follows macOS live, including when it switches at sunset. Every change applies at once, with no relaunch. `Sources/Duo/DuoApp.swift` stops pinning `.aqua` and sets `NSApp.appearance` to nil, `.aqua` or `.darkAqua`.
- **duo2:** `duo2 settings appearance system|light|dark`; `duo2 settings` reports it (DL-71).
- **What turns dark:** Duo's own surfaces: the chrome, the console, chat, the Markdown editor (its CSS variables), sheets, popovers, Settings, the task board.
- **What keeps its own colours:** an HTML page, a Word document and a slide deck stay as their author made them, marks on the page included (the Word viewer's review colours keep their light values there; their dark values are for marks Duo draws on its own chrome). A browser tab gets the appearance, so a site with a dark style shows it.
- **The app icon** doesn't change (Q-81 stays open).
- **The active pane's rule** (DL-165) stays `text` on chrome panes and `consoleText` on the console, so it is light in dark.
- System-drawn chrome (traffic lights, menus, the toolbar material, the sheet's frame) is the system's own dark look.

## Not decided here

- Increase Contrast in dark: the terminal's `ansiIncreaseContrast` set still applies; the chrome has no high-contrast variant (none in light either).
- Board-by-board checks of surfaces not drawn here (task board, deck and Word bars, the properties block's menus, the idle list, the peek). They take their tokens; anything that looks wrong once built gets a stand-in and a question.
