# duo-director test harness, Tier 1

Design: `docs/research/director-test-harness.md`. Tier 1 needs no model, no network and no running Duo.

Run it (the build takes the shared compute lock):

    GPU_LOCK=<machine lock> <main checkout>/scripts/gpu-lock.sh --shared director-harness swift build --product duo2
    scripts/check-director.sh [profile…]

For each profile in `profiles/` the check makes a scratch folder under `/tmp/dh-XXXX` (config dir, project with a
`PROJECT.md`, `DUO_SUPPORT_DIR`), then runs `duo2 director status` inside `stub-claude --as-session`, which writes a
session beacon and sets `CLAUDE_PID` and `CLAUDE_CODE_SESSION_ID`. The "This client:" lines must match the profile's
`expect`. It stops at once if the output lacks "Duo isn't running", so it can never reach a real Duo. It also checks
`duo2 director guide` and the stub's `--bg --resume` and unknown-flag behaviour.

`stub-claude` (Python 3) is driven by the profile named in `STUB_PROFILE`:
`--version`/`--help` and the accepted flags come from the profile; `--bg` and `--bg --resume` (new id, same name) keep
a list in `$CLAUDE_CONFIG_DIR/stub-sessions.json` that `agents --json` prints; `-p` prints `$STUB_REPLY` and logs
resumed turns to `stub-turns.jsonl`; interactive mode writes a beacon and blocks on stdin; a beacon has
`peerFeatures` and `messagingSocketPath` only when `stub.messaging` is true.

## Profile shape

    { "name": "pinned-219-strict", "claude": "stub",
      "stub": { "version": "2.1.219", "flags": ["--bg", "--settings"], "messaging": false },
      "settings": { … },            // becomes <config>/settings.json
      "flags": { "monitor": false }, // becomes cachedGrowthBookFeatures.tengu_amber_sentinel in <config>/.claude.json
      "env": { … },
      "duo": "none",
      "expect": { "version": "2.1.219", "messaging": "no", "background": "yes", "backgroundResume": "no",
                  "remoteControl": "no", "hooks": "no", "monitor": "no" } }

The managed settings file is system-wide and is never written; managed-only keys sit in `settings` (a user-scope
disable behaves the same, F-311). `ClientCaps.probe` still reads the real managed file at its fixed path, so a Mac
with managed settings can show different values.

## The duties check (`== duties`)

After the profiles, `check-director.sh` runs one more section that proves each red line `duo2 director status`
opens with (DL-319, the register in the skill's "Your duties") with the real binary, no model and no Duo. Run it alone
with `scripts/check-director.sh duties`; naming profiles runs only those, and no argument runs everything.

It works in one scratch folder under `/tmp/dh-XXXX`, with the loop's isolation (`DUO_ISOLATED=1`, `DUO_TEST_DUO_CLOSED=1`,
a scratch `DUO_SUPPORT_DIR` and `CLAUDE_CONFIG_DIR`, and the stop if the output lacks "Duo isn't running"), the `current`
profile (it has messaging), `DUO_CLAUDE_APP_DIR` pointed at a scratch folder standing in for the Claude app's records, and
a stand-in `claude` first on `PATH` that says it's logged in, so R8's CLI line never depends on the Mac it runs on. Each
rule gets a fixture built by hand (task notes, `.duo/director.json` workers, `.duo/director-log.jsonl` events, a transcript
at `$CLAUDE_CONFIG_DIR/projects/x/<session id>.jsonl`, `claude-code-sessions/a/b/scheduled-tasks.json` and `local_*.json`
runs) with dates taken from `date`, and an assertion on the printed line:

- R1 to R9 each fire on their fixture and not on the near miss (a future `check_by`, a routine check, a job in another
  folder, a corrupt then a missing scheduled-runs folder, Auto after bypass, a check after the first of three sends).
- R5 and R6 collapse to one line with a count however many notes; a review note never also gets R1, R2 or R6.
- A `_` note never appears, with or without `--all`; the task list shrinks to running workers while the red lines still
  name the rest.
- `duo2 director check` (with Duo closed, as the recorded director) writes a `Checked:` line, moves `check_by`, logs the
  event and clears the note's R1 and R2; a job check with `--routine` touches no note; empty evidence, a bad `--next` and
  an unknown task exit non-zero and change nothing; `--next none` clears `check_by`. `director start` writes a `check_by`
  except with `--suggest`. A verb that worked ends with `N red line(s): run duo2 director status.` only when one is open.
- Speed: `status` over 100 notes prints its time and fails over 2 s.

R8's Duo lines (a Duo running but unreachable, hot, or not checking for updates) can't fire here, because Duo's process
and update-check facts are never read in a test context: DuoChecks proves those (`DUO_CHECKS=director-duties swift run
DuoChecks`, which also checks that every duty has a row in the skill and a tagged eval). The section uses BSD `date -v`,
so it runs on a Mac only.

## The duty evals (Tier 2)

`skills/duo-director/evals/s25` to `s33` are scenario evals tagged `duty-Rn` for the duty each proves (s04 also carries
`duty-R5`); DuoChecks fails if a duty has no tagged case. Their scaffolds source `evals/_lib/fixtures.sh` after
`setup.sh`: dates relative to now (`ago`, `agoz`, `agoms`), `task_note`, `registry_worker` (a `workers` entry, never a
`current` one: that would make the caller read as another director and status would print no red lines), `log_event`, and
`wrap_duo2`, which makes `duo2` export a private location first (`DUO_CLAUDE_APP_DIR` for scheduled runs in s27,
`CLAUDE_CONFIG_DIR` for the installed skill in s32) and then run the real one. Run them with `run-evals.sh --case 's2[5-9]*'`
and `--case 's3[0-3]*'` (they spend real model turns; the check above doesn't).
