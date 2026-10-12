import React from 'react';
import {AbsoluteFill, Img, interpolate, staticFile, useCurrentFrame, useVideoConfig} from 'remotion';
import {Cursor, MiniWindow, PaperGround, ramp} from '../lib/Paper';
import tokens from '../../style/tokens.json';

// Callout options drawn from the two references (style/reference-analysis.md), Geoff 2026-10-11: the earlier
// circles "feel a little sloppy and amateur", and ring/spotlight/lift/brackets were "low effort". Same real frame
// (S3's Needs you card), 4 s each, in motion. Grammar taken, never content:
//   Loom: one clean marker loop, tight, thin, single pass; the narration quoted small, mono, above.
//   Paper Mono: mini windows (1.5 px ink border, square corners, mono title bar with ×) that snap open, no fade,
//   carrying a real crop of the UI enlarged; a solid blue bar behind the words that matter.

const W = tokens.frame.width, H = tokens.frame.height, P = tokens.paper, mono = tokens.font.mono, ui = tokens.font.ui;
const BLUE = tokens.paper.marker;
const SRC = 'capture/video-s3-list.png', SCALE = 4;
const VIEW = {x: 330, y: 0, w: 1470, h: 827};              // window points the camera shows: list + Needs you
// The capture floats as a panel on the paper ground (the references' grammar), with room above for the words.
const PANEL = {x: 120, y: 118, w: 1680};
const k = PANEL.w / VIEW.w;
const EL = {x: 1477, y: 82, w: 307, h: 126};               // the card, video.s3.needs.1
const toF = (r: {x: number; y: number; w: number; h: number}) => ({x: PANEL.x + (r.x - VIEW.x) * k, y: PANEL.y + (r.y - VIEW.y) * k, w: r.w * k, h: r.h * k});
const R = toF(EL);

const Picture = () => (
  <AbsoluteFill>
    <PaperGround />
    <div style={{position: 'absolute', left: PANEL.x, top: PANEL.y, width: PANEL.w, height: VIEW.h * k, overflow: 'hidden', borderRadius: 10, background: '#fff',
      boxShadow: `0 0 0 1px ${P.hairline}, 0 18px 48px rgba(31,35,40,0.14)`}}>
      <Img src={staticFile(SRC)} style={{position: 'absolute', left: -VIEW.x * k, top: -VIEW.y * k, transformOrigin: '0 0', transform: `scale(${k / SCALE})`, maxWidth: 'none'}} />
    </div>
  </AbsoluteFill>
);

/** A real crop of the capture at `z` px per window point. */
const Crop = ({r, z}: {r: {x: number; y: number; w: number; h: number}; z: number}) => (
  <div style={{position: 'relative', width: r.w * z, height: r.h * z, overflow: 'hidden', background: '#fff'}}>
    <Img src={staticFile(SRC)} style={{position: 'absolute', left: -r.x * z, top: -r.y * z, transformOrigin: '0 0', transform: `scale(${z / SCALE})`, maxWidth: 'none'}} />
  </div>
);

/** Loom's loop, done cleanly: one smooth ellipse a little wider than the thing, tilted 2°, drawn in one pass,
 *  ending just past where it began. Even 3.5 px stroke, round caps, no wobble. */
const Loop = ({r, u}: {r: {x: number; y: number; w: number; h: number}; u: number}) => {
  if (u <= 0) return null;
  const cx = r.x + r.w / 2, cy = r.y + r.h / 2, rx = r.w / 2 + 22, ry = r.h / 2 + 16, turns = 1.06, n = 120;
  const pts: string[] = [];
  for (let i = 0; i <= n; i++) {
    const a = -Math.PI * 0.62 + (i / n) * Math.PI * 2 * turns;
    const grow = 1 + 0.02 * (i / n);                        // the end rides just outside the start
    pts.push(`${(cx + rx * grow * Math.cos(a)).toFixed(1)},${(cy + ry * grow * Math.sin(a)).toFixed(1)}`);
  }
  const len = 2 * Math.PI * Math.sqrt((rx * rx + ry * ry) / 2) * turns * 1.03;
  return (
    <svg style={{position: 'absolute', left: 0, top: 0, overflow: 'visible', transform: `rotate(-2deg)`, transformOrigin: `${cx}px ${cy}px`}} width={1} height={1}>
      <polyline points={pts.join(' ')} fill="none" stroke={BLUE} strokeWidth={3.5} strokeLinecap="round" strokeLinejoin="round"
        strokeDasharray={len} strokeDashoffset={len * (1 - u)} />
    </svg>
  );
};

/** Loom's caption: the spoken words, quoted in mono, centred above, after a small waveform glyph. */
const Quoted = ({text, u}: {text: string; u: number}) => (
  <div style={{position: 'absolute', left: 0, right: 0, top: 44, textAlign: 'center', fontFamily: mono, fontSize: 32, color: P.ink2, opacity: u > 0 ? 1 : 0,
    clipPath: `inset(0 ${100 - u * 100}% 0 0)`}}>
    <span style={{color: BLUE, letterSpacing: -2, marginRight: 14}}>⋅ı|ıılı⋅</span>“{text}”
  </div>
);

