import React from 'react';
import {AbsoluteFill, Img, interpolate, staticFile} from 'remotion';
import {smootherstep, type Rect} from '../lib/camera';
import {Wallpaper} from '../lib/Desk';
import {Dock, MenuBar} from '../lib/Clutter';
import {Caption, Cursor, Marker} from '../lib/Paper';
import tokens from '../../style/tokens.json';

// S3 onward: the real Duo window on the desk, played as a run of captures of the app (one per state),
// with the cursor clicking what changes it, the camera pushing in on what the narrator names, and
// markers on it. Every pixel of the window is a capture; only the cursor, the camera, the markers and
// (where macOS draws a menu outside the window) a context menu are added. The planner (plan.mjs, kind
// drawn/app) resolves every time from the voice and every rect from the capture's anchors, in window points.

export type AppStep = {at: number; state: string};
export type AppClick = {at: number; x: number; y: number; right?: boolean};
export type AppDrag = {at: number; dur: number; from: {x: number; y: number}; to: {x: number; y: number}; reveal?: {state: string; rect: Rect}};
export type AppCam = {at: number; dur: number; rect: Rect | null};       // null: back to the whole desk
export type AppMark = {at: number; until: number; rect: Rect; quote?: string};
export type AppMenu = {at: number; until: number; x: number; y: number; items: string[]; hi?: {at: number; item: string}};
export type AppData = {
  window: {w: number; h: number}; scale: number; src: Record<string, string>;
  // The scene's first picture when it continues from another (S2's composite of panes): a base capture
  // with some panes drawn from others, shown until `until`.
  entry?: {base: string; panes: Record<string, string>; until: number; rects?: Record<string, Rect>};
  panes: Record<string, Rect>;
  steps: AppStep[]; clicks: AppClick[]; drags: AppDrag[]; cams: AppCam[]; marks: AppMark[]; menus: AppMenu[];
  running?: boolean; startCam?: Rect | null;
};

