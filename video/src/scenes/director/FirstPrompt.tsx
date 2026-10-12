import React from 'react';
import {AbsoluteFill} from 'remotion';
import type {SceneProps} from '../registry';
import {PaperGround} from '../../lib/Paper';
import {C, centre, DirectorCard, Heading, L, mixBox, mono, ramp, SectionLabel, SessionRow, spring, Wire, YouCard, type Box, type State} from './kit';
import {BUS_X, ORDER, PANEL, panelRow, PROMPT_A, PROMPT_B, RING_YOU, ringRow, SESSIONS, SURVEY, TREE_DIRECTOR, TREE_YOU} from './board';

// S2 · A simple prompt. It opens on S1's last picture: you in the middle of ten sessions, every line orange. One more
// session opens as a console and the first prompt types itself, verbatim, in time with the voice. On Return the console
// becomes the director, the ring settles into the tree of style frame B (DL-180), and the director's first survey runs
// down the sessions. One line reaches you now.

const PROMPT_BOX: Box = {x: 300, y: 300, w: 1320, h: 460};
const slot = (i: number) => ORDER.indexOf(i);

export const FirstPrompt = ({t, ev}: SceneProps) => {
  const open = ev.session ?? 1.0;
  const a0 = ev.typeA0 ?? open + 1, a1 = ev.typeA1 ?? a0 + 6;
  const b0 = ev.typeB0 ?? a1 + 0.5, submit = ev.submit ?? b0 + 2;
  const scan = ev.stood ?? submit + 1.6;

  // The console: it appears on "session", grows to the prompt card, and on Return becomes the director.
  const appear = spring(t, open, 8, 0.86);
  const settle = spring(t, submit, 5.5, 0.95);
  const small: Box = {x: 960 - 60, y: 540 - 30, w: 120, h: 60};
  const consoleBox = settle > 0 ? mixBox(PROMPT_BOX, TREE_DIRECTOR, settle) : mixBox(small, PROMPT_BOX, appear);
  const typedA = PROMPT_A.slice(0, Math.round(PROMPT_A.length * ramp(t, a0, a1)));
  const typedB = PROMPT_B.slice(0, Math.round(PROMPT_B.length * ramp(t, b0, submit - 0.25)));
  const caret = Math.floor(t * 2) % 2 === 0 && t < submit;
  const promptU = 1 - ramp(t, submit, submit + 0.25);
  const dirU = ramp(t, submit + 0.35, submit + 0.7);

  // The ring: dimmed while the prompt types, then each row flies to its place in the panel.
  const dim = 0.28;
  const rowU = t < submit ? 1 - (1 - dim) * ramp(t, open, open + 0.6) : dim + (1 - dim) * ramp(t, submit, submit + 0.8);
  const you = mixBox(RING_YOU, TREE_YOU, settle);
  const fly = (i: number) => spring(t, submit + 0.05 * slot(i), 5.5, 0.92);
  const rowBox = (i: number) => mixBox(ringRow(i), panelRow(slot(i)), fly(i));
  const oldWires = 1 - ramp(t, submit, submit + 0.35);

  // The survey: a highlight runs down the panel and each session takes the state the director found.
  const scanAt = (k: number) => scan + 0.16 * k;
  const stateOf = (i: number): State => (t >= scanAt(slot(i)) ? SURVEY[slot(i)].state : 'needs');
  const rightOf = (i: number) => (t >= scanAt(slot(i)) ? SURVEY[slot(i)].right : undefined);
  const focusOf = (i: number) => { const d = t - scanAt(slot(i)); return d < 0 ? 0 : Math.max(0, 1 - d / 0.5) * 0.9; };
  const surveyed = SURVEY.filter((_, k) => t >= scanAt(k) && SURVEY[k].state === 'needs').length;
  const chip = t < scan ? 10 : surveyed;

  // The tree's lines: you ← director, director → each session.
  const yc = centre(you), dc = centre(TREE_DIRECTOR);
  const upDraw = ramp(t, submit + 0.6, submit + 1.0);
  const busDraw = ramp(t, submit + 0.8, submit + 1.3);
  const panelU = ramp(t, submit + 0.3, submit + 0.8);

  return (
    <AbsoluteFill>
      <PaperGround />
      <Heading title="The problem" sub="Every session needs you." u={1 - ramp(t, open, open + 0.4)} />
      <Heading title="A simple prompt" sub="One session manages the others." u={ramp(t, submit + 0.6, submit + 1.1)} />

      {/* The panel the sessions settle into, under everything else. */}
      <div style={{position: 'absolute', left: PANEL.x, top: PANEL.y, width: PANEL.w, height: PANEL.h, boxSizing: 'border-box', background: L.pane,
        border: `2px solid ${L.rule}`, borderRadius: 12, opacity: panelU}} />
      <SectionLabel x={PANEL.x + 32} y={PANEL.y + 24} text={`SESSIONS · ${SESSIONS.length}`} u={panelU} />

      {/* S1's lines, retracting into you on Return. */}
      {SESSIONS.map((_, i) => <Wire key={`w${i}`} pts={[centre(rowBox(i)), centre(you)]} draw={oldWires} color={L.needsYou} opacity={rowU} />)}

      {/* The tree's lines. */}
      <Wire pts={[[TREE_DIRECTOR.x, dc[1]], [TREE_YOU.x + TREE_YOU.w + 1, yc[1]]]} draw={upDraw} head />
      <Wire pts={[[TREE_DIRECTOR.x + TREE_DIRECTOR.w, dc[1]], [BUS_X, dc[1]]]} draw={busDraw} />
      <Wire pts={[[BUS_X, centre(panelRow(0))[1]], [BUS_X, centre(panelRow(SESSIONS.length - 1))[1]]]} draw={ramp(t, submit + 1.0, submit + 1.4)} />
      {SESSIONS.map((_, k) => (
        <Wire key={`b${k}`} pts={[[BUS_X, centre(panelRow(k))[1]], [PANEL.x - 2, centre(panelRow(k))[1]]]} draw={ramp(t, submit + 1.2 + 0.03 * k, submit + 1.5 + 0.03 * k)} head width={2.5} />
      ))}

      {SESSIONS.map((name, i) => (
        <SessionRow key={name} box={rowBox(i)} name={name} state={stateOf(i)} right={rightOf(i)} u={rowU} flush={fly(i) > 0.6} focus={focusOf(i)} />
      ))}

      <YouCard box={you} chip={chip} />

      {/* The console: the prompt as it was typed, then the director. */}
      {appear > 0.01 && (
        <div style={{position: 'absolute', left: consoleBox.x, top: consoleBox.y, width: consoleBox.w, height: consoleBox.h, background: C.console,
          borderRadius: 12, overflow: 'hidden', opacity: Math.min(1, appear * 1.4)}}>
          <div style={{position: 'absolute', left: 48, top: 40, width: PROMPT_BOX.w - 96, opacity: promptU, fontFamily: mono}}>
            <div style={{fontSize: 20, lineHeight: '30px', color: C.consoleText2}}>claude  ·  Oct 5, 10:08</div>
            <div style={{marginTop: 24, fontSize: 34, lineHeight: '52px', color: C.consoleText, whiteSpace: 'pre-wrap'}}>
              <span style={{color: C.consoleText2}}>{'> '}</span>{typedA}{typedB}
              <span style={{display: 'inline-block', width: 18, height: 38, marginLeft: 2, verticalAlign: -6, background: caret ? C.consoleText : 'transparent'}} />
            </div>
          </div>
          <div style={{position: 'absolute', inset: 0, opacity: dirU}}>
            <DirectorCard box={{x: 0, y: 0, w: TREE_DIRECTOR.w, h: TREE_DIRECTOR.h}} sub="engineering manager · at prompt"
              needs={t >= scan + 0.16 * SESSIONS.length ? 2 : 0} />
          </div>
        </div>
      )}
    </AbsoluteFill>
  );
};
