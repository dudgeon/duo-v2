# Duo: review in Markdown — design handoff

Status: approved by Geoff, 2026-10-28 (DL-237), on top of DL-236's twelve choices. A Markdown document carries tracked changes and comments as CriticMarkup with a readable signature (DL-236 1–3); Duo draws them in a margin column beside the text, closes threads with Close and Keep or Delete, and has one Suggest Edits switch per document for people and Claude alike.

The boards were drawn on the Design canvas https://claude.ai/artifact/SBKQ1sgYF12qaqP6YXcTUX with the Duo design system; Geoff took every recommendation by buttons. They're exported here as static HTML (`screens/`, listed in `screens/manifest.json`) with PNGs at 2x in `screens/png/`. The research behind the margin (Google Docs and claude.ai comments) is the `research` board and F-379; the format research is `docs/research/markdown-review.md`.

**Build:** `close-verbs`, `close-leaves` (A only), `close-menu`, `close-shown`, `track-a`, `margin-crowded`, `margin-thread`, `margin-claude`, `margin-suggest`, `margin-narrow`. **Not chosen:** `track-b`, `track-c`, and option B on `close-leaves`. On each board the blocks under a small capitals label are the spec, not UI. Names and documents are illustrative.

## The review bar (Q-265)

44 high under the tabs, a `rule` below, buttons as Duo's one button (12/16, padding 4 10, 1 `controlEdge`, radius 6, `pane`): **Markup ⌄** and **Suggest Edits** at the left; **‹ ›** and **Review All ⌄** at the right. It shows on a Markdown document that has marks or comments, or has Suggest Edits on (stand-in until Q-265 is answered). Under 420 it drops ‹ › and says **Review ⌄**, which gains Next and Previous at its top.

## Tracking: one Suggest Edits switch (2A, `track-a`)

- **Off** (default): a hollow 8 dot (1.5 `controlEdge`) before the label. **On**: the button on `selected`, the dot filled `text`.
- **On, everyone's edits become suggestions**: your typing as marks signed with your name in your colour; Claude's Edit through the pre-edit hook written by Duo as signed marks from the hunks it already computes (research §5.2); a team-mate's Duo does the same after a pull; a Claude session outside Duo follows the convention paragraph. Obsidian and plain editors edit plainly.
- **Kept in the file**: `suggest-edits: true` in the frontmatter, written only while on and removed when switched off, so a document that never used it is never touched. Plain YAML, an Obsidian property, OKF-safe; the Properties block shows it like any other property.
- **Reached by**: the button; Edit › Suggest Edits (⇧⌘E proposed, Q-264); `duo2 doc review on|off`. The convention paragraph (DL-236 7) adds: "If the file's frontmatter has `suggest-edits: true`, write every change as a signed mark."
- Claude's green highlight (DL-186) still marks Claude's edits that land while the switch is off.

## The margin (`margin-crowded`, `margin-thread`)

