import React from 'react';
import {AbsoluteFill} from 'remotion';
import type {SceneProps} from '../registry';
import {PaperGround} from '../../lib/Paper';
import {centre, Heading, L, Pulse, ramp, SessionRow, spring, Wire, YouCard, type State} from './kit';
import {RING_YOU, ringRow, SESSIONS} from './board';

// S1 · The problem. You in the middle; the sessions arrive around you one by one, each tied to you by a line. Each
// time one asks for you, a message runs down its line and the line turns needs-you orange, until every line pulls on
// you: the switchboard. The last picture is S2's first.

/** Which sessions ask for you on which word of line 2, and the rest on "switchboard". */
const ASKS: Record<string, number[]> = {brief: [0, 5], check: [3, 8], merge: [1, 6], remember: [2, 7], switch: [4, 9]};
const TRAVEL = 0.6;

export type RingState = {appear: number[]; wire: number[]; orange: number[]; state: State[]; chip: number; chipU: number};

/** The ring as it stands at time t of S1. S2 starts from ringAt(Infinity). */
export const ringAt = (t: number, ev: Record<string, number>): RingState => {
  const n = SESSIONS.length;
  const a0 = ev.rowsStart ?? 1, a1 = ev.rowsEnd ?? a0 + 3;
  const appear = SESSIONS.map((_, i) => spring(t, a0 + (i * (a1 - a0)) / (n - 1), 10, 0.78));
  const wire = SESSIONS.map((_, i) => ramp(t, a0 + (i * (a1 - a0)) / (n - 1), a0 + (i * (a1 - a0)) / (n - 1) + 0.5));
  const askAt: number[] = new Array(n).fill(Infinity);
  for (const [word, rows] of Object.entries(ASKS)) for (const r of rows) if (ev[word] !== undefined) askAt[r] = ev[word];
  const state: State[] = askAt.map((at, i) => (t >= at ? 'needs' : i % 3 === 0 ? 'working' : i % 3 === 1 ? 'idle' : 'review'));
  const orange = askAt.map((at) => ramp(t, at + TRAVEL - 0.1, at + TRAVEL + 0.2));
  const chip = askAt.filter((at) => t >= at + TRAVEL).length;
  return {appear, wire, orange, state, chip, chipU: 1};
};

/** The ring, drawn: lines under cards. `askAt` gives the message pulses (S1 only). */
export const Ring = ({r, t, askAt, you = RING_YOU, rowBox = ringRow, rowU = 1}: {r: RingState; t?: number; askAt?: number[];
  you?: typeof RING_YOU; rowBox?: (i: number) => typeof RING_YOU; rowU?: number}) => {
  const c = centre(you);
  return (
    <>
      {SESSIONS.map((_, i) => <Wire key={`w${i}`} pts={[c, centre(rowBox(i))]} draw={r.wire[i]} />)}
      {SESSIONS.map((_, i) => <Wire key={`o${i}`} pts={[c, centre(rowBox(i))]} draw={r.wire[i]} color={L.needsYou} opacity={r.orange[i]} />)}
      {askAt && t !== undefined && SESSIONS.map((_, i) => <Pulse key={`p${i}`} a={centre(rowBox(i))} b={c} u={(t - askAt[i]) / TRAVEL} />)}
      {SESSIONS.map((name, i) => {
        const b = rowBox(i), k = 0.92 + 0.08 * r.appear[i];
        return (
          <div key={name} style={{position: 'absolute', left: 0, top: 0, transformOrigin: `${b.x + b.w / 2}px ${b.y + b.h / 2}px`, transform: `scale(${k})`}}>
            <SessionRow box={b} name={name} state={r.state[i]} u={Math.min(1, r.appear[i]) * rowU} />
          </div>
        );
      })}
      <YouCard box={you} chip={r.chip} chipU={r.chipU} />
    </>
  );
};

export const Switchboard = ({t, ev}: SceneProps) => {
  const r = ringAt(t, ev);
  const askAt: number[] = new Array(SESSIONS.length).fill(Infinity);
  for (const [word, rows] of Object.entries(ASKS)) for (const i of rows) if (ev[word] !== undefined) askAt[i] = ev[word];
  return (
    <AbsoluteFill>
      <PaperGround />
      <Heading title="The problem" sub="Every session needs you." u={ramp(t, 0.3, 0.9)} />
      <div style={{position: 'absolute', inset: 0, opacity: spring(t, 0.1, 8, 1)}}>
        <Ring r={r} t={t} askAt={askAt} />
      </div>
    </AbsoluteFill>
  );
};

