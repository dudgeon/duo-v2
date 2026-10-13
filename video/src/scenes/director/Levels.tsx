import React from 'react';
import {AbsoluteFill} from 'remotion';
import type {SceneProps} from '../registry';
import {PaperGround} from '../../lib/Paper';
import {C, Heading, L, mono, ramp, spring, ui, type Box} from './kit';
import {PatternsEnd} from './Patterns';

// S9 · How far it goes (canvas option L2, Geoff, Oct 12). The same small tree, four times, with a piece added at each
// level as the voice climbs: a prompt on one console; the director skill; shared pages (the console of buttons) and
// sessions messaging the director; and, at the far end, the tree drawn inside Claude Code as Projects' coordinator and
// threads. The piece a level adds is drawn in ink; what it keeps from the level before stays grey.

const LEVELS: {n: string; title: string; sub: string; word: string}[] = [
  {n: '1', title: 'A prompt', sub: 'one session, told it is the director', word: 'l1'},
  {n: '2', title: 'A director skill', sub: 'the job written down; survives restarts', word: 'l2'},
  {n: '3', title: 'Shared pages and messages', sub: 'a console of buttons; sessions report in', word: 'l3'},
  {n: '4', title: 'Claude Code Projects', sub: 'a coordinator and threads, built in', word: 'l4'},
];
const panel = (i: number): Box => ({x: 120 + i * 430, y: 280, w: 400, h: 600});

const Piece = ({b, children, ink, dark, u = 1, round = 10}: {b: Box; children: React.ReactNode; ink?: boolean; dark?: boolean; u?: number; round?: number}) => (
  <div style={{position: 'absolute', left: b.x, top: b.y, width: b.w, height: b.h, boxSizing: 'border-box', borderRadius: round, padding: '0 14px', display: 'flex',
    alignItems: 'center', gap: 8, fontFamily: ui, fontSize: 17, lineHeight: '22px', background: dark ? C.console : L.pane, color: dark ? C.consoleText : L.text,
    border: dark ? 'none' : `2px solid ${ink ? L.text : L.rule}`, opacity: u, transform: `translateY(${(1 - u) * 10}px)`}}>{children}</div>
);

/** One level's tree, drawn in its panel. `level` is 0..3; `add` is how far the level's own new piece has arrived. */
const LevelTree = ({i, add}: {i: number; add: number}) => {
  const p = panel(i), x = p.x, y = p.y;
  const projects = i === 3;
  return (
    <>
      <Piece b={{x: x + 26, y: y + 210, w: 112, h: 56}}><b>user</b></Piece>
      <Piece b={{x: x + 166, y: y + 200, w: 206, h: 76}} dark>
        <span style={{fontFamily: projects ? ui : mono, fontSize: 19, fontWeight: projects ? 700 : 400}}>{projects ? 'coordinator' : 'director'}</span>
      </Piece>
      {[0, 1, 2].map((k) => (
        <Piece key={k} b={{x: x + 166, y: y + 320 + k * 60, w: 206, h: 46}} ink={projects}>
          <span style={{fontSize: 16}}>○ {projects ? 'thread' : 'session'}</span>
        </Piece>
      ))}
      {i === 0 && (
        <Piece b={{x: x + 26, y: y + 300, w: 112, h: 120}} dark u={add} round={10}>
          <span style={{fontFamily: mono, fontSize: 14, lineHeight: '19px', color: C.consoleText}}>&gt; you are now their director …</span>
        </Piece>
      )}
      {i >= 1 && (
        <Piece b={{x: x + 26, y: y + 300, w: 112, h: 130}} ink={i === 1} u={i === 1 ? add : 1}>
          <span style={{fontSize: 14, lineHeight: '19px'}}><b>SKILL.md</b><br /><span style={{color: L.text2}}>the job,<br />written down</span></span>
        </Piece>
      )}
      {i >= 2 && (
        <>
          <Piece b={{x: x + 26, y: y + 450, w: 112, h: 92}} ink={i === 2} u={i === 2 ? add : 1} round={18}>
            <span style={{fontSize: 14, lineHeight: '19px'}}><b style={{color: L.needsYou}}>console</b><br />Ship it<br />Hold</span>
          </Piece>
          <div style={{position: 'absolute', left: x + 170, top: y + 498, width: 200, fontFamily: mono, fontSize: 14, lineHeight: '19px', color: i === 2 ? L.text : L.text2, opacity: i === 2 ? add : 1}}>↺ sessions message<br />&nbsp;&nbsp;the director</div>
        </>
      )}
      {projects && (
        <>
          <div style={{position: 'absolute', left: x + 150, top: y + 176, width: 238, height: 380, boxSizing: 'border-box', border: `2.5px dashed ${L.text}`, borderRadius: 18, opacity: add}} />
          <div style={{position: 'absolute', left: x + 160, top: y + 146, fontFamily: mono, fontSize: 15, color: L.text, opacity: add}}>built into Claude Code</div>
        </>
      )}
    </>
  );
};

export const Levels = ({t, ev}: SceneProps) => {
  const go = ev.go ?? 0.4;
  const leave = ramp(t, go, go + 0.5);
  const at = (w: string) => ev[w] ?? 1e9;
  return (
    <AbsoluteFill>
      <PaperGround />
      <div style={{position: 'absolute', inset: 0, opacity: 1 - leave}}><PatternsEnd /></div>
      <Heading title="How far it goes" sub="The same tree, a piece added at each level." u={ramp(t, go + 0.3, go + 0.8)} />
      {LEVELS.map((lv, i) => {
        const p = panel(i), u = spring(t, at(lv.word) - 0.3, 7, 0.9), add = ramp(t, at(lv.word) + 0.2, at(lv.word) + 0.8);
        const current = t >= at(lv.word) && (i === 3 || t < at(LEVELS[i + 1].word));
        if (u <= 0.001) return null;
        return (
          <div key={lv.n} style={{position: 'absolute', inset: 0, opacity: Math.min(1, u), transform: `translateY(${(1 - Math.min(1, u)) * 24}px)`}}>
            <div style={{position: 'absolute', left: p.x, top: p.y, width: p.w, height: p.h, boxSizing: 'border-box', borderRadius: 16, background: L.pane,
              border: `2px solid ${current || i === 3 ? L.text : L.rule}`}} />
            <div style={{position: 'absolute', left: p.x + 26, top: p.y + 22, width: p.w - 52, fontFamily: ui, color: L.text}}>
              <div style={{fontFamily: mono, fontSize: 18, color: L.text2}}>level {lv.n}</div>
              <div style={{fontSize: 26, lineHeight: '34px', fontWeight: 700}}>{lv.title}</div>
              <div style={{fontSize: 18, lineHeight: '26px', color: L.text2}}>{lv.sub}</div>
            </div>
            <LevelTree i={i} add={add} />
            {i < 3 && <div style={{position: 'absolute', left: p.x + p.w, top: p.y + 260, width: 30, textAlign: 'center', fontSize: 30, color: '#8B939C'}}>→</div>}
          </div>
        );
      })}
      <div style={{position: 'absolute', left: 120, top: 905, fontFamily: ui, fontSize: 22, color: L.text2, opacity: ramp(t, at('access'), at('access') + 0.5)}}>
        Levels 1 to 3 are built from pieces that ship with Claude Code today. Level 4 is Projects, which I don't have yet.
      </div>
    </AbsoluteFill>
  );
};
const END_EV = {go: 0, l1: 1, l2: 2, l3: 3, l4: 4, access: 5};
export const LevelsEnd = () => <Levels t={999} ev={END_EV} scene={{id: 'S9', title: ''}} />;
