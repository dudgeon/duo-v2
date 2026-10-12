import React from 'react';
import {interpolate} from 'remotion';
import tokens from '../../../style/tokens.json';

// The director film's look, B · Panes (DL-180): Duo's own language on the paper ground. The director is the dark
// console you talk to; sessions are rows with Duo's state glyphs; needs-you orange is the one accent and means only
// "waiting on you". Every piece is a pure function of the scene's time, so any frame renders on its own.

export const L = tokens.color.light;
export const C = tokens.color.console;
export const P = tokens.paper;
export const ui = tokens.font.ui, mono = tokens.font.mono;
export const W = tokens.frame.width, H = tokens.frame.height, SAFE = tokens.frame.safe;
/** Lines and arrows between things: warmer than Duo's rule so they read on paper. */
export const LINE = '#8B939C';

const clamp = {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'} as const;
export const lerp = (a: number, b: number, u: number) => a + (b - a) * u;
export const clamp01 = (u: number) => Math.min(1, Math.max(0, u));
export const smooth = (u: number) => { const x = clamp01(u); return x * x * x * (x * (x * 6 - 15) + 10); };
/** 0 → 1 over [a, b], smootherstep. */
export const ramp = (t: number, a: number, b: number) => (b <= a ? (t >= a ? 1 : 0) : smooth(interpolate(t, [a, b], [0, 1], clamp)));

/**
 * A closed-form damped spring from 0 to 1, started at `t0`: any frame is computed on its own, with no state carried
 * between frames (the motion article's rule). `k` sets speed, `z` damping (1 = no overshoot; nodes 0.8, type 1).
 */
export const spring = (t: number, t0: number, k = 9, z = 0.82) => {
  const x = t - t0;
  if (x <= 0) return 0;
  if (z >= 1) return 1 - (1 + k * x) * Math.exp(-k * x);
  const wd = k * Math.sqrt(1 - z * z);
  return 1 - Math.exp(-z * k * x) * (Math.cos(wd * x) + (z * k / wd) * Math.sin(wd * x));
};

/** A value that eases through keyframes [[t, v], …] on springs: each change starts its own spring from where the
 *  last one would be, so motion stays continuous however close the keys are. */
export const track = (t: number, keys: [number, number][], k = 9, z = 0.9) => {
  let v = keys[0][1];
  for (let i = 1; i < keys.length; i++) v += (keys[i][1] - keys[i - 1][1]) * spring(t, keys[i][0], k, z);
  return v;
};

export type State = 'needs' | 'review' | 'working' | 'idle' | 'done';

/** Duo's state glyphs (design system, State glyphs): a shape per state, so colour is never the only signal. */
export const Glyph = ({state, size = 22, onConsole = false}: {state: State; size?: number; onConsole?: boolean}) => {
  const ink = onConsole ? C.consoleText : L.text, ink2 = onConsole ? C.consoleText2 : L.text2;
  const orange = onConsole ? C.needsYouOnConsole : L.needsYou;
  return (
    <svg width={size} height={size} viewBox="0 0 10 10" style={{flex: 'none'}}>
      {state === 'needs' && <circle cx="5" cy="5" r="4.5" fill={orange} />}
      {state === 'review' && <path d="M5 0.5 L9.5 5 L5 9.5 L0.5 5 Z" fill={ink} />}
      {state === 'working' && <circle cx="5" cy="5" r="3.75" fill="none" stroke={ink} strokeWidth={1.5} />}
      {state === 'idle' && <path d="M2 5 L8 5" stroke={ink2} strokeWidth={1.6} strokeLinecap="round" />}
      {state === 'done' && <path d="M1.5 5.2 L4 7.6 L8.6 2.6" fill="none" stroke={ink2} strokeWidth={1.6} strokeLinecap="round" strokeLinejoin="round" />}
    </svg>
  );
};

type Box = {x: number; y: number; w: number; h: number};
const place = (b: Box, extra?: React.CSSProperties): React.CSSProperties => ({position: 'absolute', left: b.x, top: b.y, width: b.w, height: b.h, boxSizing: 'border-box', ...extra});

/** You, the PM: a white pane card. `chip` is the needs-you count (0 hides it). */
export const YouCard = ({box, chip = 0, chipU = 1, u = 1, label = 'the PM'}: {box: Box; chip?: number; chipU?: number; u?: number; label?: string}) => (
  <div style={place(box, {background: L.pane, border: `2px solid ${L.rule}`, borderRadius: 12, padding: '0 28px', display: 'flex',
    flexDirection: 'column', justifyContent: 'center', gap: 6, opacity: u, fontFamily: ui, color: L.text})}>
    <div style={{fontSize: 30, lineHeight: '36px', fontWeight: 700}}>You</div>
    <div style={{fontSize: 22, lineHeight: '28px', color: L.text2}}>{label}</div>
    {chip > 0 && (
      <div style={{alignSelf: 'flex-start', marginTop: 8, padding: '2px 14px', borderRadius: 18, background: L.needsYou, color: L.onNeedsYou,
        fontSize: 20, lineHeight: '30px', fontWeight: 600, letterSpacing: 1.2, opacity: chipU, whiteSpace: 'nowrap'}}>NEEDS YOU · {chip}</div>
    )}
  </div>
);

/** The director: the dark console, since it's whoever you're talking to (design system, Principles). */
export const DirectorCard = ({box, title = 'director', sub, subU = 1, needs = 0, u = 1, children}: {box: Box; title?: string; sub?: string; subU?: number; needs?: number; u?: number; children?: React.ReactNode}) => (
  <div style={place(box, {background: C.console, borderRadius: 12, padding: '24px 32px', display: 'flex', flexDirection: 'column',
    justifyContent: 'center', overflow: 'hidden', opacity: u, fontFamily: mono, color: C.consoleText})}>
    <div style={{fontSize: 30, lineHeight: '40px', fontWeight: 500, whiteSpace: 'nowrap'}}>{title}</div>
    {sub && <div style={{fontSize: 20, lineHeight: '30px', color: C.consoleText2, whiteSpace: 'nowrap', opacity: subU}}>{sub}</div>}
    {needs > 0 && <div style={{fontSize: 20, lineHeight: '30px', color: C.needsYouOnConsole, whiteSpace: 'nowrap'}}>● {needs} need you</div>}
    {children}
  </div>
);

/** A session as a row: its state glyph and name, a wait time or state on the right. Floats as a card on paper, or sits
 *  flush in a SESSIONS panel (`flush`). */
export const SessionRow = ({box, name, state, right, u = 1, flush = false, focus = 0}: {box: Box; name: string; state: State; right?: string; u?: number; flush?: boolean; focus?: number}) => (
  <div style={place(box, {background: focus > 0 ? `rgba(233,236,239,${focus})` : flush ? 'transparent' : L.pane,
    border: flush ? 'none' : `2px solid ${L.rule}`, borderRadius: 10, padding: '0 24px', display: 'flex', alignItems: 'center', gap: 16,
    opacity: u, fontFamily: ui, fontSize: 26, lineHeight: '32px', color: state === 'done' ? L.text2 : L.text})}>
    <Glyph state={state} />
    <span style={{fontWeight: state === 'needs' ? 700 : 400, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis', flex: 1}}>{name}</span>
    {right && <span style={{fontSize: 22, color: L.text2, whiteSpace: 'nowrap'}}>{right}</span>}
  </div>
);

/** A section label in Duo's style: SESSIONS · 10. */
export const SectionLabel = ({x, y, text, u = 1}: {x: number; y: number; text: string; u?: number}) => (
  <div style={{position: 'absolute', left: x, top: y, fontFamily: ui, fontSize: 22, lineHeight: '32px', fontWeight: 600, letterSpacing: 1.3,
    color: L.text2, opacity: u, whiteSpace: 'nowrap'}}>{text}</div>
);

/**
 * A line through points (orthogonal corners rounded), drawn from its start as `draw` goes 0 → 1, with an optional
 * head at the end. Lines are how things connect; they draw along their path, never fade in.
 */
export const Wire = ({pts, draw = 1, color = LINE, width = 3, head = false, radius = 14, opacity = 1, dash}: {pts: [number, number][];
  draw?: number; color?: string; width?: number; head?: boolean; radius?: number; opacity?: number; dash?: string}) => {
  if (draw <= 0 || pts.length < 2) return null;
  let d = `M ${pts[0][0]} ${pts[0][1]}`;
  for (let i = 1; i < pts.length; i++) {
    const [x, y] = pts[i];
    if (i < pts.length - 1 && radius > 0) {
      const [px, py] = pts[i - 1], [nx, ny] = pts[i + 1];
      const r = Math.min(radius, Math.hypot(x - px, y - py) / 2, Math.hypot(nx - x, ny - y) / 2);
      const ax = x - Math.sign(x - px) * r, ay = y - Math.sign(y - py) * r;
      const bx = x + Math.sign(nx - x) * r, by = y + Math.sign(ny - y) * r;
      d += ` L ${ax} ${ay} Q ${x} ${y} ${bx} ${by}`;
    } else d += ` L ${x} ${y}`;
  }
  const [ex, ey] = pts[pts.length - 1], [qx, qy] = pts[pts.length - 2];
  const ang = Math.atan2(ey - qy, ex - qx), hs = width * 3.2;
  return (
    <svg width={W} height={H} style={{position: 'absolute', left: 0, top: 0, overflow: 'visible', opacity}}>
      <path d={d} pathLength={1} fill="none" stroke={color} strokeWidth={width} strokeLinecap="round" strokeLinejoin="round"
        strokeDasharray={dash ?? '1 1'} strokeDashoffset={dash ? 0 : 1 - clamp01(draw)} />
      {head && draw >= 0.98 && (
        <path d={`M ${ex} ${ey} L ${ex - hs * Math.cos(ang - 0.45)} ${ey - hs * Math.sin(ang - 0.45)} L ${ex - hs * Math.cos(ang + 0.45)} ${ey - hs * Math.sin(ang + 0.45)} Z`}
          fill={color} />
      )}
    </svg>
  );
};

/** A dot travelling along a straight segment a → b as u goes 0 → 1 (a message in flight). */
export const Pulse = ({a, b, u, color = L.needsYou, r = 8}: {a: [number, number]; b: [number, number]; u: number; color?: string; r?: number}) => {
  if (u <= 0 || u >= 1) return null;
  const x = lerp(a[0], b[0], smooth(u)), y = lerp(a[1], b[1], smooth(u));
  return <div style={{position: 'absolute', left: x - r, top: y - r, width: 2 * r, height: 2 * r, borderRadius: r, background: color}} />;
};

/** The scene's heading, top left, small: what this part of the film is about. Arrives after motion starts, rises 12 px. */
export const Heading = ({title, sub, u = 1}: {title: string; sub?: string; u?: number}) => (
  <div style={{position: 'absolute', left: 144, top: 112, fontFamily: ui, color: L.text, opacity: u, transform: `translateY(${(1 - u) * 12}px)`}}>
    <div style={{fontSize: 44, lineHeight: '56px', fontWeight: 600, letterSpacing: -0.4}}>{title}</div>
    {sub && <div style={{marginTop: 4, fontSize: 26, lineHeight: '36px', color: L.text2}}>{sub}</div>}
  </div>
);

/** Boxes in between two layouts. */
export const mixBox = (a: Box, b: Box, u: number): Box => ({x: lerp(a.x, b.x, u), y: lerp(a.y, b.y, u), w: lerp(a.w, b.w, u), h: lerp(a.h, b.h, u)});
export const centre = (b: Box): [number, number] => [b.x + b.w / 2, b.y + b.h / 2];
export type {Box};

/** The director's context meter (S3 on): how full its context is. */
export const Meter = ({fill, u = 1}: {fill: number; u?: number}) => (
  <div style={{position: 'absolute', left: 32, right: 32, bottom: 20, height: 6, borderRadius: 3, background: C.consoleRule, overflow: 'hidden', opacity: u}}>
    <div style={{width: `${fill * 100}%`, height: 6, background: fill > 0.9 ? C.needsYouOnConsole : C.consoleText2}} />
  </div>
);

/**
 * The voice line as a caption along the foot of the frame, after the standing reference (taste.md): one line at a time,
 * arriving grey, ink while it's said, grey again as it ends. Geoff, 2026-10-12: captions "like that film".
 */
export const Captions = ({t, lines}: {t: number; lines: {text: string; start: number; duration: number}[]}) => (
  <>
    {lines.map((l, i) => {
      const next = lines[i + 1]?.start ?? l.start + l.duration + 1.2;
      const inU = ramp(t, l.start - 0.25, l.start + 0.15), outU = ramp(t, Math.min(next - 0.2, l.start + l.duration + 0.6), next);
      const u = inU * (1 - outU);
      if (u <= 0.001) return null;
      const ink = ramp(t, l.start, l.start + 0.3) * (1 - ramp(t, l.start + l.duration, l.start + l.duration + 0.3));
      return (
        <div key={i} style={{position: 'absolute', left: 144, right: 144, bottom: 44, fontFamily: ui, fontSize: 30, lineHeight: '40px', fontWeight: 500,
          color: ink > 0.5 ? L.text : L.text2, opacity: u, transform: `translateY(${(1 - inU) * 8}px)`}}>{l.text}</div>
      );
    })}
  </>
);
