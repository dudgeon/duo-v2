import {AbsoluteFill, interpolate} from 'remotion';
import {Wallpaper} from '../lib/Desk';
import {smootherstep} from '../lib/camera';
import {DuoIcon} from '../lib/DuoIcon';
import {DOCK_DUO, Dock, MenuBar} from '../lib/Clutter';
import tokens from '../../style/tokens.json';

// S0: the Duo logo builds itself, then glides left beside its title. The settled frame is the thumbnail.
// The icon is drawn from the app icon's own geometry (docs/design/icon-handoff, scripts/gen-app-icon.swift),
// on its 1024 grid, so it is the real mark, not a likeness. Parts snap in (Paper Mono's grammar), no fades.

export type LogoEvents = {title?: number; sub?: number; exit?: number};

const clamp = {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'} as const;
const ramp = (t: number, a: number, b: number) => smootherstep(interpolate(t, [a, b], [0, 1], clamp));

/** The opening: the icon builds at the centre, then glides left as "Duo" and its line arrive on the voice. */
export const LogoScene = ({t, ev}: {t: number; ev: LogoEvents}) => {
  const W = tokens.frame.width, H = tokens.frame.height, S = tokens.frame.safe;
  const titleAt = ev.title ?? 2.4, subAt = ev.sub ?? titleAt + 0.8;
  const glide = ramp(t, titleAt - 0.35, titleAt + 0.45);
  // Centre: 460 px. Settled: 300 px at the left margin, its middle on the frame's middle.
  const size = 460 + (300 - 460) * glide;
  const x = (W / 2 - 230) + (S + 32 - (W / 2 - 230)) * glide;
  const y = H / 2 - size / 2 - 10;
  const title = ramp(t, titleAt, titleAt + 0.4);
  const sub = ramp(t, subAt, subAt + 0.35), inked = ramp(t, subAt + 0.35, subAt + 1.1);
  const scrim = ramp(t, titleAt - 0.3, titleAt + 0.5);
  const tx = S + 32 + 300 + 64;

  // The way out (transition 'logo-to-dock', a motion graphic into S1): the words wipe back toward the
  // icon, the menu bar and Dock slide in, and the icon arcs down into its Dock slot. The last frame is
  // S1's first: the same wallpaper, menu bar and Dock, with Duo in it, before the clutter starts.
  const e0 = ev.exit ?? 1e9;
  const wipeSub = ramp(t, e0, e0 + 0.38), wipeTitle = ramp(t, e0 + 0.08, e0 + 0.5);
  const bars = ramp(t, e0 + 0.3, e0 + 0.85);
  const fly = ramp(t, e0 + 0.25, e0 + 1.15);
  const landed = t >= e0 + 1.15;
  const pop = landed ? Math.sin(Math.min(1, (t - e0 - 1.15) / 0.22) * Math.PI) * 0.1 : 0;
  const tileSize = DOCK_DUO.w * 1024 / 824;
  const tx0 = x, ty0 = y, tx1 = DOCK_DUO.x - (tileSize - DOCK_DUO.w) / 2, ty1 = DOCK_DUO.y - (tileSize - DOCK_DUO.w) / 2;
  // A quadratic arc: up and over, then down into the Dock.
  const cx = (tx0 + tx1) / 2, cy = Math.min(ty0, ty1) - 220;
  const bez = (a: number, c: number, b: number) => (1 - fly) ** 2 * a + 2 * (1 - fly) * fly * c + fly ** 2 * b;
  const iconSize = size + (tileSize - size) * fly;
  const ix = bez(tx0, cx, tx1), iy = bez(ty0, cy, ty1);
  return (
    <AbsoluteFill>
      <Wallpaper w={W} h={H} />
      {/* Only behind the type, for legibility; the mountain stays bright. */}
      <AbsoluteFill style={{background: 'linear-gradient(90deg, rgba(8,12,18,0.42), rgba(8,12,18,0.2) 40%, rgba(8,12,18,0) 62%)', opacity: scrim * (1 - ramp(t, e0, e0 + 0.6))}} />
      <div style={{position: 'absolute', left: 0, top: 0, width: W, transform: `translateY(${(bars - 1) * 34}px)`}}>{bars > 0 && <MenuBar app="Finder" />}</div>
      {bars > 0 && <Dock duo={landed ? 'tile' : 'slot'} y={(1 - bars) * 120} />}
      {!landed && <div style={{position: 'absolute', left: ix, top: iy}}><DuoIcon t={t} size={iconSize} /></div>}
      {landed && pop > 0 && <div style={{position: 'absolute', left: tx1 - tileSize * pop / 2, top: ty1 - tileSize * pop, transformOrigin: '0 0'}}><DuoIcon t={99} size={tileSize * (1 + pop)} /></div>}
      <div style={{position: 'absolute', left: tx, top: H / 2 - 150, fontFamily: tokens.font.ui, color: '#fff', filter: 'drop-shadow(0 2px 14px rgba(0,0,0,0.28))'}}>
        <div style={{fontSize: 200, fontWeight: 650, letterSpacing: -6, lineHeight: 1, clipPath: `inset(0 ${100 - 100 * title * (1 - wipeTitle)}% 0 0)`,
          transform: `translateX(${(1 - title) * -24}px)`}}>Duo</div>
        <div style={{fontSize: 54, fontWeight: 550, letterSpacing: -1, marginTop: 22, opacity: sub > 0 ? 1 : 0, clipPath: `inset(0 ${100 * wipeSub}% 0 0)`,
          transform: `translateY(${(1 - sub) * 14}px)`, color: `rgba(255,255,255,${0.5 + 0.45 * inked})`, }}>
          A desktop client for Claude Code
        </div>
      </div>
    </AbsoluteFill>
  );
};
