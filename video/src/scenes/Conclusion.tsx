import React from 'react';
import {AbsoluteFill, Img, staticFile} from 'remotion';
import {Wallpaper} from '../lib/Desk';
import {MenuBar} from '../lib/Clutter';
import {Lights} from '../lib/ClutterApps';
import {Cursor, PaperGround, ramp} from '../lib/Paper';
import {LogoScene} from './Logo';
import tokens from '../../style/tokens.json';
import {Trace, traceProgress} from '../lib/Trace';

// S11 · Conclusion (Geoff, 2026-10-11), off the app on the paper ground, a bookend to S0.
// 1. Duo's window steps away and a release line draws itself, one dot per real GitHub release (read at build
//    time, so it grows as Duo ships), ending in an open "next" dot and a stamp of the build this video came from.
// 2. The topic list returns, every topic ticked; the ones still in progress are circled; blank feedback cards
//    stack beside it (an invitation, not real messages).
// 3. Back on the desk: Help › Report an Issue… (the real menu item) opens GitHub's new-issue form, filled in as
//    Duo fills it (DuoLinks.newIssue). Then the opening card returns, exactly as S0 settles, and holds.

export type ConclusionData = {window: {w: number; h: number}; src: string; releases: {tag: string; date: string}[]; built: string;
  topics: string[]; inProgress: string[]; os: string};
export type ConclusionEvents = {dev?: number; next?: number; list?: number; circle?: number; cards?: number; help?: number; form?: number; card?: number};

const W = tokens.frame.width, H = tokens.frame.height, ui = tokens.font.ui, mono = tokens.font.mono, P = tokens.paper;
const ACCENT = tokens.callout.accent, K = 0.855;

const ReleaseLine = ({t, ev, d}: {t: number; ev: ConclusionEvents; d: ConclusionData}) => {
  const at = ev.dev ?? 0, n = d.releases.length;
  const x0 = 180, x1 = W - 260, y = 470, step = (x1 - x0) / n;
  const draw = ramp(t, at, at + 1.6);
  const nextU = ev.next === undefined ? 0 : ramp(t, ev.next, ev.next + 0.5);
  return (
    <>
      <div style={{position: 'absolute', left: x0, top: y - 1.5, width: (x1 - x0 + step * 0.6) * draw, height: 3, background: P.ink, borderRadius: 2}} />
      {d.releases.map((r, i) => {
        const x = x0 + i * step, u = ramp(t, at + (i / n) * 1.6, at + (i / n) * 1.6 + 0.2), last = i === n - 1;
        return (
          <div key={r.tag} style={{position: 'absolute', left: x - 11, top: y - 11, opacity: u, transform: `scale(${0.6 + 0.4 * u})`}}>
            <div style={{width: 22, height: 22, borderRadius: 11, background: last ? ACCENT : P.ink, boxShadow: last ? `0 0 0 6px rgba(47,111,235,0.18)` : 'none'}} />
            <div style={{position: 'absolute', top: i % 2 ? 36 : -54, left: -40, width: 102, textAlign: 'center', fontFamily: mono, fontSize: 19, color: last ? ACCENT : P.ink2}}>{r.tag}</div>
            {(i === 0 || last) && <div style={{position: 'absolute', top: i % 2 ? 62 : -80, left: -40, width: 102, textAlign: 'center', fontFamily: mono, fontSize: 15, color: P.ink3}}>{r.date}</div>}
          </div>);
      })}
      <div style={{position: 'absolute', left: x0 + n * step - 13, top: y - 13, width: 26, height: 26, borderRadius: 13, border: `3px dashed ${ACCENT}`, opacity: nextU}} />
      <div style={{position: 'absolute', left: x0 + n * step - 40, top: y + 36, width: 80, textAlign: 'center', fontFamily: mono, fontSize: 19, color: ACCENT, opacity: nextU}}>next</div>
      <div style={{position: 'absolute', left: 0, right: 0, top: 720, textAlign: 'center', fontFamily: mono, fontSize: 24, color: P.ink2, opacity: nextU}}>
        This video was built from Duo {d.releases[n - 1]?.tag.replace(/^v/, '')} on {d.built}
      </div>
    </>
  );
};

