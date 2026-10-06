// Answering AskUserQuestion with keys (F-106). The card says what the human chose (an intent);
// this steers the real TUI there one key at a time, re-reading the screen after every key, and
// stops the moment the screen isn't what it expects. Nothing is chosen for the human: every intent
// names the row they clicked, and only the TUI's own keys move it.
//
// io: { read() → screen state (screen.mjs), key(name), type(text), sleep(ms), request() → the
//       pending AskUserQuestion tool_input from the PermissionRequest hook, or null }
//
// Intents:
//   { type: 'pick', label }        single-select: move to the option, Enter (moves on or submits)
//   { type: 'toggle', label }      multi-select: move to the option, Space
//   { type: 'other', text }        move to the free-text row, replace its text, then Enter on
//                                  single-select (multi-select ticks it by itself)
//   { type: 'next' }               multi-select: Enter on the Next/Submit row under the list
//   { type: 'tab', index }         go to question <index> (0-based), or the review page (= count)
//   { type: 'notes', label, text } preview layout: move to the option, n, type, Enter (selects it)
//   { type: 'chat' }               "Chat about this": ends the question, back to the prompt
//   { type: 'submit' } / { type: 'cancel-review' }   the review page
//   { type: 'decline' }            Esc

const norm = s => String(s ?? '').replace(/\s+/g, ' ').trim();

export async function runAsk(intent, io, expectSig) {
  const fail = why => ({ ok: false, why });
  let s = io.read();
  if (expectSig && s.sig !== expectSig) return fail('the question changed before your answer arrived');
  if (s.kind !== 'question' && s.kind !== 'question-review') return fail(`the terminal shows ${s.kind}, not a question`);

  // The screen and the hook must tell the same story: the question on screen is one Claude asked.
  const req = io.request();
  if (!req) return fail('no question is pending from Claude');
  const qs = req.questions || [];
  // A short terminal scrolls the top of a long question off screen: the visible text is then the
  // end of exactly one asked question. Labels can wrap, so each label on screen must be the start
  // of the asked label in the same place; the card shows the asked text in full (F-106).
  const same = (asked, shown) => norm(asked) === norm(shown) || (norm(shown).length >= 20 && norm(asked).endsWith(norm(shown)));
  const locate = st => {
    const hits = qs.map((q, i) => same(q.question, st.question) ? i : -1).filter(i => i >= 0);
    return hits.length === 1 ? hits[0] : -1;
  };
  const qIndex = s.kind === 'question' ? locate(s) : qs.length;
  if (qIndex < 0) return fail('the question on screen is not the one Claude asked');
  if (s.kind === 'question') {
    const asked = qs[qIndex].options.map(o => norm(o.label));
    const shown = s.options.map(o => norm(o.label));
    if (asked.length !== shown.length || asked.some((l, i) => !shown[i] || !l.startsWith(shown[i]))) return fail('the options on screen differ from what Claude asked');
  }
  // The option row for an asked label: by position, since a wrapped label shows only its start.
  const optionRow = label => r => r.kind === 'option' && s.options.indexOf(r) === qs[locate(s)]?.options.findIndex(o => norm(o.label) === norm(label));

  // The review page reads as its own kind; give it rows so goTo works there too.
  const withRows = () => { if (s.kind === 'question-review') { s.rows = s.options.map(o => ({ kind: 'option', label: o.label, cursor: o.cursor })); s.cursor = s.rows.findIndex(r => r.cursor); } };
  const step = async k => { await io.key(k); await io.sleep(120); s = io.read(); withRows(); };
  // Moves the cursor to the first row matching `want`, one arrow at a time.
  const goTo = async want => {
    for (let i = 0; i < 16; i++) {
      if (!s.rows) return false;
      const target = s.rows.findIndex(want);
      if (target < 0) return false;
      if (s.cursor === target) return true;
      if (s.cursor < 0) return false;
      await step(target > s.cursor ? 'down' : 'up');
      if (s.kind !== 'question' && s.kind !== 'question-review') return false;
    }
    return false;
  };
  withRows();

  switch (intent.type) {
    case 'pick': case 'toggle': {
      if (s.kind !== 'question') return fail('not on a question');
      if ((intent.type === 'toggle') !== !!s.multi) return fail(s.multi ? 'this question takes several answers' : 'this question takes one answer');
      if (!await goTo(optionRow(intent.label))) return fail(`couldn't reach "${intent.label}"`);
      await step(intent.type === 'pick' ? 'enter' : 'space');
      return { ok: true };
    }
    case 'other': {
      if (s.kind !== 'question' || !s.other) return fail('this question has no free-text answer');
      if (!await goTo(r => r.kind === 'other')) return fail("couldn't reach the free-text row");
      // Replace what's there: Backspace over the typed text (the placeholder isn't text).
      for (const _ of [...(s.other.value || '')]) await io.key('bs');
      await io.type(intent.text);
      await io.sleep(150); s = io.read(); withRows();
      if (s.kind !== 'question' || norm(s.other?.value) !== norm(intent.text)) return fail('the typed answer did not appear as sent');
      if (!s.multi) await step('enter');
      return { ok: true };
    }
    case 'next': {
      if (s.kind !== 'question' || !s.multi) return fail('Next is for multi-select questions');
      if (!await goTo(r => r.kind === 'next' || r.kind === 'submit')) return fail("couldn't reach Next");
      await step('enter');
      return { ok: true };
    }
    case 'tab': {
      // ← and → move between questions, but not from inside the free-text row (they move its caret).
      for (let i = 0; i < 10; i++) {
        const here = s.kind === 'question' ? locate(s) : qs.length;
        if (here === intent.index) return { ok: true };
        if (s.kind === 'question' && s.rows[s.cursor]?.kind === 'other') await step('up');
        await step(intent.index > here ? 'right' : 'left');
      }
      return fail("couldn't reach that question");
    }
    case 'notes': {
      if (s.kind !== 'question' || !s.preview) return fail('notes are for questions with previews');
      if (!await goTo(optionRow(intent.label))) return fail(`couldn't reach "${intent.label}"`);
      await step('n');
      await io.type(intent.text);
      await io.sleep(150); s = io.read(); withRows();
      if (norm(s.notes) !== norm(intent.text)) return fail('the notes did not appear as typed');
      await step('enter');
      return { ok: true };
    }
    case 'chat': {
      if (!await goTo(r => r.kind === 'chat')) return fail('no "Chat about this" here');
      await step('enter');
      return { ok: true };
    }
    case 'submit': case 'cancel-review': {
      if (s.kind !== 'question-review') return fail('not on the review page');
      const label = intent.type === 'submit' ? 'Submit answers' : 'Cancel';
      if (!await goTo(r => r.label === label)) return fail(`couldn't reach "${label}"`);
      await step('enter');
      return { ok: true };
    }
    case 'decline': await step('esc'); return { ok: true };
  }
  return fail('unknown answer');
}
