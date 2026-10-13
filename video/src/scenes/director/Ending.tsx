import React from 'react';
import {AbsoluteFill} from 'remotion';
import type {SceneProps} from '../registry';
import {PaperGround} from '../../lib/Paper';
import {C, DirectorCard, Heading, L, lerp, Meter, mono, ramp, SectionLabel, spring, ui, Wire, YouCard, type Box} from './kit';
import {MiniTree, PatternsEnd} from './Patterns';
import {LevelsEnd} from './Levels';
import {PROMPT_A, PROMPT_B} from './board';
import qr from './qr.json';

// S9 to S11: the ending. S9 sets the home-built tree beside Claude Code Projects, part for part. S10 is the tease:
// a persistent agent (the director's trail back through the weeks) and a shared one (more people on its line).
// S11 brings the first prompt back with a QR code to a gist of it.

const OURS = {x: 144, y: 360}, THEIRS = {x: 1016, y: 360};
const S = 0.98;

/** Claude Code Projects' shape, in line art only: a coordinator and its threads (its own explainer's words). */
const ProjectsTree = ({u}: {u: number}) => {
  const thread = (i: number) => ({x: 520, y: 40 + i * 88, w: 220, h: 48});
  const box = (b: Box, label: string, dark = false) => (
    <div style={{position: 'absolute', left: b.x, top: b.y, width: b.w, height: b.h, boxSizing: 'border-box', borderRadius: 10, border: `2px solid ${L.text}`,
      background: dark ? L.text : 'transparent', color: dark ? L.pane : L.text, display: 'flex', alignItems: 'center', padding: '0 16px', fontFamily: ui, fontSize: 20}}>{label}</div>
  );
  return (
    <div style={{position: 'absolute', left: 0, top: 0, width: 760, height: 300, opacity: u}}>
      <Wire pts={[[250, 150], [192, 150]]} head width={2} color={L.text} />
      {[0, 1, 2].map((i) => <Wire key={i} pts={[[452, 150], [490, 150], [490, thread(i).y + 24], [518, thread(i).y + 24]]} head width={2} color={L.text} radius={8} />)}
      {box({x: 20, y: 110, w: 170, h: 80}, 'You')}
      {box({x: 250, y: 100, w: 200, h: 100}, 'coordinator', true)}
      {[0, 1, 2].map((i) => <React.Fragment key={i}>{box(thread(i), 'thread')}</React.Fragment>)}
    </div>
  );
};

const PIECES: [string, number, number][] = [['a prompt and a skill', 250, 210], ['SendMessage', 404, 112], ['claude --bg · worktrees', 520, 274]];

export const Projects = ({t, ev}: SceneProps) => {
  const go = ev.go ?? 0.4, projects = ev.projects ?? go + 1, coordinator = ev.coordinator ?? projects + 1.5, pieces = ev.pieces ?? coordinator + 4;
  const leave = ramp(t, go, go + 0.5);
  const map = (k: number) => ramp(t, coordinator + 0.25 * k, coordinator + 0.6 + 0.25 * k);
  return (
    <AbsoluteFill>
      <PaperGround />
      <div style={{position: 'absolute', inset: 0, opacity: 1 - leave}}><PatternsEnd /></div>
      <Heading title="Claude Code Projects" sub="The same shape, built in." u={ramp(t, go + 0.3, go + 0.8)} />
      <div style={{position: 'absolute', left: OURS.x, top: OURS.y, transform: `scale(${S})`, transformOrigin: '0 0', opacity: ramp(t, go + 0.2, go + 0.7)}}>
        <SectionLabel x={0} y={-56} text="OURS, FROM PIECES" />
        <MiniTree variant="base" />
        {PIECES.map(([label, x, y], k) => (
          <div key={label} style={{position: 'absolute', left: x, top: y, padding: '2px 10px', borderRadius: 8, background: L.selected,
            fontFamily: mono, fontSize: 16, lineHeight: '24px', color: L.text, whiteSpace: 'nowrap', opacity: ramp(t, pieces + 0.25 * k, pieces + 0.25 * k + 0.35)}}>{label}</div>
        ))}
      </div>
      <div style={{position: 'absolute', left: THEIRS.x, top: THEIRS.y, transform: `scale(${S})`, transformOrigin: '0 0'}}>
        <SectionLabel x={0} y={-56} text="CLAUDE CODE PROJECTS" u={ramp(t, projects, projects + 0.4)} />
        <ProjectsTree u={ramp(t, projects + 0.1, projects + 0.6)} />
      </div>
      {/* Part for part: you to you, the director to the coordinator, sessions to threads. */}
      {([[105, 200], [350, 210], [756, 150]] as [number, number][]).map(([x, y], k) => (
        <Wire key={k} pts={[[OURS.x + x * S, OURS.y + y * S], [OURS.x + x * S, OURS.y + 360], [THEIRS.x + x * S, OURS.y + 360], [THEIRS.x + x * S, THEIRS.y + y * S]]}
          draw={map(k)} dash="4 8" width={2} radius={10} opacity={map(k)} />
      ))}
    </AbsoluteFill>
  );
};
const PROJECTS_END = {go: 0, projects: 1, coordinator: 2, pieces: 3};
export const ProjectsEnd = () => <Projects t={999} ev={PROJECTS_END} scene={{id: 'S9', title: ''}} />;