const TopicsDone = ({t, ev, d}: {t: number; ev: ConclusionEvents; d: ConclusionData}) => {
  const at = ev.list ?? 0, row = 74, top = (H - d.topics.length * row) / 2;
  const slide = ev.cards === undefined ? 0 : ramp(t, ev.cards, ev.cards + 0.6);
  return (
    <div style={{position: 'absolute', left: 260 - slide * 120, top: 0, width: 760, height: H}}>
      {d.topics.map((name, i) => {
        const u = ramp(t, at + i * 0.07, at + 0.3 + i * 0.07), hot = d.inProgress.includes(name);
        const c = hot && ev.circle !== undefined ? ramp(t, ev.circle + 0.2 * d.inProgress.indexOf(name), ev.circle + 0.6 + 0.2 * d.inProgress.indexOf(name)) : 0;
        return (
          <div key={name} style={{position: 'absolute', top: top + i * row, left: 0, display: 'flex', alignItems: 'center', gap: 22, opacity: u}}>
            <span style={{fontFamily: mono, fontSize: 22, width: 40, color: P.ink3}}>{String(i + 1).padStart(2, '0')}</span>
            <span style={{fontFamily: ui, fontSize: 44, fontWeight: 600, letterSpacing: -1, color: P.ink}}>{name}</span>
            <span style={{fontSize: 30, color: hot ? ACCENT : '#2E7A3A'}}>{hot ? '…' : '✓'}</span>
            {/* The circle sits on the name: 44 px SF Pro semibold runs about 0.52 em a character. */}
            {c > 0 && <Trace r={{x: 62 - 10, y: -30, w: name.length * 44 * 0.52 + 20, h: 60}} radius={12} p={c} />}
          </div>);
      })}
    </div>
  );
};

const FeedbackCards = ({t, ev}: {t: number; ev: ConclusionEvents}) => {
  if (ev.cards === undefined) return null;
  return (
    <>
      {[0, 1, 2].map((i) => {
        const u = ramp(t, ev.cards! + 0.3 + i * 0.25, ev.cards! + 0.7 + i * 0.25);
        return (
          <div key={i} style={{position: 'absolute', left: 1080 + i * 26, top: 300 + i * 70, width: 560, height: 190, borderRadius: 16, background: '#fff', opacity: u,
            transform: `translateY(${(1 - u) * -40}px) rotate(${(i - 1) * 1.6}deg)`, boxShadow: `0 0 0 1px ${P.hairline}, 0 18px 40px rgba(31,35,40,0.14)`}}>
            <div style={{position: 'absolute', left: 28, top: 26, width: 200, height: 14, borderRadius: 7, background: '#E7E4DC'}} />
            <div style={{position: 'absolute', left: 28, top: 70, fontFamily: ui, fontSize: 30, color: P.ink3}}>
              How do you use Claude Code?<span style={{color: ACCENT, opacity: Math.floor(t * 2) % 2 ? 1 : 0}}>▍</span></div>
          </div>);
      })}
    </>
  );
};

const HelpAndForm = ({t, ev, d}: {t: number; ev: ConclusionEvents; d: ConclusionData}) => {
  const help = ev.help ?? 0, form = ev.form ?? help + 1;
  const win = {x: (W - d.window.w * K) / 2, y: 38, w: d.window.w * K, h: d.window.h * K};
  const menuU = ramp(t, help + 0.35, help + 0.45) * (t < form ? 1 : 0);
  const hi = t > help + 0.75;
  const fu = ramp(t, form, form + 0.5);
  const cur = t < form ? {x: 228 + (t < help + 0.3 ? (1 - ramp(t, help - 0.4, help + 0.3)) * 400 : 0), y: 12 + (t > help + 0.5 ? ramp(t, help + 0.45, help + 0.75) * 46 : 0)} : null;
  const items = ['Search', '-', 'duo2 Reference', 'What’s New in This Version', '-', 'Report an Issue…'];   // Commands.swift, Help (DL-108 m4)
  return (
    <AbsoluteFill>
      <Wallpaper w={W} h={H} />
      <MenuBar app="Duo" />
      <div style={{position: 'absolute', left: win.x, top: win.y, width: win.w, height: win.h, borderRadius: 12, overflow: 'hidden', boxShadow: '0 30px 80px rgba(0,0,0,0.42)'}}>
        <Img src={staticFile(d.src)} style={{width: win.w, height: win.h}} />
      </div>
      {menuU > 0 && (
        <div style={{position: 'absolute', left: 206, top: 26, width: 250, padding: 5, borderRadius: 10, background: 'rgba(246,246,248,0.97)', fontFamily: ui, fontSize: 14,
          boxShadow: '0 10px 30px rgba(0,0,0,0.28), 0 0 0 0.5px rgba(0,0,0,0.25)', opacity: menuU}}>
          {items.map((it, i) => it === '-' ? <div key={i} style={{height: 1, background: 'rgba(0,0,0,0.12)', margin: '5px 8px'}} /> : (
            <div key={i} style={{height: 24, lineHeight: '24px', padding: '0 12px', borderRadius: 5, background: hi && it.startsWith('Report') ? '#2F6FEB' : 'none', color: hi && it.startsWith('Report') ? '#fff' : '#1d1d1f'}}>{it}</div>))}
        </div>)}
      {fu > 0 && (
        <div style={{position: 'absolute', left: 300, top: 120, width: 1320, height: 820, borderRadius: 12, overflow: 'hidden', background: '#fff', opacity: fu,
          transform: `translateY(${(1 - fu) * 60}px)`, boxShadow: '0 30px 80px rgba(0,0,0,0.42), 0 0 0 0.5px rgba(0,0,0,0.4)', fontFamily: ui}}>
          <div style={{height: 54, background: '#ECECEE', borderBottom: '1px solid #D8D8DC', position: 'relative'}}>
            <Lights />
            <div style={{position: 'absolute', left: 300, right: 300, top: 12, height: 30, borderRadius: 8, background: '#fff', fontSize: 15, lineHeight: '30px', textAlign: 'center', color: '#4A4B50'}}>github.com/dudgeon/duo-v2/issues/new</div>
          </div>
          <div style={{padding: '34px 60px', color: '#1F2328'}}>
            <div style={{fontSize: 30, fontWeight: 600, marginBottom: 26}}>New issue <span style={{fontWeight: 400, color: '#59636E'}}>· dudgeon/duo-v2</span></div>
            <div style={{fontSize: 17, fontWeight: 600, marginBottom: 8}}>Title</div>
            <div style={{height: 44, border: '1px solid #D1D9E0', borderRadius: 8, marginBottom: 22}} />
            <div style={{fontSize: 17, fontWeight: 600, marginBottom: 8}}>Description</div>
            <div style={{border: '1px solid #D1D9E0', borderRadius: 8, padding: '16px 18px', fontFamily: mono, fontSize: 19, lineHeight: 1.6, height: 330, whiteSpace: 'pre'}}>
              {`Duo ${d.releases[d.releases.length - 1]?.tag.replace(/^v/, '')}\n${d.os}\n\nWhat happened:\n\n\nWhat I expected:`}
            </div>
            <div style={{marginTop: 22, display: 'inline-block', padding: '10px 18px', borderRadius: 8, background: '#1F883D', color: '#fff', fontSize: 17, fontWeight: 600}}>Create</div>
          </div>
        </div>)}
      {cur && <Cursor x={cur.x} y={cur.y} press={t > help + 0.3 && t < help + 0.38 ? 1 : 0} />}
    </AbsoluteFill>
  );
};

