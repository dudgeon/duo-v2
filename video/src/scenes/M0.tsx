import {AbsoluteFill, Audio, Img, interpolate, staticFile, useCurrentFrame, useVideoConfig} from 'remotion';
import {cameraAt, type Key} from '../lib/camera';
import tokens from '../../style/tokens.json';

export type Timeline = {
  duration: number;
  title: {text: string; sub: string; until: number};
  capture: {src: string; widthPt: number; heightPt: number; scale: number};
  camera: Key[];
  voice: {src: string; start: number; duration: number};
};

const c = tokens.color.light;

export const M0 = ({timeline}: {timeline: Timeline | null}) => {
  const frame = useCurrentFrame();
  const {fps, width, height} = useVideoConfig();
  if (!timeline) return null;
  const t = frame / fps;
  const {capture, title} = timeline;

  // Camera: fit the current rect to the frame. The image is drawn at its own pixel size and scaled once.
  const r = cameraAt(timeline.camera, t);
  const k = width / r.w; // output px per point
  const px = k / capture.scale; // output px per capture px
  const titleOut = interpolate(t, [title.until - 0.4, title.until], [1, 0], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'});
  const shotIn = interpolate(t, [title.until - 0.4, title.until], [0, 1], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'});

  return (
    <AbsoluteFill style={{background: c.ground}}>
      <AbsoluteFill style={{opacity: shotIn, overflow: 'hidden'}}>
        <Img
          src={staticFile(capture.src)}
          style={{
            position: 'absolute',
            left: 0,
            top: 0,
            width: capture.widthPt * capture.scale,
            height: capture.heightPt * capture.scale,
            transformOrigin: '0 0',
            transform: `translate(${-r.x * k}px, ${-r.y * k}px) scale(${px})`,
            imageRendering: 'auto',
          }}
        />
      </AbsoluteFill>
      <AbsoluteFill
        style={{
          opacity: titleOut,
          justifyContent: 'center',
          alignItems: 'center',
          fontFamily: tokens.font.ui,
          color: c.text,
        }}
      >
        <div style={{fontSize: 120, fontWeight: 600, letterSpacing: -2}}>{title.text}</div>
        <div style={{fontSize: 40, color: c.text2, marginTop: 16}}>{title.sub}</div>
      </AbsoluteFill>
      <Audio src={staticFile(timeline.voice.src)} startFrom={0} volume={1} />
    </AbsoluteFill>
  );
};
