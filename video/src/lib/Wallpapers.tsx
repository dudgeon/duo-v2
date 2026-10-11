import React from 'react';

// Our own wallpapers, drawn as SVG and rendered once to a PNG by the build (Desk.tsx draws the PNG).
// Never Apple's images unless the build is given one (desk.wallpaper.image); see Q-175.

type P = {w: number; h: number};

const wave = (w: number, h: number, y: number, amp: number, phase: number, freq = 1.4) => {
  const pts: string[] = [];
  for (let i = 0; i <= 48; i++) {
    const x = (i / 48) * w;
    const yy = y + amp * Math.sin((i / 48) * Math.PI * 2 * freq + phase) + amp * 0.35 * Math.sin((i / 48) * Math.PI * 5 + phase * 1.7);
    pts.push(`${x.toFixed(1)},${yy.toFixed(1)}`);
  }
  return `M0,${h} L${pts.join(' L')} L${w},${h} Z`;
};

/** Rolling hills under a soft evening sky. */
export const Hills = ({w, h}: P) => {
  const bands: [number, number, number, string, string][] = [
    [0.50, 0.06, 0.4, '#8E7CF0', '#C9A2F2'],
    [0.58, 0.07, 1.6, '#F07A6E', '#F7B48C'],
    [0.68, 0.06, 2.6, '#3FAF8C', '#9ED96A'],
    [0.80, 0.07, 3.8, '#1F7A55', '#5DBB4F'],
    [0.92, 0.05, 5.0, '#165C42', '#2F9A4E'],
  ];
  return (
    <svg width={w} height={h} viewBox={`0 0 ${w} ${h}`} style={{position: 'absolute', left: 0, top: 0}}>
      <defs>
        <linearGradient id="sky" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stopColor="#5E7FF2" /><stop offset="45%" stopColor="#9C9BF4" /><stop offset="70%" stopColor="#F4B3B0" />
        </linearGradient>
        {bands.map((b, i) => (
          <linearGradient key={i} id={`b${i}`} x1="0" y1="0" x2="1" y2="1">
            <stop offset="0%" stopColor={b[4]} /><stop offset="100%" stopColor={b[3]} />
          </linearGradient>
        ))}
        <filter id="soft"><feGaussianBlur stdDeviation={w * 0.002} /></filter>
      </defs>
      <rect width={w} height={h} fill="url(#sky)" />
      <g filter="url(#soft)">
        {bands.map((b, i) => <path key={i} d={wave(w, h, b[0] * h, b[1] * h, b[2])} fill={`url(#b${i})`} />)}
      </g>
    </svg>
  );
};

/** A warm dusk: deep blue to amber, a low sun and one long ridge. */
export const Dusk = ({w, h}: P) => (
  <svg width={w} height={h} viewBox={`0 0 ${w} ${h}`} style={{position: 'absolute', left: 0, top: 0}}>
    <defs>
      <linearGradient id="dsky" x1="0" y1="0" x2="0" y2="1">
        <stop offset="0%" stopColor="#1B2350" /><stop offset="45%" stopColor="#5B3F8C" /><stop offset="72%" stopColor="#E0795A" /><stop offset="100%" stopColor="#F5B867" />
      </linearGradient>
      <radialGradient id="sun" cx="0.62" cy="0.72" r="0.35">
        <stop offset="0%" stopColor="#FFE2A8" stopOpacity="0.95" /><stop offset="100%" stopColor="#FFE2A8" stopOpacity="0" />
      </radialGradient>
      <linearGradient id="ridge" x1="0" y1="0" x2="0" y2="1"><stop offset="0%" stopColor="#3A2550" /><stop offset="100%" stopColor="#140E24" /></linearGradient>
    </defs>
    <rect width={w} height={h} fill="url(#dsky)" />
    <rect width={w} height={h} fill="url(#sun)" />
    <path d={wave(w, h, 0.82 * h, 0.05 * h, 0.8, 0.9)} fill="url(#ridge)" opacity={0.92} />
  </svg>
);

/** Graphite with a warm glow and a cool one: quiet, so the window carries the frame. */
export const Graphite = ({w, h}: P) => (
  <svg width={w} height={h} viewBox={`0 0 ${w} ${h}`} style={{position: 'absolute', left: 0, top: 0}}>
    <defs>
      <radialGradient id="g1" cx="0.15" cy="0.9" r="0.7"><stop offset="0%" stopColor="#C2410C" stopOpacity="0.55" /><stop offset="100%" stopColor="#C2410C" stopOpacity="0" /></radialGradient>
      <radialGradient id="g2" cx="0.9" cy="0.1" r="0.7"><stop offset="0%" stopColor="#3B6FD8" stopOpacity="0.45" /><stop offset="100%" stopColor="#3B6FD8" stopOpacity="0" /></radialGradient>
    </defs>
    <rect width={w} height={h} fill="#1A1C20" />
    <rect width={w} height={h} fill="url(#g1)" />
    <rect width={w} height={h} fill="url(#g2)" />
  </svg>
);

export const WALLPAPERS: Record<string, (p: P) => React.ReactElement> = {hills: Hills, dusk: Dusk, graphite: Graphite};
