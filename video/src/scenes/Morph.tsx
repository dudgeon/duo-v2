import React from 'react';
import {AbsoluteFill, Img, interpolate, staticFile} from 'remotion';
import {smootherstep, type Rect} from '../lib/camera';
import {Wallpaper} from '../lib/Desk';
import {DOCK_DUO, Dock, MenuBar, PileWindow} from '../lib/Clutter';
import {CLUTTER_LAYOUT, clutterWin} from '../lib/clutterLayout';
import {Cursor, Marker, Caption} from '../lib/Paper';
import tokens from '../../style/tokens.json';

// S2: S1's pile morphs into one real Duo window (script v2, Geoff 2026-10-10). Each drawn window
// flies from its rect in clutterLayout.ts to where its job lives in Duo: Finder to the left pane, the
// terminals to the middle pane and its session tabs, the documents to the right pane and its editor
// tabs. Mid-flight each crossfades into the real capture of its destination, so it lands as the app.
// Then the camera visits each pane as the narrator names it, and the cursor clicks through the real tabs:
// every pane image is a capture of the app in that state (video/fixture/docs/states.json).

export type MorphEvents = Record<string, number>;
export type MorphData = {
  window: {w: number; h: number}; scale: number;
  src: Record<string, string>;            // state -> capture
  anchors: Record<string, Rect>;          // video.* id -> rect in window points (same in every state)
};

