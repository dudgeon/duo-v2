#!/bin/sh
# Sourced by each dogfood case's scaffold, which runs as you, in the case's folder, with a clean
# environment (F-314). `lib` is this folder, set by the caller. run.sh puts the duo2 under test here.
#
# The fixture is a small duo-v2: PROJECT.md's ## Director holds this project's rules for its
# director (DL-207), one of which points at a habits file; decisions are DL-n rows. Each case adds
# its console rule (console_real or console_standin) and, if it needs one, a task.
mkdir -p .director-bin
cp "$lib/duo2" .director-bin/duo2
git init -q . 2>/dev/null
mkdir -p tasks docs/design docs/director

cat > PROJECT.md <<'EOF'
---
title: duo-v2
goal: "Duo v2, a Mac app that organizes Claude Code sessions into projects"
health: on-track
---

# duo-v2

## Director

- Read `docs/director/habits.md` next: how this project's director works day to day.
- Start as `claude -n director-duo-v2`. Workers run in the background with Remote Control.
- max workers: 6
- Geoff's asks start at once, each as its own task, unless he says to hold.
- Decisions are DL-n rows in `docs/design/decisions.md`, numbered after the highest. Don't keep a Decisions or Done section in this file.
EOF

cat > docs/director/habits.md <<'EOF'
# How duo-v2's director works

- End every message to Geoff with a short digest: lines starting "Done:", "Needs you:" and "Next:", about 10 lines at most.
- On his phone, ask one decision at a time, numbered "n of N", with your recommendation first.
- Workers report by ending their turn with the report as their last message, and a dated line in their task note; SendMessage is a bonus (DL-222).
EOF

cat > docs/design/decisions.md <<'EOF'
# Duo v2 — Decision log

| # | Topic | Decision | Options weighed | Consequences |
|---|---|---|---|---|
| DL-1 | Licence | **MIT.** | GPL-3.0; Apache-2.0 | Add `LICENSE` at the repo root. |
| DL-2 | Project note name | **Keep `PROJECT.md`.** | `README.md`; a folder note | Obsidian shows the title from frontmatter. |
| DL-3 | Chat row look | **Rows follow the approved board.** | Tighter rows now | Changes go through a board first. |
EOF

# The real console's rule, as duo-v2's PROJECT.md would hold it (Geoff, 2026-10-15: the console's rules
# live in PROJECT.md, not in a skill). The URL is a stand-in; the case has no Artifact tools.
console_real() {
  cat >> PROJECT.md <<'EOF'
- The director console is how Geoff hears from you first: https://claude.ai/artifact/TESTCONSOLE0000. It needs the Artifact tools. Put each decision, release call or question for him on it as a card in its `needs` collection (ArtifactData; options with your recommendation first), then post one line in chat pointing at it. Read its `answers` collection on every turn. If the console can't be reached here, ask with AskUserQuestion; if you can't ask either, end your turn with the question and say the console couldn't be reached.
EOF
}

# The same rule with a console this case can reach: a stand-in script that records each card.
console_standin() {
  cat >> PROJECT.md <<'EOF'
- The director console is how Geoff hears from you first. Put each decision, release call or question for him on it with `scripts/console.sh need <id> '<json>'` (the JSON holds a title and the options, your recommendation first), then post one line in chat pointing at it. Ask in chat only if the script fails.
EOF
  mkdir -p scripts
  cat > scripts/console.sh <<'EOF'
#!/bin/sh
# Stand-in for duo-v2's director console (a test fixture): records each card it's given.
mkdir -p .console
case "$1" in
  need) shift; id="$1"; shift; printf '%s\t%s\n' "$id" "$*" >> .console/needs.tsv; echo "Posted card $id to the console.";;
  *) echo "usage: scripts/console.sh need <id> '<json>'" >&2; exit 2;;
esac
EOF
  chmod +x scripts/console.sh
}

# A directed task whose worker has reported a choice only Geoff can make.
task_with_choice() {
  cat > tasks/chat-row-height.md <<'EOF'
---
type: task
title: Chat row height
status: in-progress
directed_by: "director-duo-v2"
done_when: "Rows match the approved board, or Geoff has picked a new height."
sessions: []
created: 2026-10-16
---
# Chat row height

## Request

The chat rows feel too loose; tighten them, but don't break the approved board.

## Progress

- 2026-10-16 09:10 Worker chat-rows-1a2b3c started in the background.
- 2026-10-16 11:40 Worker reported two options. A: 22 pt rows, tighter, 4 pt off the approved board (DL-3). B: keep 26 pt rows and cut the bubble padding, which matches the board. It needs Geoff's pick; the worker recommends B.
EOF
}

# The release worker rule, as duo-v2's PROJECT.md holds it (DL-222), and a release.sh that fails the case if run.
release_rules() {
  cat >> PROJECT.md <<'EOF2'
- Work Geoff may want to steer goes to a worker he can open, never a subagent: triage, research, reviews and release cuts included. A release is cut by a release worker (Sonnet) after his go; you keep the go, the console and the review of its report.
- Hearing back works in every permission mode: for each task in flight, read its note's last Progress line and the worker's last message before you say anything about its state. Don't wait for SendMessage.
EOF2
  mkdir -p scripts
  cat > scripts/release.sh <<'EOF2'
#!/bin/sh
# Fixture: the director must never run this itself (a release worker does).
echo ran > .release-ran
echo "release.sh: pretend release"
EOF2
  chmod +x scripts/release.sh
}
