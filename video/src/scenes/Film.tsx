import {AbsoluteFill, Audio, interpolate, Sequence, staticFile, useCurrentFrame, useVideoConfig} from 'remotion';
import {cameraAt, smootherstep, type Key} from '../lib/camera';
import {DeskShot, type DeskLayout} from '../lib/Desk';
import {Wallpaper} from '../lib/Desk';
import tokens from '../../style/tokens.json';
import {DeskScene, ManyDesksScene, type ClutterEvents} from '../lib/Clutter';
import {Annotations, ChapterMark, type Annotation} from '../lib/Annotate';
import {TurnScene} from './Turn';
import type {Ground} from '../lib/Desk';

type Line = {id: string; text: string; src: string; start: number; duration: number};
type Scene = {
  id: string; title: string; kind: 'desk' | 'card' | 'drawn'; start: number; duration: number; lines: Line[];
  card?: {title: string; sub: string; standIn: boolean};
  capture?: {src: string; scale: number}; desk?: DeskLayout; camera?: Key[]; appear?: boolean;
  drawn?: {scene: 'desk' | 'many' | 'turn'; events: ClutterEvents};
  callouts?: Annotation[]; ground?: Ground; chapter?: boolean;
  turn?: {headline: [string, string]; projects: string[]; shots: string[]};
};
export type FilmTimeline = {fps: number; duration: number; frames: number; fade: number; scenes: Scene[]; calloutStyle?: string};

const clamp = {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'} as const;

const Card = ({card}: {card: NonNullable<Scene['card']>}) => (
  <AbsoluteFill>
    <Wallpaper w={tokens.frame.width} h={tokens.frame.height} />
    <AbsoluteFill style={{background: 'linear-gradient(90deg, rgba(10,14,20,0.55), rgba(10,14,20,0) 62%)'}} />
    <div style={{position: 'absolute', left: tokens.frame.safe + 32, top: 380, color: '#FFFFFF', fontFamily: tokens.font.ui}}>
      <div style={{fontSize: 120, fontWeight: 600, letterSpacing: -3, lineHeight: 1.04}}>{card.title}</div>
      <div style={{fontSize: 44, fontWeight: 500, letterSpacing: -0.5, opacity: 0.88, marginTop: 14}}>{card.sub.split(' · ')[0]}</div>
      <div style={{fontFamily: tokens.font.mono, fontSize: 24, opacity: 0.8, marginTop: 36, lineHeight: 1.7}}>
        {card.sub.split(' · ').slice(1).map((l) => <div key={l}>{l}</div>)}
      </div>
    </div>
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
      {scene.kind === 'drawn' && scene.drawn?.scene === 'desk' && <DeskScene t={t} ev={scene.drawn.events} />}
      {scene.kind === 'drawn' && scene.drawn?.scene === 'many' && <ManyDesksScene t={t} ev={scene.drawn.events} />}
      {scene.kind === 'drawn' && scene.drawn?.scene === 'turn' && scene.turn && <TurnScene t={t} ev={scene.drawn.events} {...scene.turn} />}
      {scene.kind === 'desk' && scene.capture && scene.desk && scene.camera && (
        <DeskShot src={scene.capture.src} layout={scene.desk} scale={scene.capture.scale} camera={cameraAt(scene.camera, t)} appear={appear} ground={scene.ground} />
      )}
      {scene.kind === 'desk' && scene.callouts?.length && scene.camera && scene.desk && scene.capture ? (
        <Annotations items={scene.callouts} cam={cameraAt(scene.camera, t)} t={t}
          capture={{src: scene.capture.src, scale: scene.capture.scale, winX: scene.desk.winX, winY: scene.desk.winY}} />
      ) : null}
      {scene.chapter && <ChapterMark id={scene.id} title={scene.title} t={t} />}
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
