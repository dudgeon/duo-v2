import React from 'react';
import {AbsoluteFill} from 'remotion';
import type {SceneProps} from '../registry';
import {PaperGround} from '../../lib/Paper';
import {centre, Heading, L, lerp, Meter, mixBox, mono, Pulse, ramp, spring, ui, Wire, type Box} from './kit';
import {BUS_X, PANEL, panelRow, SURVEY, TREE_DIRECTOR, TREE_YOU} from './board';
import {Tree} from './Tree';
import {SkillPage, SECTIONS} from './Skill';

// S4 · What we added. It opens on S3's last picture (the skill page and ledger open over the dimmed tree). The page
// folds back into the director, the tree comes back and makes room for a timeline of the director's first week, and
// each addition drops onto its date as the voice names it while the tree changes to match: briefs go out to new
// sessions; the sessions run in the background where your phone can follow them; three model tiers; decisions as
// buttons on a console page; and the messages that carry reports back.

/** The tree's layout with room for the timeline under it. */
export const T2_YOU: Box = {x: 144, y: 520, w: 300, h: 168};
export const T2_DIRECTOR: Box = {x: 600, y: 504, w: 380, h: 200};
export const T2_PANEL: Box = {x: 1180, y: 150, w: 596, h: 652};
export const T2_ROW_H = 56;
export const t2Row = (k: number): Box => ({x: T2_PANEL.x + 2, y: T2_PANEL.y + 72 + k * T2_ROW_H, w: T2_PANEL.w - 4, h: T2_ROW_H});
export const PHONE: Box = {x: 204, y: 236, w: 180, h: 260};

/** The timeline: Oct 5 to Oct 12. */
export const AXIS_Y = 850, AXIS_X0 = 200, AXIS_X1 = 1720;
export const dayX = (d: number) => AXIS_X0 + ((d - 5) * (AXIS_X1 - AXIS_X0)) / 7;

/** The additions, on the day each came in (decisions.md, the director skill), the word that drops each, and its row. */
const ADDS: {label: string; day: number; word: string; row: 0 | 1}[] = [
  {label: 'Delegate', day: 6, word: 'delegates', row: 0},
  {label: 'Remote Control', day: 7, word: 'background', row: 0},
  {label: 'Model rule', day: 8, word: 'model', row: 0},
  {label: 'Console', day: 9, word: 'buttons', row: 0},
  {label: 'Messages', day: 9, word: 'message', row: 1},
];

/** Which model each panel slot runs on, and the word that reveals each tier (DL-153). */
export const TIERS = ['Opus', 'Sonnet', 'Sonnet', 'Opus', 'Sonnet', 'Sonnet', 'Haiku', 'Haiku', 'Sonnet', 'Haiku'];
const TIER_WORD: Record<string, string> = {Opus: 'plans', Sonnet: 'builds', Haiku: 'tests'};
const TIER_FILL: Record<string, string> = {Opus: L.chatYou, Sonnet: L.diffAddFill, Haiku: L.ground};

export const TierPill = ({x, y, tier, u}: {x: number; y: number; tier: string; u: number}) => (
  <div style={{position: 'absolute', left: x, top: y, padding: '2px 12px', borderRadius: 9, background: TIER_FILL[tier], fontFamily: mono,
    fontSize: 18, lineHeight: '26px', color: L.text, opacity: u, transform: `translateX(${(1 - u) * 10}px)`}}>{tier}</div>
);

