# Duo Decks: comments

Status: **proposed** (marks [P]). Questions Q-394 to Q-397. The export research is in `research-comments.md`.

Geoff, 2026-10-31: "users should comment on in the preview, with authorship attributed, and the markdown holds the comments. … comments can be simple -- eg attributed to an element but not a specific text span. consider alternatives, like using the existing markdown comments tooling and just putting comment anchor icons on the rendered slide … if there is path dependency, do the research now and we can decide after decisions that this should be dependent on."

## What exists

Review in Markdown is **built** (DL-236, DL-237; `Sources/DuoControl/ReviewMarkup.swift`, the margin, @claude routing, the duo2 review verbs):
- comments are inline CriticMarkup with a readable signature, `{>>@geoff 2026-10-31 #c1: text<<}`;
- replies are `#c1.1`;
- Close and Keep or Delete;
- the margin at the side of the text, popovers when it's narrow;
- @claude comments routed to a session;
- Claude is taught the convention by Duo.

A deck is a Markdown file, so all of this already works on a deck's source today. What's missing is the preview: seeing comments on slides and adding one by pointing at a slide.

## Where the comment lives in the Markdown

| | Example | For | Against |
|---|---|---|---|
| **A. Review in Markdown, as is [recommended]** | `86%{>>@geoff 2026-10-31 #c1: rounded from 85.7?<<}` inside the `value` slot; a slide comment on its own line under the marker | No new convention. Margin, routing, close, verbs and Claude's teaching all exist. Spans come free (`{==…==}`). Readable in Obsidian and on GitHub | Comment text sits among slide text, so the parser must strip it (being built into P0 now) |
| **A′. A, with comments always on their own line** at the end of their slot (Duo writes them there when you comment from the preview) | `## value` / `86%` / `{>>@geoff … #c1: rounded?<<}` | Content lines never change when a comment is added, so diffs separate comments from content | A span comment typed in the source still sits mid-line, which is allowed |
| **B. A comments callout per slide** | `> [!comment] @geoff 2026-10-31 #c1 · value: rounded?` after the notes | Content stays clean, and comments are one block per slide | A second convention beside DL-236. The margin, routing and verbs don't read it. It's anchored by slot name, so a rename orphans it |
| **C. A sidecar file** | `field-trial-review.comments.md` | Content untouched | Ruled out by DL-236 (3): "no sidecar" |

**Recommended: A′.** It's DL-236's convention with one placement rule for comments made from the preview. An element comment is a signed comment on its own line at the end of the slot's lines. A slide comment is the same, right under the slide marker. Span comments stay possible from the source.

## What a comment attaches to

- **A slot** (element-level), which covers most cases: "the value", "the left column".
- **A slide**: "cut this slide".
- **A span**: a phrase in a slot. Only from the source side, where text can be selected. The preview has no text selection on slides.

Attribution as DL-236 (11): the Mac account's short name, changeable in Settings. Claude signs `@claude`, in green.

## In the preview [P]

| | What | For | Against |
|---|---|---|---|
| **P1. Pins on the slide [recommended]** | A small comment mark at the top right of the commented slot's box (the slide's top right for a slide comment), with a count when there's more than one. Hovering outlines the slot as the picker does. Clicking opens the thread in the source's margin, or as a popover when the split is folded to slides | Geoff's "anchor icons on the rendered slide". One place where threads are read and written (the margin), with the slides showing where they are | Needs split view's routing (R11, R12) |
| **P2. A comment rail beside the slides** | The preview gets its own margin of cards | Everything visible at once | Duplicates the source margin, and each side is only about 340–480 pt wide |
| **P3. A count on the slide's number only** | "3 · kpi · 2 comments" above the slide | Minimal | Doesn't say which element |

**Adding from the preview:**
- In Select Shape's picked bar (DL-125 C), **Add Comment** sits beside Send to Claude.
- Or right-click a slot on a slide › Add Comment.
- ⌥⌘M (DL-248's Add Comment) works on a picked element.

It opens the source margin's composer on that slot, and Duo writes the signed comment on its own line at the slot's end. @claude in a comment is routed as today.

**Verbs (DL-71):**
- `duo2 doc comment` works on decks as on any Markdown file.
- `duo2 deck comment <deck> <slide>[/<slot>] "text"` adds an element comment.
- `duo2 deck comments <deck>` lists threads by slide and slot.

## When the deck changes

- **A slot carries over to a new template** (DL-281's rules): its comments go with it.
- **A slot's content goes to the speaker notes** (DL-281): its comments go with it. The pin moves to the slide's corner, marked "in notes".
- **A slot or slide is deleted:** its comments go with the text. ⌘Z brings both back. Closed-and-kept comments are text in the file like any other.
- **A pack renames a slot:** the comment is in the deck's text, so a heading rename doesn't move it.

## Export, and the path dependency

| | What | Depends on |
|---|---|---|
| **E1. Comments stripped from the pptx [v1, recommended]** | The deck's discussion stays in git and Duo. The pptx is clean | Nothing |
| **E2. Open threads exported as PowerPoint comments** | Modern threaded comments anchored to the placeholder, with authors | Whether Google Slides keeps them on import (`research-comments.md`, and a Google test like Q-355's) |
| **E3. A choice at export** | "Include comments" in Export ⌄ | E2's answer |

## Decision order (Geoff: "I trust you to reorder the decisions")

1. **Now, before P1:** **Q-394, where comments live (A′ recommended).** The parser in P0/P1 must know, and it's being built to tolerate review marks either way.
2. **After split view (DL-275..278):**
   - **Q-395, the preview's look** (P1 pins recommended), with R11 and R12 sent to split view;
   - **Q-396, adding from the preview** (the picked bar and right-click).
3. **After the Google comment test:** **Q-397, comments in the export** (E1 now; E2 or E3 later).