export const ConclusionScene = ({t, ev, data}: {t: number; ev: ConclusionEvents; data: ConclusionData}) => {
  const help = ev.help ?? 1e9, card = ev.card ?? 1e9;
  // Paper phases until the Help menu; the desk and the form; then the opening card, held.
  if (t >= card) {
    const u = ramp(t, card, card + 0.8);
    return (
      <AbsoluteFill>
        <HelpAndForm t={t} ev={ev} d={data} />
        <AbsoluteFill style={{opacity: u}}><LogoScene t={30} ev={{title: 2.4, sub: 3.2}} /></AbsoluteFill>
      </AbsoluteFill>
    );
  }
  if (t >= help - 0.6) {
    const u = ramp(t, help - 0.6, help - 0.1);
    return (
      <AbsoluteFill>
        <HelpAndForm t={t} ev={ev} d={data} />
        {u < 1 && <AbsoluteFill style={{opacity: 1 - u}}><PaperGround /></AbsoluteFill>}
      </AbsoluteFill>
    );
  }
  // Duo's window steps away to the left as a thumbnail; the paper fills in behind.
  const away = ramp(t, (ev.dev ?? 0) - 0.6, (ev.dev ?? 0) + 0.4);
  const listU = ev.list === undefined ? 0 : ramp(t, ev.list - 0.4, ev.list);
  const win = {x: (W - data.window.w * K) / 2, y: 38, w: data.window.w * K, h: data.window.h * K};
  return (
    <AbsoluteFill>
      <Wallpaper w={W} h={H} />
      <AbsoluteFill style={{opacity: away}}><PaperGround /></AbsoluteFill>
      {away < 1 && (
        <div style={{position: 'absolute', left: win.x - away * 1400, top: win.y + away * 300, width: win.w, height: win.h, borderRadius: 12, overflow: 'hidden',
          transform: `scale(${1 - 0.7 * away})`, transformOrigin: '0 0', opacity: 1 - away * 0.6, boxShadow: '0 30px 80px rgba(0,0,0,0.42)'}}>
          <Img src={staticFile(data.src)} style={{width: win.w, height: win.h}} />
        </div>)}
      <AbsoluteFill style={{opacity: 1 - listU}}><ReleaseLine t={t} ev={ev} d={data} /></AbsoluteFill>
      {listU > 0 && <AbsoluteFill style={{opacity: listU}}><TopicsDone t={t} ev={ev} d={data} /><FeedbackCards t={t} ev={ev} /></AbsoluteFill>}
    </AbsoluteFill>
  );
};