/** A phone: the console page on it once decisions come as buttons, a list of sessions before. */
export const Phone = ({box, u, console: consoleU}: {box: Box; u: number; console: number}) => (
  <div style={{position: 'absolute', left: box.x, top: box.y, width: box.w, height: box.h, boxSizing: 'border-box', borderRadius: 30,
    border: `6px solid ${L.text}`, background: L.pane, overflow: 'hidden', opacity: u, transform: `translateY(${(1 - u) * 16}px)`, fontFamily: ui}}>
    <div style={{position: 'absolute', inset: '22px 14px', opacity: 1 - consoleU}}>
      {SURVEY.slice(0, 5).map((s, k) => (
        <div key={k} style={{display: 'flex', alignItems: 'center', gap: 8, height: 30}}>
          <div style={{width: 10, height: 10, borderRadius: 5, background: s.state === 'needs' ? L.needsYou : 'transparent',
            border: s.state === 'needs' ? 'none' : `1.5px solid ${L.text2}`}} />
          <div style={{flex: 1, height: 8, borderRadius: 4, background: L.placeholderBar}} />
        </div>
      ))}
    </div>
    <div style={{position: 'absolute', inset: '22px 14px', opacity: consoleU, display: 'flex', flexDirection: 'column', gap: 10}}>
      <div style={{fontSize: 14, lineHeight: '18px', fontWeight: 600, letterSpacing: 0.8, color: L.needsYou}}>NEEDS YOU</div>
      <div style={{fontSize: 16, lineHeight: '20px', fontWeight: 600, color: L.text}}>Release 0.2.8?</div>
      <div style={{padding: '8px 10px', borderRadius: 8, background: L.text, color: L.pane, fontSize: 14, lineHeight: '18px'}}>Ship it<br /><span style={{opacity: 0.7}}>recommended</span></div>
      <div style={{padding: '8px 10px', borderRadius: 8, border: `1.5px solid ${L.controlEdge}`, color: L.text, fontSize: 14, lineHeight: '18px'}}>Hold</div>
    </div>
  </div>
);

