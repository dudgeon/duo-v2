import { test, expect, mock } from 'claude-code/testing'

// Duo's canary (F-297), run by `claude plugin test`: with no session and no tokens, it passes only
// when this Claude Code lets mods run here (its rollout switch, disableAllHooks, allowManagedHooksOnly
// and the organization's policy) and duo-signal loads, hears a session start and writes its snapshot.
test('duo-signal loads and writes its snapshot', async ($, on) => {
  const clock = mock.clock(on, { now: 1000 })
  mock.env(on, { DUO_SIGNAL_FILE: '/duo-canary/signal.json' })
  const written: string[] = []
  on("fs.write", async ($, e) => { written.push(e.text); return { value: undefined } })
  on('session.start', async ($, e) => ({ cwd: e.cwd }))
  await $.session.start({ cwd: '/duo-canary', surface: 'terminal', isInteractive: true })
  await clock.advance(150)
  expect(written.length).toBeGreaterThan(0)
  expect(JSON.parse(written[written.length - 1])).toEqual(expect.objectContaining({ v: 1, busy: false }))
})
