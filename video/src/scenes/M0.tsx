import {AbsoluteFill, Audio, interpolate, Sequence, staticFile, useCurrentFrame, useVideoConfig} from 'remotion';
import {cameraAt, smootherstep, type Key} from '../lib/camera';
import {DeskShot, type DeskLayout} from '../lib/Desk';
import tokens from '../../style/tokens.json';

export type Timeline = {
  duration: number;
  title: {text: string; sub: string; until: number};
  capture: {src: string; scale: number};
  desk: DeskLayout;
  appear: {start: number; end: number};
  camera: Key[]; // rects in desk points
  voice: {src: string; start: number; duration: number};
};

const clamp = {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'} as const;

export const M0 = ({timeline}: {timeline: Timeline | null}) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  if (!timeline) return null;
  const t = frame / fps;
  const {title, appear} = timeline;
  const titleOpacity = interpolate(t, [title.until - 0.5, title.until], [1, 0], clamp);
  const appearU = smootherstep(interpolate(t, [appear.start, appear.end], [0, 1], clamp));

  return (
    <AbsoluteFill>
      <DeskShot src={timeline.capture.src} layout={timeline.desk} scale={timeline.capture.scale}
        camera={cameraAt(timeline.camera, t)} appear={appearU} />
      <AbsoluteFill style={{opacity: titleOpacity, justifyContent: 'center', alignItems: 'center',
        fontFamily: tokens.font.ui, color: '#FFFFFF', textShadow: '0 2px 24px rgba(0,0,0,0.25)'}}>
        <div style={{fontSize: tokens.title.size, fontWeight: tokens.title.weight, letterSpacing: tokens.title.tracking}}>{title.text}</div>
        <div style={{fontSize: tokens.title.subSize, opacity: 0.85, marginTop: 16}}>{title.sub}</div>
      </AbsoluteFill>
      <Sequence from={Math.round(timeline.voice.start * fps)}>
        <Audio src={staticFile(timeline.voice.src)} />
      </Sequence>
    </AbsoluteFill>
  );
};