/** Paper Mono's highlight: a solid blue bar laid behind words, left to right. */
const Bar = ({r, u}: {r: {x: number; y: number; w: number; h: number}; u: number}) => (
  <div style={{position: 'absolute', left: r.x - 6, top: r.y - 3, width: (r.w + 12) * u, height: r.h + 6, background: 'rgba(91,141,239,0.32)', mixBlendMode: 'multiply'}} />
);

/** The window's footer: the spoken words, quoted in mono, typed on as the voice says them. */
const Foot = ({text, u}: {text: string; u: number}) => (
  <div style={{borderTop: `1.5px solid ${P.ink}`, padding: '12px 16px', fontFamily: mono, fontSize: 26, color: P.ink, background: P.window, whiteSpace: 'nowrap', overflow: 'hidden'}}>
    <span style={{color: BLUE}}>“</span>{text.slice(0, Math.round(text.length * u))}<span style={{color: BLUE, opacity: u > 0 && u < 1 ? 1 : u >= 1 ? 1 : 0}}>{u >= 1 ? '”' : '▍'}</span>
  </div>
);

const cursorTo = (t: number, at: number, p: {x: number; y: number}) => {
  const m = ramp(t, at - 0.9, at - 0.05);
  return {x: p.x + 260 * (1 - m), y: p.y + 220 * (1 - m) - Math.sin(m * Math.PI) * 30, press: interpolate(t - at, [-0.04, 0.04, 0.14], [0, 1, 0], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'})};
};

export const CalloutStudy = ({variant}: {variant: string}) => {
  const t = useCurrentFrame() / useVideoConfig().fps;
  const click = 1.0;
  const cur = cursorTo(t, click, {x: R.x + R.w * 0.42, y: R.y + R.h * 0.55});
  const title = {x: EL.x + 30, y: EL.y + 8, w: 150, h: 22};    // "Tag crash reports" in window points
  const ask = {x: EL.x + 14, y: EL.y + 59, w: 270, h: 20};     // the permission line
  let body: React.ReactNode = null;
  if (variant === 'loop') {
    // Loom: cursor lands, the loop draws once, the words appear quoted above.
    body = (<><Loop r={R} u={ramp(t, click + 0.05, click + 0.5)} /><Quoted text="waiting for your input" u={ramp(t, click + 0.35, click + 0.7)} /></>);
  } else if (variant === 'window') {
    // Paper Mono: a mini window snaps open beside the card, its title the feature in mono, its body the card's
    // own pixels enlarged; a hairline leader ties it to the card. No circle.
    const open = ramp(t, click + 0.15, click + 0.27);
    const z = 1.9, wx = R.x - 70 - EL.w * z, wy = R.y + 40;
    body = (<>
      {open > 0 && <svg style={{position: 'absolute', left: 0, top: 0, overflow: 'visible'}} width={1} height={1}>
        <polyline points={`${R.x - 6},${R.y + R.h / 2} ${wx + EL.w * z + 1},${wy + 60}`} stroke={P.ink} strokeWidth={1.5} fill="none" strokeDasharray="4 5" />
        <rect x={R.x - 10} y={R.y + R.h / 2 - 4} width={8} height={8} fill={P.ink} />
      </svg>}
      <MiniWindow x={wx} y={wy} w={EL.w * z} title="needs you · 2" open={open}>
        <Crop r={EL} z={z} />
        <Foot text="waiting for your input" u={ramp(t, click + 0.45, click + 0.75)} />
      </MiniWindow>
    </>);
  } else {
    // Both, the approved M3 grammar: the loop draws, then the mini window snaps open with the words that matter
    // barred in blue inside it, and the narration quoted under it.
    const open = ramp(t, click + 0.5, click + 0.62);
    const z = 1.9, wx = R.x - 70 - EL.w * z, wy = R.y + 40;
    const zt = (r: typeof title) => ({x: (r.x - EL.x) * z, y: (r.y - EL.y) * z, w: r.w * z, h: r.h * z});
    body = (<>
      <Loop r={R} u={ramp(t, click + 0.05, click + 0.5)} />
      <MiniWindow x={wx} y={wy} w={EL.w * z} title="needs you · permission" open={open}>
        <Crop r={EL} z={z} />
        {open >= 1 && <Bar r={zt(ask)} u={ramp(t, click + 0.8, click + 1.2)} />}
        <Foot text="waiting for your input" u={ramp(t, click + 0.9, click + 1.2)} />
      </MiniWindow>
    </>);
  }
  return (
    <AbsoluteFill>
      <Picture />
      {body}
      <Cursor x={cur.x} y={cur.y} press={cur.press} />
    </AbsoluteFill>
  );
};
