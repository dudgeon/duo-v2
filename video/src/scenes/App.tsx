import React from 'react';
import {AbsoluteFill, Img, interpolate, staticFile} from 'remotion';
import {smootherstep, type Rect} from '../lib/camera';
import {Wallpaper} from '../lib/Desk';
import {Dock, MenuBar} from '../lib/Clutter';
import {Caption, Cursor} from '../lib/Paper';
import tokens from '../../style/tokens.json';
import {Trace, traceProgress} from '../lib/Trace';

// S3 onward: the real Duo window on the desk, played as a run of captures of the app (one per state),
// with the cursor clicking what changes it, the camera pushing in on what the narrator names, and
// markers on it. Every pixel of the window is a capture; only the cursor, the camera, the markers and
// (where macOS draws a menu outside the window) a context menu are added. The planner (plan.mjs, kind
// drawn/app) resolves every time from the voice and every rect from the capture's anchors, in window points.

// fade: the new state dissolves in over this many seconds instead of cutting (an app motion, such as Claude's highlight).
export type AppStep = {at: number; state: string; fade?: number};
export type AppClick = {at: number; x: number; y: number; right?: boolean};
export type AppDrag = {at: number; dur: number; from: {x: number; y: number}; to: {x: number; y: number}; reveal?: {state: string; rect: Rect}};
export type AppCam = {at: number; dur: number; rect: Rect | null};       // null: back to the whole desk
export type AppMark = {at: number; until: number; rect: Rect; quote?: string};
export type AppKey = {at: number; label: string};
// A wipe: `state` drawn over the picture inside `rect`, left to right over dur (typing that renders as it's typed).
export type AppWipe = {at: number; dur: number; state: string; rect: Rect; chars?: number};
export type AppMenu = {at: number; until: number; x: number; y: number; items: string[]; hi?: {at: number; item: string}};
export type AppData = {
  window: {w: number; h: number}; scale: number; src: Record<string, string>;
  // The scene's first picture when it continues from another (S2's composite of panes): a base capture
  // with some panes drawn from others, shown until `until`.
  entry?: {base: string; panes: Record<string, string>; until: number; rects?: Record<string, Rect>};
  panes: Record<string, Rect>;
  steps: AppStep[]; clicks: AppClick[]; drags: AppDrag[]; cams: AppCam[]; marks: AppMark[]; menus: AppMenu[];
  keys?: AppKey[]; wipes?: AppWipe[];
  running?: boolean; startCam?: Rect | null;
};

