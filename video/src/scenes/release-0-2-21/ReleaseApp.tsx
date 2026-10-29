import {createElement, Fragment, type ComponentType} from 'react';
import {interpolate} from 'remotion';
import {AppScene, type AppData} from '../App';
import {smootherstep} from '../../lib/camera';
import tokens from '../../../style/tokens.json';
import type {SceneProps} from '../registry';

// The 0.2.21 film's app scenes (`rel-app`): the intro's AppScene as it is (the real window on the desk, cursor, camera,
// outline traces), planned by plan.mjs exactly as an `app` scene, with the voice's captions over it (Q-297).

const clamp = {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'} as const;
const ramp = (t: number, a: number, b: number) => (b <= a ? (t >= a ? 1 : 0) : smootherstep(interpolate(t, [a, b], [0, 1], clamp)));

/** Each voice line as a caption, low and centred on a dark band (the desk is busy, unlike the director film's paper):
 *  it arrives as its line starts, reads white while it's said, and goes as the next arrives. */
export const DeskCaptions = ({t, lines}: {t: number; lines: {text: string; start: number; duration: number}[]}) => (
  <>
    {lines.map((l, i) => {
      const next = lines[i + 1]?.start ?? l.start + l.duration + 1.0;
      const inU = ramp(t, l.start - 0.2, l.start + 0.12), outU = ramp(t, Math.min(next - 0.15, l.start + l.duration + 0.5), Math.min(next, l.start + l.duration + 0.8));
      const u = inU * (1 - outU);
      if (u <= 0.001) return null;
      const ink = ramp(t, l.start, l.start + 0.25) * (1 - ramp(t, l.start + l.duration, l.start + l.duration + 0.3));
      return (
        <div key={i} style={{position: 'absolute', left: 0, right: 0, bottom: 36, display: 'flex', justifyContent: 'center', opacity: u, transform: `translateY(${(1 - inU) * 8}px)`}}>
          <div style={{maxWidth: 1340, padding: '10px 22px', borderRadius: 12, background: 'rgba(14,16,20,0.72)', fontFamily: tokens.font.ui, fontSize: 32, lineHeight: '42px',
            fontWeight: 500, textAlign: 'center', color: `rgba(255,255,255,${0.62 + 0.38 * ink})`}}>{l.text.replace(/\s+--\s*$/, '').replace(/ -- /g, ' – ')}</div>
        </div>
      );
    })}
  </>
);

type Scene = SceneProps['scene'] & {app?: AppData};

export const ReleaseApp = ({t, scene}: SceneProps) => {
  const app = (scene as Scene).app;
  return app ? <AppScene t={t} data={app} /> : null;
};

/** Every scene of this film carries its captions. */
export const captioned = (C: ComponentType<SceneProps>): ComponentType<SceneProps> => (p: SceneProps) =>
  createElement(Fragment, null, createElement(C, p), createElement(DeskCaptions, {t: p.t, lines: p.scene.lines ?? []}));
