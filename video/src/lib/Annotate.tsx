import {AbsoluteFill, interpolate} from 'remotion';
import {smootherstep, type Rect} from './camera';
import {Cursor, Marker, MiniWindow, Panel, Quote, ramp} from './Paper';
import tokens from '../../style/tokens.json';

// The callout language from style/reference-analysis.md: the cursor travels to the feature and
// clicks, a marker draws itself around it, and a mono-titled window snaps open beside it with the
// feature's own pixels and the narrator's words quoted above. All in screen space, from the camera.

export type Annotation = {
  rect: Rect;              // the feature, in desk points
  crop?: Rect;             // what the mini window shows, in window points (default: the feature, padded)
  title: string;           // the mini window's mono title
  quote?: string;          // the spoken words, quoted small
  start: number;           // the click lands here (seconds into the scene)
  end: number;
};

const W = tokens.frame.width, H = tokens.frame.height, SAFE = tokens.frame.safe;
const clamp = {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'} as const;

const toScreen = (r: Rect, cam: Rect) => {
  const k = W / cam.w;
  return {x: (r.x - cam.x) * k, y: (r.y - cam.y) * k, w: r.w * k, h: r.h * k};
};

export const Annotations = ({items, cam, t, capture}: {items: Annotation[]; cam: Rect; t: number;
  capture: {src: string; scale: number; winX: number; winY: number}}) => {
  // Where the cursor rests between callouts: it leaves the last one it clicked.
  return (
    <AbsoluteFill style={{pointerEvents: 'none'}}>
      {items.map((a, i) => {
        if (t < a.start - 1.0 || t > a.end + 0.2) return null;
        const r = toScreen(a.rect, cam);
        const cx = r.x + r.w / 2, cy = r.y + r.h / 2;
        // Cursor: from the previous callout (or lower right) to the feature's centre-right, then a click.
        const prev = items[i - 1];
        const from = prev ? (() => { const p = toScreen(prev.rect, cam); return {x: p.x + p.w * 0.6, y: p.y + p.h * 0.6}; })() : {x: W * 0.62, y: H * 0.86};
        const to = {x: cx + Math.min(r.w * 0.3, 60), y: cy + 4};
        const m = ramp(t, a.start - 0.95, a.start - 0.05);
        const press = interpolate(t, [a.start - 0.05, a.start + 0.03, a.start + 0.14], [0, 1, 0], clamp);
        const leave = ramp(t, a.end - 0.15, a.end);
        // Marker draws just after the click.
        const marker = ramp(t, a.start + 0.05, a.start + 0.5) * (1 - leave);
        // Mini window: snaps open after the marker, beside the feature, on whichever side has room.
        const crop = a.crop ?? {x: a.rect.x - capture.winX - 16, y: a.rect.y - capture.winY - 12, w: a.rect.w + 32, h: a.rect.h + 24};
        // The window enlarges the feature: 1.35x what the camera shows, up to 780 px wide.
        const camK = W / cam.w;
        const mk = Math.min(780 / crop.w, Math.max(camK * tokens.callout.enlarge, 360 / crop.w));
        const mw = crop.w * mk;
        const mh = 40 + crop.h * mk;
        const right = r.x + r.w + 70 + mw < W - SAFE * 0.5;
        const wx = right ? r.x + r.w + 70 : Math.max(SAFE * 0.5, r.x - 70 - mw);
        const wy = Math.min(Math.max(SAFE, cy - mh * 0.35), H - SAFE * 0.6 - mh);
        const open = ramp(t, a.start + 0.42, a.start + 0.56) * (1 - leave);
        const quoteU = ramp(t, a.start + 0.5, a.start + 0.8) * (1 - leave);
        return (
          <AbsoluteFill key={i}>
            <Marker cx={cx} cy={cy} rx={r.w / 2 + 20} ry={r.h / 2 + 15} progress={marker} />
            {a.quote && <Quote text={a.quote} x={wx} y={wy - 42} u={quoteU} />}
            <MiniWindow x={wx} y={wy} w={mw} title={a.title} open={open}>
              <Panel src={capture.src} scale={capture.scale} region={crop} x={0} y={0} k={mk}
                style={{position: 'relative', borderRadius: 0, boxShadow: 'none'}} />
            </MiniWindow>
            {t <= a.end && <Cursor x={from.x + (to.x - from.x) * m} y={from.y + (to.y - from.y) * m - Math.sin(m * Math.PI) * 40} press={press} />}
          </AbsoluteFill>
        );
      })}
    </AbsoluteFill>
  );
};

/** A chapter mark, top left, in screen space: `04 · Every session, found`. */
export const ChapterMark = ({id, title, t}: {id: string; title: string; t: number}) => {
  const n = id.replace(/^S/, '').padStart(2, '0');
  const u = smootherstep(interpolate(t, [0.15, 0.5], [0, 1], clamp));
  return (
    <div style={{position: 'absolute', left: SAFE, top: SAFE * 0.6, fontFamily: tokens.font.mono, fontSize: 22, letterSpacing: 1,
      color: tokens.paper.ink2, opacity: u}}>
      <span style={{color: tokens.paper.ink}}>{n}</span>  ·  {title}
    </div>
  );
};