const W = tokens.frame.width, H = tokens.frame.height;
const clamp = {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'} as const;
const ramp = (t: number, a: number, b: number) => smootherstep(interpolate(t, [a, b], [0, 1], clamp));
const lerp = (a: number, b: number, u: number) => a + (b - a) * u;
const lerpRect = (a: Rect, b: Rect, u: number): Rect => ({x: lerp(a.x, b.x, u), y: lerp(a.y, b.y, u), w: lerp(a.w, b.w, u), h: lerp(a.h, b.h, u)});

// The settled Duo window, in frame px: the 1800 pt window at 0.855 px/pt, between the menu bar and the Dock.
const K = 0.855;
const BG = {left: '#ffffff', middle: '#15171b', right: '#ffffff'};

/** A region of a capture (window points) drawn into a frame rect, scaled by width and clipped. */
const Crop = ({src, scale, region, rect, opacity = 1, radius = 0}: {src: string; scale: number; region: Rect; rect: Rect; opacity?: number; radius?: number}) => {
  if (opacity <= 0) return null;
  const k = rect.w / region.w;
  return (
    <div style={{position: 'absolute', left: rect.x, top: rect.y, width: rect.w, height: rect.h, overflow: 'hidden', opacity, borderRadius: radius}}>
      <Img src={staticFile(src)} style={{position: 'absolute', left: -region.x * k, top: -region.y * k, transformOrigin: '0 0', transform: `scale(${k / scale})`, maxWidth: 'none'}} />
    </div>
  );
};

// Where each S1 window lands, and in which order. Lead windows fill a pane; the rest fold into tabs.
type Flight = {id: string; to: string; pane: 'left' | 'middle' | 'right'; at: number};
const FLIGHTS: Flight[] = [
  {id: 'finder', to: 'video.pane.left', pane: 'left', at: 0.0},
  {id: 'term1', to: 'video.pane.middle', pane: 'middle', at: 0.16},
  {id: 'term2', to: 'video.tab.middle.1', pane: 'middle', at: 0.3},
  {id: 'term3', to: 'video.tab.middle.2', pane: 'middle', at: 0.42},
  {id: 'markdown', to: 'video.pane.right', pane: 'right', at: 0.32},
  {id: 'browser', to: 'video.tab.right.2', pane: 'right', at: 0.46},
  {id: 'deck', to: 'video.tab.right.3', pane: 'right', at: 0.58},
  {id: 'doc', to: 'video.tab.right.4', pane: 'right', at: 0.7},
];
const FLY = 1.05;   // seconds per flight

export const MorphScene = ({t, ev, data}: {t: number; ev: MorphEvents; data: MorphData}) => {
  const A = data.anchors;
  const win = {x: (W - data.window.w * K) / 2, y: 38, w: data.window.w * K, h: data.window.h * K};
  const toFrame = (r: Rect): Rect => ({x: win.x + r.x * K, y: win.y + r.y * K, w: r.w * K, h: r.h * K});
  const m0 = ev.morph ?? 0.35;

  // Which capture each pane shows now: the cursor's clicks switch them.
  const middleState = t >= (ev.chat ?? 1e9) ? 'video-s2-chat' : t >= (ev.mid2 ?? 1e9) ? 'video-s2-middle-2' : t >= (ev.mid1 ?? 1e9) ? 'video-s2-middle-1' : 'video-s2-middle-0';
  const rightState = t >= (ev.right4 ?? 1e9) ? 'video-s2-right-4' : t >= (ev.right3 ?? 1e9) ? 'video-s2-right-3' : t >= (ev.right2 ?? 1e9) ? 'video-s2-right-2' : 'video-s2-right-1';
  const paneSrc = {left: data.src[rightState], middle: data.src[middleState], right: data.src[rightState]};

  // A pane shows its capture once its lead window has landed (they are the same pixels by then).
  const landed = (pane: Flight['pane']) => {
    const lead = FLIGHTS.find((f) => f.pane === pane && f.to.startsWith('video.pane'))!;
    return t >= m0 + lead.at + FLY;
  };
  const shell = ramp(t, m0 - 0.25, m0 + 0.2);

  // The way in (transition 'dock-launch', app navigation from S1): the camera pushes toward the Dock,
  // the cursor clicks Duo's tile, it bounces as it launches, the camera pulls back and the morph begins.
  const click = ev.launch;
  const bounceK = click === undefined ? -1 : (t - click - 0.05) / 0.6;
  const lift = bounceK > 0 && bounceK < 1 ? 26 * Math.abs(Math.sin(bounceK * 2 * Math.PI)) * (1 - 0.45 * bounceK) : 0;
  const running = click !== undefined && t >= click + 0.15;

  // Camera: wide on the window, then to each pane as it's named, then back. Rects in frame px.
  const wide: Rect = {x: 0, y: 0, w: W, h: H};
  const focus = (cx: number, viewW: number): Rect => {
    const w = viewW * K, h = w * H / W, fx = win.x + cx * K;
    return {x: Math.min(Math.max(fx - w / 2, 0), W - w), y: Math.max(win.y - 30, 0), w, h};
  };
  const keys: {t: number; r: Rect}[] = [{t: 0, r: wide}];
  const push = (at: number | undefined, r: Rect, dur = 0.9) => { if (at !== undefined) { const p = keys[keys.length - 1]; keys.push({t: Math.max(p.t, at - dur), r: p.r}, {t: at, r}); } };
  if (click !== undefined) {
    const z = 1.6, w = W / z, h = H / z;
    const dock: Rect = {x: Math.min(Math.max(DOCK_DUO.x + DOCK_DUO.w / 2 - w / 2, 0), W - w), y: H - h, w, h};
    push(click, dock, click);
    push(click + 0.35, dock, 0.35);
    push(m0 + 0.2, wide, m0 + 0.2 - (click + 0.35));
  }
  push(ev.pane, focus(470, 1080));
  push(ev.terminal, focus(760, 1180));
  push(ev.flexible, focus(1380, 1080));
  push(ev.wide, wide, 1.1);
  let cam = keys[0].r;
  for (let i = 1; i < keys.length; i++) {
    if (t >= keys[i].t) cam = keys[i].r;
    else { if (t > keys[i - 1].t) cam = lerpRect(keys[i - 1].r, keys[i].r, smootherstep((t - keys[i - 1].t) / (keys[i].t - keys[i - 1].t))); break; }
  }
  const cs = W / cam.w;
  const screen = (r: Rect): Rect => ({x: (r.x - cam.x) * cs, y: (r.y - cam.y) * cs, w: r.w * cs, h: r.h * cs});

  return (
    <AbsoluteFill style={{overflow: 'hidden', background: '#000'}}>
      <div style={{position: 'absolute', left: 0, top: 0, width: W, height: H, transformOrigin: '0 0', transform: `scale(${cs}) translate(${-cam.x}px, ${-cam.y}px)`}}>
        <Wallpaper w={W} h={H} />
        <MenuBar app={t >= m0 + 0.6 ? 'Duo' : 'Terminal'} />
        <Dock lift={lift} running={running} />
        {/* The Duo window: its frame and toolbar arrive first, the panes fill as their windows land. */}
        {shell > 0 && (
          <div style={{position: 'absolute', left: win.x, top: win.y, width: win.w, height: win.h, borderRadius: 12, overflow: 'hidden',
            opacity: shell, transform: `scale(${0.97 + 0.03 * shell})`, transformOrigin: '50% 50%',
            boxShadow: '0 30px 80px rgba(0,0,0,0.42), 0 0 0 0.5px rgba(0,0,0,0.4)'}}>
            {(['left', 'middle', 'right'] as const).map((p) => {
              const r = A[`video.pane.${p}`];
              return <div key={p} style={{position: 'absolute', left: r.x * K, top: r.y * K, width: r.w * K, height: r.h * K, background: BG[p]}} />;
            })}
            <Crop src={paneSrc.left} scale={data.scale} region={{x: 0, y: 0, w: data.window.w, h: 40}} rect={{x: 0, y: 0, w: win.w, h: 40 * K}} />
            {(['left', 'middle', 'right'] as const).map((p) => landed(p) && (
              <Crop key={p} src={paneSrc[p]} scale={data.scale} region={A[`video.pane.${p}`]} rect={{...toFrame(A[`video.pane.${p}`]), x: A[`video.pane.${p}`].x * K, y: A[`video.pane.${p}`].y * K}} />
            ))}
          </div>
        )}
        {/* The flights, front window last, so the pile unstacks from the top. */}
        {[...FLIGHTS].sort((a, b) => clutterWin(a.id).z - clutterWin(b.id).z).map((f) => {
          const L = clutterWin(f.id);
          const u = ramp(t, m0 + f.at, m0 + f.at + FLY);
          if (u >= 1) return null;
          const dest = toFrame(A[f.to]);
          const from: Rect = {x: L.x, y: L.y, w: L.w, h: L.h};
          // A gentle arc: windows lift toward the camera mid-flight.
          const r = lerpRect(from, dest, u);
          const lift = Math.sin(u * Math.PI);
          const isTab = f.to.includes('.tab.');
          // A window folding into a tab keeps its own face until it is nearly tab-sized; a pane crossfades earlier.
          const x = isTab ? ramp(u, 0.72, 0.96) : ramp(u, 0.35, 0.85);
          const s = r.w / L.w;
          return (
            <div key={f.id} style={{position: 'absolute', left: r.x, top: r.y - lift * 18, width: r.w, height: r.h, overflow: 'hidden', zIndex: 100 + L.z,
              borderRadius: lerp(11, isTab ? 5 : 0, u), boxShadow: `0 ${10 + 30 * lift}px ${30 + 50 * lift}px rgba(0,0,0,${0.25 + 0.2 * lift})`}}>
              <div style={{position: 'absolute', left: 0, top: 0, width: L.w, height: L.h, transformOrigin: '0 0', transform: `scale(${s})`, opacity: 1 - x}}>
                <div style={{position: 'absolute', left: -L.x, top: -L.y, width: W, height: H}}><PileWindow id={f.id} t={t} /></div>
              </div>
              <Crop src={f.pane === 'middle' ? data.src['video-s2-middle-0'] : data.src['video-s2-right-1']} scale={data.scale} region={A[f.to]}
                rect={isTab ? {x: 0, y: 0, w: dest.w, h: dest.h} : {x: 0, y: 0, w: r.w, h: r.w * A[f.to].h / A[f.to].w}} opacity={x} />
            </div>
          );
        })}
      </div>
      {/* Screen-space overlays: callouts and the cursor. */}
      <Overlays t={t} ev={ev} A={A} toFrame={toFrame} screen={screen} data={data} paneSrc={paneSrc} />
    </AbsoluteFill>
  );
};

type OverlayProps = {t: number; ev: MorphEvents; A: Record<string, Rect>; toFrame: (r: Rect) => Rect; screen: (r: Rect) => Rect; data: MorphData;
  paneSrc: {left: string; middle: string; right: string}};

// Each pane's callout: a marker around the part that says what the pane is for, and the narrator's words.
// No mini window: the camera has already pushed in, so an enlarged crop would only repeat it. Window points.
const CALLOUTS = [
  {ev: 'pane', pane: 'left' as const, rect: {x: 6, y: 52, w: 288, h: 100}, title: 'projects · sessions · files', quote: 'a pane for managing files and projects'},
  {ev: 'terminal', pane: 'middle' as const, rect: {x: 308, y: 44, w: 570, h: 28}, title: 'terminal · chat', quote: 'a terminal or chat view'},
  {ev: 'flexible', pane: 'right' as const, rect: {x: 1150, y: 44, w: 615, h: 28}, title: 'md · html · pptx · docx', quote: 'a flexible editor'},
];

const Overlays = ({t, ev, A, toFrame, screen, data, paneSrc}: OverlayProps) => {
  const clicks: {at: number; target: Rect}[] = [];
  const add = (at: number | undefined, id: string) => { if (at !== undefined && A[id]) clicks.push({at, target: A[id]}); };
  add(ev.mid1, 'video.tab.middle.1'); add(ev.mid2, 'video.tab.middle.2');
  if (ev.chat !== undefined) clicks.push({at: ev.chat, target: {x: A['video.pane.middle'].x + A['video.pane.middle'].w - 34, y: 46, w: 24, h: 22}});
  add(ev.right2, 'video.tab.right.2'); add(ev.right3, 'video.tab.right.3'); add(ev.right4, 'video.tab.right.4');
  clicks.sort((a, b) => a.at - b.at);
  // The cursor: arrives before the first click, travels between targets, leaves after the last.
  let cursor: React.ReactNode = null;
  if (clicks.length && t > clicks[0].at - 1.0 && t < clicks[clicks.length - 1].at + 1.2) {
    const pt = (r: Rect) => { const s = screen(toFrame(r)); return {x: s.x + s.w * 0.5, y: s.y + s.h * 0.55}; };
    let i = clicks.findIndex((c) => c.at > t);
    if (i < 0) i = clicks.length;
    const to = i < clicks.length ? pt(clicks[i].target) : pt(clicks[clicks.length - 1].target);
    const from = i === 0 ? {x: W * 0.6, y: H * 0.9} : pt(clicks[i - 1].target);
    const prevAt = i === 0 ? clicks[0].at - 1.0 : clicks[i - 1].at;
    const nextAt = i < clicks.length ? clicks[i].at : prevAt + 0.01;
    const m = i < clicks.length ? ramp(t, Math.max(prevAt + 0.12, nextAt - 0.55), nextAt - 0.04) : 1;
    const last = clicks[Math.max(0, i - 1)];
    const press = interpolate(t - last.at, [-0.04, 0.04, 0.14], [0, 1, 0], clamp);
    cursor = <Cursor x={from.x + (to.x - from.x) * m} y={from.y + (to.y - from.y) * m - Math.sin(m * Math.PI) * 26} press={press} />;
  }
  return (
    <AbsoluteFill style={{pointerEvents: 'none'}}>
      {CALLOUTS.map((c) => {
        const at = ev[c.ev];
        if (at === undefined || t < at || t > at + 2.4) return null;
        const r = screen(toFrame(c.rect));
        const leave = ramp(t, at + 2.2, at + 2.4);
        const marker = ramp(t, at + 0.05, at + 0.5) * (1 - leave);
        const open = ramp(t, at + 0.4, at + 0.54) * (1 - leave);
        return (
          <AbsoluteFill key={c.ev}>
            <Marker cx={r.x + r.w / 2} cy={r.y + r.h / 2} rx={r.w / 2 + 18} ry={r.h / 2 + 14} progress={marker} />
            <Caption text={c.quote} u={open} />
          </AbsoluteFill>
        );
      })}
      {cursor}
      {ev.launch !== undefined && t < ev.launch + 0.7 && (() => {
        // The launch click: the cursor glides in to Duo's Dock tile, clicks, and fades as the app opens.
        const c = ev.launch, tile = screen(DOCK_DUO);
        const to = {x: tile.x + tile.w * 0.5, y: tile.y + tile.h * 0.45}, from = {x: W * 0.68, y: H * 0.38};
        const m = ramp(t, 0.1, c - 0.04);
        const press = interpolate(t - c, [-0.04, 0.04, 0.14], [0, 1, 0], clamp);
        const op = ramp(t, 0, 0.15) * (1 - ramp(t, c + 0.3, c + 0.7));
        return <div style={{opacity: op}}><Cursor x={from.x + (to.x - from.x) * m} y={from.y + (to.y - from.y) * m - Math.sin(m * Math.PI) * 40} press={press} /></div>;
      })()}
    </AbsoluteFill>
  );
};

export const MORPH_WINDOWS = CLUTTER_LAYOUT.map((w) => w.id);