- **Geometry at 460**: text column 228 wide from 20; margin 180 wide from 260; 20 from the right edge. The margin scrolls with the document and extends it when cards run past the end.
- **Anchor**: the commented range on `commentHighlight` (DL-162). Hovered or active: `commentHighlightActive` (new, #F5D565 light provisional, Q-265).
- **Card at rest**: `pane`, 1 `rule`, radius 6, padding 8 10, 12/16; the name semibold in the person's colour, ` · 27 Oct` in `text2`; the first comment cut to two lines; `n replies` in `text2`. Claude's name is followed by its session (`Claude · Offline one-pager · 14:03`, DL-236 9A).
- **Placement**: level with the anchor's first line; when the card above is in the way, pushed down to sit 10 below it (`gapCardToCard`). No leader lines. Hovering a card darkens its border to `controlEdge` and deepens its anchor; hovering an anchor does the same to its card.
- **Active card** (a click on it or its anchor, or ‹ ›): moves level with its anchor, cards above slide up and cards below down to make room; steps 12 left (x 248) and widens to 192 so the verbs fit on one line; 1.5 `text` border; no shadow. Shows the first comment, `3 more replies` (underlined `text2`, opens the rest) when a thread has more than three, the last two replies (indented 12), a reply field (1 `rule`, radius 6, padding 4 8, placeholder `Reply…`), then **Close and Keep** and **Delete** (buttons padded 4 8). Only the active card has the field and verbs.
- **Keys** (Q-264, Q-245): ⌥⌘M comments on the selection; with focus in the margin J and K next and previous, R reply, ⌘Return posts, Esc returns to the text where you were.

## Closing a thread (`close-verbs`, `close-leaves` A, `close-menu`, `close-shown`)

- **Close and Keep** writes a closing reply, `{>>@geoff 2026-10-28 #c1.2 closed<<}`, after the thread's last comment; the `{== ==}` highlight and the comments stay (Q-262). **Delete** removes the highlight markers and every comment of the thread; the text stays. Both undo with ⌘Z; neither asks.
- **Closed threads aren't drawn**: no fill, no mark. The margin's foot (after the last card, 12/16 `text2`) says `2 closed · Show` (Show underlined `text`), or `· Hide` while shown.
- **The mode**: Markup ⌄ is the Word viewer's menu (DL-162 W4) with **Show Closed Comments** (and its count) where Word says Show Resolved Comments. Off by default; kept per document while Duo runs. Also View › Show Closed Comments; `duo2 doc comments --closed`.
- **Shown**: a closed anchor gets a 1.5 dotted `controlEdge` underline at offset 3, no fill; its card folds to one line in `text2`, `› Closed · Sam: Say “turn” for…`. Opened (active), it reads in `text2` with `Closed by Geoff · 28 Oct` (11/16) at the top, its anchor's underline solid `text2`, the reply field says `Reply to reopen…`, and the verbs are **Reopen** and **Delete**. Reopen (or posting a reply) removes the closing line.

## Suggestions (`margin-suggest`)

- Inline marks only, in the person's colour as on Word documents: insertion underlined at offset 3; deletion struck through; substitution both. **Claude is always `reviewAuthor3` green** (beside DL-186's `claudeEdit`); people take `reviewAuthor1, 2, 4, 5` in the order they appear, then repeat (Q-266).
- **Label** on hover or click: a Duo popover (`pane`, radius 10, `shadowPopover`, padding 6 10 8, 12/16): the name in colour and `suggested · <session> · 14:03` in `text2`; the mark's note if it has one; **Accept**, **Reject**, **Reply**. Reply turns the note into a thread with a card.
- **Review All ⌄**: Accept All, Reject All, then the same per person, then the counts (`3 suggestions · 4 comments`). Simple Markup draws the text as accepted with a 2 `text2` bar at the left of each changed paragraph (DL-162).

## @claude (`margin-claude`)

- **Writing**: typing `@claude` (semibold, Claude's green) in a comment shows `To` and the **session pill** under the field: height 20, radius 9, 1 `controlEdge`, padding 0 6, 11/16: `>_` (SF Mono 10, `text2`), the session name (truncates first), `· at prompt` / `· working` in `text2` (never truncated), `⌄`. A click opens the Send To list. Its first guess is DL-236 9A's order. **Post** (⌘Return) sends (DL-236 10A); **Cancel**.
- **Status line** under the comment (11/16, `text2`, glyphs 10 from Duo's set): **Queued: waits for its turn** with the idle dash (the session is working, at a permission prompt, or has text in its prompt; sends at the next idle with an empty prompt, re-checked just before typing); **Sent · 14:02**; **Claude is replying** with the working ring in `text`; on **Replied** the line goes and Claude's reply sits in the thread; **Not delivered: Pricing study ended** in `text`, with **Retry** and **Send To…** (no accent: nothing waits on the person); a comment that came in with the file reads `· from the file` after its date and `Not sent`, with **Send** and the pill (DL-236 10A, C-112). The pill stays under the comment in every state; on a sent comment it opens the session.

## The narrow cut (`margin-narrow`, Q-263)

Under 420 the text takes the width (288 at 360) and the margin folds to a 24 gutter: per thread a marker level with its anchor, 20×16, radius 4, 1 `rule`, `pane`, its comment count at 10/14 `text2`; the open thread's marker is `selected` with a 1.5 `text` border. Markers that collide stack 4 apart. A click on a marker or anchor opens the thread as a popover under the anchor's line (280 wide, `pane`, radius 10, `shadowPopover`, padding 10 12) with the same contents as the active card; Esc or a click in the text closes it.

## Verbs (DL-71)

`duo2 doc review on|off`, `duo2 doc markup all|simple|none|original` (extended to Markdown), `duo2 doc comments [--closed]`, and the research's `duo2 comment add|list|reply|send|close|delete|reopen|status` and `duo2 suggestion list|accept|reject` (research §6.5, with `resolve` renamed to `close` and `--dismiss` to `delete` by DL-236 4).

## Not drawn yet

Dark appearance (tokens have dark values except `commentHighlightActive`); the composer for a new comment on a selection (a card at the anchor with the field focused, as the active card); the Send To list (as Send To today); the Properties block's look for `suggest-edits` (as any property).
