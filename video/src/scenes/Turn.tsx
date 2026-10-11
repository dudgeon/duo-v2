import {AbsoluteFill, interpolate} from 'remotion';
import {smootherstep} from '../lib/camera';
import {Headline, Panel, PaperGround, ramp} from '../lib/Paper';
import tokens from '../../style/tokens.json';

// S3, the turn: a left-aligned headline on paper with the real window in perspective (lines 1–2),
// then every project, one window each, in a cascade (lines 3–4). Events come from the voice's words.

const S = tokens.capture.scale;
const clamp = {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'} as const;

export const TurnScene = ({t, ev, headline, projects, shots}: {t: number; ev: Record<string, number>;
  headline: [string, string]; projects: string[]; shots: string[]}) => {
  const cascadeAt = ev.cascade ?? 1e9;
  const x = smootherstep(interpolate(t, [cascadeAt - 0.4, cascadeAt + 0.3], [0, 1], clamp)); // headline → cascade
  const settle = ramp(t, 0, 1.4);
  return (
    <AbsoluteFill style={{overflow: 'hidden'}}>
      <PaperGround />
      <AbsoluteFill style={{background: `radial-gradient(120% 90% at 20% 20%, ${tokens.paper.washA}, transparent 60%), radial-gradient(110% 90% at 85% 85%, ${tokens.paper.washB}, transparent 60%)`, opacity: x}} />
      <AbsoluteFill style={{opacity: 1 - x, transform: `translateX(${-x * 120}px)`}}>
        <Headline lines={headline} x={tokens.frame.safe + 32} y={330} shown={ramp(t, (ev.line2 ?? 1) - 0.3, ev.line2 ?? 1)} inked={ramp(t, ev.ink ?? 2, (ev.ink ?? 2) + 0.6)} />
        <div style={{position: 'absolute', left: tokens.frame.safe + 36, top: 640, fontFamily: tokens.font.mono, fontSize: 22, lineHeight: 1.7,
          color: tokens.paper.ink2, opacity: ramp(t, ev.projects ?? 3, (ev.projects ?? 3) + 0.4)}}>
          {projects.slice(0, 2).join('  ·  ')}<br />{projects.slice(2, 4).join('  ·  ')}
        </div>
        <div style={{position: 'absolute', left: 980 + (1 - settle) * 120, top: 170, perspective: 2400}}>
          <div style={{transform: `rotateY(${-16 + 4 * settle}deg) rotateX(4deg)`, transformOrigin: '0 50%'}}>
            <Panel src={shots[shots.length - 1]} scale={S} region={{x: 0, y: 0, w: 1440, h: 901}} x={0} y={0} k={0.7}
              style={{position: 'relative', borderRadius: 14, boxShadow: `0 0 0 1px ${tokens.paper.hairline}, 0 40px 90px rgba(31,35,40,0.22)`}} />
          </div>
        </div>
      </AbsoluteFill>
      {t > cascadeAt - 0.4 && (
        <div style={{position: 'absolute', left: 260, top: 210, perspective: 2600}}>
          {shots.map((src, i) => {
            const u = smootherstep(interpolate(t, [cascadeAt + 0.22 * i, cascadeAt + 0.22 * i + 0.8], [0, 1], clamp));
            return (
              <div key={src} style={{position: 'absolute', left: i * 200, top: i * 70 - (1 - u) * 60, opacity: u,
                transform: 'rotateY(-28deg) rotateX(8deg)', transformOrigin: '0 0'}}>
                <Panel src={src} scale={S} region={{x: 0, y: 0, w: 1440, h: 901}} x={0} y={0} k={0.5}
                  style={{position: 'relative', borderRadius: 12, boxShadow: `0 0 0 1px ${tokens.paper.hairline}, 0 30px 70px rgba(31,35,40,0.25)`}} />
              </div>
            );
          })}
        </div>
      )}
    </AbsoluteFill>
  );
};
