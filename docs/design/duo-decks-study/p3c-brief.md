# Duo Decks P3 track C, the brief: the deck's editor pieces

Lead: duo-decks (6a39b999). A Sonnet worker in the existing worktree `/Users/geoff/repos/duo-v2/.claude/worktrees/duo-decks-editor`, branch `build/duo-decks-editor` (from origin/main 8ba74b25; nothing on it yet). Never push or touch other worktrees or main.

**Done when:** the slide chip, the template picker on ⌃⌘N, the anchor mark and `revealDeckSlot` are built to the approved handoff (DL-295, DL-296, DL-303), proven by captures in Light, Dark and Classic, with full DuoChecks passing. Report to duo-decks and director-duo-v2.

Follow CLAUDE.md:
- Xcode-free.
- Tokens only: no raw hex in Swift views. The editor page takes its colours from the theme the editor already injects.
- Every UI action has a duo2 verb, or is listed in `Parity.uiOnly` with why.
- Build to the screens, and prove it with captures compared region by region.

Builds, DuoChecks and captures run only under `GPU_LOCK=/Users/geoff/repos/duo-voice/.gpu.lock GPU_LOCK_MAX_MIN=40 /Users/geoff/repos/duo-v2/scripts/gpu-lock.sh --shared p3c <cmd>`, in short batches, releasing after each.

## What not to touch

- `Sources/DuoKit/Split/*` and `AppModel+Split.swift` belong to split-view-build.
- In `Vendor/codemirror`, Duo Decks' code goes in NEW files, `src/deck.js` and `src/deck-picker.js`.
- The ONLY change to `src/duo-editor.js` is the two lines agreed with md-bar-build:
  - `import { deckExtensions } from './deck.js'`;
  - `...deckExtensions(),` inside `extensions()`. It returns [] unless the doc's frontmatter has `type: deck`.
- Rebuild `dist/cm6.js` with `Vendor/codemirror/build.sh`. Never hand-edit it.
- **The Swift side:** extend the editor host (`DocumentEditor.swift` etc.) minimally:
  - to pass the deck's templates into the page: `window.duo.setDeckTemplates(json)`, with name, purpose, slots and a thumbnail data or file URL;
  - to receive picks.

## Safety (F-524: a previous run reached Geoff's real Duo)

- Live runs only on an isolated instance:
  - its own short DUO_SUPPORT_DIR, e.g. `/tmp/p3c-sup`;
  - a scratch CLAUDE_CONFIG_DIR;
  - launched with `open -g` and `env -u DUO_SUPPORT_DIR`.
- Set BOTH DUO_SOCKET and DUO_TOKEN from its `endpoint.json`.
- Set `DUO_ISOLATED=1` once duo2-isolation-guard lands.
- `duo2 status` must name your fixture project before any write. Otherwise abort.
- Quit with `kill -TERM <its pid>`.
- No visible windows. Never touch Geoff's Duo.

## Targets

- `docs/design/duo-decks-handoff/` on `build/duo-decks-viewer`: the README and `screens/P3-2-picker.html` and `.png`. Copy them in with `git show build/duo-decks-viewer:<path>` under the same path.
- Split view's `docs/design/split-view-handoff/screens/png/split-deck.png`: the 2 pt controlEdge anchor mark.
- Decisions DL-295, DL-296, DL-303, DL-281 and DL-285, in `decisions.md` on `build/duo-decks-viewer`.
- DuoDeck (`Sources/DuoDeck/`) has the parse, insert and change logic. Use it from Swift, so the behaviour matches `duo2 deck insert` and `duo2 deck change`.

## Build

Commit each as its own slice; messages end with `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`.
1. **The slide chip (DL-296, DL-303).**
   - In a type: deck document, each `<!-- slide: name -->` line becomes a widget: 22 high, a 1 pt rule above, reading "**Slide n** · name ⌄" in 11/20.
   - n is semibold in the text colour; the rest is text2.
   - The comment text is hidden, and the file is unchanged. The cursor treats the line atomically.
   - Clicking it opens the picker in change mode. Swift runs DuoDeck's change on the buffer through the editor, as one undo step.
2. **⌃⌘N, New Slide (DL-295).**
   - In a deck, it inserts a new empty chip below the caret's slide and opens the picker.
   - Typing filters. Each row has a thumbnail, the name in mono and the purpose in text2.
   - ↩ inserts the skeleton with the caret in the title. Esc removes the empty chip.
   - The list looks like the editor's autocomplete (`.cm-tooltip-autocomplete`, `.duo-fm-refmenu`).
   - Register ⌃⌘N in `Commands.swift` as New Slide, enabled only in a deck. It's a new chord adding to DL-34.
3. **The anchor mark.** A 2 pt controlEdge bar in the left margin, 8 in, radius 1, over the lines of the caret's slide. Swift supplies it from DuoDeck's parser via `window.duo.setDeckAnchor(first, last)`.
4. **Reveal.** `window.duo.revealDeckSlot(first, last)` scrolls the lines into view and puts the caret on the slot's first content line, without taking focus.
5. **Verbs and parity.**
   - New Slide uses `duo2 deck insert`.
   - The chip uses `duo2 deck change`.
   - The picker's typing goes in `Parity.uiOnly` with the reason.
6. **DuoChecks.** The pure parts (skeleton text, the chip's label, change via DuoDeck), then the full DuoChecks.
7. **Proof.**
   - Fixture: a Home (`_HOME.md`), then a project (`_PROJECT.md`) with `decks/field-trial-review.md` and `templates/decks/northwind/`, from `docs/design/duo-decks-study/samples`. Confirm through the instance's duo2.
   - Capture the chip, the picker open with "k" typed, and the anchor mark, in Light, Dark and Classic.
   - Compare with P3-2-picker.png and split-deck.png (compare.sh, pixels.py).
   - Keep the images in `docs/design/duo-decks-handoff/proof/`.
8. **Write-up.** `docs/design/duo-decks-study/p3c.md`: what's built, the comparisons with measured differences, stand-ins and requests.

Don't edit `decisions.md` or docs/plan records. Report the commits (full shas), checks, comparisons and blockers.
