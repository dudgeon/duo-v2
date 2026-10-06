// Reads Claude Code's TUI screen (2.1.291) into a state chat mode can show. Anything it can't name
// is "unknown", and unknown means fall back to the terminal (DL-118).
// A full-width rule. Once a session has a name, the TUI writes it into the input box's top rule
// ("──── add-second-line-notes ─"), seen with a real model, never with the mock (F-105).
const RULE = /^─{20,}(?: \S.*\S ─+)?$/;
const opt = /^\s*(❯)?\s*(\d+)\.\s(\[[ ✔]\]\s)?(.*)$/;

function options(lines, from, to, cols = 100) {
  const out = [];
  for (let i = from; i < to; i++) {
    if (/^\s*(ctrl\+g|Enter to|Esc to)/.test(lines[i])) break;
    const m = lines[i].match(opt);
    if (m) out.push({ n: +m[2], label: m[4].trim(), cursor: !!m[1], checked: m[3] ? m[3].includes('✔') : undefined, note: '' });
    else if (out.length && lines[i].trim() && !/^(Enter to|Esc to|ctrl\+g|─|╌)/.test(lines[i].trim())) {
      const last = out[out.length - 1];
      if (lines[i - 1].length >= cols - 4 && !last.note) { last.label += ' ' + lines[i].trim(); continue; }  // a label wrapped at the edge
      // Wrapped label lines sit under the label; descriptions sit deeper. Both are kept as text.
      last.note = (last.note ? last.note + ' ' : '') + lines[i].trim();
    }
  }
  return out;
}

