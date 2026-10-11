import React from 'react';
import {AbsoluteFill, Img, staticFile} from 'remotion';
import {Marker, PaperGround} from '../lib/Paper';
import tokens from '../../style/tokens.json';

// Static options for the running topic list (Geoff, 2026-10-11): at each scene change the list comes up
// and the scene being entered is highlighted. Drawn over the last frame of S4 (build/public/topics-bg.png),
// at the moment S5 · Chat mode begins. Geoff picks one; the chosen one becomes a transition overlay.

const P = tokens.paper, ui = tokens.font.ui, mono = tokens.font.mono, W = tokens.frame.width, H = tokens.frame.height;
const ACCENT = tokens.callout.accent;
export const TOPICS = ['Intro', 'Too many windows', 'One window', 'All projects', 'Sessions', 'Chat mode', 'Slash commands'];
const CUR = 5;
const num = (i: number) => String(i + 1).padStart(2, '0');

const Backdrop = ({scale = 1, dim = 0, blur = 0, x = 0, y = 0, radius = 0}: {scale?: number; dim?: number; blur?: number; x?: number; y?: number; radius?: number}) => (
  <div style={{position: 'absolute', left: x, top: y, width: W, height: H, transform: `scale(${scale})`, transformOrigin: '0 0',
    borderRadius: radius / scale, overflow: 'hidden', boxShadow: radius ? '0 30px 80px rgba(31,35,40,0.28), 0 0 0 1px rgba(31,35,40,0.2)' : undefined}}>
    <Img src={staticFile('topics-bg.png')} style={{width: W, height: H, filter: blur ? `blur(${blur}px)` : undefined}} />
    {dim > 0 && <AbsoluteFill style={{background: `rgba(15,17,20,${dim})`}} />}
  </div>
);

/** A · Rail: the picture steps back to the right; the whole list stands on paper at the left, the new topic in ink with an accent bar. */
const Rail = () => (
  <AbsoluteFill>
    <PaperGround />
    <Backdrop scale={0.62} x={W - W * 0.62 - 80} y={(H - H * 0.62) / 2} radius={18} />
    <div style={{position: 'absolute', left: 110, top: 0, height: H, display: 'flex', flexDirection: 'column', justifyContent: 'center', gap: 6}}>
      {TOPICS.map((t, i) => {
        const cur = i === CUR, past = i < CUR;
        return (
          <div key={t} style={{display: 'flex', alignItems: 'center', gap: 22, height: cur ? 96 : 64, position: 'relative'}}>
            {cur && <div style={{position: 'absolute', left: -34, top: 14, bottom: 14, width: 7, borderRadius: 4, background: ACCENT}} />}
            <span style={{fontFamily: mono, fontSize: cur ? 30 : 24, width: 46, color: cur ? ACCENT : past ? P.ink2 : P.ink3}}>{num(i)}</span>
            <span style={{fontFamily: ui, fontSize: cur ? 68 : 40, fontWeight: cur ? 650 : 500, letterSpacing: cur ? -1.5 : -0.5,
              color: cur ? P.ink : past ? P.ink2 : P.ink3}}>{t}</span>
            {past && <span style={{fontSize: 28, color: P.ink3}}>✓</span>}
          </div>
        );
      })}
    </div>
  </AbsoluteFill>
);

/** B · Ribbon: a progress strip across the top of the live picture; past segments filled pale, the new one solid accent. */
const Ribbon = () => (
  <AbsoluteFill>
    <Backdrop dim={0.18} />
    <div style={{position: 'absolute', left: 64, right: 64, top: 40, display: 'flex', gap: 10, padding: 10, borderRadius: 22,
      background: 'rgba(255,255,255,0.985)', boxShadow: '0 18px 50px rgba(0,0,0,0.30), 0 0 0 1px rgba(31,35,40,0.12)'}}>
      {TOPICS.map((t, i) => {
        const cur = i === CUR, past = i < CUR;
        return (
          <div key={t} style={{flex: cur ? 1.5 : 1, height: 86, borderRadius: 14, display: 'flex', flexDirection: 'column', justifyContent: 'center',
            padding: '0 20px', background: cur ? ACCENT : past ? '#E3ECFC' : 'transparent', border: cur || past ? 'none' : `2px dashed ${P.ink3}`}}>
            <span style={{fontFamily: mono, fontSize: 20, color: cur ? 'rgba(255,255,255,0.8)' : past ? ACCENT : P.ink3}}>{num(i)}</span>
            <span style={{fontFamily: ui, fontSize: cur ? 38 : 28, fontWeight: cur ? 650 : 550, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis',
              color: cur ? '#fff' : past ? '#1D4FB8' : P.ink3}}>{t}</span>
          </div>
        );
      })}
    </div>
  </AbsoluteFill>
);

