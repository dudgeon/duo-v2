import {AbsoluteFill, Img, interpolate, staticFile} from 'remotion';
import {Wallpaper} from '../../lib/Desk';
import {smootherstep} from '../../lib/camera';
import {DuoIcon} from '../../lib/DuoIcon';
import {DOCK_DUO, Dock, MenuBar} from '../../lib/Clutter';
import tokens from '../../../style/tokens.json';
import type {SceneProps} from '../registry';

// The 0.2.21 film's bookends (shots.json S0 `rel-title`, S5's ending `rel-end`): the intro's title card (Logo.tsx's
// build, glide and type, on the same wallpaper) with the release's own words, and the window opening out of the Dock
// tile and folding back into it. The window is drawn where AppScene draws it (App.tsx: 0.855 px a point, centred, 38
// from the top), so the frame either side of a hand-over is the same picture.

const W = tokens.frame.width, H = tokens.frame.height, S = tokens.frame.safe;
const K = 0.855;
const clamp = {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'} as const;
const ramp = (t: number, a: number, b: number) => (b <= a ? (t >= a ? 1 : 0) : smootherstep(interpolate(t, [a, b], [0, 1], clamp)));
const lerp = (a: number, b: number, u: number) => a + (b - a) * u;

export type Stills = {window: {w: number; h: number}; src: Record<string, string>; first: string; last: string};
type Scene = SceneProps['scene'] & {stills?: Stills; duration?: number};

const TILE = DOCK_DUO.w * 1024 / 824;
const tileAt = {x: DOCK_DUO.x - (TILE - DOCK_DUO.w) / 2, y: DOCK_DUO.y - (TILE - DOCK_DUO.w) / 2};

/** Duo's window, `u` of the way from its Dock tile (0) to where AppScene draws it (1): a genie-less scale and glide. */
const Window = ({stills, state, u}: {stills: Stills; state: string; u: number}) => {
  const ww = stills.window.w * K, wh = stills.window.h * K;
  const to = {x: (W - ww) / 2, y: 38};
  const from = {x: DOCK_DUO.x + DOCK_DUO.w / 2 - ww * 0.03, y: DOCK_DUO.y + DOCK_DUO.w / 2 - wh * 0.03};
  const s = lerp(0.06, 1, u);
  const x = lerp(from.x, to.x, u), y = lerp(from.y, to.y, Math.pow(u, 0.8));
  if (u <= 0) return null;
  return (
    <div style={{position: 'absolute', left: x, top: y, width: ww, height: wh, transformOrigin: '0 0', transform: `scale(${s})`,
      borderRadius: 12, overflow: 'hidden', opacity: Math.min(1, u * 3), boxShadow: '0 30px 80px rgba(0,0,0,0.42), 0 0 0 0.5px rgba(0,0,0,0.4)'}}>
      <Img src={staticFile(stills.src[state])} style={{width: ww, height: wh}} />
    </div>
  );
};

/** The card's type: "Duo 0.2.21", then the release's line; `title`, `sub` reveal, `wipe` takes them back to the icon. */
const Words = ({x, title, sub, ink, wipe, foot}: {x: number; title: number; sub: number; ink: number; wipe: number; foot?: number}) => (
  <div style={{position: 'absolute', left: x, top: H / 2 - 172, fontFamily: tokens.font.ui, color: '#fff', filter: 'drop-shadow(0 2px 14px rgba(0,0,0,0.28))'}}>
    <div style={{fontSize: 200, fontWeight: 650, letterSpacing: -6, lineHeight: 1, whiteSpace: 'nowrap',
      clipPath: `inset(0 ${100 - 100 * title * (1 - ramp(wipe, 0.08, 1))}% 0 0)`, transform: `translateX(${(1 - title) * -24}px)`}}>
      Duo <span style={{fontWeight: 300, letterSpacing: -4, opacity: 0.82}}>0.2.21</span>
    </div>
    <div style={{fontSize: 50, fontWeight: 550, letterSpacing: -0.8, lineHeight: 1.22, marginTop: 24, opacity: sub > 0 ? 1 : 0,
      clipPath: `inset(0 ${100 * ramp(wipe, 0, 0.75)}% 0 0)`, transform: `translateY(${(1 - sub) * 14}px)`, color: `rgba(255,255,255,${0.5 + 0.45 * ink})`}}>
      Review in Markdown<br />Comments, suggested edits and @claude
    </div>
    {foot !== undefined && (
      <div style={{fontFamily: tokens.font.mono, fontSize: 30, marginTop: 36, opacity: 0.86 * foot, transform: `translateY(${(1 - foot) * 10}px)`}}>
        Duo › Check for Updates…
      </div>
    )}
  </div>
);

/** S0: the icon builds, glides left as the words arrive on the voice; at the exit it drops into the Dock and the window opens out of it. */
export const ReleaseTitle = ({t, ev, scene}: SceneProps) => {
  const st = (scene as Scene).stills;
  const titleAt = ev.title ?? 2.4, subAt = ev.sub ?? titleAt + 0.8;
  const glide = ramp(t, titleAt - 0.35, titleAt + 0.45);
  const size = 460 + (300 - 460) * glide;
  const x = (W / 2 - 230) + (S + 32 - (W / 2 - 230)) * glide;
  const y = H / 2 - size / 2 - 10;
  const title = ramp(t, titleAt, titleAt + 0.4), sub = ramp(t, subAt, subAt + 0.35), ink = ramp(t, subAt + 0.35, subAt + 1.1);
  const scrim = ramp(t, titleAt - 0.3, titleAt + 0.5);
  // The way out ('rel-open'): Logo.tsx's 'logo-to-dock' (words back, bars in, the icon arcs into its slot), then the window opens.
  const e0 = ev.exit ?? 1e9;
  // Quicker than Logo.tsx's (Q-303): the film is under a minute, and the window starts opening under a second after the exit.
  const wipe = interpolate(t, [e0, e0 + 0.4], [0, 1], clamp);
  const bars = ramp(t, e0 + 0.15, e0 + 0.6), fly = ramp(t, e0 + 0.1, e0 + 0.8), landed = t >= e0 + 0.8;
  const pop = landed ? Math.sin(Math.min(1, (t - e0 - 0.8) / 0.18) * Math.PI) * 0.1 : 0;
  const open = ramp(t, e0 + 0.9, e0 + 1.65);
  const cx = (x + tileAt.x) / 2, cy = Math.min(y, tileAt.y) - 220;
  const bez = (a: number, c: number, b: number) => (1 - fly) ** 2 * a + 2 * (1 - fly) * fly * c + fly ** 2 * b;
  return (
    <AbsoluteFill>
      <Wallpaper w={W} h={H} />
      <AbsoluteFill style={{background: 'linear-gradient(90deg, rgba(8,12,18,0.42), rgba(8,12,18,0.2) 40%, rgba(8,12,18,0) 62%)', opacity: scrim * (1 - ramp(t, e0, e0 + 0.6))}} />
      <div style={{position: 'absolute', left: 0, top: 0, width: W, transform: `translateY(${(bars - 1) * 34}px)`}}>{bars > 0 && <MenuBar app={open > 0 ? 'Duo' : 'Finder'} />}</div>
      {bars > 0 && <Dock duo={landed ? 'tile' : 'slot'} y={(1 - bars) * 120} running={open > 0} />}
      {!landed && <div style={{position: 'absolute', left: bez(x, cx, tileAt.x), top: bez(y, cy, tileAt.y)}}><DuoIcon t={t} size={size + (TILE - size) * fly} /></div>}
      {landed && pop > 0 && <div style={{position: 'absolute', left: tileAt.x - TILE * pop / 2, top: tileAt.y - TILE * pop}}><DuoIcon t={99} size={TILE * (1 + pop)} /></div>}
      <Words x={S + 32 + 300 + 64} title={title} sub={sub} ink={ink} wipe={wipe} />
      {st && <Window stills={st} state={st.first} u={open} />}
    </AbsoluteFill>
  );
};

/** S5's ending: opens on the app's last picture, wide; the window folds into its Dock tile, the icon rises and the card comes back,
 *  with the way to get it under it. Events: `fold` (the window starts back), `card` (the words), `foot` (Check for Updates). */
export const ReleaseEnd = ({t, ev, scene}: SceneProps) => {
  const st = (scene as Scene).stills;
  const f0 = ev.fold ?? 1;
  const fold = ramp(t, f0, f0 + 0.85);
  const rise = ramp(t, f0 + 0.9, f0 + 1.8);
  const bars = 1 - ramp(t, f0 + 0.9, f0 + 1.5);
  const size = TILE + (300 - TILE) * rise;
  const x1 = S + 32, y1 = H / 2 - 150 - 10;
  const cx = (tileAt.x + x1) / 2, cy = Math.min(tileAt.y, y1) - 220;
  const bez = (a: number, c: number, b: number) => (1 - rise) ** 2 * a + 2 * (1 - rise) * rise * c + rise ** 2 * b;
  const c0 = Math.max(ev.card ?? 0, f0 + 1.75);   // the words come in once the icon has landed beside them
  const title = ramp(t, c0, c0 + 0.4), sub = ramp(t, c0 + 0.3, c0 + 0.65), ink = ramp(t, c0 + 0.65, c0 + 1.3);
  const f1 = Math.max(ev.foot ?? 0, c0 + 0.7), foot = ramp(t, f1, f1 + 0.4);
  return (
    <AbsoluteFill>
      <Wallpaper w={W} h={H} />
      <AbsoluteFill style={{background: 'linear-gradient(90deg, rgba(8,12,18,0.42), rgba(8,12,18,0.2) 40%, rgba(8,12,18,0) 62%)', opacity: ramp(t, c0 - 0.3, c0 + 0.5)}} />
      <div style={{position: 'absolute', left: 0, top: 0, width: W, transform: `translateY(${(bars - 1) * 34}px)`}}>{bars > 0 && <MenuBar app={fold < 1 ? 'Duo' : 'Finder'} />}</div>
      {bars > 0 && <Dock duo={rise > 0 ? 'slot' : 'tile'} y={(1 - bars) * 120} running={fold < 1} />}
      {rise > 0 && <div style={{position: 'absolute', left: bez(tileAt.x, cx, x1), top: bez(tileAt.y, cy, y1)}}><DuoIcon t={99} size={size} /></div>}
      {st && <Window stills={st} state={st.last} u={1 - fold} />}
      <Words x={S + 32 + 300 + 64} title={title} sub={sub} ink={ink} wipe={0} foot={foot} />
    </AbsoluteFill>
  );
};
