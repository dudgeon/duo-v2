import React from 'react';
import {AbsoluteFill, Img, interpolate, staticFile} from 'remotion';
import {Wallpaper} from '../lib/Desk';
import {Dock, MenuBar} from '../lib/Clutter';
import {Lights, caret} from '../lib/ClutterApps';
import {PaperGround, ramp} from '../lib/Paper';
import tokens from '../../style/tokens.json';
import {Trace, traceProgress} from '../lib/Trace';
import content from '../../fixture/docs/content.json';
import world from '../../fixture/world.json';

// S8 · Projects Background (Geoff, 2026-10-11): what a "project" is to Claude Code, before Duo.
// Duo's window fades to the bare desk; a drawn Terminal and a Finder window open in ~; `claude` starts there
// and its banner shows ~ (circled: that folder is the project); a line runs from the circled ~ to the Finder window, whose
// folder lights up, so the working directory and the folder read as one place. A motion graphic on paper shows the ideal,
// one folder per project with its own stack of sessions, its columns arriving one at a time; a small terminal cds into
// shelf-scan (its folder lights up) and starts claude, and a new session card drops onto shelf-scan's stack. Then every
// stack but the one you're in fades to faint outlines, as if hidden (Geoff's v10 notes).
// Back in the Terminal, `claude --resume` opens the real picker on Sam's whole pile, scrolled a screen.
// The screens are Claude Code 2.1.296's own renders (fixture/terms/s8-*.txt). At the exit the pile fades
// and Duo's window fades back in on the next scene's first capture.

export type ProjectsData = {window: {w: number; h: number}; scale: number; src: string; back: string;
  screens: {banner: string; top: string; scrolled: string}};
export type ProjectsEvents = {fade?: number; windows?: number; claude?: number; here?: number; link?: number; map?: number; cd?: number;
  newsession?: number; cdOut?: number; grey?: number; fold?: number; resume?: number; scroll?: number; exit?: number};

