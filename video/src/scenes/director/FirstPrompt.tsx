import React from 'react';
import {AbsoluteFill} from 'remotion';
import type {SceneProps} from '../registry';
import {PaperGround} from '../../lib/Paper';
import {C, centre, DirectorCard, Heading, L, mixBox, mono, ramp, SectionLabel, SessionRow, spring, Wire, YouCard, type Box, type State} from './kit';
import {BUS_X, ORDER, PANEL, panelRow, RING_YOU, ringRow, SESSIONS, SURVEY, TREE_DIRECTOR, TREE_YOU} from './board';
import {OpeningEnd} from './Opening';

// S2 · A simple prompt (script v2, Geoff's rewrite, Oct 12). It opens on S1's last picture, the switchboard. Line 1:
// a big orchestrator sketches itself faintly over the dimmed ring, then is set aside: start simple. Line 2: one more
// session opens as a console. Lines 3 to 8: the first prompt and the 10:25 message go onto it as bullets that build in
// time with the voice (Geoff: "split the concepts of the prompt into bullets"). On the last word the console becomes the
// director, the ring settles into style frame B's tree, and the first survey runs down the sessions.

const PROMPT_BOX: Box = {x: 380, y: 196, w: 1160, h: 700};
const slot = (i: number) => ORDER.indexOf(i);
const at = (ev: Record<string, number>, w: string, d = 0) => (ev[w] ?? 1e9) + d;
const has = (ev: Record<string, number>, w: string) => ev[w] !== undefined;

/** The two messages as their ideas, each lit by a word of the voice (the verbatim text is in the script's notes). */
const FIRST: [string, string][] = [['a1', 'Many sessions, in various states'], ['a2', 'You are now their director'], ['a3', 'I am the PM; you are the engineering manager'], ['a4', 'Survey the state of each active session']];
const SECOND: [string, string][] = [['c1', 'Keep a director reviews page: decisions for me, as buttons that message you'], ['c2', 'Branches and worktrees: when to review, merge and ship; how to resolve conflicts'],
  ['c3', 'Watch all the other agents and review their work'], ['c4', 'Surface decisions to me as needed']];

/** The orchestrator Geoff had been thinking about: one agent over layers of agents, sketched and set aside. */
const Orchestrator = ({u, gone}: {u: number; gone: number}) => {
  const top = {x: 960, y: 300}, mid = [700, 960, 1220].map((x) => ({x, y: 470})), leaf = [600, 760, 880, 1040, 1160, 1320].map((x) => ({x, y: 640}));
  const d = (a: number, b: number) => ramp(u, a, b);
  return (
    <svg width={1920} height={1080} style={{position: 'absolute', left: 0, top: 0, opacity: 0.6 * (1 - gone), transform: `scale(${1 - 0.15 * gone})`, transformOrigin: '960px 540px'}}>
      <g fill="none" stroke={L.text} strokeWidth={2} strokeDasharray="6 7">
        {mid.map((m, i) => <path key={i} d={`M ${top.x} ${top.y + 30} L ${m.x} ${m.y - 26}`} opacity={d(0.15 + 0.1 * i, 0.4 + 0.1 * i)} />)}
        {leaf.map((l, i) => <path key={i} d={`M ${mid[Math.floor(i / 2)].x} ${mid[0].y + 26} L ${l.x} ${l.y - 20}`} opacity={d(0.45 + 0.05 * i, 0.7 + 0.05 * i)} />)}
      </g>
      <rect x={top.x - 110} y={top.y - 30} width={220} height={60} rx={10} fill={L.pane} stroke={L.text} strokeWidth={2.5} opacity={d(0, 0.2)} />
      <text x={top.x} y={top.y + 8} textAnchor="middle" fontFamily={mono} fontSize={22} fill={L.text} opacity={d(0, 0.2)}>orchestrator</text>
      {mid.map((m, i) => <rect key={i} x={m.x - 80} y={m.y - 26} width={160} height={52} rx={9} fill={L.pane} stroke={L.text} strokeWidth={2} opacity={d(0.3 + 0.1 * i, 0.5 + 0.1 * i)} />)}
      {leaf.map((l, i) => <rect key={i} x={l.x - 50} y={l.y - 20} width={100} height={40} rx={8} fill={L.pane} stroke={L.text} strokeWidth={1.5} opacity={d(0.6 + 0.05 * i, 0.8 + 0.05 * i)} />)}
    </svg>
  );
};