const W = tokens.frame.width, H = tokens.frame.height;
const K = 0.855;   // px per window point: the same placement as S2's morph, so scenes hand over exactly
const clamp = {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'} as const;
const ramp = (t: number, a: number, b: number) => smootherstep(interpolate(t, [a, b], [0, 1], clamp));
const lerp = (a: number, b: number, u: number) => a + (b - a) * u;
const lerpRect = (a: Rect, b: Rect, u: number): Rect => ({x: lerp(a.x, b.x, u), y: lerp(a.y, b.y, u), w: lerp(a.w, b.w, u), h: lerp(a.h, b.h, u)});

const Crop = ({src, scale, region, rect}: {src: string; scale: number; region: Rect; rect: Rect}) => {
  const k = rect.w / region.w;
  return (
    <div style={{position: 'absolute', left: rect.x, top: rect.y, width: rect.w, height: rect.h, overflow: 'hidden'}}>
      <Img src={staticFile(src)} style={{position: 'absolute', left: -region.x * k, top: -region.y * k, transformOrigin: '0 0', transform: `scale(${k / scale})`, maxWidth: 'none'}} />
    </div>
  );
};

/** A macOS context menu, drawn where the click was: macOS draws menus in their own window, which a window capture can't include. Its items are the app's real ones. */
const ContextMenu = ({x, y, items, hi, u}: {x: number; y: number; items: string[]; hi?: string; u: number}) => (
  <div style={{position: 'absolute', left: x, top: y, minWidth: 230, padding: '5px 5px', borderRadius: 10, background: 'rgba(246,246,248,0.97)',
    boxShadow: '0 10px 30px rgba(0,0,0,0.28), 0 0 0 0.5px rgba(0,0,0,0.25)', fontFamily: tokens.font.ui, fontSize: 13.5, color: '#1d1d1f',
    opacity: u, transform: `scale(${0.97 + 0.03 * u})`, transformOrigin: '0 0'}}>
    {items.map((it, i) => it === '-' ? <div key={i} style={{height: 1, background: 'rgba(0,0,0,0.12)', margin: '5px 8px'}} /> : (
      <div key={i} style={{height: 22, lineHeight: '22px', padding: '0 12px', borderRadius: 5, display: 'flex', justifyContent: 'space-between',
        background: it === hi ? '#2F6FEB' : 'none', color: it === hi ? '#fff' : it === 'Send to Claude' ? 'rgba(0,0,0,0.3)' : undefined}}>
        <span>{it.replace(' ▸', '')}</span>{it.endsWith(' ▸') && <span style={{opacity: 0.6}}>›</span>}</div>
    ))}
  </div>
);

export const AppScene = ({t, data}: {t: number; data: AppData}) => {
  const win = {x: (W - data.window.w * K) / 2, y: 38, w: data.window.w * K, h: data.window.h * K};
  const toFrame = (r: Rect): Rect => ({x: win.x + r.x * K, y: win.y + r.y * K, w: r.w * K, h: r.h * K});

  // Which capture is on screen: the last step at or before now.
  let state = data.steps[0].state;
  for (const s of data.steps) if (t >= s.at) state = s.state;
  const inEntry = data.entry && t < data.entry.until;

  // Camera: frame rects, eased between keys. A focus rect is fitted to the frame's aspect around its centre.
  const wide: Rect = {x: 0, y: 0, w: W, h: H};
  const fit = (r: Rect | null): Rect => {
    if (!r) return wide;
    const f = toFrame(r);
    let w = Math.max(f.w * 1.12, f.h * 1.12 * W / H), h = w * H / W;
    w = Math.min(w, W); h = Math.min(h, H);
    const x = Math.min(Math.max(f.x + f.w / 2 - w / 2, 0), W - w), y = Math.min(Math.max(f.y + f.h / 2 - h / 2, 0), H - h);
    return {x, y, w, h};
  };
  let cam = fit(data.startCam ?? null);
  let prev = cam;
  for (const c of data.cams) {
    const to = fit(c.rect);
    if (t >= c.at) { cam = to; prev = to; continue; }
    if (t > c.at - c.dur) cam = lerpRect(prev, to, smootherstep((t - (c.at - c.dur)) / c.dur));
    break;
  }
  const cs = W / cam.w;
  const screen = (r: Rect): Rect => ({x: (r.x - cam.x) * cs, y: (r.y - cam.y) * cs, w: r.w * cs, h: r.h * cs});
  const pt = (p: {x: number; y: number}) => { const s = screen(toFrame({x: p.x, y: p.y, w: 0, h: 0})); return {x: s.x, y: s.y}; };

  // The cursor's path: every click and both ends of every drag, in time order.
  type Way = {at: number; x: number; y: number; press: boolean; hold?: number};
  const ways: Way[] = [
    ...data.clicks.map((c) => ({at: c.at, x: c.x, y: c.y, press: true})),
    ...data.drags.flatMap((d) => [{at: d.at, x: d.from.x, y: d.from.y, press: false, hold: d.dur}, {at: d.at + d.dur, x: d.to.x, y: d.to.y, press: false}]),
  ].sort((a, b) => a.at - b.at);
  let cursor: React.ReactNode = null;
  if (ways.length && t > ways[0].at - 1.0 && t < ways[ways.length - 1].at + 1.0) {
    let i = ways.findIndex((w) => w.at > t);
    if (i < 0) i = ways.length;
    const last = ways[Math.max(0, i - 1)], next = ways[Math.min(i, ways.length - 1)];
    const a = i === 0 ? {x: next.x + 160, y: next.y + 120} : last, b = i < ways.length ? next : last;
    const from = pt(a), to = pt(b);
    const t0 = i === 0 ? ways[0].at - 1.0 : last.at, t1 = i < ways.length ? next.at : t0 + 0.01;
    // A drag moves straight and steadily; otherwise the cursor glides in an arc and settles before it clicks.
    const dragging = i > 0 && last.hold !== undefined;
    const m = dragging ? interpolate(t, [t0, t1], [0, 1], clamp) : i < ways.length ? ramp(t, Math.max(t0 + 0.12, t1 - 0.6), t1 - 0.04) : 1;
    const press = data.clicks.reduce((p, c) => Math.max(p, interpolate(t - c.at, [-0.04, 0.04, 0.14], [0, 1, 0], clamp)), dragging ? 1 : 0);
    const op = ramp(t, ways[0].at - 1.0, ways[0].at - 0.8) * (1 - ramp(t, ways[ways.length - 1].at + 0.6, ways[ways.length - 1].at + 1.0));
    cursor = <div style={{opacity: op}}><Cursor x={lerp(from.x, to.x, m)} y={lerp(from.y, to.y, m) - (dragging ? 0 : Math.sin(m * Math.PI) * 26)} press={press} /></div>;
  }

  return (
    <AbsoluteFill style={{overflow: 'hidden', background: '#000'}}>
      <div style={{position: 'absolute', left: 0, top: 0, width: W, height: H, transformOrigin: '0 0', transform: `scale(${cs}) translate(${-cam.x}px, ${-cam.y}px)`}}>
        <Wallpaper w={W} h={H} />
        <MenuBar app="Duo" />
        <Dock running={data.running ?? true} />
        <div style={{position: 'absolute', left: win.x, top: win.y, width: win.w, height: win.h, borderRadius: 12, overflow: 'hidden',
          boxShadow: '0 30px 80px rgba(0,0,0,0.42), 0 0 0 0.5px rgba(0,0,0,0.4)'}}>
          {inEntry ? (
            <>
              <Crop src={data.src[data.entry!.base]} scale={data.scale} region={{x: 0, y: 0, w: data.window.w, h: data.window.h}} rect={{x: 0, y: 0, w: win.w, h: win.h}} />
              {Object.entries(data.entry!.panes).map(([p, st]) => {
                const r = data.entry!.rects?.[p] ?? data.panes[p];
                return <Crop key={p} src={data.src[st]} scale={data.scale} region={r} rect={{x: r.x * K, y: r.y * K, w: r.w * K, h: r.h * K}} />;
              })}
            </>
          ) : <Crop src={data.src[state]} scale={data.scale} region={{x: 0, y: 0, w: data.window.w, h: data.window.h}} rect={{x: 0, y: 0, w: win.w, h: win.h}} />}
          {/* A drag's selection grows under the cursor: the selected capture, from the drag's start to the cursor. */}
          {data.drags.map((d, i) => {
            if (!d.reveal || t < d.at || t > d.at + d.dur + 0.1) return null;
            const x1 = lerp(d.from.x, d.to.x, interpolate(t, [d.at, d.at + d.dur], [0, 1], clamp));
            const r = d.reveal.rect, x0 = Math.min(d.from.x, x1), w = Math.abs(x1 - d.from.x);
            if (w < 0.5) return null;
            const region = {x: x0, y: r.y, w, h: r.h};
            return <Crop key={`rv${i}`} src={data.src[d.reveal.state]} scale={data.scale} region={region} rect={{x: x0 * K, y: r.y * K, w: w * K, h: r.h * K}} />;
          })}
        </div>
        {data.menus.map((mn, i) => {
          if (t < mn.at || t > mn.until) return null;
          const p = toFrame({x: mn.x, y: mn.y, w: 0, h: 0});
          return <ContextMenu key={i} x={p.x + 2} y={p.y + 2} items={mn.items} hi={mn.hi && t >= mn.hi.at ? mn.hi.item : undefined} u={ramp(t, mn.at, mn.at + 0.08)} />;
        })}
      </div>
      <AbsoluteFill style={{pointerEvents: 'none'}}>
        {data.marks.map((mk, i) => {
          if (t < mk.at || t > mk.until) return null;
          const r = screen(toFrame(mk.rect));
          const leave = ramp(t, mk.until - 0.2, mk.until);
          const u = ramp(t, mk.at + 0.05, mk.at + 0.5) * (1 - leave);
          return (
            <AbsoluteFill key={i}>
              <Marker cx={r.x + r.w / 2} cy={r.y + r.h / 2} rx={r.w / 2 + 18} ry={r.h / 2 + 14} progress={u} />
              {mk.quote && <Caption text={mk.quote} u={ramp(t, mk.at + 0.3, mk.at + 0.6) * (1 - leave)} />}
            </AbsoluteFill>
          );
        })}
        {cursor}
      </AbsoluteFill>
    </AbsoluteFill>
  );
};
