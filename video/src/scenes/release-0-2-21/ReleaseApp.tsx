import {createElement, Fragment, type ComponentType} from 'react';
import {AbsoluteFill, interpolate} from 'remotion';
import {AppScene, type AppData} from '../App';
import {smootherstep} from '../../lib/camera';
import tokens from '../../../style/tokens.json';
import type {SceneProps} from '../registry';

// The 0.2.21 film's app scenes (`rel-app`): the intro's AppScene as it is (the real window on the desk, cursor, camera,
// outline traces), planned by plan.mjs exactly as an `app` scene. Captions (Q-297) never sit on the picture's subject:
// in the app scenes they have a band of their own along the bottom, which the cameras frame above (shots.json); at the
// ending they move to the lake under the card. The title card has none: its words say the line, and its frame is the poster.

const W = tokens.frame.width, H = tokens.frame.height;
const clamp = {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'} as const;
const ramp = (t: number, a: number, b: number) => (b <= a ? (t >= a ? 1 : 0) : smootherstep(interpolate(t, [a, b], [0, 1], clamp)));

/** The caption band's height: the cameras keep what a shot is about above it. */
export const BAND = 92;

type Line = {text: string; start: number; duration: number};
const words = (s: string) => s.replace(/\s+--\s*$/, '').replace(/ -- /g, ' – ');

/** Each line arrives as it starts, reads white while it's said, and goes as the next arrives; set balanced (no orphan). */
const Lines = ({t, lines, style}: {t: number; lines: Line[]; style: React.CSSProperties}) => (
  <>
    {lines.map((l, i) => {
      const next = lines[i + 1]?.start ?? l.start + l.duration + 1.0;
      const inU = ramp(t, l.start - 0.2, l.start + 0.12), outU = ramp(t, Math.min(next - 0.15, l.start + l.duration + 0.5), Math.min(next, l.start + l.duration + 0.8));
      const u = inU * (1 - outU);
      if (u <= 0.001) return null;
      const ink = ramp(t, l.start, l.start + 0.25) * (1 - ramp(t, l.start + l.duration, l.start + l.duration + 0.3));
      return (
        <div key={i} style={{position: 'absolute', left: 0, right: 0, display: 'flex', justifyContent: 'center', alignItems: 'center', opacity: u, ...style}}>
          <div style={{maxWidth: 1500, fontFamily: tokens.font.ui, fontSize: 30, lineHeight: '38px', fontWeight: 500, textAlign: 'center', textWrap: 'balance',
            color: `rgba(255,255,255,${0.6 + 0.4 * ink})`} as React.CSSProperties}>{words(l.text)}</div>
        </div>
      );
    })}
  </>
);

/** The band: solid, the full width, `u` of the way up (it rises as the first app scene opens and drops before the ending). */
export const CaptionBand = ({t, lines, u = 1}: {t: number; lines: Line[]; u?: number}) => (
  <div style={{position: 'absolute', left: 0, top: H - BAND * u, width: W, height: BAND, background: '#111317', overflow: 'hidden'}}>
    <Lines t={t} lines={lines} style={{top: 0, height: BAND}} />
  </div>
);

/** Over the title card: low over the lake, with a soft shadow for the bright water. */
export const LakeCaptions = ({t, lines}: {t: number; lines: Line[]}) => (
  <AbsoluteFill style={{filter: 'drop-shadow(0 1px 8px rgba(0,0,0,0.55))'}}>
    <Lines t={t} lines={lines} style={{bottom: 40, height: 80}} />
  </AbsoluteFill>
);

type Scene = SceneProps['scene'] & {app?: AppData; transitionIn?: {name: string}};

export const ReleaseApp = ({t, scene}: SceneProps) => {
  const s = scene as Scene;
  // The first app scene opens on the title card's last picture, which has no band: it rises there.
  const u = s.transitionIn?.name === 'rel-open' ? ramp(t, 0.1, 0.6) : 1;
  return (
    <>
      {s.app ? <AppScene t={t} data={s.app} /> : null}
      <CaptionBand t={t} lines={scene.lines ?? []} u={u} />
    </>
  );
};

/** The ending opens on the last app scene's picture, band and all: the line starts in the band, the band drops as the window
 *  folds into its Dock tile (the band would hide the Dock), and the rest of the line reads over the lake under the card. */
export const endCaptioned = (C: ComponentType<SceneProps>): ComponentType<SceneProps> => (p: SceneProps) => {
  const f0 = p.ev.fold ?? 1, lines = p.scene.lines ?? [];
  const lake = ramp(p.t, f0 + 0.35, f0 + 0.7);
  return createElement(Fragment, null, createElement(C, p),
    createElement(CaptionBand, {t: p.t, lines, u: 1 - ramp(p.t, f0 - 0.15, f0 + 0.3)}),
    lake > 0 ? createElement('div', {style: {position: 'absolute', inset: 0, opacity: lake}}, createElement(LakeCaptions, {t: p.t, lines})) : null);
};
