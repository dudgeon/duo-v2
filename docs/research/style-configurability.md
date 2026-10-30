# How style-guide driven is Duo v2, really? (style-audit, 2026-10-29)

Geoff's question (task `classic-style-study`): a v1 user misses the orange scheme; could a "classic" look be a modular, configurable Easter egg without separate assets, hard-coded colours, or future features having to think about it? This note is the codebase half: a quantified audit of how much of Duo's look comes from `tokens.json` and how much is written into views. A parallel worker (legacy-teardown) catalogues v1's style; a design worker turns both into options. **Research only: nothing here changes the app.** Records: F-414 (the counts), F-415 (the dark rails and what a third palette needs), F-416 (the loud-palette proof), F-417 (a shadow bug the audit found).

Method: twelve agents over the work tree at `fb1b2773` (origin/main, 2026-10-29). Seven auditors read every Swift file in DuoKit and Duo, the web side (`Vendor/codemirror/src`, `docx-viewer`, `pptx-renderer`, the HTML and JS built inside Swift), the generators, the assets and the type and shape code; four skeptics then opened every claimed `file:line` and ruled on it, and re-grepped each scope for misses. Only confirmed lines are counted below. An eighth agent ran the proof: a scratch branch with a loud palette, built and captured in both appearances (§7). Every count is a source line, not a token.

## 1. Headline

**Colour is fully token-driven; shape and spacing are not.** Across 220 Swift files and 25 web files there are **zero** raw colour literals in view code and **three** system colours used for a chrome role. Every chrome colour is one of 39 named dynamic `NSColor`s generated from `tokens.json`, and the proof (§7) shows a palette edit moving 99.8% of the pixels in the fixture states with no view touched. Type is half-driven: sizes, weights and line heights come from the 23 `DuoTextStyle`s at 401 sites, but the font family is hard-wired, 32 sites size text or SF Symbols by hand, and the web pages get no type token at all (44 literal font declarations). Shape and metrics are where the debt is: about 700 padding, spacing, stroke and radius literals, a 200-line component layer with no shared card, pill, field or selection component, and a selection shape written inline at 20 sites.

So: a **palette** swap (tiers a and b in §8) is trivial in the views and needs only a selector that the pipeline lacks today, because its one switch is `NSAppearance` (light or dark). A **type** swap is a day of plumbing (export the families and sizes, retire the hand-typed sites). A **shape** swap is a redesign, not a theme.

## 2. The token pipeline

`docs/design/build-handoff/tokens.json` is the one source. `scripts/gen-tokens.py` writes `Sources/DuoKit/Design/Tokens.swift`; `scripts/gen-design-system.py` writes `docs/design/system/tokens.json` and the glyph and icon SVGs. Web views get a subset as CSS variables from `EditorController.tokenCSS()` (`Sources/DuoKit/Editor/DocumentEditor.swift:149-171`), injected at document start and re-run when the appearance changes (`DocumentEditor.swift:853-858`).

