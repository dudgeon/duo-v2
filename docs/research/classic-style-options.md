# Classic style: options, costs and a recommendation (classic-options, 2026-10-29)

Step 3 of task `classic-style-study`. A v1 user misses "the orange". Geoff wants a modular, configurable Easter egg that future features never have to think about, with no separate asset sets and no colours hard-coded around the app. This note turns the two research halves into options Geoff can decide from:
- `docs/research/style-configurability.md` (style-audit, F-414 to F-417);
- `docs/research/legacy-style-teardown.md` (legacy-teardown, F-408).

**Research and design only: nothing in the app changes.** Records: F-418 (what the prototype showed), Q-317 (the decision).

- **Canvas:** https://claude.ai/artifact/58jBVfGCNHjNcrFtaa2HVj (10 boards: recommendation, the needs-you collision, options A, B, C′, C, invocation, icon, element ranking, reference).
- **Captures:** `docs/research/classic-options/` (`<scheme>-<state>.jpg`, 1600 px wide; `crop-*` close-ups; `icon-*`; `c-settings.jpg`).
- **Prototype:** scratch branch `scratch/classic-proof` (d9c35e80), never merged. `docs/research/classic-proof/` on that branch holds the overlay and the throwaway patches.

## Recommendation

**C′: paper, the serif page, the warm terminal, soft orange for "here", and red for needs you.** Turn it on with a fourth Appearance choice, **Settings › General › Appearance › Classic**, and `duo2 settings appearance classic`.

It brings back the four things a v1 user notices first (cream paper, the serif page, the brown-black terminal, orange where you are) as one tokens block, two colour roles and one font variable. v2 doesn't change, and a feature built later is classic for free as long as it uses tokens, which a DuoCheck enforces. The app icon (D) is an optional half-day add-on.

## How the renderings were made

The style-audit's proof method, four times over:
1. `schemes.py <a|b|c|c-soft>` writes v1's values (from `globals.css` and `TerminalPane.tsx` at v0.13.8) onto v2's roles in `tokens.json`.
2. `gen-tokens.py` and `gen-design-system.py` regenerate.
3. `bundle.sh` builds; `cap.sh` captures five states in the background, light, each launch with its own `DUO_SUPPORT_DIR`. Builds and captures ran under the shared GPU lock.

The states, all sample data:
- `project`, `overview` (All projects) and `chat-text` from the design fixture;
- `video-s2-middle-0` (a terminal with recorded Claude output, and the PRD in the editor) and `video-s7-tab-md` (chat, a needs-you session, the PRD) from the video fixture. These are the only fixture states whose terminals and editor draw text in a capture (F-25).

Code the prototype couldn't fake with tokens (throwaway, scratch branch only):
- **B (`patch_b.py`):** the editor's body, heading weight and h1/h2 rules read `--duo-font-document`, `--duo-document-size` and `--duo-document-line`, with v2's values as fallback (5 rules in `duo-editor.js`). `tokenCSS()` sets them as literals. A build would emit them from a `font.document` token.
- **C and C′ (`patch_c.py`):**
  - `PaneFocusRule` reads new roles `paneFocus` / `paneFocusOnConsole` (one line);
  - the file tree's selected row uses `onSelected` (one site of about 20);
  - `AppearanceSetting` gains `.classic` (applied as aqua), so Settings could be rendered with Classic chosen.

**Measured** (pixels differing by more than 8 levels in any channel, against main at 77e9a0a6): A moved 99.4–100% of pixels in all five states. The diff was `tokens.json` and its generated files only, with no view touched. This matches the audit's 99.8%.

## The options

Cumulative tiers. Build estimates assume the audit's fix list is done as part of the work; more than half of it is worth doing for dark anyway.

