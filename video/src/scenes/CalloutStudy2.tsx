import React from 'react';
import {AbsoluteFill, Img, spring, staticFile, useCurrentFrame, useVideoConfig} from 'remotion';
import {Caption, Cursor} from '../lib/Paper';
import tokens from '../../style/tokens.json';

// Callout studies, round 2 (Geoff, 2026-10-11: "I don't want the feature pop out; the outline is better than
// before; please just research more options"). From the research (product-launch films and the motion-design
// articles Geoff sent): none of the top films draw annotations on their UI; they point with the app's own
// selection state, the camera, or an outline that follows the element's real shape. Four studies on S3's frame,
// 6 s each: the outline traces Needs you's first card, then moves to the second.
//   trace  — a concentric border trace: the card's own radius + 5 px, from the cursor's corner, constant speed,
//            closes exactly, un-draws (never fades).
//   morph  — one outline that never cuts: it glides to the next feature, the leading edge on a quick spring,
//            the trailing edge on a slower one, so it stretches and settles.
//   swipe  — a text-selection block behind the words that matter, sliding phrase to phrase.
//   focus  — the camera's own tool: everything outside the card goes soft (no dimming), with the trace on top.

const W = tokens.frame.width, H = tokens.frame.height, BLUE = tokens.paper.marker;
const SRC = 'capture/video-s3-list.png', SCALE = 4;
const VIEW = {x: 964, y: 20, w: 836, h: 470};
const k = W / VIEW.w;
type Rect = {x: number; y: number; w: number; h: number};
const toF = (r: Rect): Rect => ({x: (r.x - VIEW.x) * k, y: (r.y - VIEW.y) * k, w: r.w * k, h: r.h * k});
const CARD1 = toF({x: 1477, y: 82, w: 307, h: 126});
const CARD2 = toF({x: 1477, y: 218, w: 307, h: 226});
const RADIUS = 8 * k;                                      // the cards' own corner radius, in output px
const OFF = 5;

const Picture = ({blur = 0}: {blur?: number}) => (
  <AbsoluteFill style={{overflow: 'hidden', background: '#fff'}}>
    <Img src={staticFile(SRC)} style={{position: 'absolute', left: -VIEW.x * k, top: -VIEW.y * k, transformOrigin: '0 0', transform: `scale(${k / SCALE})`,
      maxWidth: 'none', filter: blur ? `blur(${blur}px)` : undefined}} />
  </AbsoluteFill>
);

/** A rounded rect as one path starting at its bottom-right corner (the cursor's side), clockwise. */
function roundedRect(r: Rect, rad: number) {
  const {x, y, w, h} = r, q = Math.min(rad, w / 2, h / 2);
  const d = `M ${x + w} ${y + h - q} A ${q} ${q} 0 0 1 ${x + w - q} ${y + h} L ${x + q} ${y + h} A ${q} ${q} 0 0 1 ${x} ${y + h - q} ` +
    `L ${x} ${y + q} A ${q} ${q} 0 0 1 ${x + q} ${y} L ${x + w - q} ${y} A ${q} ${q} 0 0 1 ${x + w} ${y + q} Z`;
  const len = 2 * (w - 2 * q) + 2 * (h - 2 * q) + 2 * Math.PI * q;
  return {d, len};
}
const grow = (r: Rect, o: number): Rect => ({x: r.x - o, y: r.y - o, w: r.w + 2 * o, h: r.h + 2 * o});

/** The trace: progress 0→1 draws, 1→2 un-draws from where it began (the tail chases the head). */
const Trace = ({r, p, width = 3}: {r: Rect; p: number; width?: number}) => {
  if (p <= 0 || p >= 2) return null;
  const {d, len} = roundedRect(grow(r, OFF), RADIUS + OFF);
  const on = p <= 1 ? len * p : len * (2 - p), start = p <= 1 ? 0 : len * (p - 1);
  return (
    <svg style={{position: 'absolute', left: 0, top: 0, overflow: 'visible'}} width={W} height={H}>
      <path d={d} fill="none" stroke={BLUE} strokeWidth={width} strokeLinecap="round" strokeLinejoin="round"
        strokeDasharray={`${on} ${len}`} strokeDashoffset={-start} />
    </svg>
  );
};

// Constant-speed eases for the draw (cubic in-out, as the research recommends), in seconds.
const io = (t: number, a: number, d: number) => { const u = Math.min(1, Math.max(0, (t - a) / d)); return u < 0.5 ? 4 * u ** 3 : 1 - (-2 * u + 2) ** 3 / 2; };

const useT = () => { const f = useCurrentFrame(), {fps} = useVideoConfig(); return {t: f / fps, f, fps}; };

