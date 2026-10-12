import React from 'react';
import {AbsoluteFill} from 'remotion';
import type {SceneProps} from '../registry';
import {PaperGround} from '../../lib/Paper';
import {Heading, L, lerp, Meter, mixBox, mono, ramp, spring, ui, Wire, type Box} from './kit';
import {TREE_DIRECTOR} from './board';
import {Tree} from './Tree';

// S3 · Writing the job down. It opens on S2's tree. The director's context fills up; on "compacted" it collapses and
// the director's job falls away. On "skill" its job unfolds out of it as a page, SKILL.md, whose sections light up as
// the voice names them; on "record" a ledger of numbered decisions stacks beside it. All real: the section titles are
// the skill's own, the records are decisions.md's.

export const SKILL_BOX: Box = {x: 1040, y: 150, w: 520, h: 780};
export const LEDGER_BOX: Box = {x: 1600, y: 150, w: 224, h: 780};

/** The skill's sections (.claude/skills/director/SKILL.md), and which word of line 2 lights each. */
export const SECTIONS: [string, string | null][] = [
  ['0 · Resuming', null], ['1 · Taking work from Geoff', 'brief'], ['2 · Reviewing and merging', 'review'], ['3 · Records', null],
  ['4 · Releases', null], ["5 · Geoff's Duo and sessions", null], ['6 · Talking to Geoff', 'ask'], ['7 · The director console', null],
  ['8 · Dependencies', null],
];

/** A few of the numbered decisions (docs/design/decisions.md), as they were titled. */
export const RECORDS: [string, string][] = [
  ['DL-128', 'Remote Control'], ['DL-145', 'Newer Claude Code versions'], ['DL-151', 'Test builds'], ['DL-153', 'Model efficiency'],
  ['DL-162', 'Word documents'], ['DL-166', 'A director that publishes'], ['DL-173', 'The narrator'], ['DL-179', 'Where the voice lives'],
];
export const DECISIONS = 179;

/** The page and the ledger at a given openness (S3 opens them; S4 folds them back). */
export const SkillPage = ({open, lit, ledger}: {open: number; lit: (k: number) => number; ledger: (k: number) => number}) => {
  if (open <= 0.001) return null;
  const box = mixBox(TREE_DIRECTOR, SKILL_BOX, open);
  const textU = ramp(open, 0.7, 1);
  return (
    <>
      <div style={{position: 'absolute', left: box.x, top: box.y, width: box.w, height: box.h, boxSizing: 'border-box', background: L.pane,
        border: `2px solid ${L.rule}`, borderRadius: 12, overflow: 'hidden'}}>
        <div style={{position: 'absolute', left: 40, top: 32, width: SKILL_BOX.w - 80, opacity: textU, fontFamily: ui, color: L.text}}>
          <div style={{fontFamily: mono, fontSize: 18, lineHeight: '26px', color: L.text2}}>.claude/skills/director/SKILL.md</div>
          <div style={{marginTop: 18, fontSize: 34, lineHeight: '42px', fontWeight: 700}}>Director</div>
          <div style={{marginTop: 6, fontSize: 20, lineHeight: '28px', color: L.text2}}>You're the engineering manager over every Claude session. Geoff is the PM.</div>
          <div style={{marginTop: 22, display: 'flex', flexDirection: 'column', gap: 6}}>
            {SECTIONS.map(([title], k) => (
              <div key={title} style={{padding: '8px 14px', borderRadius: 8, background: `rgba(233,236,239,${lit(k)})`, fontSize: 24, lineHeight: '34px',
                color: lit(k) > 0.5 ? L.text : L.text2, fontWeight: lit(k) > 0.5 ? 600 : 400}}>{title}</div>
            ))}
          </div>
        </div>
      </div>
      {ledger(0) > 0 && (
        <div style={{position: 'absolute', left: LEDGER_BOX.x, top: LEDGER_BOX.y, width: LEDGER_BOX.w, fontFamily: ui}}>
          <div style={{fontSize: 22, lineHeight: '32px', fontWeight: 600, letterSpacing: 1.3, color: L.text2, opacity: ledger(0)}}>DECISIONS · {DECISIONS}</div>
          {RECORDS.map(([id, title], k) => (
            <div key={id} style={{marginTop: 12, padding: '10px 14px', boxSizing: 'border-box', background: L.pane, border: `2px solid ${L.rule}`, borderRadius: 10,
              opacity: Math.min(1, ledger(k) * 1.5), transform: `translateY(${(1 - ledger(k)) * -18}px)`}}>
              <div style={{fontFamily: mono, fontSize: 18, lineHeight: '24px', color: L.text2}}>{id}</div>
              <div style={{fontSize: 20, lineHeight: '26px', color: L.text, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis'}}>{title}</div>
            </div>
          ))}
        </div>
      )}
    </>
  );
};

export const Skill = ({t, ev}: SceneProps) => {
  const compact = ev.compact ?? 1.5, lost = ev.lost ?? compact + 1, skill = ev.skill ?? lost + 2, record = ev.record ?? skill + 4;

  // The director's context: a meter that fills as the session runs, then collapses on "compacted".
  const fill = t < compact ? lerp(0.55, 0.96, ramp(t, 0, compact)) : lerp(0.96, 0.12, spring(t, compact, 9, 0.9));
  const jobU = 1 - ramp(t, lost - 0.2, lost + 0.3); // the job description falls away
  const backU = ramp(t, skill + 0.4, skill + 0.9); // and comes back, read from the skill
  const sub = t < skill ? 'engineering manager · at prompt' : 'reads SKILL.md';
  const subU = t < skill ? jobU : backU;

  const open = spring(t, skill, 6, 0.95);
  const dimU = 1 - 0.8 * ramp(t, skill - 0.2, skill + 0.4);
  const word = (k: number) => SECTIONS[k][1];
  const lit = (k: number) => { const w = word(k); return w && ev[w] !== undefined ? ramp(t, ev[w] - 0.1, ev[w] + 0.25) : 0; };
  const ledger = (k: number) => spring(t, record + 0.18 * k, 10, 0.9);

  const meter = <Meter fill={fill} u={ramp(t, 0, 0.5)} />;

  return (
    <AbsoluteFill>
      <PaperGround />
      <Heading title="A simple prompt" sub="One session manages the others." u={1 - ramp(t, 0.2, 0.6)} />
      <Heading title="Writing the job down" sub="So it survives a long run." u={ramp(t, 0.5, 1.0)} />
      <Tree youU={dimU} panelU={dimU} wiresU={dimU} sub={sub} subU={subU} needs={t < lost ? 2 : 0} directorChildren={meter} />
      <Wire pts={[[TREE_DIRECTOR.x + TREE_DIRECTOR.w, TREE_DIRECTOR.y + 40], [SKILL_BOX.x - 2, TREE_DIRECTOR.y + 40]]} draw={ramp(t, skill + 0.5, skill + 0.9)} head />
      <SkillPage open={open} lit={lit} ledger={ledger} />
    </AbsoluteFill>
  );
};
