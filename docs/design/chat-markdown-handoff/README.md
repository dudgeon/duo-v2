# Chat · your Markdown — handoff (DL-188)

Status: **approved** (Geoff, 2026-10-13, by button: "looks good; in your build plan, include kb shortcut handling, eg for cmd b, cmd k"). Canvas: https://claude.ai/artifact/HqqgRX8mpDfZjRLM14Btd9.

## Screens

- `screens/composer.html` (680 × 1460): the composer with light Markdown styling. A is today's plain field, for reference. B is as you type. C is a wrapped bullet. D sits beside a paste block and a file chip. E is the sent bubble.

## The composer (B, C, D)

- **Every character stays where you typed it.** What's sent is the field's text, byte for byte, as before. The styling is attributes only, never edits.
- **Inline marks stay visible, in `text2`:** `**` `*` `` ` `` `~~` `#` `[ ]( )`.
  - Bold goes semibold, italic goes italic, strikethrough is struck.
  - Inline code goes mono on the code ground (`chatGround`, radius `chatInlineCode`), backticks included.
  - A heading goes semibold at the body size.
  - A link's text is underlined in `controlEdge`.
  - `@` mentions keep their mono (DL-133).
- **Block marks are drawn over:**
  - a line's `-`, `*` or `+` shows as a bullet, and its wrapped lines hang under the text (C);
  - a `>` shows as the quote rule (2 wide, `rule`), and the line's text is `text2`;
  - numbers stay as typed, with a hanging indent.
  - The characters are still there: ⌫ after a bullet deletes the dash, and the line is plain again.
- **Fences stay**, mono and dim, and the lines from fence to fence sit on the code ground (`chatGround`, radius `chatCodeBlock`) in mono.
- A folded paste block and a file chip keep their own look (D). The words around them are styled.
- Line height stays 22 for every line, so the field's height math (eight lines, then it scrolls) is unchanged.

## Keys (composer focused)

Each one wraps the selection, or puts the pair at the caret with the caret between. A selection already wrapped (marks inside it or just outside) is unwrapped. One ⌘Z undoes each. This matches the editor (DL-189).
- ⌘B `**`
- ⌘I `*`
- ⇧⌘X `~~`
- ⌘E `` ` `` (composer only; the editor's Code has no chord)
- ⌘K `[text]()` with the caret in the parentheses; with nothing selected, `[]()` with the caret in the brackets.

## The bubble (E)

Your sent message renders your Markdown as Claude's card does (F-305). Task items are a stand-in (Q-194).