| | What's in | What it costs | Debt | Guardrail |
|---|---|---|---|---|
| **A · Paper** | pane #FBF8EE, ground #F0E9D6, selected #E5DCC1, ink text #1A1410 / #7B6F58, rules #D4C8A6, console #1A1410 with v1's dark paper tones, your bubble in accent-soft. needsYou unchanged. | A `color.classic` block (25 values); gen-tokens reads a third palette; the provider answers three ways; an Appearance value and its verb; a redraw on switch (needs a spike, audit §4.3); the 11 palette leaks fixed. About 12 plumbing files and no views: ~2 days. | **Low.** Ongoing: a new colour token needs a classic value. | StyleLiteralChecks (no hex, system colour or `Color(red:)` in views or web pages; colour passes at 0 today), and a missing palette value fails generation. |
| **B · + serif, warm terminal** | A + documents in New York 16/27 (ui-serif, a system face, nothing bundled), headings 500; v1's light xterm palette. | A + a `font.document` token exported to the web; the editor's px geometry (list markers, tables, code) made relative: the render shows list item "3." wrapping because markers are sized for 13 px (fix list #6, 44 literals). Terminal palette per scheme, re-applied on switch (fix list #5). +2–3 days. | **Low–medium**, one-time. Ongoing: editor CSS uses variables. | A's check, plus a web lint (no `font-family` or px font size outside `var(--duo-*)`), plus an editor capture in classic. |
| **C′ · + soft orange here** (recommended) | B + selected = accent-soft #F2D9B8 (ink on it, ~13:1); a 2 pt orange rule over the active pane (#C66A2E, #E08F4A on the console); orange cursor; needsYou #B91C1C (#DC2626 on the console). | Two colour roles that in v2 take today's values (`text`, `consoleText`), so v2 doesn't change; one line in `PaneFocus.swift`. No text-colour role. +½ day. | **Low–medium**, nearly all of it B's. | B's checks, plus AppearanceChecks: needsYou stays at least 15° of hue and 3:1 apart from `selected` and `paneFocus` in every scheme. |
| **C · + solid orange** (v1-exact) | B + selected #C66A2E with white `onSelected` text. | The render shows the misses: "edited by Claude" and "12m" vanish on orange; a selected needs-you row puts a red glyph on orange (1.7:1, which fails C′'s guardrail); the Board, List and chat toggles go solid orange; hover shares `selected` (`ProjectPanes.swift:280`). It needs `onSelected`, `onSelected2`, glyph-on-selected, a hover role and a `.duoSelected()` modifier over ~20 sites and 53 uses: ~3 days. | **Medium–high.** Every new selectable thing must decide its colours on orange: "thinking about classic" comes back. | Forbid `.fill(DuoColor.selected)` outside `.duoSelected()`. It can be enforced, but it constrains every future row. |
| **D · App icon** (add-on) | v2's two-pane icon (DL-131) in classic values, rendered by `gen-app-icon.swift` with only its colours changed. | The script reads tokens (4 new ones); one more .icns; `NSApp.applicationIconImage` on a switch changes the Dock icon only, while Duo runs. ~½ day. | **Low.** | DuoChecks scans the icon script for `0x` literals. |

**Not offered:** shape (4 px radii, square selection, density: ~700 literals and no component layer), the project rail and "All" tile, the breathing dot, serif italic labels, orange folder icons. Each is either high debt or has no v2 equivalent. The element-by-element ranking is on the canvas's "v1 elements" board.

## The collision

v1's orange meant selection and focus; v2's orange (`needsYou`) means only "a session needs you". In classic:
- needs you moves to v1's own error red: #B91C1C on paper, #DC2626 on the console.
- Orange becomes a **surface** (a fill, a rule, the cursor), never a glyph or a word.
- Red is a **signal** (the glyph, the label, the question box, the chip), never a selection.

Shapes and the words "needs you" don't change, so colour is never the only signal. The canvas's collision board shows the chip, a selected needs-you row and a needs-you card in v2, C′ and C. In C′ the worst case (a selected needs-you row) stays legible; in C it nearly disappears.

## How she turns it on

1. **Appearance › Classic** (recommended): Match System · Light · Dark · Classic, plus `duo2 settings appearance classic`. Classic is light-only, so it's an appearance value, not a second setting. It reuses the state field, the verb, `DUO_APPEARANCE` captures and AppearanceChecks. Rendered for real from the scratch build (`c-settings.jpg`). The help line under the picker needs a Classic sentence; that's stand-in copy, in Q-317.
2. **Verb first, then visible:** the picker lists Classic only once the verb has chosen it. That makes it a real Easter egg, at the cost of one conditional.
3. **A theme file** (not recommended): `theme.json` overrides any token. It turns tokens.json into a public API.

A hidden gesture and a separate "Scheme" row were dropped: hiding code has no verb (DL-71), and a second row is only right if a classic dark exists.

## Found while building

- Native controls (checkboxes, the radio at `GitHubProjectSheet.swift:168`) keep the system accent, blue, in every scheme. A classic look can't reach them without replacing them; they're a few small marks, left as is.
- The editor's list-marker, table and code geometry is in px sized for the 13 px body, so any document size change breaks it (list item "3." wraps at 16 px). This is the web half of the audit's type finding, now seen in a capture.
- Rows use `selected` for hover too, so a strong selection colour needs its own hover role. A pale one doesn't.
