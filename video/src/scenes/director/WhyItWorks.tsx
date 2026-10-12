import React from 'react';
import {AbsoluteFill} from 'remotion';
import type {SceneProps} from '../registry';
import {PaperGround} from '../../lib/Paper';
import {centre, DirectorCard, Heading, L, lerp, Meter, mixBox, mono, Pulse, ramp, SectionLabel, SessionRow, spring, ui, Wire, YouCard, type Box} from './kit';
import {slotNames} from './Tree';
import {AdditionsEnd, T2_DIRECTOR, T2_YOU} from './Additions';

// S5 · Why it works. Two diagrams side by side, then one. Left, subagents: small boxes inside the parent session's
// outline; their work flows back into it, its context fills and the outline swells. Right, the director: full sessions
// outside it, each on its own branch line, with only a short report back (tagged with the Claude Code version that
// added messaging between sessions); you step into one session and back out. The director's context stays small.

const PARENT: Box = {x: 200, y: 340, w: 520, h: 180};
const SUBS = ['feature A', 'feature B', 'feature C', 'feature D'];
const sub = (i: number): Box => ({x: 214 + i * 124, y: 560, w: 112, h: 56});
export const WHY_DIR: Box = {x: 1000, y: 340, w: 380, h: 180};
export const WHY_WORKERS = [2, 3, 4, 5]; // panel slots that become the right-hand workers
export const whyWorker = (i: number): Box => ({x: 1460, y: 300 + i * 104, w: 340, h: 64});
export const WHY_YOU: Box = {x: 1000, y: 680, w: 300, h: 140};