const W = tokens.frame.width, H = tokens.frame.height;
const K = 0.855;   // px per window point: the same placement as S2's morph, so scenes hand over exactly
const clamp = {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'} as const;
const ramp = (t: number, a: number, b: number) => (b <= a ? (t >= a ? 1 : 0) : smootherstep(interpolate(t, [a, b], [0, 1], clamp)));
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

/** The macOS text cursor (I-beam), centred on (x, y). */
const IBeam = ({x, y}: {x: number; y: number}) => (
  <svg style={{position: 'absolute', left: x - 9, top: y - 20, overflow: 'visible'}} width={18} height={40} viewBox="0 0 18 40">
    <path d="M3 2 Q9 2 9 6 Q9 2 15 2 M9 6 V34 M3 38 Q9 38 9 34 Q9 38 15 38 M5 20 H13" fill="none" stroke="#fff" strokeWidth={5} strokeLinecap="round" />
    <path d="M3 2 Q9 2 9 6 Q9 2 15 2 M9 6 V34 M3 38 Q9 38 9 34 Q9 38 15 38 M5 20 H13" fill="none" stroke="#000" strokeWidth={2.2} strokeLinecap="round" />
  </svg>
);

/** A shortcut as it's pressed: keycaps low in the frame, centred (S7's ⌘B, ⌘K). */
const KeyCap = ({label, u, down}: {label: string; u: number; down: number}) => {
  const keys = label.split(/(?<=⌘|⇧|⌥|⌃)/);
  return (
    <div style={{position: 'absolute', left: 0, right: 0, bottom: 150, display: 'flex', justifyContent: 'center', gap: 14, opacity: u, transform: `translateY(${(1 - u) * 14}px)`}}>
      {keys.map((k, i) => (
        <div key={i} style={{minWidth: 92, height: 92, padding: '0 22px', borderRadius: 18, background: '#FFFFFF', display: 'flex', alignItems: 'center', justifyContent: 'center',
          fontFamily: tokens.font.ui, fontSize: 48, fontWeight: 600, color: '#1F2328',
          boxShadow: `0 ${8 - 6 * down}px 0 #C9CDD3, 0 ${18 - 8 * down}px 40px rgba(0,0,0,0.30), 0 0 0 1px rgba(31,35,40,0.18)`, transform: `translateY(${6 * down}px)`}}>{k}</div>
      ))}
    </div>
  );
};

export const AppScene = ({t, data}: {t: number; data: AppData}) => {
  const win = {x: (W - data.window.w * K) / 2, y: 38, w: data.window.w * K, h: data.window.h * K};
  const toFrame = (r: Rect): Rect => ({x: win.x + r.x * K, y: win.y + r.y * K, w: r.w * K, h: r.h * K});

  // Which capture is on screen: the last step at or before now.
  let state = data.steps[0].state, under: string | null = null, mix = 1;
  for (const s of data.steps) if (t >= s.at) {
    if (s.fade && t < s.at + s.fade && s.state !== state) { under = state; mix = (t - s.at) / s.fade; } else { under = null; mix = 1; }
    state = s.state;
  }
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
    // Two waypoints can sit a hair apart (a click right after a drag ends); the ease needs a real span.
    const ea = Math.max(t0 + 0.12, t1 - 0.6), eb = Math.max(ea + 0.01, t1 - 0.04);
    const m = dragging ? interpolate(t, [t0, Math.max(t1, t0 + 0.01)], [0, 1], clamp) : i < ways.length ? ramp(t, ea, eb) : 1;
    const press = data.clicks.reduce((p, c) => Math.max(p, interpolate(t - c.at, [-0.04, 0.04, 0.14], [0, 1, 0], clamp)), dragging ? 1 : 0);
    const op = ramp(t, ways[0].at - 1.0, ways[0].at - 0.8) * (1 - ramp(t, ways[ways.length - 1].at + 0.6, ways[ways.length - 1].at + 1.0));
    // Over text being selected the pointer is the macOS I-beam, as it is in the real editor and composer.
    const cx = lerp(from.x, to.x, m), cy = lerp(from.y, to.y, m) - (dragging ? 0 : Math.sin(m * Math.PI) * 26);
    const beam = dragging || (i < ways.length && next.hold !== undefined && t > next.at - 0.35);
    cursor = <div style={{opacity: op}}>{beam ? <IBeam x={cx} y={cy} /> : <Cursor x={cx} y={cy} press={press} />}</div>;
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
          ) : <>
            {under && <Crop src={data.src[under]} scale={data.scale} region={{x: 0, y: 0, w: data.window.w, h: data.window.h}} rect={{x: 0, y: 0, w: win.w, h: win.h}} />}
            <div style={{position: 'absolute', inset: 0, opacity: under ? 1 - Math.pow(1 - mix, 3) : 1}}>
              <Crop src={data.src[state]} scale={data.scale} region={{x: 0, y: 0, w: data.window.w, h: data.window.h}} rect={{x: 0, y: 0, w: win.w, h: win.h}} />
            </div>
          </>}
          {(data.wipes ?? []).map((w, i) => {
            if (t < w.at || t > w.at + w.dur + 0.1) return null;
            // `chars`: typing, not a wipe. The text arrives a character at a time, with the small uneven gaps of real
            // typing (a fixed pseudo-random spread, so every render is the same), finishing at w.at + w.dur.
            let u = interpolate(t, [w.at, w.at + w.dur], [0, 1], clamp);
            if (w.chars) {
              const n = w.chars, gaps = Array.from({length: n}, (_, i) => 0.6 + 0.8 * Math.abs(Math.sin(i * 12.9898) * 43758.5453 % 1));
              const total = gaps.reduce((a, b) => a + b, 0);
              let acc = 0, typed = 0;
              for (const g of gaps) { acc += g; if (w.at + (acc / total) * w.dur <= t) typed++; else break; }
              u = typed / n;
            }
            const ww = w.rect.w * u;
            if (ww < 0.5) return null;
            return <Crop key={`wp${i}`} src={data.src[w.state]} scale={data.scale} region={{...w.rect, w: ww}} rect={{x: w.rect.x * K, y: w.rect.y * K, w: ww * K, h: w.rect.h * K}} />;
          })}
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
              <Trace r={r} radius={8 * K * cs} p={traceProgress(t, mk.at + 0.05, mk.until)} />
              {mk.quote && <Caption text={mk.quote} u={ramp(t, mk.at + 0.3, mk.at + 0.6) * (1 - leave)} />}
            </AbsoluteFill>
          );
        })}
        {(data.keys ?? []).map((k, i) => {
          if (t < k.at - 0.05 || t > k.at + 1.1) return null;
          const u = ramp(t, k.at - 0.05, k.at + 0.1) * (1 - ramp(t, k.at + 0.85, k.at + 1.1));
          const down = interpolate(t - k.at, [0, 0.06, 0.18], [0, 1, 0], clamp);
          return <KeyCap key={`k${i}`} label={k.label} u={u} down={down} />;
        })}
        {cursor}
      </AbsoluteFill>
    </AbsoluteFill>
  );
};
