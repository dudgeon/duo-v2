import {AbsoluteFill, Audio, interpolate, Sequence, staticFile, useCurrentFrame, useVideoConfig} from 'remotion';
import {cameraAt, smootherstep, type Key} from '../lib/camera';
import {DeskShot, type DeskLayout} from '../lib/Desk';
import {Wallpaper} from '../lib/Desk';
import tokens from '../../style/tokens.json';

type Line = {id: string; text: string; src: string; start: number; duration: number};
type Scene = {
  id: string; title: string; kind: 'desk' | 'card'; start: number; duration: number; lines: Line[];
  card?: {title: string; sub: string; standIn: boolean};
  capture?: {src: string; scale: number}; desk?: DeskLayout; camera?: Key[]; appear?: boolean;
};
export type FilmTimeline = {fps: number; duration: number; frames: number; fade: number; scenes: Scene[]};

const clamp = {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'} as const;

const Card = ({card}: {card: NonNullable<Scene['card']>}) => (
  <AbsoluteFill>
    <Wallpaper w={tokens.frame.width} h={tokens.frame.height} />
    <AbsoluteFill style={{justifyContent: 'center', alignItems: 'center', fontFamily: tokens.font.ui, color: '#FFFFFF',
      textShadow: '0 2px 24px rgba(0,0,0,0.25)', textAlign: 'center', padding: tokens.frame.safe}}>
      <div style={{fontSize: tokens.title.size, fontWeight: tokens.title.weight, letterSpacing: tokens.title.tracking}}>{card.title}</div>
      <div style={{fontSize: tokens.title.subSize, opacity: 0.85, marginTop: 16}}>{card.sub}</div>
      {card.standIn && (
        <div style={{position: 'absolute', top: tokens.frame.safe / 2, left: tokens.frame.safe / 2, fontSize: 24, fontWeight: 600,
          padding: '6px 14px', borderRadius: 8, background: 'rgba(0,0,0,0.35)', letterSpacing: 1}}>STAND-IN</div>
      )}
    </AbsoluteFill>
  </AbsoluteFill>
);

const SceneView = ({scene, fade}: {scene: Scene; fade: number}) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const t = frame / fps;
  const opacity = scene.start === 0 ? 1 : interpolate(t, [0, fade], [0, 1], clamp);
  const appear = scene.appear ? smootherstep(interpolate(t, [0.2, 1.0], [0, 1], clamp)) : 1;
  return (
    <AbsoluteFill style={{opacity}}>
      {scene.kind === 'card' && scene.card && <Card card={scene.card} />}
      {scene.kind === 'desk' && scene.capture && scene.desk && scene.camera && (
        <DeskShot src={scene.capture.src} layout={scene.desk} scale={scene.capture.scale} camera={cameraAt(scene.camera, t)} appear={appear} />
      )}
      {scene.lines.map((l) => (
        <Sequence key={l.id} from={Math.round(l.start * fps)} durationInFrames={Math.ceil((l.duration + 0.1) * fps)}>
          <Audio src={staticFile(l.src)} />
        </Sequence>
      ))}
    </AbsoluteFill>
  );
};

export const Film = ({timeline}: {timeline: FilmTimeline | null}) => {
  if (!timeline) return null;
  const {fps, fade} = timeline;
  return (
    <AbsoluteFill style={{background: tokens.desk.wallpaper.base}}>
      {timeline.scenes.map((s, i) => {
        const last = i === timeline.scenes.length - 1;
        // Each scene runs `fade` past its end so the next one dissolves in over it.
        return (
          <Sequence key={s.id} name={s.id} from={Math.round(s.start * fps)} durationInFrames={Math.ceil((s.duration + (last ? 0 : fade)) * fps)}>
            <SceneView scene={s} fade={fade} />
          </Sequence>
        );
      })}
    </AbsoluteFill>
  );
};
