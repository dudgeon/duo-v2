import React from 'react';
import {AbsoluteFill, interpolate} from 'remotion';
import {smootherstep} from './camera';
import {Wallpaper} from './Desk';
import tokens from '../../style/tokens.json';

// The cold open's cluttered Mac desktop (S1, S2): windows from several apps, drawn about 75% as
// faithfully as the real thing (Geoff, 2026-10-10), on sample data only, never a real desktop.
// Everything is a pure function of `t` (seconds into the scene) and the event times the planner
// resolved from the voiceover's words.

export type ClutterEvents = Record<string, number>; // event name -> seconds into the scene
const W = tokens.frame.width, H = tokens.frame.height;
const clamp = {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'} as const;
const ui = tokens.font.ui, mono = tokens.font.mono;

const since = (t: number, at: number | undefined) => (at === undefined ? -1 : t - at);
const opened = (t: number, at: number | undefined, dur = 0.28) => (at === undefined ? 0 : smootherstep(interpolate(t, [at, at + dur], [0, 1], clamp)));
const typed = (text: string, t: number, at: number | undefined, cps = 22) => (at === undefined || t < at ? '' : text.slice(0, Math.floor((t - at) * cps)));
const caret = (t: number) => (Math.floor(t * 2) % 2 === 0 ? '▍' : ' ');

// ---- Window chrome --------------------------------------------------------------------------

type WinProps = {x: number; y: number; w: number; h: number; title: string; appear: number; z?: number; dark?: boolean; children: React.ReactNode; bar?: React.ReactNode};
const Lights = () => (
  <div style={{display: 'flex', gap: 8, position: 'absolute', left: 14, top: 10}}>
    {['#FF5F57', '#FEBC2E', '#28C840'].map((c) => <div key={c} style={{width: 12, height: 12, borderRadius: 6, background: c, boxShadow: 'inset 0 0 0 0.5px rgba(0,0,0,0.15)'}} />)}
  </div>
);
const Win = ({x, y, w, h, title, appear, z = 0, dark, children, bar}: WinProps) => {
  if (appear <= 0) return null;
  return (
    <div style={{position: 'absolute', left: x, top: y, width: w, height: h, borderRadius: 12, overflow: 'hidden', zIndex: z,
      background: dark ? '#1E1F22' : '#FFFFFF', opacity: appear, transform: `scale(${0.94 + 0.06 * appear})`, transformOrigin: '50% 40%',
      boxShadow: '0 18px 50px rgba(0,0,0,0.35), 0 0 0 0.5px rgba(0,0,0,0.3)', fontFamily: ui}}>
      <div style={{height: bar ? 52 : 30, background: dark ? '#2B2D31' : '#ECECEE', borderBottom: `1px solid ${dark ? '#111' : '#D6D6D9'}`, position: 'relative'}}>
        <Lights />
        <div style={{position: 'absolute', left: 0, right: 0, top: 7, textAlign: 'center', fontSize: 13, fontWeight: 600, color: dark ? '#C9CBD0' : '#4A4B50'}}>{title}</div>
        {bar}
      </div>
      <div style={{position: 'absolute', top: bar ? 52 : 30, left: 0, right: 0, bottom: 0}}>{children}</div>
    </div>
  );
};

// ---- The apps ---------------------------------------------------------------------------------

const Terminal = ({lines, prompt, t, typedAt, folder}: {lines: string[]; prompt?: string; t: number; typedAt?: number; folder: string}) => (
  <div style={{padding: '14px 18px', fontFamily: mono, fontSize: 15, lineHeight: '22px', color: '#1F2328', whiteSpace: 'pre-wrap'}}>
    <div style={{border: '1px solid #D97757', borderRadius: 6, padding: '8px 12px', marginBottom: 12}}>
      <span style={{color: '#D97757'}}>✻</span> Claude Code{'\n'}<span style={{color: '#6B7280'}}>{folder}</span>
    </div>
    {lines.map((l, i) => <div key={i} style={{color: l.startsWith('>') ? '#1F2328' : '#4B5563'}}>{l}</div>)}
    {prompt !== undefined && <div>{'> '}{typed(prompt, t, typedAt)}{caret(t)}</div>}
  </div>
);

const MARKDOWN = `# PRD: Guest checkout v2

## Problem
- 38% of guests abandon at payment
- Retyping a card on mobile is the top complaint

## Goals
- Cut guest-checkout abandonment 15% by Q1
- Keep the flow to three steps

## Non-goals
- Accounts for guests
- Saved cards for guests`;

const Markdown = () => (
  <div style={{padding: '18px 22px', fontFamily: mono, fontSize: 15, lineHeight: '23px', color: '#24292F', whiteSpace: 'pre'}}>
    {MARKDOWN.split('\n').map((l, i) => <div key={i} style={{color: l.startsWith('#') ? '#0550AE' : '#24292F', fontWeight: l.startsWith('#') ? 600 : 400}}>{l || ' '}</div>)}
  </div>
);

const FOLDERS = ['api-deprecations', 'checkout-redesign', 'fraud-rules-review', 'onboarding-v3', 'pricing-experiment-q4', 'refunds-api-spec', 'vendor-review'];
const Finder = ({t, huntAt}: {t: number; huntAt?: number}) => {
  // The selection walks down the list, overshoots and comes back: a hunt, landing on checkout-redesign.
  const path = [0, 2, 4, 3, 1];
  const step = huntAt === undefined || t < huntAt ? -1 : Math.min(path.length - 1, Math.floor((t - huntAt) / 0.32));
  const sel = step < 0 ? -1 : path[step];
  return (
    <div style={{display: 'flex', height: '100%', fontSize: 14}}>
      <div style={{width: 170, background: '#F3F3F5', padding: '12px 10px', color: '#6B6C70', borderRight: '1px solid #DDDDE0'}}>
        <div style={{fontSize: 11, fontWeight: 700, marginBottom: 6}}>Favourites</div>
        {['Desktop', 'Documents', 'Downloads', 'work'].map((f) => <div key={f} style={{padding: '4px 6px', borderRadius: 5, color: '#2B2C30', background: f === 'work' ? '#DCDCE0' : 'none'}}>📁 {f}</div>)}
      </div>
      <div style={{flex: 1}}>
        <div style={{padding: '8px 14px', fontSize: 12, color: '#6B6C70', borderBottom: '1px solid #ECECEE'}}>work › payments</div>
        {FOLDERS.map((f, i) => (
          <div key={f} style={{padding: '5px 14px', background: i === sel ? '#2F6FEB' : i % 2 ? '#F7F7F9' : '#FFF', color: i === sel ? '#FFF' : '#2B2C30'}}>📁 {f}</div>
        ))}
      </div>
    </div>
  );
};

const BrowserBar = ({url}: {url: string}) => (
  <div style={{position: 'absolute', left: 90, right: 16, top: 26, height: 20, borderRadius: 6, background: '#FFFFFF', border: '1px solid #D6D6D9', fontSize: 12, color: '#55565B', padding: '1px 10px', fontFamily: ui}}>{url}</div>
);
const Page = () => (
  <div style={{padding: '26px 34px', fontFamily: 'Georgia, serif', color: '#1F2328', background: '#FBFAF7', height: '100%'}}>
    <div style={{fontSize: 30, fontWeight: 700}}>Checkout options</div>
    <div style={{fontSize: 14, color: '#6B6C70', margin: '6px 0 18px', fontFamily: ui}}>Three flows for guest checkout · draft for review</div>
    <div style={{display: 'flex', gap: 14, fontFamily: ui}}>
      {[['A', 'One page', '#E8F0FA'], ['B', 'Three steps', '#EAF6EC'], ['C', 'Wallet first', '#FBEFE6']].map(([k, n, c]) => (
        <div key={k} style={{flex: 1, background: c, borderRadius: 10, padding: 14, height: 150}}>
          <div style={{fontSize: 13, color: '#6B6C70'}}>Option {k}</div>
          <div style={{fontSize: 18, fontWeight: 600, marginTop: 4}}>{n}</div>
        </div>
      ))}
    </div>
  </div>
);

// ---- Menu bar and dock (generic: no Apple logo or Apple icons) -------------------------------

const MenuBar = ({app}: {app: string}) => (
  <div style={{position: 'absolute', left: 0, right: 0, top: 0, height: 30, background: 'rgba(255,255,255,0.28)', backdropFilter: 'blur(20px)',
    display: 'flex', alignItems: 'center', gap: 22, padding: '0 18px', fontFamily: ui, fontSize: 14, color: '#0B0B0C'}}>
    <div style={{width: 14, height: 14, borderRadius: 4, background: 'rgba(0,0,0,0.75)'}} />
    <b>{app}</b>{['File', 'Edit', 'View', 'Window', 'Help'].map((m) => <span key={m}>{m}</span>)}
    <span style={{marginLeft: 'auto'}}>Tue 9:41</span>
  </div>
);
const DOCK = [['>_', '#2B2D31'], ['M↓', '#4A6CF7'], ['🗂', '#5AA9F7'], ['◎', '#F0F0F2'], ['✎', '#F7C948'], ['✉', '#3D9BF5']];
const Dock = () => (
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
const ASK = 'the third bullet, under the second heading, in prd.md — can you tighten it?';
const CD = 'cd ~/work/payments/checkout-redesign';

export const ClutteredDesk = ({t, ev, content, front = 'Terminal'}: {t: number; ev: ClutterEvents; content: DeskContent; front?: string}) => {
  const f = content.folder;
  // The window opened last is in front, as on a real desktop.
  const order = ['term1', 'term2', 'markdown', 'finder', 'term3', 'browser'].sort((a, b) => (ev[a] ?? 1e9) - (ev[b] ?? 1e9));
  const z = (k: string) => (k === 'term3' && ev.ask !== undefined && t >= ev.ask - 0.4 ? 50 : 10 + order.indexOf(k));
  const pulse = content.question ? 0.5 + 0.5 * Math.sin(t * 6) : 0;
  return (
    <AbsoluteFill style={{overflow: 'hidden'}}>
      <Wallpaper w={W} h={H} />
      <MenuBar app={front} />
      <Win x={110} y={90} w={720} h={430} title={`${content.project} — claude — 90×24`} appear={opened(t, ev.term1)} z={z('term1')}>
        <Terminal folder={f} t={t} lines={['> what changed in the spec since Friday?', 'Read 3 files', 'Two sections changed: Goals and Non-goals.']} />
      </Win>
      <Win x={300} y={170} w={700} h={380} title={`${content.project} — claude — 80×20`} appear={opened(t, ev.term2)} z={z('term2')}>
        <Terminal folder={f} t={t} lines={['> draft the rollout plan', 'Wrote docs/rollout.md']} />
      </Win>
      <Win x={1010} y={70} w={600} h={520} title="prd-v2.md" appear={opened(t, ev.markdown)} z={z('markdown')}><Markdown /></Win>
      <Win x={140} y={560} w={640} h={380} title="payments" appear={opened(t, ev.finder)} z={z('finder')}><Finder t={t} huntAt={ev.hunt} /></Win>
      <Win x={1080} y={430} w={760} h={480} title="Checkout options" appear={opened(t, ev.browser)} z={z('browser')} bar={<BrowserBar url="file:///work/payments/checkout-redesign/options.html" />}><Page /></Win>
      <Win x={520} y={380} w={820} h={400} title={`${content.project} — claude — 100×24`} appear={opened(t, ev.term3)} z={z('term3')}>
        <Terminal folder={since(t, ev.path) > 1.8 ? f : '~'} t={t} lines={since(t, ev.path) >= 0 && since(t, ev.path) < 1.8 ? [] : ['> ' + CD]}
          prompt={since(t, ev.path) >= 0 && since(t, ev.path) < 1.8 ? CD.slice(0, Math.floor(since(t, ev.path) * 24)) : undefined}
          typedAt={undefined} />
        {ev.ask !== undefined && t >= ev.ask && (
          <div style={{position: 'absolute', left: 18, bottom: 22, right: 18, fontFamily: mono, fontSize: 15, color: '#1F2328'}}>{'> '}{typed(ASK, t, ev.ask, 20)}{caret(t)}</div>
        )}
      </Win>
      {content.question && ev.term1 !== undefined && (
        <div style={{position: 'absolute', left: 126, top: 102, padding: '3px 10px', borderRadius: 10, background: tokens.color.light.needsYou, color: '#FFF',
          fontFamily: ui, fontSize: 13, fontWeight: 600, opacity: 0.6 + 0.4 * pulse}}>● Waiting for you · 1h</div>
      )}
      <Dock />
    </AbsoluteFill>
  );
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
const ALL: ClutterEvents = {term1: -9, term2: -9, markdown: -9, finder: -9, browser: -9, term3: -9};

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
