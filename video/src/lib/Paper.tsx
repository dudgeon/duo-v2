import React from 'react';
import {AbsoluteFill, Img, interpolate, staticFile} from 'remotion';
import {smootherstep} from './camera';
import tokens from '../../style/tokens.json';

// The look from style/reference-analysis.md: paper and ink, a faint grid, real UI as floating
// panels, mini windows with mono title bars, a real cursor and a self-drawing marker stroke.
// Everything is a pure function of the progress values passed in.

const P = tokens.paper;
const ui = tokens.font.ui, mono = tokens.font.mono;
const clamp = {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'} as const;
export const ramp = (t: number, a: number, b: number) => smootherstep(interpolate(t, [a, b], [0, 1], clamp));

/** Warm paper with a faint graph grid. */
export const PaperGround = () => (
  <AbsoluteFill style={{background: P.ground,
    backgroundImage: `linear-gradient(${P.grid} 1px, transparent 1px), linear-gradient(90deg, ${P.grid} 1px, transparent 1px)`,
    backgroundSize: `${P.gridSize}px ${P.gridSize}px`, backgroundPosition: `${P.gridSize / 2}px ${P.gridSize / 2}px`}} />
);

/** A chapter mark, top left: `03 · What needs you`. */
export const Chapter = ({n, title, u = 1}: {n: string; title: string; u?: number}) => (
  <div style={{position: 'absolute', left: tokens.frame.safe, top: tokens.frame.safe * 0.6, fontFamily: mono, fontSize: 22,
    letterSpacing: 1, color: P.ink2, opacity: u}}>
    <span style={{color: P.ink}}>{n}</span>  ·  {title}
  </div>
);

/** A region of a real window capture, drawn as a floating panel. `region` is in window points. */
export const Panel = ({src, scale, region, x, y, k, style}: {src: string; scale: number;
  region: {x: number; y: number; w: number; h: number}; x: number; y: number; k: number; style?: React.CSSProperties}) => (
  <div style={{position: 'absolute', left: x, top: y, width: region.w * k, height: region.h * k, overflow: 'hidden',
    borderRadius: 10, boxShadow: `0 0 0 1px ${P.hairline}, 0 18px 48px rgba(31,35,40,0.14)`, background: '#fff', ...style}}>
    <Img src={staticFile(src)} style={{position: 'absolute', left: -region.x * k, top: -region.y * k, transformOrigin: '0 0',
      transform: `scale(${k / scale})`}} />
  </div>
);

/** A mini window: square corners, hairline border, mono title bar with ×. Snaps open (no fade). */
export const MiniWindow = ({x, y, w, title, open, children}: {x: number; y: number; w: number; title: string; open: number; children: React.ReactNode}) => {
  if (open <= 0) return null;
  const s = 0.92 + 0.08 * open; // a snap, not a fade
  return (
    <div style={{position: 'absolute', left: x, top: y, width: w, transform: `scale(${s})`, transformOrigin: '0 0',
      background: P.window, border: `1.5px solid ${P.ink}`, boxShadow: '0 10px 30px rgba(31,35,40,0.16)'}}>
      <div style={{display: 'flex', justifyContent: 'space-between', alignItems: 'center', height: 40, padding: '0 14px',
        borderBottom: `1.5px solid ${P.ink}`, fontFamily: mono, fontSize: 20, color: P.ink}}>
        <span>{title}</span><span style={{fontSize: 22}}>×</span>
      </div>
      <div style={{position: 'relative'}}>{children}</div>
    </div>
  );
};

/** A hand-drawn ellipse that draws itself (progress 0..1), slightly open where it ends, as in Loom's marker. */
export const Marker = ({cx, cy, rx, ry, progress, color = P.marker, width = 4}: {cx: number; cy: number; rx: number; ry: number;
  progress: number; color?: string; width?: number}) => {
  if (progress <= 0) return null;
  // One and a bit turns with a gentle wobble, starting top-left like a hand would.
  const pts: string[] = [];
  const turns = 1.12, n = 90;
  for (let i = 0; i <= n; i++) {
    const a = -2.4 + (i / n) * Math.PI * 2 * turns;
    const wob = 1 + 0.035 * Math.sin(i * 0.37) + 0.02 * (i / n);
    pts.push(`${(cx + rx * wob * Math.cos(a)).toFixed(1)},${(cy + ry * wob * Math.sin(a) - (i / n) * ry * 0.12).toFixed(1)}`);
  }
  const len = 2 * Math.PI * Math.sqrt((rx * rx + ry * ry) / 2) * turns * 1.05;
  return (
    <svg style={{position: 'absolute', left: 0, top: 0, overflow: 'visible'}} width={1} height={1}>
      <polyline points={pts.join(' ')} fill="none" stroke={color} strokeWidth={width} strokeLinecap="round" strokeLinejoin="round"
        strokeDasharray={len} strokeDashoffset={len * (1 - progress)} />
    </svg>
  );
};

/** The macOS arrow cursor, tip at (x, y). `press` 0..1 shrinks it slightly for a click. */
export const Cursor = ({x, y, press = 0, size = 34}: {x: number; y: number; press?: number; size?: number}) => (
  <svg style={{position: 'absolute', left: x, top: y, overflow: 'visible', transform: `scale(${1 - 0.12 * press})`, transformOrigin: '0 0'}}
    width={size} height={size * 1.5} viewBox="0 0 20 30">
    <path d="M1 1 L1 23 L6.5 17.8 L10.2 26.6 L13.6 25.1 L9.9 16.5 L17.2 16.5 Z" fill="#000" stroke="#fff" strokeWidth="1.6" strokeLinejoin="round" />
  </svg>
);

/** Left-aligned two-line headline: line 1 ink; line 2 arrives grey and turns ink (`inked` 0..1). */
export const Headline = ({lines, x, y, size = 108, shown = 1, inked = 1}: {lines: [string, string]; x: number; y: number; size?: number; shown?: number; inked?: number}) => {
  const mix = (a: string, b: string, u: number) => {
    const h = (s: string) => [1, 3, 5].map((i) => parseInt(s.slice(i, i + 2), 16));
    const [A, B] = [h(a), h(b)];
    return `rgb(${A.map((v, i) => Math.round(v + (B[i] - v) * u)).join(',')})`;
  };
  return (
    <div style={{position: 'absolute', left: x, top: y, fontFamily: ui, fontSize: size, fontWeight: 600, letterSpacing: -2.5, lineHeight: 1.06}}>
      <div style={{color: P.ink}}>{lines[0]}</div>
      <div style={{color: mix(P.ink3, P.ink, inked), opacity: shown, transform: `translateY(${(1 - shown) * 18}px)`}}>{lines[1]}</div>
    </div>
  );
};

/** The spoken words, quoted small: Loom's caption over the UI. */
export const Quote = ({text, x, y, u = 1}: {text: string; x: number; y: number; u?: number}) => (
  <div style={{position: 'absolute', left: x, top: y, fontFamily: mono, fontSize: 20, color: P.ink2, opacity: u, whiteSpace: 'nowrap',
    background: P.ground, padding: '4px 10px', boxShadow: `0 0 0 1px ${P.hairline}`}}>
    <span style={{color: P.marker}}>—</span> “{text}”
  </div>
);