/** C · Contents page: full-frame paper, the list set large like a book's contents, the new topic circled with the marker the callouts use; the picture waits as a card. */
const Contents = () => (
  <AbsoluteFill>
    <PaperGround />
    <div style={{position: 'absolute', left: tokens.frame.safe, top: 86, fontFamily: mono, fontSize: 24, letterSpacing: 2, color: P.ink2}}>DUO · IN TWO MINUTES</div>
    <div style={{position: 'absolute', left: tokens.frame.safe, top: 170}}>
      {TOPICS.map((t, i) => {
        const cur = i === CUR, past = i < CUR;
        return (
          <div key={t} style={{display: 'flex', alignItems: 'center', gap: 34, height: 104}}>
            <span style={{fontFamily: mono, fontSize: 28, width: 46, color: cur ? ACCENT : P.ink3}}>{num(i)}</span>
            <span style={{fontFamily: ui, fontSize: 76, fontWeight: 600, letterSpacing: -2.2, color: cur ? P.ink : past ? P.ink2 : 'rgba(31,35,40,0.26)'}}>{t}</span>
          </div>
        );
      })}
    </div>
    <Marker cx={tokens.frame.safe + 80 + 245} cy={170 + CUR * 104 + 54} rx={235} ry={58} progress={1} />
    <Backdrop scale={0.4} x={W - W * 0.4 - 110} y={H / 2 - H * 0.2 + 40} radius={14} />
  </AbsoluteFill>
);

/** D · Carousel: a dark glass strip low on the live picture: the previous and next topics either side, the new one large in the middle, with a dot per topic. */
const Carousel = () => {
  const side = (i: number, align: 'right' | 'left') => (i < 0 || i >= TOPICS.length ? <div style={{width: 420}} /> : (
    <div style={{width: 420, textAlign: align, fontFamily: ui, fontSize: 34, fontWeight: 500, color: 'rgba(255,255,255,0.45)'}}>
      <span style={{fontFamily: mono, fontSize: 20, marginRight: 12}}>{num(i)}</span>{TOPICS[i]}
    </div>));
  return (
    <AbsoluteFill>
      <Backdrop dim={0.22} />
      <div style={{position: 'absolute', left: (W - 1400) / 2, width: 1400, bottom: 70, height: 190, borderRadius: 28, background: 'rgba(21,23,27,0.97)', backdropFilter: 'blur(20px)',
        boxShadow: '0 24px 70px rgba(0,0,0,0.45), 0 0 0 1px rgba(255,255,255,0.08)', display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: 22}}>
        <div style={{display: 'flex', alignItems: 'center', gap: 30}}>
          {side(CUR - 1, 'right')}
          <div style={{fontFamily: ui, fontSize: 64, fontWeight: 650, letterSpacing: -1.5, color: '#fff', whiteSpace: 'nowrap'}}>
            <span style={{fontFamily: mono, fontSize: 28, color: '#8FB3FF', marginRight: 16, verticalAlign: 'middle'}}>{num(CUR)}</span>{TOPICS[CUR]}
          </div>
          {side(CUR + 1, 'left')}
        </div>
        <div style={{display: 'flex', gap: 14}}>
          {TOPICS.map((t, i) => <div key={t} style={{width: i === CUR ? 44 : 12, height: 12, borderRadius: 6,
            background: i === CUR ? ACCENT : i < CUR ? 'rgba(255,255,255,0.7)' : 'rgba(255,255,255,0.22)'}} />)}
        </div>
      </div>
    </AbsoluteFill>
  );
};

export const TOPIC_VARIANTS: Record<string, () => React.ReactElement> = {rail: Rail, ribbon: Ribbon, contents: Contents, carousel: Carousel};
export const TopicVariant = ({variant}: {variant: string}) => {
  const V = TOPIC_VARIANTS[variant] ?? Rail;
  return <V />;
};
