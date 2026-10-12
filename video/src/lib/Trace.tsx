import React from 'react';
import tokens from '../../style/tokens.json';

// The video's one callout (Geoff, 2026-10-12, from the second round of studies: "Trace is fine for now but make
// the stroke twice as thick"). An outline traced on the element's own shape: a rounded rect offset outward, its
// corners concentric with the element's, drawn from the bottom-right corner (the cursor's side) clockwise at a
// constant speed, closing exactly, and un-drawn the same way (the tail chasing the head), never faded.
// It replaces the hand-drawn marker loops (style/shot-grammar.md, "Callouts").

export type Box = {x: number; y: number; w: number; h: number};
export const TRACE = {width: 6, offset: 8, color: tokens.paper.marker, draw: 0.45, undraw: 0.3};

export function roundedRect(r: Box, rad: number) {
  const {x, y, w, h} = r, q = Math.max(0, Math.min(rad, w / 2, h / 2));
  const d = `M ${x + w} ${y + h - q} A ${q} ${q} 0 0 1 ${x + w - q} ${y + h} L ${x + q} ${y + h} A ${q} ${q} 0 0 1 ${x} ${y + h - q} ` +
    `L ${x} ${y + q} A ${q} ${q} 0 0 1 ${x + q} ${y} L ${x + w - q} ${y} A ${q} ${q} 0 0 1 ${x + w} ${y + q} Z`;
  return {d, len: 2 * (w - 2 * q) + 2 * (h - 2 * q) + 2 * Math.PI * q};
}

/** A cubic in-out from a to a+d (seconds). */
export const inOut = (t: number, a: number, d: number) => {
  const u = Math.min(1, Math.max(0, (t - a) / Math.max(d, 1e-3)));
  return u < 0.5 ? 4 * u ** 3 : 1 - (-2 * u + 2) ** 3 / 2;
};

/** Progress for a trace shown from `at` to `until`: 0→1 draws, 1→2 un-draws. */
export const traceProgress = (t: number, at: number, until: number) =>
  inOut(t, at, TRACE.draw) + inOut(t, Math.max(at + TRACE.draw, until - TRACE.undraw), TRACE.undraw);

/** The outline around `r` (output px), whose own corner radius is `radius`. */
export const Trace = ({r, radius = 10, p, width = TRACE.width, color = TRACE.color}: {r: Box; radius?: number; p: number; width?: number; color?: string}) => {
  if (p <= 0 || p >= 2) return null;
  const o = TRACE.offset;
  const {d, len} = roundedRect({x: r.x - o, y: r.y - o, w: r.w + 2 * o, h: r.h + 2 * o}, radius + o);
  const on = p <= 1 ? len * p : len * (2 - p), start = p <= 1 ? 0 : len * (p - 1);
  // The svg covers its parent rather than being a 1x1 box the path overflows: Chrome repaints only an element's own box
  // when it goes, so a 1x1 trace could stay in the next frame a render tab shoots (V2's proof, frame 1942).
  return (
    <svg style={{position: 'absolute', left: 0, top: 0, width: '100%', height: '100%', overflow: 'visible', pointerEvents: 'none'}}>
      <path d={d} fill="none" stroke={color} strokeWidth={width} strokeLinecap="round" strokeLinejoin="round" strokeDasharray={`${on} ${len + 1}`} strokeDashoffset={-start} />
    </svg>
  );
};
