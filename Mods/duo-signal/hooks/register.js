// duo-signal (ENH-70, DL-183): a sensor, never a decoration. It draws nothing and changes nothing:
// every hook only notes what it saw and passes its event on unchanged, with no wait and no I/O of
// its own, so a slow disk or a fault here can't hold up a turn or a permission question (a hook
// that hangs at a gating site costs the session 10 s and can lose the question, F-297). All writing
// is on a timer started at session.start: one small JSON snapshot of the session's state in
// $DUO_SIGNAL_FILE, written within 100 ms of a change and every 500 ms regardless, as a heartbeat,
// so Duo can tell a live signal from a silent, refused or crashed one and fall back to the screen.
// Without $DUO_SIGNAL_FILE (a session Duo didn't start, a nested claude) it does nothing at all.
// The engine wants `$` spelled at each call (`claude plugin validate`), so nothing holds it.
export function register(on) {
  const s = { v: 1, seq: 0, at: 0, version: null, busy: false, aborted: false, turns: 0, working: null, draft: null, question: null }
  let file, dirty = false, written = 0
  const note = f => { if (file !== undefined) { f(); dirty = true } }

  on('session.start', async ($, e, next) => {
    file = await $.env.get('DUO_SIGNAL_FILE')
    if (file !== undefined) {
      try { s.version = (await $.session.version()).version } catch {}
      dirty = true
      $.clock.every(100, async () => {
        const now = await $.clock.now()
        if (!dirty && now - written < 500) return
        dirty = false; written = now
        s.seq += 1; s.at = now
        try { await $.fs.write(file, JSON.stringify(s) + '\n') } catch {}
      })
    }
    return next(e)
  }).catch(($, e, next) => next(e))

  on('turn.start', ($, e, next) => {
    note(() => { s.busy = true; s.aborted = false; s.turns += 1; s.question = null })
    return next(e)
  }).catch(($, e, next) => next(e))

  on('turn.complete', async ($, e, next) => {
    const done = await next(e)
    if (!e.agentId) note(() => { s.busy = false; s.aborted = e.isAborted === true; s.question = null })
    return done
  }).catch(($, e, next) => next(e))

  // The permission question: the engine's verdict is `ask` for a call on the main loop.
  on('tool.check', async ($, e, next) => {
    const verdict = await next(e)
    if (e.tool_use_id && !e.agentId && verdict?.decision === 'ask') {
      note(() => { s.question = { tool: e.tool, id: e.tool_use_id, input: e.input ?? null } })
    }
    return verdict
  }).catch(($, e, next) => next(e))

  // A call that ran (allowed, answered, or never asked) closes its question.
  on('tool.call', async ($, e, next) => {
    const r = await next(e)
    if (s.question?.id === e.tool_use_id) note(() => { s.question = null })
    return r
  }).catch(($, e, next) => next(e))

  // Whether a turn runs and the prompt holds a draft, as the hint line is drawn; drawn unchanged.
  // (SessionMode, the footer's mode labels, is never raised on 2.1.296's terminal, so the mode
  // stays the screen's.)
  on('ui.render', { component: 'PromptHint' }, ($, e, next) => {
    const w = e.props?.isWorking ?? null, d = e.props?.isDraft ?? null
    if (w !== s.working || d !== s.draft) note(() => { s.working = w; s.draft = d })
    return next(e)
  }).catch(($, e, next) => next(e))
}