const W = tokens.frame.width, H = tokens.frame.height, ui = tokens.font.ui, mono = tokens.font.mono, P = tokens.paper;
const K = 0.855;   // the Duo window's placement, as AppScene draws it
const clamp = {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'} as const;
const S8 = (content as unknown as {s8: {prompt: string; finder: {path: string; items: string[]}}}).s8;
const ACCENT = tokens.callout.accent;
const T = {bg: '#141416', fg: '#E8E6E3', dim: '#8E8E93', orange: '#D97757'};

const TERM = {x: 120, y: 120, w: 980, h: 760};
const FIND = {x: 1150, y: 230, w: 640, h: 440};
const COLS = 100, FS = 15.2;   // 100 columns of 15.2 px mono fill the terminal's width

const Win = ({r, title, dark, children, u = 1, lit = 0}: {r: {x: number; y: number; w: number; h: number}; title: string; dark?: boolean; children: React.ReactNode; u?: number; lit?: number}) => (
  <div style={{position: 'absolute', left: r.x, top: r.y, width: r.w, height: r.h, borderRadius: 12, overflow: 'hidden', opacity: u,
    transform: `translateY(${(1 - u) * 30}px) scale(${0.97 + 0.03 * u})`, transformOrigin: '50% 100%',
    background: dark ? T.bg : '#fff', boxShadow: '0 30px 80px rgba(0,0,0,0.42), 0 0 0 0.5px rgba(0,0,0,0.4)'}}>
    <div style={{height: 38, position: 'relative', background: dark ? '#2A2A2E' : '#ECECEE', borderBottom: dark ? '1px solid #000' : '1px solid #D8D8DC',
      color: dark ? '#B8B8BE' : '#4A4B50', fontFamily: ui, fontSize: 13, fontWeight: 600, textAlign: 'center', lineHeight: '38px'}}>
      <Lights /><span style={{padding: '2px 8px', borderRadius: 6, boxShadow: lit > 0 ? `0 0 0 ${2.5 * lit}px ${LIT}` : 'none'}}>{title}</span>
    </div>
    <div style={{position: 'absolute', top: 38, left: 0, right: 0, bottom: 0}}>{children}</div>
  </div>
);

/** A terminal screen as Claude Code drew it: fixed columns, no wrapping. */
const Screen = ({text, dy = 0}: {text: string; dy?: number}) => (
  <pre style={{margin: 0, padding: '12px 16px', fontFamily: mono, fontSize: FS, lineHeight: '21px', color: T.fg, whiteSpace: 'pre', transform: `translateY(${dy}px)`}}>
    {text.replace(/\s+$/, '')}
  </pre>
);

const FolderIcon = ({s = 15, grey = 0}: {s?: number; grey?: number}) => (
  <svg width={s * 1.25} height={s} viewBox="0 0 20 16" style={{flex: 'none', filter: `grayscale(${grey})`, opacity: 1 - grey * 0.55}}>
    <path d="M1 3a2 2 0 0 1 2-2h4.2l1.8 2H17a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H3a2 2 0 0 1-2-2z" fill="#5BB3F2" />
    <path d="M1 6h18v7a2 2 0 0 1-2 2H3a2 2 0 0 1-2-2z" fill="#7CC6FA" />
  </svg>
);

const LIT = '#FFB37A';   // the banner trace's orange: what's lit belongs to the circled folder
const FinderHome = ({lit = 0}: {lit?: number}) => (
  <div style={{display: 'flex', height: '100%', fontFamily: ui, fontSize: 14}}>
    <div style={{width: 150, background: '#F1F1F4', padding: '12px 8px', borderRight: '1px solid #DDDDE0'}}>
      <div style={{fontSize: 11, fontWeight: 600, color: '#8A8B90', margin: '0 6px 4px'}}>Favourites</div>
      {['sam', 'Desktop', 'Documents', 'Downloads'].map((f) => (
        <div key={f} style={{display: 'flex', gap: 7, alignItems: 'center', padding: '3px 6px', borderRadius: 5, color: '#2B2C30', background: f === 'sam' ? '#D9D9DE' : 'none',
          boxShadow: f === 'sam' && lit > 0 ? `0 0 0 ${2.5 * lit}px ${LIT}` : 'none'}}>
          <FolderIcon s={12} />{f}</div>))}
    </div>
    <div style={{flex: 1, display: 'flex', flexWrap: 'wrap', alignContent: 'flex-start', gap: '18px 6px', padding: '22px 18px'}}>
      {S8.finder.items.map((f) => (
        <div key={f} style={{width: 100, display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 6, fontSize: 13, color: '#2B2C30'}}>
          <FolderIcon s={52} />{f}</div>))}
    </div>
  </div>
);

// The ideal Claude Code assumes: one folder per project, each with its own sessions (titles from the fixture).
const home = (world as unknown as {homeSessions: {sessions: {title: string}[]}}).homeSessions.sessions.map((s) => s.title);
const pick = (re: RegExp) => home.filter((t) => re.test(t)).slice(0, 4);
const MAP: {folder: string; cards: string[]}[] = [
  {folder: 'work/…/shelf-scan', cards: pick(/shelf-scan|interview|Auto-add|Ravi/)},
  {folder: 'taxes-2026', cards: pick(/tax|Bank CSV|refinance|insurance/i)},
  {folder: 'maya-birthday', cards: pick(/birthday|Meal plan|Screen-time/)},
  {folder: 'home-network', cards: pick(/router|zsh|Downloads/)},
  {folder: 'garden', cards: pick(/Watering/)},
];

const COL = 0.85;   // a column's turn: its folder, then its cards, before the next column starts
const CD = 'cd ~/work/little-shared-library/shelf-scan';

/** The small terminal over the map: Sam cds into shelf-scan, the prompt follows, then `claude` starts a session there. */
const CdTerminal = ({t, ev}: {t: number; ev: ProjectsEvents}) => {
  if (ev.cd === undefined) return null;
  const u = ramp(t, ev.cd - 0.5, ev.cd) * (ev.cdOut === undefined ? 1 : 1 - ramp(t, ev.cdOut, ev.cdOut + 0.5));
  if (u <= 0) return null;
  const cdDone = ev.cd + CD.length / 28 + 0.25, there = t >= cdDone;
  const typed = (text: string, at: number, cps: number) => (t < at ? '' : text.slice(0, Math.floor((t - at) * cps)));
  const lines = there
    ? `${S8.prompt} ${CD}\nsam@mbp shelf-scan % ${ev.newsession !== undefined ? typed('claude', ev.newsession, 16) : ''}`
    : `${S8.prompt} ${typed(CD, ev.cd, 28)}`;
  return (
    <Win r={{x: 1040, y: 640, w: 760, h: 170}} title={`sam — ${there ? 'shelf-scan' : '~'} — -zsh`} dark u={u}>
      <Screen text={lines + caret(t)} />
    </Win>
  );
};

const FolderMap = ({t, ev}: {t: number; ev: ProjectsEvents}) => {
  const at = ev.map ?? 0, grey = ev.grey === undefined ? 0 : ramp(t, ev.grey, ev.grey + 0.8);
  const colW = 300, x0 = (W - colW * MAP.length) / 2;
  // shelf-scan lights up once the cd lands, and a new session card drops onto its stack when claude starts.
  const cdDone = ev.cd === undefined ? undefined : ev.cd + CD.length / 28 + 0.25;
  const lit = cdDone === undefined ? 0 : ramp(t, cdDone, cdDone + 0.4) * (ev.grey === undefined ? 1 : 1 - ramp(t, ev.grey, ev.grey + 0.4));
  const drop = ev.newsession === undefined ? 0 : ramp(t, ev.newsession + 0.55, ev.newsession + 1.0);
  return (
    <AbsoluteFill>
      <PaperGround />
      <div style={{position: 'absolute', left: tokens.frame.safe, top: 90, fontFamily: mono, fontSize: 26, letterSpacing: 1, color: P.ink2}}>
        ~ <span style={{color: P.ink3}}>/</span> one folder per project
      </div>
      {MAP.map((m, i) => {
        const c0 = at + 0.3 + i * COL, u = ramp(t, c0, c0 + 0.35);
        const g = i === 0 ? 0 : grey;   // the folder you started in stays; Claude Code shows only its sessions
        const cards = i === 0 && drop > 0 ? [...m.cards, 'New session'] : m.cards;
        return (
          <div key={m.folder} style={{position: 'absolute', left: x0 + i * colW, top: 230, width: colW - 40, opacity: u, transform: `translateY(${(1 - u) * 24}px)`}}>
            <div style={{display: 'flex', alignItems: 'center', gap: 14, opacity: 1 - g * 0.55, padding: '6px 8px', margin: '-6px -8px', borderRadius: 12,
              boxShadow: i === 0 && lit > 0 ? `0 0 0 ${3 * lit}px ${ACCENT}` : 'none'}}>
              <FolderIcon s={58} grey={g} />
              <div style={{fontFamily: mono, fontSize: 21, color: P.ink, opacity: 1 - g * 0.6}}>{m.folder}</div>
            </div>
            <div style={{marginTop: 26, position: 'relative'}}>
              {cards.map((c, j) => {
                const fresh = j === m.cards.length;   // the session claude just started
                const cu = fresh ? drop : ramp(t, c0 + 0.3 + j * 0.1, c0 + 0.5 + j * 0.1);
                // Hidden, not gone: the fill and the words fade to a faint dashed outline.
                return (
                  <div key={c} style={{position: 'relative', borderRadius: 10, padding: '14px 16px', marginBottom: 12, fontFamily: ui, fontSize: 19, lineHeight: 1.25,
                    background: `rgba(255,255,255,${1 - 0.92 * g})`, color: P.ink, opacity: cu,
                    boxShadow: fresh ? `0 0 0 2px ${ACCENT}, 0 8px 22px rgba(31,35,40,0.12)` : `0 0 0 1px ${P.hairline}, 0 8px 22px rgba(31,35,40,${0.10 * (1 - g)})`,
                    outline: g > 0 ? `1.5px dashed rgba(31,35,40,${0.32 * g})` : 'none', outlineOffset: -1,
                    transform: `translateY(${(1 - cu) * (fresh ? -40 : 14)}px)`}}>
                    <span style={{opacity: 1 - 0.82 * g}}>{c}</span></div>);
              })}
            </div>
          </div>);
      })}
      {ev.grey !== undefined && (
        <Trace r={{x: x0 - 16, y: 214, w: colW - 8, h: 520}} radius={14} p={traceProgress(t, ev.grey + 0.2, ev.fold ?? ev.grey + 4)} />
      )}
      <CdTerminal t={t} ev={ev} />
    </AbsoluteFill>
  );
};

export const ProjectsScene = ({t, ev, data}: {t: number; ev: ProjectsEvents; data: ProjectsData}) => {
  const win = {x: (W - data.window.w * K) / 2, y: 38, w: data.window.w * K, h: data.window.h * K};
  const duo = ev.fade === undefined ? 1 : 1 - ramp(t, ev.fade, ev.fade + 0.9);
  const wins = ev.windows === undefined ? 0 : ramp(t, ev.windows, ev.windows + 0.5);
  const mapU = ev.map === undefined ? 0 : ramp(t, ev.map, ev.map + 0.6) * (ev.fold === undefined ? 1 : 1 - ramp(t, ev.fold, ev.fold + 0.6));
  const out = ev.exit === undefined ? 0 : ramp(t, ev.exit, ev.exit + 0.8);           // the pile goes
  const back = ev.exit === undefined ? 0 : ramp(t, ev.exit + 0.6, ev.exit + 1.5);   // Duo returns

  // What the Terminal shows: the prompt and `claude`, then the banner; later `claude --resume`, then the picker.
  const prompt = S8.prompt + ' ';
  const typedAt = (text: string, at: number | undefined, cps = 16) => (at === undefined || t < at ? '' : text.slice(0, Math.floor((t - at) * cps)));
  let term: React.ReactNode;
  if (ev.resume !== undefined && t >= ev.resume) {
    const cmd = 'claude --resume', done = t >= ev.resume + cmd.length / 16 + 0.35;
    if (!done) term = <Screen text={`${prompt}${typedAt(cmd, ev.resume)}${caret(t)}`} />;
    else {
      const sc = ev.scroll !== undefined && t >= ev.scroll;
      const slide = sc ? interpolate(t, [ev.scroll!, ev.scroll! + 0.35], [40, 0], clamp) : 0;
      term = <Screen text={sc ? data.screens.scrolled : data.screens.top} dy={slide} />;
    }
  } else if (ev.claude !== undefined && t >= ev.claude + 'claude'.length / 16 + 0.35) term = <Screen text={data.screens.banner} />;
  else term = <Screen text={`${prompt}${typedAt('claude', ev.claude)}${caret(t)}`} />;

  // The banner's folder: `~` on its third line, circled as the project.
  const hereU = ev.here === undefined ? 0 : ramp(t, ev.here, ev.here + 0.5) * (ev.map === undefined ? 1 : 1 - ramp(t, ev.map - 0.2, ev.map));
  const cw = FS * 0.602;   // SF Mono's advance
  // The circled ~ draws a line across to the Finder window, whose folder lights up as it lands: the same place.
  const away = ev.map === undefined ? 1 : 1 - ramp(t, ev.map - 0.2, ev.map);
  const linkP = ev.link === undefined ? 0 : ramp(t, ev.link, ev.link + 0.7);
  const findLit = ev.link === undefined ? 0 : ramp(t, ev.link + 0.6, ev.link + 0.9) * away;
  const a = {x: TERM.x + 16 + 11 * cw + cw / 2, y: TERM.y + 38 + 12 + 2 * 21 + 10.5}, b = {x: FIND.x + FIND.w / 2 - 22, y: FIND.y + 19};
  const ctl = {x: (a.x + b.x) / 2, y: Math.min(a.y, b.y) - 120};
  const linkLen = 1.15 * Math.hypot(b.x - a.x, b.y - a.y);

  return (
    <AbsoluteFill style={{overflow: 'hidden', background: '#000'}}>
      <Wallpaper w={W} h={H} />
      <MenuBar app={duo > 0.5 ? 'Duo' : 'Terminal'} />
      <Dock running />
      {duo > 0 && (
        <div style={{position: 'absolute', left: win.x, top: win.y, width: win.w, height: win.h, borderRadius: 12, overflow: 'hidden', opacity: duo,
          transform: `scale(${0.98 + 0.02 * duo})`, boxShadow: '0 30px 80px rgba(0,0,0,0.42), 0 0 0 0.5px rgba(0,0,0,0.4)'}}>
          <Img src={staticFile(data.src)} style={{width: win.w, height: win.h}} />
        </div>
      )}
      <div style={{opacity: 1 - out}}>
        <Win r={FIND} title="sam" u={wins} lit={findLit}><FinderHome lit={findLit} /></Win>
        <Win r={TERM} title={`sam — ${ev.resume !== undefined && t >= ev.resume ? 'claude --resume' : ev.claude !== undefined && t >= ev.claude ? 'claude' : '-zsh'} — 100×32`} dark u={wins}>
          {term}
          {hereU > 0 && <Trace r={{x: 16 + 11 * cw - 4, y: 12 + 2 * 21, w: cw + 8, h: 21}} radius={4} p={traceProgress(t, ev.here!, ev.map !== undefined ? ev.map - 0.2 : ev.here! + 3)} color="#FFB37A" />}
        </Win>
      </div>
      {linkP > 0 && away > 0 && (
        <svg style={{position: 'absolute', left: 0, top: 0, width: W, height: H, overflow: 'visible', pointerEvents: 'none', opacity: away * (1 - out)}}>
          <path d={`M${a.x} ${a.y} Q${ctl.x} ${ctl.y} ${b.x} ${b.y}`} fill="none" stroke={LIT} strokeWidth={4} strokeLinecap="round"
            strokeDasharray={`${linkLen * linkP} ${linkLen + 1}`} />
          {linkP >= 1 && <circle cx={b.x} cy={b.y} r={5} fill={LIT} />}
        </svg>
      )}
      {mapU > 0 && <AbsoluteFill style={{opacity: mapU}}><FolderMap t={t} ev={ev} /></AbsoluteFill>}
      {back > 0 && (
        <div style={{position: 'absolute', left: win.x, top: win.y, width: win.w, height: win.h, borderRadius: 12, overflow: 'hidden', opacity: back,
          transform: `scale(${0.98 + 0.02 * back})`, boxShadow: '0 30px 80px rgba(0,0,0,0.42), 0 0 0 0.5px rgba(0,0,0,0.4)'}}>
          <Img src={staticFile(data.back)} style={{width: win.w, height: win.h}} />
        </div>
      )}
    </AbsoluteFill>
  );
};
