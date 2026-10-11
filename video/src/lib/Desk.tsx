import {AbsoluteFill, Img, staticFile} from 'remotion';
import tokens from '../../style/tokens.json';
import {PaperGround} from './Paper';

// A Mac desktop: our own wallpaper look-alike (never Apple's image), with Duo's window on it.
// Everything is laid out in desk points and drawn at `scale` px per point, then scaled down once by
// the camera, so a landed 1:1 frame is the capture's own pixels (F-276).

const d = tokens.desk;

export type DeskLayout = {deskW: number; deskH: number; winX: number; winY: number; winW: number; winH: number};

export const deskLayout = (winW: number, winH: number, aspect: number): DeskLayout => {
  const deskW = Math.round(winW / d.windowWidthShare);
  const deskH = Math.round(deskW / aspect);
  return {deskW, deskH, winX: (deskW - winW) / 2, winY: (deskH - winH) / 2, winW, winH};
};

export const WallpaperSvg = ({w, h}: {w: number; h: number}) => {
  const wp = d.wallpaper;
  const blur = wp.blur * Math.max(w, h);
  return (
    <svg width={w} height={h} viewBox={`0 0 ${w} ${h}`} style={{position: 'absolute', left: 0, top: 0}}>
      <defs>
        <filter id="wpblur" x="-20%" y="-20%" width="140%" height="140%">
          <feGaussianBlur stdDeviation={blur} />
        </filter>
        {wp.stops.map((s, i) => (
          <radialGradient key={i} id={`wp${i}`}>
            <stop offset="0%" stopColor={s.color} stopOpacity={0.95} />
            <stop offset="100%" stopColor={s.color} stopOpacity={0} />
          </radialGradient>
        ))}
      </defs>
      <rect width={w} height={h} fill={wp.base} />
      <g filter="url(#wpblur)">
        {wp.stops.map((s, i) => (
          <ellipse key={i} cx={s.x * w} cy={s.y * h} rx={s.r * w} ry={s.r * h * 0.8} fill={`url(#wp${i})`} />
        ))}
      </g>
    </svg>
  );
};

/** The wallpaper as drawn: a PNG rendered once from WallpaperSvg by the build (it's slow to blur per frame). */
export const Wallpaper = ({w, h}: {w: number; h: number}) => (
  <Img src={staticFile('wallpaper.png')} style={{position: 'absolute', left: 0, top: 0, width: w, height: h}} />
);

/** The desk at `scale` px per point. Place it with a transform; don't scale it up. */
export type Ground = 'wallpaper' | 'paper';

export const Desk = ({src, layout, scale, appear = 1, ground = 'wallpaper'}: {src: string; layout: DeskLayout; scale: number; appear?: number; ground?: Ground}) => {
  const {deskW, deskH, winX, winY, winW, winH} = layout;
  const pt = (v: number) => v * scale;
  const tl = d.trafficLights;
  return (
    <div style={{position: 'absolute', left: 0, top: 0, width: pt(deskW), height: pt(deskH)}}>
      {ground === 'wallpaper' && <Wallpaper w={pt(deskW)} h={pt(deskH)} />}
      <div
        style={{
          position: 'absolute', left: pt(winX), top: pt(winY), width: pt(winW), height: pt(winH),
          borderRadius: pt(d.windowRadius), overflow: 'hidden',
          boxShadow: (ground === 'paper' ? d.paperShadow : d.shadow).replace(/([\d.]+)pt/g, (_, n) => `${pt(+n)}px`),
          opacity: appear, transform: `scale(${0.96 + 0.04 * appear})`, transformOrigin: '50% 50%',
        }}
      >
        <Img src={staticFile(src)} style={{width: pt(winW), height: pt(winH), display: 'block'}} />
        {/* A background capture is never the key window, so its lights draw grey; paint the active ones. */}
        {tl.centersX.map((cx, i) => (
          <div
            key={i}
            style={{
              position: 'absolute', left: pt(cx - tl.diameter / 2), top: pt(tl.centerY - tl.diameter / 2),
              width: pt(tl.diameter), height: pt(tl.diameter), borderRadius: '50%',
              background: tl.colors[i], boxShadow: `inset 0 0 0 ${pt(0.5)}px ${tl.ring}`,
            }}
          />
        ))}
      </div>
    </div>
  );
};

export const DeskShot = ({src, layout, scale, camera, appear = 1, ground = 'wallpaper'}: {src: string; layout: DeskLayout; scale: number; camera: {x: number; y: number; w: number}; appear?: number; ground?: Ground}) => (
  <AbsoluteFill style={{overflow: 'hidden', background: d.wallpaper.base}}>
    {/* Paper is drawn in screen space so its grid stays one crisp pixel at every zoom. */}
    {ground === 'paper' && <PaperGround />}
    <CameraOver camera={camera} scale={scale}>
      <Desk src={src} layout={layout} scale={scale} appear={appear} ground={ground} />
    </CameraOver>
  </AbsoluteFill>
);

const CameraOver = ({camera, scale, children}: {camera: {x: number; y: number; w: number}; scale: number; children: React.ReactNode}) => {
  // Output px per point = frame width / camera width; the desk is drawn at `scale` px per point.
  const k = tokens.frame.width / camera.w;
  return (
    <div style={{position: 'absolute', left: 0, top: 0, transformOrigin: '0 0',
      transform: `translate(${-camera.x * k}px, ${-camera.y * k}px) scale(${k / scale})`}}>
      {children}
    </div>
  );
};