export const WhyItWorks = ({t, ev}: SceneProps) => {
  const go = ev.go ?? 0.4, farm = ev.farm ?? go + 1, back = ev.back ?? farm + 2;
  const here = ev.here ?? back + 2, branch = ev.branch ?? here + 1, open = ev.open ?? branch + 2, alongside = ev.alongside ?? open + 1.5;
  const report = ev.report ?? alongside + 2, small = ev.small ?? report + 2;

  // Leaving S4: the timeline, phone and panel go; the director and you move to the right-hand diagram.
  const leave = ramp(t, go, go + 0.6);
  const move = spring(t, go + 0.2, 5.5, 0.95);
  const dir = mixBox(T2_DIRECTOR, WHY_DIR, move);

  // Left: subagents inside the parent's outline.
  const leftU = ramp(t, go + 0.4, go + 0.9) * (1 - 0.75 * ramp(t, here, here + 0.6));
  const subU = (i: number) => spring(t, farm + 0.15 * i, 10, 0.85);
  const flowBack = (i: number) => (t - (back + 0.2 * i)) / 0.7;
  const swell = ramp(t, back, back + 1.4);
  const outline: Box = {x: PARENT.x - 20, y: PARENT.y - 20, w: PARENT.w + 40, h: lerp(320, 420, swell)};
  const parentFill = lerp(0.3, 0.97, swell);

  // Right: workers outside the director, each on its own branch; reports are short; you step in and out.
  const rightU = ramp(t, go + 0.4, go + 0.9);
  const wU = (i: number) => spring(t, here + 0.15 * i, 10, 0.85);
  const brU = (i: number) => ramp(t, branch + 0.12 * i, branch + 0.5 + 0.12 * i);
  const stepIn = spring(t, open, 6, 0.9) * (1 - spring(t, alongside + 0.8, 6, 0.9));
  const youBox = mixBox(WHY_YOU, {x: whyWorker(1).x - 20, y: whyWorker(1).y + 72, w: 300, h: 140}, stepIn);
  const reportU = (i: number) => (t - (report + 0.25 * i)) / 0.6;
  const tagU = ramp(t, report + 0.3, report + 0.7);
  const smallU = ramp(t, small, small + 0.4);

  return (
    <AbsoluteFill>
      <PaperGround />
      {/* S4's picture leaving. */}
      <div style={{position: 'absolute', inset: 0, opacity: 1 - leave}}><AdditionsEnd /></div>
      <Heading title="Why it works" sub="Workers are whole sessions; the director reads reports." u={ramp(t, go + 0.5, go + 1.0)} />

      {/* Left: subagents. */}
      <div style={{position: 'absolute', inset: 0, opacity: leftU}}>
        <SectionLabel x={PARENT.x - 20} y={250} text="SUBAGENTS" />
        <div style={{position: 'absolute', left: outline.x, top: outline.y, width: outline.w, height: outline.h, boxSizing: 'border-box',
          border: `2px dashed ${L.controlEdge}`, borderRadius: 18}} />
        <DirectorCard box={PARENT} title="one session" sub="its own context holds it all"><Meter fill={parentFill} /></DirectorCard>
        {SUBS.map((name, i) => (
          <React.Fragment key={name}>
            <div style={{position: 'absolute', left: sub(i).x, top: sub(i).y, width: sub(i).w, height: sub(i).h, boxSizing: 'border-box', borderRadius: 8,
              background: L.pane, border: `2px solid ${L.rule}`, display: 'flex', alignItems: 'center', justifyContent: 'center', fontFamily: ui,
              fontSize: 18, color: L.text2, opacity: Math.min(1, subU(i)), transform: `scale(${0.9 + 0.1 * subU(i)})`}}>{name}</div>
            <Pulse a={centre(sub(i))} b={[centre(sub(i))[0], PARENT.y + PARENT.h - 10]} u={flowBack(i)} color={L.text} r={7} />
          </React.Fragment>
        ))}
      </div>

      {/* Right: the director. */}
      <div style={{position: 'absolute', inset: 0, opacity: rightU}}>
        <SectionLabel x={WHY_DIR.x} y={250} text="A DIRECTOR" />
      </div>
      {WHY_WORKERS.map((k, i) => {
        const b = whyWorker(i), c = centre(b);
        return (
          <React.Fragment key={k}>
            <Wire pts={[[b.x + b.w + 6, c[1]], [b.x + b.w + 6, c[1] - 30], [1860, c[1] - 30]]} draw={brU(i)} color="#6F8A5C" width={3} radius={10} />
            <Wire pts={[[b.x - 2, c[1]], [dir.x + dir.w + 2, centre(dir)[1]]]} draw={ramp(t, report - 0.3, report)} width={2} opacity={rightU} />
            <Pulse a={[b.x, c[1]]} b={[dir.x + dir.w, centre(dir)[1]]} u={reportU(i)} color={L.text} r={7} />
            <div style={{position: 'absolute', inset: 0, opacity: Math.min(1, wU(i)) * rightU}}>
              <SessionRow box={b} name={slotNames[k]} state="working" />
            </div>
            <div style={{position: 'absolute', left: b.x + b.w + 18, top: c[1] - 62, fontFamily: mono, fontSize: 16, color: '#4E6A3F', opacity: brU(i)}}>own branch</div>
          </React.Fragment>
        );
      })}
      <div style={{position: 'absolute', left: 1180, top: 600, padding: '4px 12px', borderRadius: 8, background: L.pane, border: `1.5px solid ${L.rule}`,
        fontFamily: mono, fontSize: 18, lineHeight: '26px', color: L.text2, opacity: tagU}}>since Claude Code 2.1.224</div>

      <DirectorCard box={dir} sub={t < go + 0.6 ? 'Opus · plans and reviews' : t < small ? 'reads short reports' : 'context stays small'}>
        <Meter fill={lerp(0.12, 0.2, ramp(t, report, report + 2))} u={1} />
      </DirectorCard>
      <div style={{position: 'absolute', left: dir.x + dir.w - 120, top: dir.y + dir.h - 46, fontFamily: mono, fontSize: 16, color: '#9AA1AB', opacity: smallU}}>context</div>

      <YouCard box={mixBox(T2_YOU, youBox, move)} chip={t < go + 0.3 ? 2 : 0} label={stepIn > 0.5 ? 'working alongside' : 'the PM'} />
    </AbsoluteFill>
  );
};

/** S5's last picture, for the scene after it to open on. */
const END_EV = {go: 0, farm: 1, back: 2, here: 3, branch: 4, open: 5, alongside: 6, report: 7, small: 8};
export const WhyEnd = () => <WhyItWorks t={999} ev={END_EV} scene={{id: 'S5', title: ''}} />;