/** S10: two patterns (Geoff's lines, Oct 12). The director's trail through the weeks; then two circles, director
 *  agents and shared agents; inside the first, task agents pass artifacts and only review and conflict calls rise to the
 *  user; inside the second, people gather round one shared agent; then the circles slide together and the overlap is a
 *  team of people sharing one director over many agents. */
const DIR: Box = {x: 770, y: 520, w: 380, h: 150};
const R = 270;
const circleAt = (k: 0 | 1, merge: number) => ({x: lerp(k === 0 ? 640 : 1280, k === 0 ? 840 : 1080, merge), y: 590});

export const NextUp = ({t, ev}: SceneProps) => {
  const go = ev.go ?? 0.4, at = (w: string) => ev[w] ?? 1e9;
  const leave = ramp(t, go, go + 0.5);
  const trail = ramp(t, go + 0.3, at('two') - 0.3), trailOut = ramp(t, at('two') - 0.3, at('two') + 0.3);
  const circles = spring(t, at('two'), 6, 0.9);
  const merge = spring(t, at('combine'), 4.5, 0.95);
  const team = ramp(t, at('combine') + 0.8, at('combine') + 1.6);
  const c0 = circleAt(0, merge), c1 = circleAt(1, merge);
  const art = (k: number) => (t - at('artifacts') - 0.35 * k) / 0.7;
  const rise = (k: number) => spring(t, at('surface') + 0.3 * k, 7, 0.85);
  const people = (k: number) => spring(t, at('shared') + 0.25 * k, 8, 0.85);
  const inner = 1 - ramp(t, at('combine') + 0.2, at('combine') + 0.8);
  const agentsAround = (c: {x: number; y: number}, n: number, r: number) => Array.from({length: n}, (_, k) => {
    const a = -Math.PI / 2 + (k + 0.5) * (2 * Math.PI / n);
    return {x: c.x + r * Math.cos(a), y: c.y + r * Math.sin(a)};
  });
  const left = agentsAround(c0, 5, 170), right = agentsAround(c1, 4, 175);
  const circle = (c: {x: number; y: number}, label: string, u: number) => (
    <>
      <div style={{position: 'absolute', left: c.x - R * u, top: c.y - R * u, width: 2 * R * u, height: 2 * R * u, borderRadius: R, boxSizing: 'border-box',
        border: `2.5px solid ${L.text}`, background: 'rgba(255,255,255,0.55)'}} />
      <div style={{position: 'absolute', left: c.x - 200, top: c.y - R - 46, width: 400, textAlign: 'center', fontFamily: ui, fontSize: 24, fontWeight: 700,
        color: L.text, opacity: ramp(u, 0.6, 1)}}>{label}</div>
    </>
  );
  const dot = (p: {x: number; y: number}, key: string, u: number, label?: string) => (
    <div key={key} style={{position: 'absolute', left: p.x - 34, top: p.y - 22, width: 68, height: 44, boxSizing: 'border-box', borderRadius: 10, background: L.pane,
      border: `2px solid ${L.rule}`, fontFamily: ui, fontSize: 13, display: 'flex', alignItems: 'center', justifyContent: 'center', color: L.text2, opacity: u}}>{label ?? 'agent'}</div>
  );
  const person = (p: {x: number; y: number}, key: string, u: number) => (
    <div key={key} style={{position: 'absolute', left: p.x - 46, top: p.y - 24, width: 92, height: 48, boxSizing: 'border-box', borderRadius: 24, background: L.chatYou,
      fontFamily: ui, fontSize: 15, fontWeight: 600, display: 'flex', alignItems: 'center', justifyContent: 'center', color: L.text, opacity: Math.min(1, u),
      transform: `scale(${0.85 + 0.15 * Math.min(1, u)})`}}>person</div>
  );
  return (
    <AbsoluteFill>
      <PaperGround />
      <div style={{position: 'absolute', inset: 0, opacity: 1 - leave}}><LevelsEnd /></div>
      <Heading title="What's next" sub="Two patterns, and what they might do together." u={ramp(t, go + 0.3, go + 0.8)} />

      {/* Line 1: a director that keeps its job for weeks: its trail back through them. */}
      <div style={{position: 'absolute', inset: 0, opacity: 1 - trailOut}}>
        <Wire pts={[[DIR.x - 2, DIR.y + DIR.h / 2], [160, DIR.y + DIR.h / 2]]} draw={trail} color={L.text2} width={3} />
        {[1, 2, 3, 4, 5, 6].map((w) => {
          const x = DIR.x - 100 * w, u = ramp(trail, 1 - (w - 0.5) / 6.5, 1 - (w - 1) / 6.5 + 0.02);
          return (
            <React.Fragment key={w}>
              <div style={{position: 'absolute', left: x - 7, top: DIR.y + DIR.h / 2 - 7, width: 14, height: 14, borderRadius: 7, background: L.text, opacity: u}} />
              <div style={{position: 'absolute', left: x - 40, top: DIR.y + DIR.h / 2 + 16, width: 80, textAlign: 'center', fontFamily: mono, fontSize: 16, color: L.text2, opacity: u}}>week {7 - w}</div>
            </React.Fragment>
          );
        })}
        <DirectorCard box={DIR} sub="keeps its job for weeks" u={ramp(t, go + 0.2, go + 0.6)}><Meter fill={0.2} /></DirectorCard>
      </div>

      {/* Line 2 on: two circles. */}
      {circles > 0.01 && (
        <>
          {circle(c0, 'Director agents', Math.min(1, circles))}
          {circle(c1, 'Shared agents', Math.min(1, circles))}
          <div style={{position: 'absolute', inset: 0, opacity: inner}}>
            {/* Inside the first: a director, task agents passing artifacts, only review and conflict rising to you. */}
            <div style={{position: 'absolute', left: c0.x - 70, top: c0.y - 28, width: 140, height: 56, borderRadius: 10, background: C.console, color: C.consoleText,
              fontFamily: mono, fontSize: 18, display: 'flex', alignItems: 'center', justifyContent: 'center', opacity: ramp(t, at('two') + 0.4, at('two') + 0.8)}}>director</div>
            {left.map((p, k) => dot(p, `a${k}`, ramp(t, at('two') + 0.5 + 0.1 * k, at('two') + 0.9 + 0.1 * k)))}
            {left.map((p, k) => {
              const q = left[(k + 1) % left.length], u = art(k);
              if (u <= 0 || u >= 1) return null;
              return <div key={`d${k}`} style={{position: 'absolute', left: lerp(p.x, q.x, u) - 9, top: lerp(p.y, q.y, u) - 11, width: 18, height: 22, borderRadius: 3,
                background: L.pane, border: `2px solid ${L.text}`}} />;
            })}
            {['review', 'conflict'].map((w, k) => {
              const u = rise(k);
              if (u <= 0.01) return null;
              return <div key={w} style={{position: 'absolute', left: c0.x - 140 + k * 150, top: lerp(c0.y - 120, c0.y - R + 24, Math.min(1, u)), padding: '3px 12px', borderRadius: 9,
                background: L.needsYou, color: L.onNeedsYou, fontFamily: ui, fontSize: 18, fontWeight: 600, opacity: Math.min(1, u)}}>{w}</div>;
            })}
            {/* Inside the second: people around one shared agent. */}
            <div style={{position: 'absolute', left: c1.x - 75, top: c1.y - 28, width: 150, height: 56, borderRadius: 10, background: C.console, color: C.consoleText,
              fontFamily: mono, fontSize: 17, display: 'flex', alignItems: 'center', justifyContent: 'center', opacity: ramp(t, at('shared'), at('shared') + 0.4)}}>shared agent</div>
            {right.map((p, k) => person(p, `p${k}`, people(k)))}
          </div>
          {/* Line 5: the overlap: a team of people, one director, many agents. */}
          <div style={{position: 'absolute', inset: 0, opacity: team}}>
            {[-130, 0, 130].map((dx, k) => person({x: 960 + dx, y: 430}, `t${k}`, 1))}
            {[-130, 0, 130].map((dx, k) => <Wire key={`tw${k}`} pts={[[960 + dx, 454], [960 + dx, 500], [960, 500], [960, 540]]} width={2} radius={8} />)}
            <div style={{position: 'absolute', left: 960 - 80, top: 542, width: 160, height: 56, borderRadius: 10, background: C.console, color: C.consoleText, fontFamily: mono,
              fontSize: 18, display: 'flex', alignItems: 'center', justifyContent: 'center'}}>director</div>
            {[-180, -90, 0, 90, 180].map((dx, k) => (
              <React.Fragment key={`ta${k}`}>
                <Wire pts={[[960, 600], [960, 640], [960 + dx, 640], [960 + dx, 676]]} width={2} radius={8} />
                {dot({x: 960 + dx, y: 698}, `tg${k}`, 1)}
              </React.Fragment>
            ))}
          </div>
        </>
      )}
    </AbsoluteFill>
  );
};
const NEXT_END = {go: 0, two: 1, artifacts: 2, surface: 2.5, shared: 3, combine: 4};
export const NextEnd = () => <NextUp t={999} ev={NEXT_END} scene={{id: 'S10', title: ''}} />;

