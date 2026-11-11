# Word and PowerPoint comments in the Markdown margin (DL-337)

The approved design for comments in the Word and PowerPoint viewers, exported from the Design canvas
https://claude.ai/artifact/8EpSVPXmKFyayEbBFZU2e3 (v9, approved by Geoff 2026-11-11). Q-494, F-642, F-654.

**Read board N (`notes`) first**: it lists what is the Markdown margin unchanged and every difference the file format forces.
Everything else is the Markdown margin (DL-236, DL-237, DL-251, `markdown-review-handoff/`) and the PDF viewer's (DL-335): the
same page (`Vendor/codemirror/src/side-margin.js`, `cards.js`), the same tokens, the same cards, composer, @ menu and keys.

| Board | File | What it draws |
|---|---|---|
| W1 | `screens/word-margin.html` | Word at 460: the margin beside the text, anchors highlighted, closed threads hidden, ‹ › and ⋯ in the bar |
| W2 | `screens/word-composer.html` | the composer in the margin and the @ menu |
| W3 | `screens/word-thread.html` | every card state: not sent, queued, replying, replied, not delivered |
| W4 | `screens/word-closed.html` | Show Closed Comments: the Markup menu, folded closed threads, dotted anchors |
| S1 | `screens/slides-margin.html` | PowerPoint at 640: the slide at normal size, the margin beside it, anchors on text, a shape and the slide |
| S1b | `screens/slides-narrow.html` | under 420: the gutter, markers and the popover |
| S2 | `screens/slides-active.html` | the active card level with its outlined shape, and a closed thread |
| N | `screens/notes.html` | exceptions to Markdown, anchors and what writing them costs |

The boards' names and text are illustrative. The `screens/` are a snapshot of the canvas: do not edit them.