export const Additions = ({t, ev}: SceneProps) => {
  const fold = ev.fold ?? 0.6;
  // S3's page folds back into the director; the tree comes back, then makes room for the timeline.
  const open = 1 - spring(t, fold, 6, 0.95);
  const dimU = 0.2 + 0.8 * ramp(t, fold + 0.3, fold + 0.9);
  const move = spring(t, fold + 0.5, 5, 0.95);
  const you = mixBox(TREE_YOU, T2_YOU, move), director = mixBox(TREE_DIRECTOR, T2_DIRECTOR, move), panel = mixBox(PANEL, T2_PANEL, move);
  const row = (k: number) => mixBox(panelRow(k), t2Row(k), move);
  const axis = ramp(t, fold + 0.8, fold + 1.6);
  const lit = (k: number) => (SECTIONS[k][1] && (SECTIONS[k][1] === 'brief' || SECTIONS[k][1] === 'review' || SECTIONS[k][1] === 'ask') ? 1 : 0);

  const drop = (w: string) => (ev[w] !== undefined ? spring(t, ev[w], 9, 0.8) : 0);
  const at = (w: string, d = 0) => (ev[w] ?? 1e9) + d;

  // Line 1: a brief goes out from the director to a new piece of work.
  const briefAt = at('session');
  const bc = centre(director);
  // Line 2: the sessions are in the background; your phone follows them.
  const bgU = ramp(t, at('background'), at('background', 0.4));
  const phoneU = spring(t, at('phone', -0.2), 8, 0.9);
  // Line 3: three tiers. Line 4: the console on the phone. Line 5: reports and wake-ups as messages.
  const tierU = (tier: string) => ramp(t, at(TIER_WORD[tier]), at(TIER_WORD[tier], 0.35));
  const consoleU = ramp(t, at('buttons'), at('buttons', 0.4));
  const reportRows = [2, 4, 5];

  return (
    <AbsoluteFill>
      <PaperGround />
      <Heading title="Writing the job down" sub="So it survives a long run." u={1 - ramp(t, fold, fold + 0.4)} />
      <Heading title="What we added" sub="One change at a time, each when we needed it." u={ramp(t, fold + 0.6, fold + 1.1)} />

      <Tree you={you} director={director} panel={panel} row={row} busX={lerp(BUS_X, 1080, move)} youU={dimU} panelU={dimU} wiresU={dimU}
        sub={t < at('model') ? 'reads SKILL.md' : 'Opus · plans and reviews'} needs={0} chip={2} directorChildren={<Meter fill={0.12} u={1 - ramp(t, fold, fold + 0.4)} />}
        label={bgU > 0.5 ? 'IN THE BACKGROUND · 10' : 'SESSIONS · 10'}
        rowRight={(k) => <TierPill x={row(k).x + row(k).w - 120} y={row(k).y + (T2_ROW_H - 30) / 2} tier={TIERS[k]} u={tierU(TIERS[k])} />} />
      {/* The background lane: a dashed outline around the panel once the sessions run there. */}
      <div style={{position: 'absolute', left: panel.x - 14, top: panel.y - 14, width: panel.w + 28, height: panel.h + 28, boxSizing: 'border-box',
        border: `2px dashed ${L.controlEdge}`, borderRadius: 18, opacity: bgU}} />

      <SkillPage open={open} lit={lit} ledger={() => open} />

      {/* The brief going out (line 1), and reports coming back as messages (line 5). */}
      <Pulse a={[director.x + director.w, bc[1]]} b={[BUS_X, centre(row(4))[1]]} u={(t - briefAt) / 0.7} color={L.text} />
      {reportRows.map((k, i) => (
        <Pulse key={`r${k}`} a={[panel.x, centre(row(k))[1]]} b={[director.x + director.w, bc[1]]} u={(t - at('tells', 0.15 * i)) / 0.8} color={L.text} r={7} />
      ))}
      <Pulse a={[director.x + director.w, bc[1]]} b={[panel.x, centre(row(4))[1]]} u={(t - at('wakes')) / 0.8} color={L.text} r={7} />

      <Phone box={PHONE} u={phoneU} console={consoleU} />

      {/* The timeline of the first week, with each addition on its day. */}
      <Wire pts={[[AXIS_X0, AXIS_Y], [AXIS_X1, AXIS_Y]]} draw={axis} color={L.text} width={3} head />
      {[5, 6, 7, 8, 9, 10, 11, 12].map((d) => (
        <div key={d} style={{position: 'absolute', left: dayX(d) - 40, top: AXIS_Y + 16, width: 80, textAlign: 'center', fontFamily: mono, fontSize: 18,
          lineHeight: '24px', color: L.text2, opacity: ramp(axis, (d - 5) / 8, (d - 4) / 8)}}>Oct {d}</div>
      ))}
      {ADDS.map((a) => {
        const u = drop(a.word), y = a.row === 0 ? AXIS_Y - 70 : AXIS_Y - 124;
        return (
          <React.Fragment key={a.label}>
            <div style={{position: 'absolute', left: dayX(a.day) - 1.5, top: y + 44, width: 3, height: AXIS_Y - y - 44, background: L.text2, opacity: Math.min(1, u)}} />
            <div style={{position: 'absolute', left: dayX(a.day), top: lerp(y - 40, y, Math.min(1.1, u)), transform: 'translateX(-50%)', padding: '6px 14px',
              borderRadius: 10, background: L.pane, border: `2px solid ${L.rule}`, fontFamily: ui, fontSize: 20, lineHeight: '28px', fontWeight: 600,
              color: L.text, whiteSpace: 'nowrap', opacity: Math.min(1, u * 1.4)}}>{a.label}</div>
          </React.Fragment>
        );
      })}
    </AbsoluteFill>
  );
};

/** S4's last picture, for the scene after it to open on. */
const END_EV = {fold: 0, session: 1, delegates: 1.5, background: 2, phone: 2.3, model: 3, plans: 3.2, builds: 3.5, tests: 3.8, buttons: 4.2,
  message: 5, tells: 5.3, wakes: 6};
export const AdditionsEnd = () => <Additions t={999} ev={END_EV} scene={{id: 'S4', title: ''}} />;