export const FirstPrompt = ({t, ev}: SceneProps) => {
  const orch = has(ev, 'orch') ? ev.orch : 0.8, simple = has(ev, 'simple') ? ev.simple : orch + 3;
  const open = has(ev, 'session') ? ev.session : simple + 1.5;
  const b0 = at(ev, 'b0'), submit = has(ev, 'submit') ? ev.submit : open + 12, scan = has(ev, 'stood') ? ev.stood : submit + 1.4;

  // S1's ring dims under the orchestrator sketch and the console; on Return the rows fly to the panel.
  const dimU = 1 - 0.75 * ramp(t, orch - 0.2, orch + 0.5);
  const baseU = t < submit ? dimU : dimU * (1 - ramp(t, submit, submit + 0.3));
  const settle = spring(t, submit, 5.5, 0.95);
  const ownU = ramp(t, submit - 0.05, submit + 0.2);
  const sketch = ramp(t, orch, simple), sketchGone = ramp(t, simple, simple + 0.6);

  const appear = spring(t, open, 8, 0.86);
  const small: Box = {x: 960 - 60, y: 540 - 30, w: 120, h: 60};
  const consoleBox = settle > 0 ? mixBox(PROMPT_BOX, TREE_DIRECTOR, settle) : mixBox(small, PROMPT_BOX, appear);
  const promptU = 1 - ramp(t, submit, submit + 0.25);
  const dirU = ramp(t, submit + 0.35, submit + 0.7);
  const lit = (w: string) => ramp(t, at(ev, w, -0.15), at(ev, w, 0.25));

  const you = mixBox(RING_YOU, TREE_YOU, settle);
  const fly = (i: number) => spring(t, submit + 0.05 * slot(i), 5.5, 0.92);
  const rowBox = (i: number) => mixBox(ringRow(i), panelRow(slot(i)), fly(i));
  const scanAt = (k: number) => scan + 0.16 * k;
  const stateOf = (i: number): State => (t >= scanAt(slot(i)) ? SURVEY[slot(i)].state : 'needs');
  const rightOf = (i: number) => (t >= scanAt(slot(i)) ? SURVEY[slot(i)].right : undefined);
  const focusOf = (i: number) => { const d = t - scanAt(slot(i)); return d < 0 ? 0 : Math.max(0, 1 - d / 0.5) * 0.9; };
  const chip = t < scan ? 10 : SURVEY.filter((_, k) => t >= scanAt(k) && SURVEY[k].state === 'needs').length;
  const yc = centre(you), dc = centre(TREE_DIRECTOR);
  const panelU = ramp(t, submit + 0.3, submit + 0.8);

  const bullets = (items: [string, string][]) => (
    <div style={{display: 'flex', flexDirection: 'column', gap: 10, marginTop: 14}}>
      {items.map(([w, text]) => (
        <div key={w} style={{display: 'flex', gap: 16, fontSize: 28, lineHeight: '38px', color: C.consoleText, opacity: lit(w), transform: `translateX(${(1 - lit(w)) * -12}px)`}}>
          <span style={{color: C.consoleText2}}>–</span><span>{text}</span>
        </div>
      ))}
    </div>
  );

  return (
    <AbsoluteFill>
      <PaperGround />
      <div style={{position: 'absolute', inset: 0, opacity: baseU}}><OpeningEnd /></div>
      <Heading title="A simple prompt" sub="One session manages the others." u={ramp(t, submit + 0.6, submit + 1.1)} />
      {sketch > 0 && sketchGone < 1 && <Orchestrator u={sketch} gone={sketchGone} />}

      <div style={{position: 'absolute', inset: 0, opacity: ownU}}>
        <div style={{position: 'absolute', left: PANEL.x, top: PANEL.y, width: PANEL.w, height: PANEL.h, boxSizing: 'border-box', background: L.pane,
          border: `2px solid ${L.rule}`, borderRadius: 12, opacity: panelU}} />
        <SectionLabel x={PANEL.x + 32} y={PANEL.y + 24} text={`SESSIONS · ${SESSIONS.length}`} u={panelU} />
        {SESSIONS.map((_, i) => <Wire key={`w${i}`} pts={[centre(rowBox(i)), centre(you)]} draw={1 - ramp(t, submit, submit + 0.35)} color={L.needsYou} />)}
        <Wire pts={[[TREE_DIRECTOR.x, dc[1]], [TREE_YOU.x + TREE_YOU.w + 1, yc[1]]]} draw={ramp(t, submit + 0.6, submit + 1.0)} head />
        <Wire pts={[[TREE_DIRECTOR.x + TREE_DIRECTOR.w, dc[1]], [BUS_X, dc[1]]]} draw={ramp(t, submit + 0.8, submit + 1.3)} />
        <Wire pts={[[BUS_X, centre(panelRow(0))[1]], [BUS_X, centre(panelRow(SESSIONS.length - 1))[1]]]} draw={ramp(t, submit + 1.0, submit + 1.4)} />
        {SESSIONS.map((_, k) => (
          <Wire key={`b${k}`} pts={[[BUS_X, centre(panelRow(k))[1]], [PANEL.x - 2, centre(panelRow(k))[1]]]} draw={ramp(t, submit + 1.2 + 0.03 * k, submit + 1.5 + 0.03 * k)} head width={2.5} />
        ))}
        {SESSIONS.map((name, i) => <SessionRow key={name} box={rowBox(i)} name={name} state={stateOf(i)} right={rightOf(i)} flush={fly(i) > 0.6} focus={focusOf(i)} />)}
        <YouCard box={you} chip={chip} />
      </div>

      {appear > 0.01 && (
        <div style={{position: 'absolute', left: consoleBox.x, top: consoleBox.y, width: consoleBox.w, height: consoleBox.h, background: C.console, borderRadius: 14,
          overflow: 'hidden', opacity: Math.min(1, appear * 1.4)}}>
          <div style={{position: 'absolute', left: 52, top: 40, width: PROMPT_BOX.w - 104, opacity: promptU, fontFamily: mono}}>
            <div style={{fontSize: 20, lineHeight: '28px', color: C.consoleText2}}>claude  ·  Oct 5, 10:08</div>
            {bullets(FIRST)}
            <div style={{marginTop: 30, fontSize: 20, lineHeight: '28px', color: C.consoleText2, opacity: ramp(t, b0 - 0.1, b0 + 0.3)}}>10:25</div>
            {bullets(SECOND)}
          </div>
          <div style={{position: 'absolute', inset: 0, opacity: dirU}}>
            <DirectorCard box={{x: 0, y: 0, w: TREE_DIRECTOR.w, h: TREE_DIRECTOR.h}} sub="engineering manager" needs={t >= scan + 0.16 * SESSIONS.length ? 2 : 0} />
          </div>
        </div>
      )}
    </AbsoluteFill>
  );
};
