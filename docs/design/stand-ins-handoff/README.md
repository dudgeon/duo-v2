# Duo: two stand-ins settled (Q-42, Q-43) — design handoff

Status: approved by Geoff, 2026-10-06 (DL-111, DL-112), and built (F-86, F-92). Answers Q-42 and Q-43. The boards were drawn on the Design canvas https://claude.ai/artifact/JRX1VKzcgfTh5z3Da6eMqM with the Duo design system (every mark a [P]), and are exported here as static HTML with PNGs in `screens/png/`. Q-44, on the same canvas, has its own handoff (`folder-handoff/`, DL-110).

## What the boards settle

**Q-42, the map when Home's projects sit directly in Home (DL-111): keep what's built.**
- `q42-one-list`: with no topic folders the map shows one list. It fills the width in rows of three (two or one when narrow): Home's ★ tile first, **+ New project** last.
- `q42-two-lists`: projects directly in Home plus one topic folder make two lists. Each stays a third wide and the right third stays empty, so tiles are the same size as everywhere else on the map.

**Q-43, New Session in Task (DL-112).**
- `q43-hover` (board B): hovering over a task row shows a **+** where its status or time sits, with the tooltip "New Session in Task". The hovered line takes the `selected` fill. The board draws the line style (the Tasks fold); the decision covers the group style too.
- `q43-menu` (board A): the task row's right-click keeps Open Task Note, **New Session in Task**, Status ›. The note's `sessions:` **+ Add** keeps New Session in Task as its first item.
- `q43-drafted` (opening 1): the new session starts with Duo typing `@tasks/<note>.md` into Claude's prompt **without sending it**. Claude reads the task once the user adds a word and presses Return. No turn is spent.

## Behaviour a picture can't show

- Every control runs `duo2 task session <task>` (DL-71); the drafted prompt is its default too.
- The draft waits for Claude's prompt (its beacon reads idle; up to two minutes, so a folder-trust prompt can be answered first), then goes in as one bracketed paste: no Return. It doesn't switch project or take the keyboard.
- The session's link is in the note's `sessions:` from its start (F-87).

## Not drawn

- The group-style task row on hover: built with the same + at the row's trailing end (where a wait would sit) and no hover fill, since only the line was drawn. Its "status · n" gives way to the + when space is short.
- The tooltip is the system's (`.help`); the board draws it in that look.

## Exempt from the comparison

Names, sessions and times are illustrative; live captures use scratch data. Inside a terminal (the drafted prompt) the window capture is blank (F-25): the text is read with the harness's `dump`.
