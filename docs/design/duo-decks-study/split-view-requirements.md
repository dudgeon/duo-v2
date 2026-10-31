# Duo Decks: what it needs from split view

From duo-decks (6a39b999) to split-view (e357a951), 2026-10-31, cc director-duo-v2.

Geoff, 2026-10-31: "split view is the correct way to handle the side-by-side of source editing and rendered preview … those requirements/needs should inform the split view build".

Duo Decks' viewer (Q-350) now waits for split view. Everything else in Duo Decks goes ahead now (`plan.md` §6). This note says what the deck viewer needs, and proposes the interface between split view and a preview. Split view owns the decision; this is input.

## The case

A deck is one Markdown file (`decks/x.md`, `type: deck`). Its preview is that file compiled to a pptx in memory by Duo's writer and drawn by the vendored pptx-renderer (DL-121), so the preview is the export. Sample: `samples/decks/field-trial-review.md`; boards 2 and 8 on https://claude.ai/artifact/Sk28K1tkHgwk6gHs7RFGqQ.

The same shape fits other files. A Markdown note beside its rendered view, an HTML file beside its page, a Mermaid or CSV file beside a drawing. Decks are the first, not the only, source-and-preview pair.

## Requirements

**R1. One file, two views, one buffer.**
- The source (the Markdown editor) and the preview (the slides) show the same file side by side.
- The preview renders from the editor's buffer, unsaved edits included, never from disk alone.
- If the file changes on disk (Claude edits it), both update, as the editor does today.
- Doc-beside-doc (legacy Split View, two different files) is a different case. It should fall out of the same mechanism, but it isn't what decks need.

**R2. Live re-render on edit.**
- The preview redraws about 250 ms after typing pauses (writer plus renderer, about 20–40 ms for a 30-slide deck).
- It keeps its scroll position and doesn't flash: draw the new deck, then swap.
- Rendering never writes a file. Export writes the pptx.

**R3. Two-way sync.**
- **Source to preview.** The caret in slide n's lines makes slide n current: the preview scrolls to it (`motionSlide`) and the bar reads "Slide n of N". Moving within a slide's slots doesn't scroll.
- **Preview to source.** Clicking text on a slide puts the caret in that slot's lines and scrolls the source to it. Clicking empty slide area puts the caret on the slide's marker line.
- **Optional scroll-follow.** Scrolling one side follows on the other. Off by default; caret-follow is enough.
- **No loops.** Each event carries its origin, and a view doesn't react to its own echo.

**R4. Selection and comments.**
- Selecting text in the source behaves as in any Markdown document: Send to Claude (⌘D), comments and suggestions (Review in Markdown, DL-236/237). Comments live in the source.
- The preview shows a quiet mark on a slide whose source range has open comments or suggestions. Clicking the mark goes to them in the source.
- Select Shape on the preview (DL-125's picker) resolves to the slot. Send to Claude says `decks/x.md, slide 3 (kpi), slot value, lines 27–28`, plus the shape facts it sends today.

**R5. Problems.**
- The checker's problems (file:line, slide, slot, message) mark the source lines and show under their slide in the preview (board 3).
- The provider hands split view a problems list. Split view or the editor decides how lines are marked.

**R6. Export state.**
- The preview's bar shows whether the exported pptx is current: "Exported 5m ago", "Changed since export", or nothing if never exported.
- It also holds Export ⌄. That's the preview's own bar, not split view's.

**R7. Narrow widths.**
- Slides under about 360 pt wide are hard to read.
- Below a threshold, split view's call on how to fold (one side with a Source/Slides toggle, or stacked). Decks need a way to keep both reachable.
- The non-split fallback is the same toggle in one tab (board 8, F).

**R8. The formatting bar and voice.**
- The Markdown formatting bar (DL-266, 24 high, only while the editor has the keyboard) and its mic belong to the source side only, over the editor column, as in any Markdown tab.
- The preview has its own bar: ‹ › Slide n of N, problems, Select Shape, Export ⌄.
- Dictation goes into the source.

**R9. duo2 (DL-71).** Every split control needs a verb. Decks need:
- **opening:** `duo2 split <file>` opens a file as source beside its preview, if it has one;
- **status:** `duo2 split` gives the state: which file, which sides, the focused side, sync on or off;
- **closing:** `duo2 split close`;
- **deck verbs:** `duo2 deck` (the slide current in the preview, and the slot the caret is in), `duo2 deck go <n>` (moves both sides), `duo2 deck pick`.

The deck verbs are Duo Decks'. The split verbs are split view's.

**R10. Persistence.** A file opened in split reopens in split, with the same sides and the divider where the user left it, as panes do today.

## Proposed interface (to agree)

The **preview provider** is a small protocol a viewer implements to pair with a source:

```
protocol SourcePreview {
  static func canPreview(file: URL, frontmatter: [String: String]) -> Bool   // deck: type == "deck"
  func render(text: String, revision: Int)                                     // from the buffer, debounced by split view
  func reveal(anchor: PreviewAnchor, reason: SyncReason)                       // scroll to slide n / slot
  var onAnchorMap: ([AnchorRange]) -> Void            // after each render: source line ranges → anchors
  var onActivate: (PreviewAnchor) -> Void             // user clicked a slide or slot
  var onCurrent: (PreviewAnchor) -> Void              // preview scrolled; this anchor is current
  var onProblems: ([SourceProblem]) -> Void           // line range, message
}
struct AnchorRange { let lines: ClosedRange<Int>; let anchor: PreviewAnchor }   // e.g. slide 3, or slide 3 / slot "value"
```

**Who owns what:**
- **The provider owns the anchor map.** Only it parses the file, so only it knows that lines 24–34 are slide 3 and lines 27–28 are its `value` slot.
- **Split view owns the policy.** It owns caret-follow, scroll-follow, debounce and loop suppression. It owns the panes, the divider, narrow folding, persistence and the `duo2 split` verbs.
- **The editor owns the source side:** its caret and visible-range events, revealing a line range, marking lines.

**The events:**
1. editor → split view: `textChanged(text, rev)`, `caretMoved(line)`, `visibleLines(range)`, `selection(range)`.
2. split view → provider: `render(text, rev)`, `reveal(anchor, reason)`.
3. provider → split view: `anchorMap`, `activate(anchor)`, `current(anchor)`, `problems`.
4. split view → editor: `reveal(lines, select:)` and `mark(problems)`.

What we'd like back from split view:
- Whether this shape works.
- What split view provides.
- The threshold and folding it chooses for narrow widths.
- Whether "same file, two views" is in its first build.

Duo Decks will build its provider (writer, renderer page, anchor map) to the agreed protocol. Until split view exists, the same provider sits in a single tab with a Source/Slides toggle.
