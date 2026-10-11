import {interpolate} from 'remotion';
import {smootherstep} from './camera';

// The Duo app icon, drawn from its own geometry (docs/design/icon-handoff, scripts/gen-app-icon.swift)
// on its 1024 grid, so it is the real mark, not a likeness. `t` plays its build; any t past 2.5 is the
// finished icon (the Dock tile). The squircle spans 100-924 of the grid: a 62 px tile is size 77.

const clamp = {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'} as const;
const ramp = (t: number, a: number, b: number) => smootherstep(interpolate(t, [a, b], [0, 1], clamp));
// A snap: a quick overshoot-free settle from 96% scale, visible from its first frame.
const snap = (t: number, at: number, d = 0.14) => (t < at ? 0 : ramp(t, at, at + d));

// The build, in scene seconds.
const B = {outline: [0.15, 0.75], console: 0.72, page: 0.84, seam: 0.98, chevron: [1.02, 1.3],
  cons: [1.3, 1.42, 1.54], head: 1.36, page1: 1.56, page2: 1.68, highlight: 1.86, hl: [1.98, 2.1], last: 2.24};

const Pill = ({x, y, w, h, color, u}: {x: number; y: number; w: number; h: number; color: string; u: number}) =>
  u <= 0 ? null : <rect x={x} y={y} width={w * u} height={h} rx={h / 2} fill={color} />;

export const DuoIcon = ({t, size}: {t: number; size: number}) => {
  const outline = ramp(t, B.outline[0], B.outline[1]);
  const cons = snap(t, B.console), page = snap(t, B.page), seam = snap(t, B.seam, 0.1);
  const chev = ramp(t, B.chevron[0], B.chevron[1]);
  const grow = (at: number) => ramp(t, at, at + 0.2);
  const hl = snap(t, B.highlight, 0.16);
  const perim = 4 * 824 - 8 * 185 + 2 * Math.PI * 185;
  const chevLen = 2 * Math.hypot(64, 52);
  return (
    <svg width={size} height={size} viewBox="0 0 1024 1024" style={{overflow: 'visible'}}>
      <defs>
        <clipPath id="sq"><rect x={100} y={100} width={824} height={824} rx={185} /></clipPath>
        <linearGradient id="console" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stopColor="#24272d" /><stop offset="1" stopColor="#121418" /></linearGradient>
        <linearGradient id="page" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stopColor="#ffffff" /><stop offset="1" stopColor="#e9edf1" /></linearGradient>
        <filter id="drop" x="-20%" y="-20%" width="140%" height="150%"><feDropShadow dx="0" dy="14" stdDeviation="16" floodColor="#000" floodOpacity="0.34" /></filter>
      </defs>
      {/* The shadowed body arrives with the console. */}
      {/* The shadow lands once both panes are in, so nothing dark shows where the page is still arriving. */}
      {seam > 0 && <rect x={100} y={100} width={824} height={824} rx={185} fill="#121418" filter="url(#drop)" opacity={seam} />}
      <g clipPath="url(#sq)">
        {/* Console wipes down from the top; the page wipes up from the bottom. */}
        {seam > 0 && <rect x={100} y={100} width={824} height={824} fill="#121418" />}
        {cons > 0 && <rect x={100} y={100} width={372} height={824 * cons} fill="url(#console)" />}
        {page > 0 && <rect x={472} y={100 + 824 * (1 - page)} width={452} height={824 * page} fill="url(#page)" />}
        {seam > 0 && <rect x={472} y={100} width={6} height={824 * seam} fill="rgba(0,0,0,0.18)" />}
      </g>
      {chev > 0 && <polyline points="206,364 270,416 206,468" fill="none" stroke="#e6e8eb" strokeWidth={30} strokeLinecap="round" strokeLinejoin="round"
        strokeDasharray={chevLen} strokeDashoffset={chevLen * (1 - chev)} />}
      <Pill x={206} y={538} w={176} h={26} color="#9aa1ab" u={grow(B.cons[0])} />
      <Pill x={206} y={594} w={128} h={26} color="#9aa1ab" u={grow(B.cons[1])} />
      <Pill x={206} y={650} w={156} h={26} color="#9aa1ab" u={grow(B.cons[2])} />
      <Pill x={556} y={317} w={240} h={34} color="#1f2328" u={grow(B.head)} />
      <Pill x={556} y={395} w={268} h={24} color="#c9cdd3" u={grow(B.page1)} />
      <Pill x={556} y={447} w={226} h={24} color="#c9cdd3" u={grow(B.page2)} />
      {/* Claude's highlight: the block snaps in behind two lines, as Duo marks what Claude added. */}
      {hl > 0 && <rect x={538 + 160 * (1 - (0.96 + 0.04 * hl))} y={509 + 63 * (1 - (0.96 + 0.04 * hl))} width={320 * (0.96 + 0.04 * hl)} height={126 * (0.96 + 0.04 * hl)} rx={16} fill="#dfe3e8" />}
      <Pill x={556} y={537} w={252} h={24} color="#8b939c" u={grow(B.hl[0])} />
      <Pill x={556} y={585} w={182} h={24} color="#8b939c" u={grow(B.hl[1])} />
      <Pill x={556} y={683} w={240} h={24} color="#c9cdd3" u={grow(B.last)} />
      {/* The outline draws first, a white hairline on the wallpaper, and becomes the icon's faint edge. */}
      <rect x={103} y={103} width={818} height={818} rx={182} fill="none" stroke={seam > 0 ? 'rgba(0,0,0,0.12)' : 'rgba(255,255,255,0.92)'}
        strokeWidth={seam > 0 ? 6 : 5} strokeDasharray={perim} strokeDashoffset={perim * (1 - outline)} />
    </svg>
  );
};

