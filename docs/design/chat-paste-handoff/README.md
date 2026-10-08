# Duo: chat paste — design handoff

Status: approved by Geoff, 2026-10-08 (DL-161). Pasting into chat mode (`chat-mode-handoff`, DL-119): a picture, long text, a copied file. Geoff, 2026-10-08: "chat mode does not show pasted items … would be great if we could show an image thumbnail for pasted image, and expandable text snippet for pasted text". Why paste did nothing before: F-231. How Claude Code takes a picture: F-232.

The boards were drawn on the Design canvas https://claude.ai/artifact/9XConwuo9RTSvgzvd4njAj with the Duo design system; Geoff chose by buttons (P1 A, P2 A, P3 A, P4 and P5 as drawn). They're exported here as static HTML (`screens/`, listed in `screens/manifest.json`), with PNGs in `screens/png/`. Each board is the console pane, 680 wide. **Build the A snippets; B and C were not chosen.** The section labels and the grey line under each snippet on P1 to P4 are the board's notes, not the app's; on P5 the two failure lines under the field are app copy.

## The composer: a picture (P1 A, `picture`)

- **Pictures sit in a row above your text, inside the field**: 64×64, radius 8, a 1 `rule` edge, 8 apart, 8 above the text. The picture fills its square, cropped to the centre (Q-148c). Eight fit a row at the drawn width; more wrap (P4).
- **Under the pointer, a picture shows its ×**: an 18 circle on `pane` with a 1 `controlEdge` edge, its centre on the picture's top-right corner, an 8×8 cross in `text` at 1.3. The × removes the picture; so does Backspace with the caret at the start of an empty field (the last picture first).
- **A click opens the picture in Quick Look.** Space does too while the picture has the keyboard.
- **While Claude Code takes it** (Ctrl+V, about half a second): a dashed tile (1 `controlEdge`, `borderDash`) with `Adding…` in `control` `text2` holds its place.
- **Where it goes:** into Claude's prompt as Claude Code's own `[Image #N]`, through its image paste (Ctrl+V), which reads the Mac's clipboard itself. Duo writes no picture for Claude. On send your pictures go first, then your words, on every version (F-233).

## The composer: long text (P2 A, `text`)

- **A paste over 12 lines folds to a block** in the field where it was pasted: `ground` fill, 1 `rule` edge, radius 8, padding 6 10. Its first line: a chevron (10, `text2`), `Pasted text` semibold and `· 42 lines` in `text2`, 12/16, and a × at the end. Its second: the paste's start on one line, 13/20 `text2`, cut with `…`.
- **The chevron opens it in place**: the text, 13/20 `text`, editable; eight lines show and it scrolls inside. Folding it again keeps your edits.
- **Claude gets every line**, where you pasted it. A paste of 12 lines or fewer is plain text, as before.
- **The field scrolls** past its 8 lines, typed or pasted (it overflowed before, F-231; Q-148b).

## The feed (P3 A, `sent`; P4; P5)

- **Your pictures sit at the top of your bubble**, right-aligned: up to three at 120×90 in a row, 6 apart; four or more in a three-column grid at 100×75 (P4). Radius 8, 1 `rule` edge, cropped to the centre. A click opens Quick Look.
- **The bubble's text has no `[Image #N]`**: the pictures stand for them.
- **A long paste folds by K8** (DL-135) like any message over 12 lines: the transcript keeps pasted text unmarked, so there's one rule for typed and pasted.
- **Replay** (P5): a message from the transcript (pasted in the terminal, or before a restart) shows its pictures the same way, from the transcript's own image blocks.

## When it fails (P5, `replay`)

The hint row under the field gives way to one line in `control` `text2` until you type or paste again; your text stays:
- `Claude Code didn’t take the picture. Paste it in the terminal` (a link that shows the terminal).
- `Your Claude Code keys move Ctrl+V, so pictures go in from the terminal. Show terminal`.
While Claude asks something (a review card), a pasted picture shows the terminal with `Claude is asking something in the terminal; paste the picture there.`

## A file, a path (P4, `edges`)

- A picture file copied in Finder pastes as a picture (Claude Code's Ctrl+V reads the file).
- Any other file copied pastes as the file chip, its full path sent, as a drop is (DL-117).
- A path copied as text stays text.

## ⌘V with nothing focused (P5)

In the terminal the prompt always has the keyboard. In chat, ⌘V pastes into the composer even before you click it, and the composer takes the keyboard.

## Behaviour a picture can't show

- Removing a picture before sending: on 2.1.269 and later the hand-over leaves its token out and Claude Code drops it; before, Duo deletes the token from Claude's prompt with Ctrl+A, Right × its place + 1, Backspace, Ctrl+E (F-232), checking the screen after.
- No new `duo2` verb: paste, the × and Quick Look act on the composer and bubble the way typing does (DL-71's exemption for the composer's own editing).

## Not drawn (stand-ins and questions)

- Q-148: the Adding… tile's time limit (3 s, then the failure line), the field's scroller (none drawn), the thumbnail crop.
- ENH-53: opening a pasted picture in the right pane.
