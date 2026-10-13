import React from 'react';
import {AbsoluteFill} from 'remotion';
import type {SceneProps} from '../registry';
import {PaperGround} from '../../lib/Paper';
import {C, DirectorCard, Heading, L, lerp, Meter, mono, ramp, SectionLabel, spring, ui, Wire, YouCard, type Box} from './kit';
import {MiniTree, PatternsEnd} from './Patterns';
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

/** S10: persistent and shared. */
const DIR: Box = {x: 770, y: 560, w: 380, h: 180};
const PEOPLE: [Box, string][] = [[{x: 360, y: 250, w: 300, h: 120}, 'the PM'], [{x: 810, y: 250, w: 300, h: 120}, 'a teammate'], [{x: 1260, y: 250, w: 300, h: 120}, 'a teammate']];

export const NextUp = ({t, ev}: SceneProps) => {
  const go = ev.go ?? 0.4, persistent = ev.persistent ?? go + 1.5, weeks = ev.weeks ?? persistent + 2, shared = ev.shared ?? weeks + 1.5, several = ev.several ?? shared + 1;
  const leave = ramp(t, go, go + 0.5);
  const trail = ramp(t, persistent, weeks + 0.6);
  const person = (k: number) => (k === 0 ? ramp(t, go + 0.4, go + 0.9) : spring(t, several + 0.3 * (k - 1), 8, 0.85));
  const cy = DIR.y + DIR.h / 2;
  return (
    <AbsoluteFill>
      <PaperGround />
      <div style={{position: 'absolute', inset: 0, opacity: 1 - leave}}><ProjectsEnd /></div>
      <Heading title="What's next" sub="Agents that stay, and agents that are shared." u={ramp(t, go + 0.3, go + 0.8)} />
      {/* Persistent: the director's trail back through the weeks it has kept its job. */}
      <Wire pts={[[DIR.x - 2, cy], [160, cy]]} draw={trail} color={L.text2} width={3} />
      {[1, 2, 3, 4, 5, 6].map((w) => {
        const x = DIR.x - 100 * w;
        const u = ramp(trail, 1 - (w - 0.5) / 6.5, 1 - (w - 1) / 6.5 + 0.02);
        return (
          <React.Fragment key={w}>
            <div style={{position: 'absolute', left: x - 7, top: cy - 7, width: 14, height: 14, borderRadius: 7, background: L.text, opacity: u}} />
            <div style={{position: 'absolute', left: x - 40, top: cy + 18, width: 80, textAlign: 'center', fontFamily: mono, fontSize: 16, color: L.text2, opacity: u}}>week {7 - w}</div>
          </React.Fragment>
        );
      })}
      {/* Shared: more people on its line. */}
      {PEOPLE.map(([b, label], k) => {
        const u = Math.min(1, person(k));
        return (
          <React.Fragment key={k}>
            <Wire pts={[[b.x + b.w / 2, b.y + b.h], [b.x + b.w / 2, b.y + b.h + 50], [DIR.x + DIR.w / 2, b.y + b.h + 50], [DIR.x + DIR.w / 2, DIR.y - 2]]} draw={u} head width={2.5} radius={12} />
            <div style={{position: 'absolute', inset: 0, opacity: u}}>
              <YouCard box={b} label={label} />
            </div>
          </React.Fragment>
        );
      })}
      <DirectorCard box={DIR} sub={t < shared ? 'keeps its job for weeks' : 'shared by a team'} u={ramp(t, go + 0.2, go + 0.6)}><Meter fill={0.2} /></DirectorCard>
    </AbsoluteFill>
  );
};
const NEXT_END = {go: 0, persistent: 1, weeks: 2, shared: 3, several: 3.5};
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
