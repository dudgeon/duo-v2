import {AbsoluteFill, Img, interpolate, staticFile} from 'remotion';
import {smootherstep, type Rect} from './camera';
import tokens from '../../style/tokens.json';

// On-screen callouts that point at a feature as the voice names it (Geoff, 2026-10-10). Each one
// targets an anchor, resolved by the planner to a rect in desk points, so it follows the real UI.

export type CalloutSpec = {rect: Rect; label: string; start: number; end: number; side?: 'above' | 'below' | 'left' | 'right'};
export type CalloutStyle = 'spotlight' | 'ring' | 'lift';
const c = tokens.callout;
const clamp = {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'} as const;

/** Where a desk rect lands on screen, for the camera at this frame. */
const toScreen = (r: Rect, cam: Rect) => {
  const k = tokens.frame.width / cam.w;
  return {x: (r.x - cam.x) * k, y: (r.y - cam.y) * k, w: r.w * k, h: r.h * k, k};
};

const Label = ({text, box, side, u}: {text: string; box: {x: number; y: number; w: number; h: number}; side: string; u: number}) => {
  const gap = c.labelGap;
  const pos: React.CSSProperties = side === 'above' ? {left: box.x, top: box.y - gap, transform: 'translateY(-100%)'}
    : side === 'left' ? {left: box.x - gap, top: box.y + box.h / 2, transform: 'translate(-100%, -50%)'}
    : side === 'right' ? {left: box.x + box.w + gap, top: box.y + box.h / 2, transform: 'translateY(-50%)'}
    : {left: box.x, top: box.y + box.h + gap};
  return (
    <div style={{position: 'absolute', ...pos, opacity: u, fontFamily: tokens.font.ui}}>
      <div style={{transform: `translateY(${(1 - u) * 10}px)`, display: 'inline-flex', alignItems: 'center', gap: 10, whiteSpace: 'nowrap',
        padding: '10px 18px', borderRadius: 999, background: c.labelFill, color: c.labelText, fontSize: c.labelSize, fontWeight: 600,
        boxShadow: '0 8px 24px rgba(0,0,0,0.28)'}}>
        <span style={{width: 10, height: 10, borderRadius: 5, background: c.accent}} />{text}
      </div>
    </div>
  );
};

export const Callouts = ({items, cam, t, style, capture}: {items: CalloutSpec[]; cam: Rect; t: number; style: CalloutStyle;
  capture?: {src: string; scale: number; winX: number; winY: number}}) => (
  <AbsoluteFill style={{pointerEvents: 'none'}}>
    {items.map((it, i) => {
      const u = smootherstep(interpolate(t, [it.start, it.start + c.in, it.end - c.out, it.end], [0, 1, 1, 0], clamp));
      if (u <= 0) return null;
      const pad = c.pad;
      const s = toScreen({x: it.rect.x - pad, y: it.rect.y - pad, w: it.rect.w + 2 * pad, h: it.rect.h + 2 * pad}, cam);
      const r = c.radius * s.k;
      const side = it.side ?? 'below';
      if (style === 'spotlight') {
        return (
          <AbsoluteFill key={i}>
            <div style={{position: 'absolute', left: s.x, top: s.y, width: s.w, height: s.h, borderRadius: r,
              boxShadow: `0 0 0 9999px rgba(10,12,16,${c.scrim * u})`}} />
            <Label text={it.label} box={s} side={side} u={u} />
          </AbsoluteFill>
        );
      }
      if (style === 'ring') {
        const grow = 1 + (1 - u) * 0.06;
        return (
          <AbsoluteFill key={i}>
            <div style={{position: 'absolute', left: s.x, top: s.y, width: s.w, height: s.h, borderRadius: r, opacity: u,
              transform: `scale(${grow})`, border: `${c.ringWidth}px solid ${c.accent}`, boxShadow: `0 0 0 6px ${c.accent}33, 0 0 28px ${c.accent}88`}} />
            <Label text={it.label} box={s} side={side} u={u} />
          </AbsoluteFill>
        );
      }
      // lift: the feature's own pixels, raised off the screen with a shadow, the rest dimmed
      if (!capture) return null;
      const lift = 1 + c.lift * u;
      const src = it.rect;
      const k = s.k;
      const cx = s.x + s.w / 2, cy = s.y + s.h / 2;
      return (
        <AbsoluteFill key={i}>
          <AbsoluteFill style={{background: `rgba(10,12,16,${c.scrim * 0.7 * u})`}} />
          <div style={{position: 'absolute', left: cx - (src.w * k * lift) / 2, top: cy - (src.h * k * lift) / 2, width: src.w * k * lift, height: src.h * k * lift,
            overflow: 'hidden', borderRadius: c.radius * k * lift, boxShadow: `0 ${24 * u}px ${60 * u}px rgba(0,0,0,${0.45 * u})`}}>
            <Img src={staticFile(capture.src)} style={{position: 'absolute', transformOrigin: '0 0',
              left: -(src.x - capture.winX) * k * lift, top: -(src.y - capture.winY) * k * lift,
              transform: `scale(${(k * lift) / capture.scale})`}} />
          </div>
          <Label text={it.label} box={{x: cx - (src.w * k * lift) / 2, y: cy - (src.h * k * lift) / 2, w: src.w * k * lift, h: src.h * k * lift}} side={side} u={u} />
        </AbsoluteFill>
      );
    })}
  </AbsoluteFill>
);
