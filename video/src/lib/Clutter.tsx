import React from 'react';
import {AbsoluteFill, interpolate} from 'remotion';
import {smootherstep} from './camera';
import {Wallpaper} from './Desk';
import tokens from '../../style/tokens.json';
import content from '../../fixture/docs/content.json';
import {CLUTTER_LAYOUT, clutterWin} from './clutterLayout';
import {BROWSER_BAR_H, BrowserBar, BrowserPage, ClaudeTerminal, DeckApp, DocApp, Finder, Lights, MarkdownEditor, TERM1, TERM2, ZshTerminal} from './ClutterApps';

// The cold open's cluttered Mac desktop (S1, S2): windows from several apps, drawn about 75% as
// faithfully as the real thing (Geoff, 2026-10-10), on sample data only, never a real desktop.
// Everything is a pure function of `t` (seconds into the scene) and the event times the planner
// resolved from the voiceover's words. Where each window sits is clutterLayout.ts, shared with S2's morph.

export type ClutterEvents = Record<string, number>; // event name -> seconds into the scene
const W = tokens.frame.width, H = tokens.frame.height;
const clamp = {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'} as const;
const ui = tokens.font.ui, mono = tokens.font.mono;

const since = (t: number, at: number | undefined) => (at === undefined ? -1 : t - at);
const opened = (t: number, at: number | undefined, dur = 0.28) => (at === undefined ? 0 : smootherstep(interpolate(t, [at, at + dur], [0, 1], clamp)));

// ---- Window chrome --------------------------------------------------------------------------

type Chrome = 'light' | 'dark' | 'bare';
type WinProps = {id: string; title: string; appear: number; chrome?: Chrome; children: React.ReactNode; bar?: React.ReactNode; barH?: number};
const Win = ({id, title, appear, chrome = 'light', children, bar, barH}: WinProps) => {
  if (appear <= 0) return null;
  const {x, y, w, h, z} = clutterWin(id);
  const dark = chrome === 'dark', bare = chrome === 'bare';
  const th = bare ? 0 : bar ? barH ?? 52 : 30;
  return (
    <div style={{position: 'absolute', left: x, top: y, width: w, height: h, borderRadius: 11, overflow: 'hidden', zIndex: z,
      background: dark ? '#141416' : '#FFFFFF', opacity: appear, transform: `scale(${0.94 + 0.06 * appear})`, transformOrigin: '50% 40%',
      boxShadow: dark ? '0 18px 50px rgba(0,0,0,0.45), 0 0 0 1px rgba(255,255,255,0.14), 0 0 0 1.5px rgba(0,0,0,0.5)' : '0 18px 50px rgba(0,0,0,0.35), 0 0 0 0.5px rgba(0,0,0,0.3)', fontFamily: ui}}>
      {!bare && (
        <div style={{height: th, background: dark ? 'linear-gradient(#3B3B3F, #2E2E32)' : '#ECECEE', borderBottom: `1px solid ${dark ? '#0A0A0B' : '#D6D6D9'}`, position: 'relative'}}>
          <Lights />
          <div style={{position: 'absolute', left: 0, right: 0, top: 7, textAlign: 'center', fontSize: 13, fontWeight: 600, color: dark ? '#C9CBD0' : '#4A4B50'}}>{!bar && title}</div>
          {bar}
        </div>)}
      <div style={{position: 'absolute', top: th, left: 0, right: 0, bottom: 0}}>{children}</div>
    </div>
  );
};

// ---- Menu bar and dock (generic: no Apple logo or Apple icons) -------------------------------

export const MenuBar = ({app}: {app: string}) => (
  <div style={{position: 'absolute', left: 0, right: 0, top: 0, height: 30, background: 'rgba(255,255,255,0.28)', backdropFilter: 'blur(20px)',
    display: 'flex', alignItems: 'center', gap: 22, padding: '0 18px', fontFamily: ui, fontSize: 14, color: '#0B0B0C'}}>
    <div style={{width: 14, height: 14, borderRadius: 4, background: 'rgba(0,0,0,0.75)'}} />
    <b>{app}</b>{['File', 'Edit', 'View', 'Window', 'Help'].map((m) => <span key={m}>{m}</span>)}
    <span style={{marginLeft: 'auto'}}>Tue 9:41</span>
  </div>
);
const DOCK = [['>_', '#2B2D31'], ['M↓', '#4A6CF7'], ['🗂', '#5AA9F7'], ['◎', '#F0F0F2'], ['✎', '#F7C948'], ['✉', '#3D9BF5']];
export const Dock = () => (
  <div style={{position: 'absolute', left: '50%', bottom: 10, transform: 'translateX(-50%)', display: 'flex', gap: 12, padding: 10, borderRadius: 22,
    background: 'rgba(255,255,255,0.25)', backdropFilter: 'blur(20px)', boxShadow: '0 0 0 0.5px rgba(255,255,255,0.4)'}}>
    {DOCK.map(([g, c]) => (
      <div key={g} style={{width: 62, height: 62, borderRadius: 15, background: c, display: 'flex', alignItems: 'center', justifyContent: 'center',
        fontFamily: mono, fontSize: 24, color: c === '#F0F0F2' ? '#333' : '#FFF', boxShadow: '0 2px 6px rgba(0,0,0,0.25)'}}>{g}</div>
    ))}
  </div>
);

// ---- One desk ---------------------------------------------------------------------------------

export type DeskContent = {project: string; folder: string; question?: boolean};

/** The camera hunts across the pile for an older session: dt seconds after `hunt`, a zoom on a point, and back to the full pile. */
const HUNT: {dt: number; s: number; cx: number; cy: number}[] = [
  {dt: 0, s: 1, cx: W / 2, cy: H / 2},
  {dt: 0.55, s: 1.7, cx: 380, cy: 230},
  {dt: 1.15, s: 1.7, cx: 590, cy: 420},
  {dt: 1.75, s: 1.6, cx: 300, cy: 730},
  {dt: 2.4, s: 1.5, cx: 1000, cy: 240},
  {dt: 3.2, s: 1, cx: W / 2, cy: H / 2},
];
const huntCamera = (t: number, hunt: number | undefined) => {
  if (hunt === undefined || t <= hunt) return {s: 1, tx: 0, ty: 0};
  const dt = t - hunt;
  let i = HUNT.findIndex((k) => k.dt > dt);
  if (i < 0) return {s: 1, tx: 0, ty: 0};
  if (i === 0) i = 1;
  const a = HUNT[i - 1], b = HUNT[i], u = smootherstep(interpolate(dt, [a.dt, b.dt], [0, 1], clamp));
  const s = a.s + (b.s - a.s) * u, cx = a.cx + (b.cx - a.cx) * u, cy = a.cy + (b.cy - a.cy) * u;
  return {s, tx: Math.min(0, Math.max(W - s * W, W / 2 - s * cx)), ty: Math.min(0, Math.max(H - s * H, H / 2 - s * cy))};
};

export const ClutteredDesk = ({t, ev, content: desk, front = 'Terminal'}: {t: number; ev: ClutterEvents; content: DeskContent; front?: string}) => {
  const pulse = desk.question ? 0.5 + 0.5 * Math.sin(t * 6) : 0;
  const cam = huntCamera(t, ev.hunt);
  const [s1, s2, s3] = content.terminals;
  // term3 (the new window): wrong cd, then the right one. No `path` event (S2's copies): it is finished.
  const pu = ev.path === undefined ? undefined : since(t, ev.path);
  const cdDone = pu === undefined || pu >= 2.25;
  return (
    <AbsoluteFill style={{overflow: 'hidden'}}>
      <div style={{position: 'absolute', left: 0, top: 0, width: W, height: H, transform: `translate(${cam.tx}px, ${cam.ty}px) scale(${cam.s})`, transformOrigin: '0 0'}}>
      <Wallpaper w={W} h={H} />
      <MenuBar app={front} />
      <Win id="term1" chrome="dark" title={`✳ ${s1.session}`} appear={opened(t, ev.term1)}>
        <ClaudeTerminal t={t} lines={TERM1} />
      </Win>
      <Win id="term2" chrome="dark" title={`✳ ${s2.session}`} appear={opened(t, ev.term2)}>
        <ClaudeTerminal t={t} lines={TERM2} working="Frosting" />
      </Win>
      <Win id="finder" title="payments" appear={opened(t, ev.finder)}><Finder t={t} huntAt={ev.hunt} /></Win>
      <Win id="markdown" title="prd-v2.md — checkout-redesign" appear={opened(t, ev.markdown)}><MarkdownEditor /></Win>
      <Win id="browser" title={content.prototype.title} appear={opened(t, ev.browser)} bar={<BrowserBar />} barH={BROWSER_BAR_H}>
        <BrowserPage w={clutterWin('browser').w} h={clutterWin('browser').h - BROWSER_BAR_H} />
      </Win>
      <Win id="deck" chrome="bare" title="exec-review-oct14.pptx" appear={opened(t, ev.deck)}><DeckApp /></Win>
      <Win id="doc" chrome="bare" title="interview-synthesis.docx" appear={opened(t, ev.doc)}><DocApp /></Win>
      <Win id="term3" chrome="dark" title={cdDone ? 'checkout-redesign — -zsh — 80×20' : '~ — -zsh — 80×20'} appear={opened(t, ev.term3)}>
        <ZshTerminal t={t} u={pu} />
      </Win>
      {desk.question && ev.term1 !== undefined && (
        <div style={{position: 'absolute', left: 66, top: 82, padding: '3px 10px', borderRadius: 10, background: tokens.color.light.needsYou, color: '#FFF', zIndex: 60,
          fontFamily: ui, fontSize: 13, fontWeight: 600, opacity: 0.6 + 0.4 * pulse}}>● Waiting for you · 1h</div>
      )}
      <Dock />
      </div>
    </AbsoluteFill>
  );
};

/** One window of S1's finished pile, at its layout rect (S2's morph flies each from here). */
export const PileWindow = ({id, t}: {id: string; t: number}) => {
  const [s1, s2] = content.terminals;
  switch (id) {
    case 'term1': return <Win id="term1" chrome="dark" title={`✳ ${s1.session}`} appear={1}><ClaudeTerminal t={t} lines={TERM1} /></Win>;
    case 'term2': return <Win id="term2" chrome="dark" title={`✳ ${s2.session}`} appear={1}><ClaudeTerminal t={t} lines={TERM2} working="Frosting" /></Win>;
    case 'finder': return <Win id="finder" title="payments" appear={1}><Finder t={t} /></Win>;
    case 'markdown': return <Win id="markdown" title="prd-v2.md — checkout-redesign" appear={1}><MarkdownEditor /></Win>;
    case 'browser': return (
      <Win id="browser" title={content.prototype.title} appear={1} bar={<BrowserBar />} barH={BROWSER_BAR_H}>
        <BrowserPage w={clutterWin('browser').w} h={clutterWin('browser').h - BROWSER_BAR_H} />
      </Win>);
    case 'deck': return <Win id="deck" chrome="bare" title="exec-review-oct14.pptx" appear={1}><DeckApp /></Win>;
    case 'doc': return <Win id="doc" chrome="bare" title="interview-synthesis.docx" appear={1}><DocApp /></Win>;
    case 'term3': return <Win id="term3" chrome="dark" title="checkout-redesign — -zsh — 80×20" appear={1}><ZshTerminal t={t} u={undefined} /></Win>;
    default: throw new Error(`PileWindow: no window ${id}`);
  }
};

// ---- The scenes -------------------------------------------------------------------------------

/** S1: the desk fills up as each app is named. */
export const DeskScene = ({t, ev}: {t: number; ev: ClutterEvents}) => (
  <ClutteredDesk t={t} ev={ev} content={{project: 'checkout-redesign', folder: '~/work/payments/checkout-redesign'}} />
);

const PROJECTS: DeskContent[] = [
  {project: 'refunds-api-spec', folder: '~/work/payments/refunds-api-spec', question: true},
  {project: 'checkout-redesign', folder: '~/work/payments/checkout-redesign'},
  {project: 'onboarding-v3', folder: '~/work/growth/onboarding-v3'},
  {project: 'pricing-experiment-q4', folder: '~/work/growth/pricing-experiment-q4'},
];
const ALL: ClutterEvents = Object.fromEntries(CLUTTER_LAYOUT.map((w) => [w.id, -9]));

/** S2: pull back from the one desk to a desk per project, side by side. */
export const ManyDesksScene = ({t, ev}: {t: number; ev: ClutterEvents}) => {
  const u = smootherstep(interpolate(t, [ev.pullStart ?? 0, ev.pullEnd ?? 2], [0, 1], clamp));
  const slots = [[0.02, 0.02], [0.51, 0.02], [0.02, 0.51], [0.51, 0.51]];
  const dim = interpolate(t, [ev.dim ?? 1e9, (ev.dim ?? 1e9) + 1.2], [0, 0.45], clamp);
  return (
    <AbsoluteFill style={{background: '#0B1220'}}>
      {PROJECTS.map((p, i) => {
        const [sx, sy] = slots[i];
        // checkout-redesign (slot 1) starts full-frame: it's S1's desk, and the camera pulls back from it.
        const isHero = i === 1;
        const scale = isHero ? 1 - (1 - 0.47) * u : 0.47;
        const x = isHero ? sx * W * u : sx * W, y = isHero ? sy * H * u : sy * H;
        const opacity = isHero ? 1 : u;
        return (
          <div key={p.project} style={{position: 'absolute', left: x, top: y, width: W, height: H, transform: `scale(${scale})`, transformOrigin: '0 0',
            opacity, zIndex: isHero ? 10 : 1, borderRadius: 18 / scale, overflow: 'hidden', boxShadow: u > 0 ? '0 10px 40px rgba(0,0,0,0.5)' : 'none'}}>
            <ClutteredDesk t={t + i * 1.3} ev={ALL} content={p} />
          </div>
        );
      })}
      <AbsoluteFill style={{background: `rgba(11,18,32,${dim})`}} />
    </AbsoluteFill>
  );
};