/** The cursor glides on an arc to a point and presses there. */
const useCursor = (t: number, legs: {at: number; x: number; y: number}[]) => {
  let from = {x: W * 0.62, y: H * 0.95}, x = from.x, y = from.y, press = 0;
  for (const g of legs) {
    const u = io(t, g.at - 0.75, 0.7);
    if (t < g.at - 0.75) break;
    x = from.x + (g.x - from.x) * u; y = from.y + (g.y - from.y) * u - Math.sin(u * Math.PI) * 30;
    if (t >= g.at && t < g.at + 0.12) press = 1 - Math.abs(t - g.at - 0.06) / 0.06;
    from = {x: g.x, y: g.y};
  }
  return {x, y, press};
};

const lerpR = (a: Rect, b: Rect, top: number, bottom: number): Rect => {
  const y0 = a.y + (b.y - a.y) * top, y1 = a.y + a.h + (b.y + b.h - a.y - a.h) * bottom;
  return {x: a.x + (b.x - a.x) * top, y: y0, w: a.w + (b.w - a.w) * top, h: y1 - y0};
};

export const CalloutStudy2 = ({variant}: {variant: string}) => {
  const {t, f, fps} = useT();
  const c1 = {x: CARD1.x + CARD1.w * 0.86, y: CARD1.y + CARD1.h * 0.92}, c2 = {x: CARD2.x + CARD2.w * 0.86, y: CARD2.y + CARD2.h * 0.94};
  const cur = useCursor(t, [{at: 0.9, ...c1}, {at: 3.1, ...c2}]);
  let overlay: React.ReactNode = null, blur: React.ReactNode = null;

  if (variant === 'trace') {
    // Draw on the first card (0.45 s), hold, un-draw at x1.5 tempo (0.3 s); then the second.
    const p1 = io(t, 0.95, 0.45) + io(t, 2.7, 0.3), p2 = io(t, 3.15, 0.5) + io(t, 5.4, 0.3);
    overlay = <><Trace r={CARD1} p={p1} /><Trace r={CARD2} p={p2} /></>;
  } else if (variant === 'morph' || variant === 'focus') {
    // One outline: drawn once, then it travels to the second card and never cuts. Moving down, the bottom edge
    // leads on a quick spring (320/30) and the top follows on a slower one (140/22).
    const at = 3.15 * fps;
    const lead = spring({frame: f - at, fps, config: {stiffness: 320, damping: 30}});
    const trail = spring({frame: f - at - 2, fps, config: {stiffness: 140, damping: 22}});
    const r = lerpR(CARD1, CARD2, trail, lead);
    const p = io(t, 0.95, 0.45) + io(t, 5.4, 0.3);
    overlay = <Trace r={r} p={p < 1 && t > 1.4 && t < 5.4 ? 1 : p} />;
    if (variant === 'focus') {
      // Focus falloff, no dimming: the frame goes soft and only the outlined card stays sharp (a sharp window
      // onto the same picture, following the outline as it moves).
      const fu = io(t, 0.95, 0.5) * (1 - io(t, 5.4, 0.4));
      const g = grow(r, OFF);
      blur = fu > 0 && (
        <>
          <AbsoluteFill style={{opacity: fu}}><Picture blur={6} /></AbsoluteFill>
          <div style={{position: 'absolute', left: g.x, top: g.y, width: g.w, height: g.h, overflow: 'hidden', borderRadius: RADIUS + OFF}}>
            <div style={{position: 'absolute', left: -g.x, top: -g.y, width: W, height: H}}><Picture /></div>
          </div>
        </>
      );
    }
  } else if (variant === 'swipe') {
    // A selection block behind the words: "NEEDS YOU · 2", then the first card's title, then the second's,
    // sliding (x and width on springs) between them; it wipes in left to right and out to the right.
    const words: Rect[] = [toF({x: 1477, y: 60, w: 96, h: 16}), toF({x: 1494, y: 92, w: 128, h: 20}), toF({x: 1494, y: 228, w: 120, h: 20})];
    const at = [0.9, 2.0, 3.2];
    let cur2 = words[0];
    for (let i = 1; i < words.length; i++) {
      const s = spring({frame: f - at[i] * fps, fps, config: {stiffness: 320, damping: 30}});
      cur2 = {x: cur2.x + (words[i].x - cur2.x) * s, y: cur2.y + (words[i].y - cur2.y) * s, w: cur2.w + (words[i].w - cur2.w) * s, h: cur2.h + (words[i].h - cur2.h) * s};
    }
    const inU = io(t, at[0], 0.28), out = io(t, 5.3, 0.25);
    overlay = inU > 0 && (
      <div style={{position: 'absolute', left: cur2.x - 6 + (cur2.w + 12) * out, top: cur2.y - 4, width: (cur2.w + 12) * inU * (1 - out), height: cur2.h + 8,
        background: 'rgba(47,111,235,0.24)', mixBlendMode: 'multiply', borderRadius: 3}} />
    );
  }

  return (
    <AbsoluteFill>
      <Picture />
      {blur}
      {overlay}
      <Cursor x={cur.x} y={cur.y} press={cur.press} />
      {t > 1.2 && t < 5.6 && <Caption text="waiting for your input" />}
    </AbsoluteFill>
  );
};
