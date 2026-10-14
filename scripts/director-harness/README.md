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
