# Chat mode spike (ENH-13, DL-118)

A proof of concept, not app code: the real Claude Code TUI in a PTY beside a chat rendering of the same session. The write-up is `docs/plan/spikes/chat-mode.md`; findings F-103 and F-104.

```
npm install && find node_modules/node-pty -name spawn-helper -exec chmod +x {} \;
./start.sh                              # http://127.0.0.1:8780 against the mock API (no login, no tokens)
./start.sh --real                       # your own login, a throwaway workspace, Haiku: spends tokens
./tour.sh scenario-tour.json /tmp/tour  # every dialog, headless; diff /tmp/tour against screens/tour-2.1.291/
```

With the mock, put `SCENARIO:<name>` in a prompt: `md`, `bash`, `read` (then an edit), `ask`, `askmulti`, `ask1`, `askmulti1`, `ask4`, `asklong`, `askpreview`, `plan` (Shift+Tab twice into plan mode first), `agent`, `long`, `err`.

| File | What |
|---|---|
| `server.mjs` | Runs `claude` with per-session hooks (print nothing), tails events and transcript, reads the screen, serves the page, turns answers into keys after re-checking the screen |
| `ask.mjs` | AskUserQuestion: turns the card's intent (pick, toggle, other, next, tab, notes, chat, submit, decline) into keys one at a time, re-reading the screen after each (F-106) |
| `asktest.mjs`, `asktest.sh` | 13 AskUserQuestion cases end to end through the server, at three terminal sizes; checks what Claude received |
| `screen.mjs` | The 2.1.291 dialog signatures: idle, busy, permission, plan, question, review, else `unknown` |
| `index.html` | Terminal (xterm.js) and chat side by side: Markdown from `MessageDisplay`, tool cards, dialog cards, composer, toggle, automatic fallback |
| `mock.mjs` | A scripted stand-in for the Messages API |
| `drive.mjs`, `tour.sh`, `scenario-tour.json` | Headless runs that dump each screen |
| `scratch.sh` | The scratch config (`./scratch/`, ignored): trusts the workspace, approves only the dummy key |
| `screens/` | Captured TUI states, including the desyncs (`desync-glued-prompt.txt`) and unknown screens |

`screens/real-cli-login-2.1.291/` holds the same states from real Haiku turns under the CLI login (F-105). Differences from the mock baseline are listed in the spike doc.

`./asktest.sh` runs the AskUserQuestion suite (mock, about 10 minutes for three terminal sizes).
