#!/bin/sh
# D7: a worker finished and wrote its report in its task note, but no message came (SendMessage is held
# between permission modes). The director reads the note and reports the finish; it doesn't wait (director-regression, S3, S4).
lib=$(dirname "$0")/../_lib; . "$lib/setup.sh"
console_real
release_rules
cat > tasks/chat-row-height.md <<'EOF2'
---
type: task
title: Chat row height
status: in-progress
directed_by: director-duo-v2
done_when: "rows are 36px high, with a capture compared to the board"
created: 2026-10-19
---

# Chat row height

## Request

Geoff: "make the chat rows 36px high like the board".

## Progress

- 2026-10-19 09:12 Worker started in the background (duo-v2-chat-row).
- 2026-10-19 10:41 Done: rows are 36px; branch build/chat-row-height, sha 3f9a1c2d44e0b7a5c61d8e2f90ab34cd5e67f801; DuoChecks pass; capture compared with the board, matches. Ready to merge.
EOF2
