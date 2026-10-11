import {AbsoluteFill, Img, interpolate, staticFile, useCurrentFrame, useVideoConfig} from 'remotion';
import {Chapter, Cursor, Headline, Marker, MiniWindow, Panel, PaperGround, Quote, ramp} from '../lib/Paper';
import {smootherstep} from '../lib/camera';
import tokens from '../../style/tokens.json';

// Style frames for Geoff's approval (M3), drawn from style/reference-analysis.md on real captures.
// Each is a 4 s clip; the build also takes a still at its settled frame.

const S = 4; // capture scale
const clamp = {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'} as const;

/** S6: the needs-you chip, in the overlay language: cursor, marker, mini window with the real list. */
export const CalloutFrame = () => {
  const t = useCurrentFrame() / useVideoConfig().fps;
  const k = 1.25; // output px per window point
  const px = 96, py = 150;
  const chip = {x: 220.5, y: 12, w: 84.5, h: 20}; // video.needs-you-chip in board-1440
  const c = {x: px + (chip.x + chip.w / 2) * k, y: py + (chip.y + chip.h / 2) * k};
  // Cursor springs in from lower right and clicks the chip.
  const m = ramp(t, 0.2, 1.1);
  const cur = {x: 980 + (c.x + 18 - 980) * m, y: 760 + (c.y + 6 - 760) * m};
  const press = interpolate(t, [1.15, 1.22, 1.32], [0, 1, 0], clamp);
  return (
    <AbsoluteFill>
      <PaperGround />
      <Chapter n="06" title="What needs you" />
      <Panel src="capture/board-1440.png" scale={S} region={{x: 0, y: 0, w: 1040, h: 640}} x={px} y={py} k={k} />
      <Marker cx={c.x} cy={c.y} rx={chip.w * k / 2 + 22} ry={chip.h * k / 2 + 16} progress={ramp(t, 1.25, 1.75)} />
      <Quote text="…or waiting on you." x={1416} y={326} u={ramp(t, 1.6, 1.9)} />
      <MiniWindow x={1330} y={366} w={500} title="needs-you · 3" open={ramp(t, 1.7, 1.86)}>
        <Panel src="capture/board-1440.png" scale={S} region={{x: 1104, y: 44, w: 333, h: 300}} x={0} y={0} k={1.5}
          style={{position: 'relative', borderRadius: 0, boxShadow: 'none'}} />
      </MiniWindow>
      <Cursor x={cur.x} y={cur.y} press={press} />
    </AbsoluteFill>
  );
};

/** S3: the turn. Left-aligned headline on paper; the real window floats in perspective at the right. */
export const HeadlineFrame = () => {
  const t = useCurrentFrame() / useVideoConfig().fps;
  const settle = ramp(t, 0, 1.4);
  const k = 0.7;
  return (
    <AbsoluteFill style={{overflow: 'hidden'}}>
      <PaperGround />
      <Chapter n="03" title="The turn" />
      <Headline lines={['Built around', 'your projects.']} x={tokens.frame.safe + 32} y={330} shown={ramp(t, 0.5, 0.9)} inked={ramp(t, 1.4, 2.2)} />
      <div style={{position: 'absolute', left: tokens.frame.safe + 36, top: 640, fontFamily: tokens.font.mono, fontSize: 22, lineHeight: 1.7,
        color: tokens.paper.ink2, opacity: ramp(t, 2.2, 2.6)}}>
        checkout-redesign  ·  refunds-api-spec<br />onboarding-v3  ·  pricing-experiment-q4
      </div>
      <div style={{position: 'absolute', left: 980 + (1 - settle) * 120, top: 170, perspective: 2400}}>
        <div style={{transform: `rotateY(${-16 + 4 * settle}deg) rotateX(4deg)`, transformOrigin: '0 50%'}}>
          <Panel src="capture/board-1440.png" scale={S} region={{x: 0, y: 0, w: 1440, h: 901}} x={0} y={0} k={k}
            style={{position: 'relative', borderRadius: 14, boxShadow: `0 0 0 1px ${tokens.paper.hairline}, 0 40px 90px rgba(31,35,40,0.22)`}} />
        </div>
      </div>
    </AbsoluteFill>
  );
};

/** S3, line 3: every project, one window each, in a perspective cascade on a soft wash. */
export const CascadeFrame = () => {
  const t = useCurrentFrame() / useVideoConfig().fps;
  const shots = ['capture/project.png', 'capture/list-1440.png', 'capture/chat-window.png', 'capture/board-1440.png'];
  return (
    <AbsoluteFill style={{overflow: 'hidden'}}>
      <AbsoluteFill style={{background: `radial-gradient(120% 90% at 20% 20%, ${tokens.paper.washA}, transparent 60%), radial-gradient(110% 90% at 85% 85%, ${tokens.paper.washB}, transparent 60%), ${tokens.paper.ground}`}} />
      <Chapter n="03" title="Any project, where you left off" />
      <div style={{position: 'absolute', left: 260, top: 210, perspective: 2600}}>
        {shots.map((src, i) => {
          const u = smootherstep(interpolate(t, [0.25 * i, 0.25 * i + 0.9], [0, 1], clamp));
          return (
            <div key={src} style={{position: 'absolute', left: i * 200, top: i * 70 - (1 - u) * 60, opacity: u,
              transform: `rotateY(-28deg) rotateX(8deg)`, transformOrigin: '0 0'}}>
              <Panel src={src} scale={S} region={{x: 0, y: 0, w: 1440, h: 901}} x={0} y={0} k={0.5}
                style={{position: 'relative', borderRadius: 12, boxShadow: `0 0 0 1px ${tokens.paper.hairline}, 0 30px 70px rgba(31,35,40,0.25)`}} />
            </div>
          );
        })}
      </div>
    </AbsoluteFill>
  );
};

export const StyleFrame = ({frame}: {frame: 'callout' | 'headline' | 'cascade'}) =>
  frame === 'callout' ? <CalloutFrame /> : frame === 'headline' ? <HeadlineFrame /> : <CascadeFrame />;