export function classify(text, solid = text) {
  const lines = text.split('\n');
  const sl = solid.split('\n');
  const t = lines.map(l => l.trimEnd());
  const rules = t.map((l, i) => RULE.test(l.trim()) ? i : -1).filter(i => i >= 0);
  // The status footer sits under the input box, which is not always at the bottom of the screen.
  const footer = (rules.length ? t.slice(rules[rules.length - 1] + 1, rules[rules.length - 1] + 3) : t.slice(-3)).join(' ');
  const mode = /plan mode on/.test(footer) ? 'plan' : /accept edits on/.test(footer) ? 'accept-edits' : /manual mode on/.test(footer) ? 'manual' : null;
  // The input box: the last two full-width rules with "❯ " between them.
  let input = null;
  if (rules.length >= 2) {
    const a = rules[rules.length - 2], b = rules[rules.length - 1];
    if (b > a && /^❯/.test(t[a + 1] ?? '')) input = sl.slice(a + 1, b).map(l => l.trimEnd()).map((l, i) => i === 0 ? l.replace(/^❯\s?/, '') : l.replace(/^  /, '')).join('\n').trimEnd();
  }
  const busy = /esc to interrupt/.test(footer);
  const find = re => t.findIndex(l => re.test(l));

  // Plan approval.
  const ready = find(/^\s*Ready to code\?/);
  if (ready >= 0 && find(/Would you like to proceed\?/) > ready) {
    const q = find(/Would you like to proceed\?/);
    return { kind: 'plan', title: 'Ready to code?', options: options(t, q + 1, t.length), mode, sig: 'plan:' + t[q].trim() };
  }
  // Permission dialog: "Do you want to …?" with numbered options and "Esc to cancel".
  const dw = find(/^\s*Do you want to .*\?\s*$/);
  if (dw >= 0 && find(/Esc to cancel/) > dw) {
    const top = rules.filter(i => i < dw).pop() ?? 0;
    const head = t.slice(top + 1, dw).filter(l => l.trim() && !/^╌+$/.test(l.trim()));
    if (!options(t, dw + 1, t.length).length) return { kind: 'unknown', sig: 'unknown', why: 'a question with no options' };
    return { kind: 'permission', title: t[dw].trim(), kindLabel: head[0]?.trim(), body: head.slice(1).map(l => l.replace(/^ /, '')).join('\n'), options: options(t, dw + 1, t.length), amend: /Tab to amend/.test(t.join(' ')), mode, sig: 'perm:' + t[dw].trim() };
  }
  // AskUserQuestion: a tab strip of ☐/☒ headers or one header, a question, numbered options.
  const review = find(/^Review your answers/);
  if (review >= 0 && find(/Ready to submit your answers\?/) > review) {
    {
      const strip = t.find(l => /(☐|☒)/.test(l)) || '';
      return { kind: 'question-review', tabs: [...strip.matchAll(/(☐|☒|✔)\s([^☐☒✔→]+?)(?=\s{2}|\s*→|$)/g)].map(m => ({ done: m[1] !== '☐', label: m[2].trim() })), options: options(t, find(/Ready to submit your answers\?/) + 1, t.length), answers: t.slice(review + 1, find(/Ready to submit/)).join('\n').trim(), sig: 'review' };
    }
  }
  const nav = find(/^Enter to select · /);
  if (nav >= 0) return question(t, sl, nav);
  const status = rules.length >= 2 ? t.slice(0, rules[rules.length - 2]).reverse().find(l => /^[✻✽✶✳✢·*] \S/.test(l)) : null;
  if (input !== null) return { kind: busy ? 'busy' : 'idle', input, mode, status: status?.trim(), menu: /^\s+❯ \//.test(t[rules[rules.length - 2] - 4] ?? '') || t.some(l => /^\s{2}❯ \/\S+\s{2,}/.test(l)), sig: 'input' };
  return { kind: 'unknown', sig: 'unknown' };
}

// AskUserQuestion (F-106). Every row in screen order, so answers can steer the cursor row by row:
//   option  a choice ("1. Postgres", "1. [✔] Lint"; a chosen answer on a revisited question ends " ✔")
//   other   the free-text row ("Type something." until typed into; typing ticks it on multi-select)
//   next / submit   the unnumbered row under a multi-select list
//   chat    "Chat about this", below the rule (numbered, or not in the preview layout)
// The preview layout draws the focused option's preview in a box to the right of the list, has no
// free-text row, and takes notes with "n".
const BOX = /\s{2,}(?=[┌│└├])/;   // ├ is the clipped preview's "✂ n lines hidden" row
function question(t, sl, nav) {
  const tabsAt = t.findIndex(l => /(☐|☒)/.test(l));
  const strip = tabsAt >= 0 ? t[tabsAt] : '';
  const tabs = [...strip.matchAll(/(☐|☒|✔)\s([^☐☒✔→]+?)(?=\s{2}|\s*→|$)/g)].map(m => ({ done: m[1] !== '☐', label: m[2].trim() }));
  const rows = [];
  const qlines = [];
  let afterRule = false, preview = false, notes = null;
  const widest = Math.max(...t.map(l => l.length));
  for (let i = tabsAt + 1; i < nav; i++) {
    const raw = t[i];
    if (!raw.trim()) continue;
    if (/^─{20,}/.test(raw.trim())) { afterRule = true; continue; }
    const nm = raw.match(/Notes: (.*)$/);
    if (nm) { notes = /^(press n to add notes|Add notes on this design…)$/.test(nm[1].trim()) ? '' : nm[1].trim(); continue; }
    if (BOX.test(raw)) preview = true;
    const left = raw.split(BOX)[0];
    const solid = (sl[i] ?? '').split(BOX)[0];
    let m = left.match(/^\s*(❯)?\s*(\d+)\.\s(\[([ ✔])\]\s)?(.*?)\s*$/);
    if (m) {
      let label = m[5], selected = false;
      if (/ ✔$/.test(label)) { selected = true; label = label.replace(/ ✔$/, ''); }
      const sm = solid.match(/^\s*(?:❯)?\s*\d+\.\s(?:\[[ ✔]\]\s)?(.*?)\s*$/);
      rows.push({ kind: afterRule && label === 'Chat about this' ? 'chat' : 'option', n: +m[2], label, cursor: !!m[1],
                  checked: m[3] ? m[4] === '✔' : undefined, selected, note: '', solid: sm ? sm[1] : label, at: i });
      continue;
    }
    m = left.match(/^\s*(❯)?\s+(Next|Submit)\s*$/);
    if (m && rows.length) { rows.push({ kind: m[2].toLowerCase(), label: m[2], cursor: !!m[1] }); continue; }
    m = left.match(/^\s*(❯)?\s*Chat about this\s*$/);
    if (m) { rows.push({ kind: 'chat', label: 'Chat about this', cursor: !!m[1] }); continue; }
    const last = rows[rows.length - 1];
    if (!last) { qlines.push(left.trim().replace(/^│\s?/, '')); continue; }   // the question, possibly wrapped
    if (last.kind === 'option' && left.trim()) {
      if (!last.note && t[i - 1].length >= widest - 4) last.label += ' ' + left.trim();   // a label wrapped at the edge
      else last.note = (last.note ? last.note + ' ' : '') + left.trim();
    }
  }
  // The free-text row is the last numbered row above the rule (not in the preview layout).
  if (!preview) {
    const above = rows.filter(r => r.kind === 'option' && (afterRule ? true : true));
    const ruleRow = rows.findIndex(r => r.kind === 'chat');
    const cands = rows.slice(0, ruleRow < 0 ? rows.length : ruleRow).filter(r => r.kind === 'option');
    const other = cands[cands.length - 1];
    if (other && rows.length > 1) {
      other.kind = 'other';
      other.value = /^Type something\.?$/.test(other.solid.trim()) || !other.solid.trim() ? '' : other.solid.replace(/\s+$/, '');
    }
  }
  const multi = rows.some(r => r.checked !== undefined);
  const q = qlines.join(' ').replace(/\s+/g, ' ').trim();
  return { kind: 'question', tabs, question: q, rows, options: rows.filter(r => r.kind === 'option'), other: rows.find(r => r.kind === 'other') || null,
           cursor: rows.findIndex(r => r.cursor), multi, preview, notes, sig: 'q:' + q };
}