| Category | Tokens | Becomes | Dark value | Reaches the web | Not covered |
|---|---|---|---|---|---|
| `color.light` | 30 | `DuoColor.x` (SwiftUI) and `DuoNSColor.x`, each `NSColor.duoDynamic(light:dark:name:)` | all 30 | 16 of 30 (hand-listed at `DocumentEditor.swift:162-164`) | focus ring, hover, pressed, disabled, link, scrollbar, badge (views disable the system ring and draw their own) |
| `color.console` | 9 | same | all 9 (console sinks in dark, DL-224) | none | — |
| `color.dark` | 39 | the `dark:` argument of every call; not its own symbol | — | — | a missing dark entry silently falls back to light (`gen-tokens.py:35, 51`) |
| `font.family` | 2 | **nothing**: `Typography.swift:14-22, 67-69` hard-wire `.system(...)` and `NSFont.systemFont` | — | no `--duo-font-*` variable | a family swap is impossible from tokens (and the design system forbids bundling faces) |
| `font.style` | 23 | `DuoTextStyle` with `DuoTextSpec(size, lineHeight, weight, mono, tracking, uppercase)`, applied by `.duoText(_:)` | — | none | italic, colour, a numeric variant |
| `radius` | 17 | `DuoMetric.radiusX` (15 scalars, 2 per-corner) | — | `--duo-radius-card` only | — |
| `border` | 6 | `DuoMetric.borderX` (5 widths), `DuoShadow.dashPattern` | — | none | `borderTileFocusOutline` is defined and read nowhere |
| `size` | 47 groups | 154 `DuoMetric` statics, mostly by **explicit name** in the generator (`gen-tokens.py:90-149`); 17 groups by a fixed list (`:120`) | — | none | `size.newTabMenu` and `size.propertiesBlock` are never emitted; a new top-level key needs a generator edit |
| `space` | 18 | `DuoSpace` (29 statics), paddings as `EdgeInsets`, gaps generically | — | `--duo-heading-above` only | a generic spacing scale: values are per-purpose, so a new purpose has no token and the view reaches for a literal |
| `shadow` | 2 | `DuoShadow.popover*` (dynamic) and `consoleLift*` (**fixed** sRGB, `Tokens.swift:528`) | popover only | `--duo-shadow` as a colour only (no offsets) | elevation scale |
| `glyph` | 5 | `DuoGlyphPath.x` SVG strings, **referenced by no view**; the fill and stroke token names are dropped, so `StateGlyph.swift:23-34` hand-codes the colour mapping | — | the editor re-declares the same paths (`duo-editor.js:301-305`) | — |
| `icon` | 20 | **nothing** in Swift; each mark is a hand-drawn Canvas with the viewBox and stroke width copied from the token | — | re-declared in JS | — |
| `terminal` | 35 | `DuoTerminalPalette` (16 ANSI, 16 high-contrast, cursor, selection), all `duoFixed` | **none**; re-applied only when Increase Contrast changes (`Terminals.swift:393-397`) | — | a scheme-specific console palette |
| `motion`, `motionEase` | 30 + 30 | `DuoMotion`, `DuoMotionToken` (duration and ease) | — | 4 durations as `--duo-motion-*-ms` | easing names for CSS |
| `docxDefaults` | 21 | `DuoDocxDefaults.json` for the Word page | — | as JSON | content defaults by design (Google Docs' own, DL-233) |

The generator is honest about what it does. What it does **not** do matters for a scheme: it knows exactly two palettes (`gen-tokens.py:24-26` reads `light`, `console`, `dark` and nothing else), the switch between them is baked into every generated call, and the web variable list is written by hand in Swift (and again in `scripts/check-editor-dark.mjs:15-17`).

## 3. Leaks

A leak is a style value set outside the pipeline: a colour literal, a system colour in a brand role, an opacity that invents a shade, a font not from a `DuoTextStyle`, or a padding, spacing, stroke or radius number with no token. Legitimate exceptions were counted apart: the terminal's ANSI colours (from `DuoTerminalPalette`), a document's own colours and fonts, `Color.clear`, vendored code, and debug-only drawing (`Debug/`, the gallery, DuoChecks assertions).

Confirmed by the verifiers (each scope's claims were read line by line; misses were added):

| Scope | Files | Lines | Token uses | Colour literal | System colour | Opacity shade | Font literal | Metric literal | Leaks | Tokens per leak |
|---|---|---|---|---|---|---|---|---|---|---|
| `DuoKit/Chat` | 31 | 9,123 | 548 | 0 | 0 | 2 | 6 | 233 | 241 | 2.3 |
| `Shell`, `Project`, `Navigation`, `AllProjects`, `Terminal` | 46 | 11,314 | 1,464 | 0 | 3 | 10 | 21 | 299 | 333 | 4.4 |
| `Editor`, `Browser`, `Design`, `Search`, `Git`, `Model`, `Live`, `Control`, `Debug`, `Duo` | 143 | ~28,000 | 440 | 0 | 0 | 0 | 6 | 134 | 140 | 3.1 |
| Web: `codemirror/src`, `docx-viewer`, `pptx-renderer` chrome, HTML and JS strings in Swift | 25 | ~4,000 | 214 `var(--duo-*)` | 0 | 0 | 3 | 44 | 42 | 89 | 2.4 |
| **All** | **245** | | **2,666** | **0** | **3** | **15** | **77** | **708** | **~800** | **3.3** |

Token uses in DuoKit, for the ratio: `DuoColor.` 977, `DuoMetric.` 703, `DuoSpace.` 247, `.duoText(` 420, `DuoNSColor.` 110.

By how much each leak would hurt a scheme: **11 palette-breaking**, 68 type-breaking, 41 shape-breaking, 684 minor (spacing with no token).

**The 11 palette-breaking lines**, the whole list (plus one the pipeline auditor found in the About panel):

| Where | What | Should be |
|---|---|---|
| `Shell/GitHubProjectSheet.swift:168` | `Color.accentColor` for the chosen radio, `lineWidth: on ? 4 : 1` | `DuoColor.needsYou` or `text`; a radio token |
| `Project/ProjectPanes.swift:1246` | `.foregroundStyle(.secondary)` on the element-picker bar | `DuoColor.text2` |
| `Project/ProjectPanes.swift:1260` | `.background(.bar)` system material, system `Button`s | `DuoColor.ground`, `.buttonStyle(.duo)` (the bar is a stand-in; Q-21) |
| `Shell/AboutCredits.swift:28` | `NSColor.labelColor` (and `smallSystemFontSize`) in the About credits | `DuoNSColor.text`, `pill` spec |
| `Project/DocxView.swift:121-122`, `Project/MarkdownReviewBar.swift:141-142`, `AllProjects/AllProjectsPanes.swift:1272` | three hand-rolled popover shadows: `text.opacity(0.18)` radius 12 plus a `text.opacity(0.08)` edge | `.duoPopoverShadow()`, `DuoColor.rule` |
| `Shell/ConsoleStates.swift:143` | `consoleText2.opacity(0.2)` pressed fill | `consoleHover` / `consoleMenuTarget` |
| `Browser/BrowserTabs.swift:601` | `text2.opacity(0.5)` disabled icon | the disabled convention as a token |
| `Vendor/docx-viewer/docx.html:90` | its own `0 8px 24px` shadow from `text` at 18% | `--duo-shadow` (already injected into that page) |

Everything else that bypasses the palette is in the pipeline, not the views: `DuoShadow.consoleLiftColor` is a fixed colour (`Tokens.swift:528`), `DuoTerminalPalette` has no variant, the app icon is literals (§5), and `FixtureHarness.swift:387` has a `#ccc` border in a capture-only action.

**Top offenders by confirmed leaks** (nearly all spacing and stroke literals):

| File | Leaks | Mostly |
|---|---|---|
| `Search/SearchView.swift` | 87 | stack spacings 6/8/12, frame sizes |
| `Project/TaskBoardView.swift` | 70 | `lineWidth: 1` ×12, `dash: [3, 3]` ×5 (the token is `[3, 2]`), radius 4 |
| `AllProjects/AllProjectsPanes.swift` | 57 | `.padding(.top, 6)` ×10, section headers, the tile focus outline drawn as `1 + padding(-1)` while `borderTileFocusOutline` (2) goes unused |
| `Chat/ChatReviewCard.swift` | 52 | `lineWidth: 1.5` ×7 where `borderEmphasis` is 1.5 |
| `Project/ProjectPanes.swift` | 50 | row insets `8 + selectionInset` ×6, picker bar |
| `Vendor/codemirror/src/duo-editor.js` | 41 | every font size, line height and family; `6px` radius ×13 beside `var(--duo-radius-card)` |
| `Chat/ChatToolViews.swift` | 38 | radius 3 (= `radiusChatCheckbox`), 1.5 strokes |
| `Chat/ChatComposerView.swift` | 33 | `Capsule()` pills, 9 pt mode glyph |
| `Chat/ChatView.swift` | 29 | spacing |
| `Design/Explainer.swift` | 22 | its own 10/11/12 pt text, radius 6 |

Patterns the auditors named, which explain most of the 700 and point at the cheap fixes:

- **Values that equal a token but are typed by hand.** `1.5` for `borderEmphasis` (11 sites), `[3, 3]` for the dash (5, and visibly different from the token's `[3, 2]`), radius `9` for `radiusPill` (3), `3` for `radiusChatCheckbox` (2), `6` for `radiusCard` on the web (13), `EdgeInsets` that equal `questionBoxPadding`, `cardPadding` or `pointerCardPadding` (6), `12 on a 16 line` that is `.control` (`ProjectPanes.swift:426`, with a comment saying so). About 60 Swift lines and 30 web lines are exact matches: a mechanical fix.
- **`N + 1` and `token + 1.5`.** The house way of adding the border to a CSS inset writes the border as a literal (12 sites in Chat alone).
- **Hand-drawn icons carry their SVG numbers.** ShellPromptMark, ForkMark, LockMark, FolderMark, BranchMark, ArrowMark, HomeViewMark, BoardGlyph (13 kinds), Chevron: each copies `tokens.json`'s viewBox and stroke width into Swift because the generator emits no icon symbols. Three copies of the glyph geometry exist (`tokens.json`, Swift Paths, `duo-editor.js`). The verifiers ruled these geometry rather than leaks, and they are one pipeline gap, not 30 mistakes.
- **Per-purpose spacing with no scale.** Chat stacks use 4/5/6/8/10/12/16 and never a `DuoSpace.gap*` (100 `spacing:` literals, 0 tokens); `DuoSpace` names six gaps and the views don't reach for them.
- **Web type is hand-typed everywhere** because nothing exports it: six spellings of the UI font stack and four of the mono stack coexist, none equal to `font.family.*.css`, and `13px/20px`, `12px/16px`, `11px/16px` are typed as the body, control and pill styles by value.
- **A real bug.** `margin.js:432` and `critic.js:409` write `boxShadow: var(--duo-shadow)`; the variable is a bare `rgba()` colour (`DocumentEditor.swift:161`), so the declaration is invalid and the narrow-mode thread popover and the suggestion tooltip draw **no shadow** (F-417).

## 4. The precedent: dark appearance (DL-224)

How the switch works, end to end:

1. **Choice.** `AppearanceSetting.current` (`Design/Appearance.swift:13-16`): `DUO_APPEARANCE` from the environment if set (so `check-ui.sh` can capture either), else `DuoState.appearance` (a string in the state file, `Live/HookEvents.swift:261`), else `.system`.
2. **Apply.** `AppearanceSetting.apply()` sets `NSApp.appearance` to nil, `.aqua` or `.darkAqua` (`Appearance.swift:19-25`), at launch (`DuoApp.swift:25`), from the Settings picker (`Shell/SettingsView.swift:84-88`) and from `duo2 settings appearance` (`Control/AppModel+Control.swift:434-437`; the verb at `DuoControl/Actions.swift:147`).
3. **Resolution.** Every chrome colour is `NSColor(name: "duo.<token>") { appearance in bestMatch([.aqua, .darkAqua]) == .darkAqua ? dark : light }` (`Design/ColorSupport.swift:15-20`). AppKit re-runs the provider whenever a colour is resolved for drawing, and SwiftUI resolves `Color(nsColor:)` against the view's appearance at draw time, so **no view has any appearance code**: there is no `colorScheme` read in the app outside the Settings capture harness, no KVO, no theme-changed observer, no cached resolved colour (zero `static let … = DuoColor.`, zero `Color(nsColor:` outside `Tokens.swift`).
4. **Snapshots that must be redone.** Three places copy a resolved colour out and override `viewDidChangeEffectiveAppearance` to copy again: the sheet field's CALayer (`Shell/Sheets.swift:227-239`), the terminal's background and foreground (`Terminal/Terminals.swift:305-313`; the ANSI set is not re-applied), and the editor web view, which re-runs `tokenCSS()` (`DocumentEditor.swift:853-858`). The Word and deck pages take `tokenCSS()` once and pin themselves to `.aqua` (`DocxViewer.swift:95, 100`, `DeckViewer.swift:51, 53`): a document keeps its author's colours, by decision.
5. **Checks.** `DuoChecks/AppearanceChecks.swift:16-20` asserts four tokens' hex in each appearance and that the setting has exactly three cases; `scripts/check-editor-dark.mjs` checks the editor's computed colours.

So dark cost DL-224 one tokens.json block, one generator change, one provider, one setting, one verb and three snapshot refreshes. **Nothing per view.** That is the model a scheme wants.

**Could a third palette ride the same rails with zero per-view code?** In the views, yes: changing what the 39 providers answer changes the whole app, as the proof shows. In the pipeline, not as it stands, because the only selector is `NSAppearance` and macOS has exactly two of them that mean anything (custom appearance names need a compiled asset catalog, which DL-30 keeps out). What breaks first, in order:

1. `ColorSupport.swift:17-19, 28-30`: the provider is a binary `? dark : light`; a third value has nowhere to go.
2. `gen-tokens.py:24-26, 34-36, 48-62`: reads exactly `light`, `console`, `dark`; a `color.classic` block is ignored; a token missing from a palette silently takes the light value.
3. **Invalidation.** If the scheme is a global read inside the provider, nothing redraws when it flips: SwiftUI re-resolves `Color(nsColor:)` only on an appearance or environment change, and the three snapshot sites listen only to `viewDidChangeEffectiveAppearance`. The cheap route is to make a scheme change also re-apply the appearance so every existing observer fires (accepting a relaunch, or a one-frame nudge through the other appearance). This is the one piece of mechanism nobody has built yet; it needs a spike before any option is costed as "trivial".
4. `DuoTerminalPalette` (`Tokens.swift:347-354`): fixed, no variant, re-applied only on Increase Contrast. A classic console with v1's colours needs a palette per scheme and a new trigger. If classic leaves the console alone, nothing to do.
5. `Appearance.swift:5` and everything that enumerates it (Settings picker, verb usage, control switch, `DuoState`, `check-ui.sh:27-30`, `docs/cli/duo2.md`, `AppearanceChecks.swift:20`): a scheme is orthogonal to light and dark, so it is a second setting (`duo2 settings scheme duo|classic`) and a second row, not a fourth appearance.
6. `DocumentEditor.swift:162-164`: the hand-written variable list, and the Word and deck pages frozen in aqua at creation, so classic chrome in their bars needs a re-run path they lack today.
7. `Tokens.swift:528` `consoleLiftColor` fixed; `gen-design-system.py:270` themes hard-coded to `[light, dark]`, terminal colours light-only, icon SVGs stroked with the light hex.
8. The 11 palette leaks in §3.

Files a scheme selector touches, with the palette-as-global route: `tokens.json`, `gen-tokens.py`, `gen-design-system.py`, `ColorSupport.swift`, a new `Scheme.swift` (or `Appearance.swift`), `SettingsView.swift`, `Actions.swift`, `AppModel+Control.swift`, `HookEvents.swift` (state), `AppearanceChecks.swift`, `check-ui.sh` (a `DUO_SCHEME` for captures), `docs/cli/duo2.md`. Twelve, all plumbing, none a view.

The design worker should also decide how scheme and appearance combine. The simplest honest answer: **classic is a light scheme**; choosing it forces the light appearance (one `color.classic` block, no `classicDark`), so no one designs a classic dark.

## 5. Assets

Of everything Duo draws or ships, **one asset family bakes colour in: the app icon.** Everything else is drawn at run time from tokens.

| Asset | How it gets its colour | Swap tier |
|---|---|---|
| App icon (`docs/design/icon-handoff/AppIcon.icns`, dev variant) | `scripts/gen-app-icon.swift` draws from 11 `0xRRGGBB` literals; 7 equal tokens by value (`consoleRule`, `text`, `rule`, `controlEdge`, `pane`, …), 4 have no token (`#121418`, `#E9EDF1`, `#DFE3E8`, the dev hazard `#F2C230`). One `.icns`, no dark or tinted layer (Q-81; DL-224 says the icon doesn't change). | Cheap for a re-coloured icon if the script reads `tokens.json` and the build makes one per scheme; a runtime swap is `NSApp.applicationIconImage`, no actool needed. macOS 26 tinted or clear layers need Icon Composer (expensive, and against DL-30). |
| Dock badge, notifications, Dock menu | System: `badgeLabel` is a string (`Model/AppModel+Notify.swift:15`); macOS draws the red badge. | n/a |
| Session and state glyphs (`StateGlyph`, `SessionGlyph`), Chevron, SearchIcon, ShellPromptMark, ForkMark, KeepRunningPin, TabCloseMark, BoardGlyph ×13, HomeViewMark, LockMark, BranchMark, ArrowMark | SwiftUI Canvas paths shaded with `DuoColor` at draw time; the console surface maps to `needsYouOnConsole` / `consoleText` / `consoleText2`. Never images. | Free (tint at draw time). The colour mapping is hand-coded in `StateGlyph.swift:23-34`, not read from `glyph.fill`, so a scheme that re-maps which token a state uses is a Swift edit; a scheme that only recolours the tokens is free. |
| SF Symbols | 16 `Image(systemName:)` sites, 0 `NSImage(systemSymbolName:)`; all 16 end in a `DuoColor` (direct `foregroundStyle`, the parent stack, or `DuoButtonStyle`). Sizes are `.font(.system(size: 8…14))` literals (§6). | Free for colour; size needs an icon-size token family |
| Composer file chip | An `NSImage` drawn from `DuoNSColor` at insert time | Free |
| Editor inline SVGs (checkbox, copy, 5 state glyphs, 8 property icons, chevrons, reference icons) | Every stroke and fill is `var(--duo-*)` (`duo-editor.js:28-29, 51-52, 301-310, 403-416, 581, 632-634`) | Free |
| Word viewer and deck chrome | `currentColor` and `var(--duo-*)`; 0 literal colours | Free; the content keeps its own colours by decision |
| Design-system SVG exports (`docs/design/system/assets/Glyphs`, `Icons`) | Light hex baked by `gen-design-system.py:291-306` | Cheap: regenerate per scheme, or switch to `currentColor` |
| Sparkle `ReleaseNotesColorStyle.css` | Vendored; Duo draws the update notes itself (F-406), so it never shows | n/a |
| README and guide screenshots, the intro film | Captured; show whatever palette the app had | n/a (re-capture) |

## 6. Type and shape

**Type.** 401 `.duoText(...)` sites over 23 styles (`body` 192, `control` 79, `chatMeta` 39, `bodyEmphasis` 28, `mono` 19, …; nine styles are reached only through a variable or `.spec.size`). Size, weight, line height, tracking and case swap from `tokens.json` for all of them and for 31 "half-token" sites that build an `NSFont.systemFont(ofSize: DuoTextStyle.x.spec.size)` by hand. What does **not** swap:

- **The family.** `font.family` is documentation; `Typography.swift:15, 19-21, 67-69` hard-wire SF; the terminal (`Terminals.swift:151`) and the 31 half-token sites re-hard-wire it; the web pages type it 24 times in 6 spellings; `tokenCSS()` exports no font variable. A family swap would need a `DuoFontFamily` token, `Font.custom` with descriptor weights, bundled faces, `@font-face` on the pages, and re-measuring the F-11 baseline shifts. The design system forbids it ("System faces only; don't bundle fonts", `docs/design/system/README.md:74`). If v1 used a different face, that is the first thing the design worker must argue for or drop.
- **32 literal font sites.** 16 are SF Symbol sizes (`DuoToolbar.swift:48, 65, 124, 131, 201`; `AllProjectsPanes.swift:339, 394, 435, 475, 562`; `DocxView.swift:62`; `MarkdownReviewBar.swift:35`; `BinaryFileView.swift:84`; `DeckView.swift:148`; `BrowserTabs.swift:599`; `ChatMarkdownView.swift:121`), the same chevron at 8 in two files and 9 in two others. The rest are text: `Explainer.swift:310, 343, 356, 362`; `ChatComposerView.swift:132`; `ChatReviewCard.swift:58`; `ChatPasteBlock.swift:93`; `ProjectPanes.swift:426, 730, 1225, 1246, 1250`; `TaskBoardView.swift:377, 672`; `AboutCredits.swift:27`; `BrowserTabs.swift:714`. Seven of these are an existing style typed by value.
- **The web.** 44 confirmed font declarations in `duo-editor.js`, `margin.js`, `critic.js`, `docx.html`, `deck.html`; the editor's `13px` body stayed 13 when the proof set `body.size` to 15.

**Shape.** Radii: 195 token uses against 18 literal sites (92% from tokens; `RepoBlock.swift:139-164` uses an 8 that is on no scale). Strokes: `borderHairline` 160 uses, `borderEmphasis` 10, against about 16 chrome literals and 5 off-token dashes. The web: 7 `var(--duo-radius-card)` against 24 `px` radii. A radius or stroke retune from tokens lands about nine times in ten.

**Selection.** The selected row is `RoundedRectangle(cornerRadius: DuoMetric.radiusSelection).fill(DuoColor.selected)` inset by `DuoSpace.selectionInset`, written inline at 20 sites (`ProjectPanes.swift:280, 444, 636, 741`; `SessionListView.swift:258`; `AllProjectsPanes.swift:521, 727`; `ChatComposerView.swift:154, 225`; `DocxView.swift:109, 147`; …), with three shared helpers (`SelectionRunFill`, `DropHighlight`, `MenuTargetFill`). Colour, radius and inset are tokens, so a recolour or re-rounding is a `tokens.json` edit. The **shape** (fill behind the row versus an outline or an accent bar, which is what v1 may have had) is a 20-site edit unless a `.duoSelected()` modifier is introduced first. No SwiftUI `List` selection, no `NSTableView`, no `selectedContentBackgroundColor` anywhere; keyboard focus is Duo's own (`PaneFocusRule`, fully tokenised; the tile outline at `AllProjectsPanes.swift:447, 679` draws `1 + padding(-1)` while the 2 pt `borderTileFocusOutline` token is unused). Two system colours leak into selection: the radio at `GitHubProjectSheet.swift:168` and the AppKit focus ring at `Explainer.swift:420`.

**The component layer is thin.** `Design/Components.swift` is 200 lines: `SectionLabel` (33 uses), `DuoButtonStyle` (97 uses, 11 `.plain` escapes), `Bordered` (9), `Chevron` (20), `WaitLabel`, `FlexShrinkRow`. There is no shared card, pill, chip, field, popover, row, selection fill or icon button: 216 inline `RoundedRectangle(` and 104 `strokeBorder(` across 54 view files draw them. Buttons and section labels go through a component nine times in ten; cards, pills and fields almost never. That is why colour and radius **values** swap and **shapes** don't.

## 7. The proof

Scratch branch `scratch/style-proof` (commit `2a13060a`, work tree `.claude/worktrees/style-proof`, never merged): `needsYou` magenta, `ground` pale yellow, `pane` pale cyan, `selected` gold, `text` blue, `text2` green, `rule` and `controlEdge` red, `chatYou` pink, `chatGround` yellow (light and dark blocks), `console.console` purple, `radius.card` and `radius.control` 0, `body.size` 15. Regenerated with both scripts; the diff was `tokens.json`, `Tokens.swift` and `docs/design/system` only. Built and captured six states in both appearances under the shared GPU lock, in the background with an isolated support and config folder. The captures are in `docs/research/style-proof/` (before | after | difference).

| State | Light pixels changed | Dark pixels changed |
|---|---|---|
| overview, project, flow-zoom-2, flow-zoom-4 | 99.8% | 52.8% to 76.4% (the console pane was not in the change set in dark) |
| chat-text, chat-tools | 74.2%, 62.2% (the terminal's blank area stays) | 100% |

What moved with no view touched: every pane and ground, text, rules, borders, selection, chat bubbles and cards, the tab underline, toolbars, section labels, the sidebar's body size (15), card corners (square). What did not, and why:

- The console tab strip's needs-you dot stayed orange: it is its own token (`needsYouOnConsole`), not a leak.
- The dark console stayed `#0C0D10`: `color.dark.console` is its own key, not a leak.
- Pills, the composer and the chat bubble and card corners stayed round: `Capsule()` at `ChatComposerView.swift:55, 110` and `Explainer.swift:393`, and `radiusPill`, `radiusChatBubble`, `radiusChatCard`, `radiusField` are separate tokens from `card` and `control`. Those were not changed; the capsules are a shape leak.
- The editor's body text would have stayed 13 px: `duo-editor.js:1813` types it. (No captured state shows the editor; the claim is from code, and the body-size change proves the Swift half.)
- A 1 px strip at the window's top edge kept the system window colour: the title bar, outside any token view.
- The only system colour the proof's grep found is the radio at `GitHubProjectSheet.swift:168`.

## 8. The cost model

"Future-proof" means a feature built next month looks right in the scheme with its author never thinking about it. It holds exactly where the tokens are the only way to get a value, which today is colour.

| Tier | What changes | Files touched (estimate) | Risk | Future-proof? |
|---|---|---|---|---|
| **(a) accent only** | `needsYou`, `onNeedsYou`, `needsYouOnConsole` per scheme (3 tokens, 2 appearances) | A permanent recolour: **1** (`tokens.json`, regenerate). A user-selectable scheme: the **12 plumbing files** in §4 (selector, setting, verb, state, checks, capture env) and the invalidation spike. | Low. The selector and invalidation are the only new mechanism. | **Yes**: new views use `DuoColor` (0 literals today) and the check in §9 keeps it so. |
| **(b) full palette** | all 39 chrome colours per scheme; the console palette if classic changes it; `consoleLift` made dynamic; the 11 palette leaks fixed | (a) + `Terminals.swift` (palette per scheme, re-apply on change) + the 7 leak files + `gen-design-system.py` theme list | Low to medium. Dark took one block and no view code; classic is the same shape plus a selector. The terminal palette is the one new category. | **Yes**, with the guardrail. |
| **(c) + type** | sizes, weights, line heights per scheme (already token-driven); a family only if the design argues for one | `Typography.swift`, `gen-tokens.py` (family token), `tokenCSS()` (export `--duo-font-*` and `--duo-size-*`), 5 web files (44 sites), 32 Swift font sites, 31 half-token sites, 16 symbol-size sites | Medium. Sizes swap now; the web and the family don't. A family change also moves every F-11 baseline. | **Mostly**: `.duoText` is the habit (401 to 32); the web pages need a `var()` habit they lack. |
| **(d) + shape and metrics** | radii, strokes, selection shape, paddings | 18 radius sites, ~16 stroke sites, 20 selection sites (or one `.duoSelected()` first), then ~700 spacing literals with no token to swap to | High. This is a redesign of chrome, not a theme. | **No**, not without a component layer: cards, pills and fields are drawn inline. |
| **(e) + assets and icon** | the app icon per scheme | `gen-app-icon.swift` reads tokens (4 new tokens), `bundle.sh` makes one `.icns` per scheme, `NSApp.applicationIconImage` at scheme change | Low for a recoloured icon; high for macOS 26 tinted layers (Icon Composer, against DL-30). Everything else tints free. | Yes for icons drawn in code; the `.icns` is a build artefact per scheme. |

The honest line is between (b) and (c): a classic **palette** is cheap and stays cheap; classic **type** is a day of plumbing that Duo should do anyway for the web pages; classic **shape** is where tech debt would start, because it can't be a token change.

## 9. The guardrail

What keeps "future features never think about it" true is not a rule in CLAUDE.md (there is one, unenforced: "never use raw hex in views") but a check that fails. The pieces, all small, in the order they pay:

1. **`StyleLiteralChecks` in DuoChecks.** `main.swift:1527-1532` already walks every DuoKit source to forbid `.spring(` and `accessibilityReduceMotion`; the same walk fails on a colour literal (`0x`/`#` hex, `Color(red:`, `NSColor(srgbRed:`, `NSColor(white:`), a system colour in view code (`Color.accentColor`, `.primary`, `.secondary`, `.blue`…, `NSColor.labelColor`, `.controlAccentColor`, `.background(.bar)`), a font not from a style (`.font(.system(size: <digit>`, `.font(.caption|.title|.callout…)`, `NSFont.systemFont(ofSize: <digit>`), and a dash literal. Allowlist: `Design/ColorSupport.swift`, `Tokens.swift`, `Debug/`, `DuoChecks`, the docx defaults. Colour passes today at 0 and 3; fonts fail at 32 until §10 lands, so phase it: colour now, fonts after the fix list, metrics never (report only).
2. **A web lint in the same check** over `Vendor/codemirror/src`, `docx-viewer`, `pptx-renderer/deck.*` and the HTML strings in Swift: no hex or `rgb(`, no `font-family` and no `px` font size outside `var(--duo-*)`. Colour passes today at 0.
3. **A token-coverage report**, not a gate: per file, token uses against metric literals (the §3 ratio), printed by DuoChecks and kept in `docs/design/system/`, so the number is visible when it slides.
4. **Pipeline checks.** `Tokens.swift` is current (regenerate to a temp file and diff, as `gen-design-system.py --check` already does for the design system; today nothing checks it); every colour token has a value in **every** palette (make the silent fallback at `gen-tokens.py:35, 51` an error); the web variable list is generated from `tokens.json` rather than hand-written in `DocumentEditor.swift:162-164` and `check-editor-dark.mjs:15-17`.
5. **Captures per scheme.** `check-ui.sh` takes `DUO_SCHEME` as it takes `DUO_APPEARANCE`, and the acceptance fixtures are captured in each scheme once, so a scheme regression is a pixel diff, not a bug report.

With 1, 2 and 4 in place, a new feature that uses a literal fails the check before review, and a palette is a `tokens.json` block that cannot be incomplete. That is the property Geoff asked for, and it is worth having for dark mode alone.

## 10. Fix list

Worth doing regardless of classic, because each one is also a dark-mode gap or a bug. Ordered by value.

1. **The invalid shadows** (F-417): `margin.js:432`, `critic.js:409` `boxShadow: var(--duo-shadow)` draws nothing. Export `--duo-shadow` as the full `0 12px 32px rgba()` (or add `--duo-shadow-x/y/blur`) and fix `duo-editor.js:1921, 1943` and `docx.html:90` to use it.
2. **The three hand-rolled popover shadows and edges**: `DocxView.swift:121-122`, `MarkdownReviewBar.swift:141-142`, `AllProjectsPanes.swift:1272` → `.duoPopoverShadow()` and `DuoColor.rule`.
3. **The system colours**: `GitHubProjectSheet.swift:168`, `ProjectPanes.swift:1246, 1250, 1260`, `AboutCredits.swift:27-28`, `Explainer.swift:420` (AppKit focus ring).
4. **`consoleLift` shadow**: give it a `colorDark` and emit it dynamic like `popover` (`gen-tokens.py:240-243`).
5. **The terminal palette**: a dark (and per-scheme) set in `tokens.json`, emitted dynamic, re-applied in `viewDidChangeEffectiveAppearance` (`Terminals.swift:305-313`), not only on Increase Contrast.
6. **`tokenCSS()`**: export all 39 colours (14 light and the console set are missing), the radii, `documentPadding`, the font families and the type sizes; generate the list. Then retire the web's literals: `duo-editor.js` (41), `margin.js` (15), `docx.html` (12), `critic.js` (4), `deck.html` (4), and the six UI and four mono font stacks become one each.
7. **Opacity shades as a token or a documented convention**: disabled 0.5 (`Components.swift:35, 55, 63`, `BrowserTabs.swift:601`), pressed 0.2 (`ConsoleStates.swift:143`), 0.4 (`:139`), dragged 0.55 (`TaskBoardView.swift:557`, equals `sheetDimmedOpacity` by coincidence), lifted 0.35 and landed 0.5 (`AllProjectsPanes.swift:1231, 1255`), queued 0.6 (`ChatView.swift:286`), the paste fade (`ChatPasteBlock.swift:222`).
8. **Exact-match literals → their token** (mechanical): `1.5` → `borderEmphasis` (11), `dash: [3, 3]` → `dashPattern` (5, and the board's dashes then match the map's), `9` → `radiusPill` (3), `3` → `radiusChatCheckbox` (2), the six `EdgeInsets` that equal a padding token, the tile focus outline → `borderTileFocusOutline`, `ProjectPanes.swift:426, 730, 1225` and `ChatReviewCard.swift:58`, `ChatPasteBlock.swift:93`, `BrowserTabs.swift:714` → their style.
9. **An icon-size token family** for the 16 SF Symbol sites, and the generator emitting `tokens.json`'s `icon` block so the hand-drawn marks read their viewBox and stroke from it. Delete `DuoGlyphPath` or make it the one source for Swift and JS.
10. **Generator strictness**: a missing palette value is an error; `size.newTabMenu` and `size.propertiesBlock` are emitted or removed; new `size` and `space` keys emit without a generator edit.
11. **Docs**: `docs/design/system/README.md:66` still says the console tokens are fixed in every appearance (stale since DL-224).
12. **Later, if shape ever matters**: a `.duoSelected()` modifier and a `Pill`, `Card` and `Field` in `Components.swift`, so the 20 selection sites and ~200 inline rounded rectangles have one place to change.

Items 1 to 8 are about two days of mechanical work and make tiers (a) and (b) literally a `tokens.json` block plus the selector. Item 6 is what makes (c) possible. Item 12 is the price of (d), and it is a price worth refusing until a design asks for it.
