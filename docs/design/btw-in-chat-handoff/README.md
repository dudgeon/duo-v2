# Duo: /btw in chat, the side card — design handoff

Status: approved. Geoff took every recommendation on 2026-11-16 (**DL-344**; Q-550 to Q-554). The canvas is https://claude.ai/artifact/L2NaLSyuma4dDhExA9SH4G ("Duo · /btw in chat"); its sources are in `../btw-in-chat-study/project/`, and the research is `docs/research/btw-in-chat.md`. Built on `build/btw-in-chat`.

The screens are the canvas boards rendered to static HTML (`export.mjs` does it from the study's sources; `render.sh` makes `screens/png/*@2x.png`). They are pictures: match what they draw, do not port their markup. Names and data are illustrative.

## Targets

| Screen | Build | Not chosen (canvas only) |
|---|---|---|
| `00-what-and-why` | Context only. | — |
| `01-where` | **Q-550 A:** a side card docked in the composer's place while the reply above keeps streaming; chat never falls back to the terminal on `/btw`. | B (an aside in the feed), C (a popover) |
| `02-states` | The card's states: answering (one Close), answered (Copy, Fork…, Close), a long answer scrolling inside the card, "No answer available…", at the prompt with history (‹ 2 of 2 ›, Clear history), over a running agent. | — |
| `03-after` | **Q-551 A:** a quiet line "Side question: … · Show" where you asked, reopening the card from Duo's memory while Duo runs. **Q-552 A:** the card holds its place; typing closes it (Esc to Claude Code) and starts your message with what you typed. | Q-551 B and C, Q-552 B and C |
| `04-entry` | **Q-554 A:** `/btw` typed in the composer; its `/` menu row reads Claude Code's description. **Q-553 A:** Fork… only when a mock run per CLI version shows what Claude Code's `f` does. | Q-554 B (an "Ask aside" control) |

## The card

`pane` fill, a 1 `controlEdge` edge, radius 12, no accent (a side question never needs you). Section label "Side question · not part of the conversation" (uppercase label style), your question in `bodyEmphasis`, the answer as Markdown (the hook's text when it came, else the screen's), then the buttons: Copy `c`, Fork… `f`, Close `esc`, and at the prompt Clear history `x` and a pager. "Claude keeps working above" on the right while Claude works. Answering shows the still working ring and "Answering · 3s" with Close only. It docks where the composer is and rises with `motionCardIn`, as the review cards do (DL-119).

## Rules from the decisions

- The card's keys send Claude Code's own (`c`, `f`, Esc, ↑/↓, ⇧←/→, `x`) after re-reading the screen.
- Bare `/btw` opens no card: Claude Code prints "Usage: /btw <your question>", chat shows it as its quiet one-line output.
- A `/btw` you send is not a message bubble: no Queued line, no turn timer.
- The side answer's SubagentStop (empty `agent_type`) is the card's Markdown and never finishes an Agent card.