/** S11: the first prompt again, and a QR code to the gist. */
const CARD: Box = {x: 144, y: 280, w: 900, h: 480};
const Q = qr.rows.length, MOD = 12, QX = 1300, QY = 270;

export const StartHere = ({t, ev}: SceneProps) => {
  const go = ev.go ?? 0.4, prompt = ev.prompt ?? go + 1, gist = ev.gist ?? prompt + 3;
  const leave = ramp(t, go, go + 0.5);
  const card = spring(t, prompt - 0.4, 6, 0.95);
  const draw = (r: number, c: number) => ramp(t, gist + (r + c) * 0.018, gist + (r + c) * 0.018 + 0.2);
  return (
    <AbsoluteFill>
      <PaperGround />
      <div style={{position: 'absolute', inset: 0, opacity: 1 - leave}}><NextEnd /></div>
      <Heading title="Start with a prompt" sub="No skill needed." u={ramp(t, go + 0.3, go + 0.8)} />
      <div style={{position: 'absolute', left: CARD.x, top: lerp(CARD.y + 30, CARD.y, card), width: CARD.w, height: CARD.h, background: C.console, borderRadius: 12,
        opacity: Math.min(1, card * 1.3), padding: '40px 48px', boxSizing: 'border-box', fontFamily: mono}}>
        <div style={{fontSize: 20, lineHeight: '30px', color: C.consoleText2}}>claude  ·  Oct 5, 10:08</div>
        <div style={{marginTop: 24, fontSize: 30, lineHeight: '46px', color: C.consoleText, whiteSpace: 'pre-wrap'}}>
          <span style={{color: C.consoleText2}}>{'> '}</span>{PROMPT_A}{PROMPT_B}
        </div>
      </div>
      <svg width={Q * MOD} height={Q * MOD} style={{position: 'absolute', left: QX, top: QY}}>
        {qr.rows.map((row: string, r: number) => [...row].map((bit, c) => bit === '1' && (
          <rect key={`${r}-${c}`} x={c * MOD} y={r * MOD} width={MOD} height={MOD} fill={L.text} opacity={draw(r, c)} />
        )))}
      </svg>
      <div style={{position: 'absolute', left: QX, top: QY + Q * MOD + 24, width: Q * MOD, fontFamily: ui, color: L.text, opacity: ramp(t, gist + 1.2, gist + 1.6)}}>
        <div style={{fontSize: 24, lineHeight: '32px', fontWeight: 600}}>The prompt, as a gist</div>
        <div style={{fontFamily: mono, fontSize: 18, lineHeight: '28px', color: L.text2}}>gist.github.com/dudgeon</div>
      </div>
    </AbsoluteFill>
  );
};
