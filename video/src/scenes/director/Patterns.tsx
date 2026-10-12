import React from 'react';
import {AbsoluteFill} from 'remotion';
import type {SceneProps} from '../registry';
import {PaperGround} from '../../lib/Paper';
import {C, Glyph, Heading, L, lerp, mono, ramp, SectionLabel, spring, ui, Wire} from './kit';
import {DoneEnd} from './Done';

// S8 · Patterns for your setup. The tree, small, as it runs on the latest Claude Code; then four copies of it, one per
// constraint, each redrawn to show what changes: on an older version the reports travel as files and workers run as
// one-shot jobs; without Remote Control everything is followed in one app; without a page for buttons the questions come
// in the chat; on a pinned work laptop the director still runs and only the reporting changes.

type Variant = 'base' | 'files' | 'oneApp' | 'chat' | 'laptop';
const CW = 760, CH = 300;

/** The small tree in its own 760 × 300 box. */
export const MiniTree = ({variant, u = 1}: {variant: Variant; u?: number}) => {
  const files = variant === 'files' || variant === 'laptop';
  const worker = (i: number) => ({x: 520, y: 40 + i * 88, w: 220, h: 48});
  return (
    <div style={{position: 'absolute', left: 0, top: 0, width: CW, height: CH, opacity: u, fontFamily: ui}}>
      {variant === 'laptop' && (
        <>
          <div style={{position: 'absolute', left: -14, top: -12, width: CW + 28, height: CH + 6, boxSizing: 'border-box', borderRadius: 16, border: `4px solid ${L.text}`}} />
          <div style={{position: 'absolute', left: -60, top: CH - 6, width: CW + 120, height: 16, borderRadius: '0 0 12px 12px', background: L.text}} />
          <div style={{position: 'absolute', left: 14, top: 8, padding: '0 8px', borderRadius: 6, background: L.selected, fontFamily: mono, fontSize: 15, lineHeight: '22px', color: L.text}}>pinned, months behind</div>
        </>
      )}
      {variant === 'oneApp' && (
        <div style={{position: 'absolute', left: -12, top: -10, width: CW + 24, height: CH + 20, boxSizing: 'border-box', borderRadius: 12, border: `2px dashed ${L.controlEdge}`}}>
          <div style={{position: 'absolute', left: 10, top: 8, display: 'flex', gap: 6}}>{[0, 1, 2].map((i) => <div key={i} style={{width: 10, height: 10, borderRadius: 5, background: L.rule}} />)}</div>
        </div>
      )}
      {/* You ← director, and the director → each worker. */}
      <Wire pts={[[250, 150], [192, 150]]} head width={2.5} />
      {[0, 1, 2].map((i) => {
        const w = worker(i), cy = w.y + w.h / 2;
        return files
          ? <Wire key={i} pts={[[w.x - 2, cy], [470, cy], [470, 150], [452, 150]]} head width={2.5} dash="6 6" radius={8} />
          : <Wire key={i} pts={[[452, 150], [490, 150], [490, cy], [w.x - 2, cy]]} head width={2.5} radius={8} />;
      })}
      {files && (
        <div style={{position: 'absolute', left: 440, top: 236, padding: '2px 8px', borderRadius: 6, border: `1.5px solid ${L.controlEdge}`, background: L.pane,
          fontFamily: mono, fontSize: 15, lineHeight: '22px', color: L.text2}}>reports/*.md</div>
      )}
      <div style={{position: 'absolute', left: 20, top: 110, width: 170, height: 80, boxSizing: 'border-box', background: L.pane, border: `2px solid ${L.rule}`, borderRadius: 10,
        padding: '0 16px', display: 'flex', flexDirection: 'column', justifyContent: 'center', color: L.text}}>
        <b style={{fontSize: 22, lineHeight: '28px'}}>You</b><span style={{fontSize: 16, lineHeight: '22px', color: L.text2}}>the PM</span>
      </div>
      <div style={{position: 'absolute', left: 250, top: 100, width: 200, height: 100, boxSizing: 'border-box', background: C.console, borderRadius: 10, padding: '0 18px',
        display: 'flex', flexDirection: 'column', justifyContent: 'center', fontFamily: mono, color: C.consoleText}}>
        <span style={{fontSize: 20, lineHeight: '28px'}}>director</span>
      </div>
      {[0, 1, 2].map((i) => {
        const w = worker(i);
        return (
          <div key={i} style={{position: 'absolute', left: w.x, top: w.y, width: w.w, height: w.h, boxSizing: 'border-box', background: L.pane, border: `2px solid ${L.rule}`,
            borderRadius: 8, padding: '0 14px', display: 'flex', alignItems: 'center', gap: 10, fontSize: 18, color: L.text}}>
            <Glyph state="working" size={16} /><span style={{fontFamily: files ? mono : ui, fontSize: files ? 16 : 18}}>{files ? 'claude -p' : 'session'}</span>
          </div>
        );
      })}
      {/* How decisions reach you: buttons on a phone page, or questions in the chat. */}
      {variant !== 'chat' && variant !== 'oneApp' && (
        <div style={{position: 'absolute', left: 64, top: 2, width: 44, height: 78, boxSizing: 'border-box', borderRadius: 10, border: `3px solid ${L.text}`, background: L.pane}}>
          <div style={{margin: '18px 6px 0', height: 10, borderRadius: 3, background: L.text}} />
          <div style={{margin: '5px 6px 0', height: 10, borderRadius: 3, border: `1.5px solid ${L.controlEdge}`}} />
        </div>
      )}
      {variant === 'chat' && (
        <div style={{position: 'absolute', left: 20, top: 12, width: 220, padding: '8px 12px', boxSizing: 'border-box', borderRadius: 12, background: L.chatYou,
          fontFamily: mono, fontSize: 15, lineHeight: '22px', color: L.text}}>Release 0.2.8?<br />1 · Ship it  2 · Hold</div>
      )}
    </div>
  );
};

const CELLS: {variant: Variant; title: string; word: string}[] = [
  {variant: 'files', title: 'AN OLDER CLAUDE CODE', word: 'older'},
  {variant: 'laptop', title: 'A PINNED WORK LAPTOP', word: 'laptop'},
  {variant: 'oneApp', title: 'NO REMOTE CONTROL', word: 'Remote'},
  {variant: 'chat', title: 'NO PAGE FOR BUTTONS', word: 'page'},
];
const cellAt = (k: number) => ({x: 144 + (k % 2) * (CW + 112), y: 290 + Math.floor(k / 2) * (CH + 96)});

export const Patterns = ({t, ev}: SceneProps) => {
  const go = ev.go ?? 0.4;
  const leave = ramp(t, go, go + 0.5);
  const at = (w: string) => ev[w] ?? 1e9;
  // The baseline tree sits large in the middle, then gives way to the grid as the first constraint is named.
  const split = spring(t, at('older') - 0.3, 6, 0.95);
  const active = CELLS.reduce((a, c, k) => (t >= at(c.word) ? k : a), -1);

  return (
    <AbsoluteFill>
      <PaperGround />
      <div style={{position: 'absolute', inset: 0, opacity: 1 - leave}}><DoneEnd /></div>
      <Heading title="Patterns" sub="What changes with your setup." u={ramp(t, go + 0.3, go + 0.8)} />

      {/* The baseline: the latest Claude Code, everything available. */}
      <div style={{position: 'absolute', left: lerp(580, 580, split), top: 380, transformOrigin: '0 0', transform: `scale(${lerp(1.0, 0.6, split)})`,
        opacity: ramp(t, go + 0.2, go + 0.7) * (1 - ramp(t, at('older') - 0.1, at('older') + 0.4))}}>
        <SectionLabel x={0} y={-56} text="THE LATEST CLAUDE CODE" />
        <MiniTree variant="base" />
      </div>

      {CELLS.map((c, k) => {
        const p = cellAt(k), u = spring(t, at(c.word) - 0.2, 8, 0.9);
        if (u <= 0.001) return null;
        const dim = active === k ? 1 : 0.42;
        return (
          <div key={c.title} style={{position: 'absolute', left: p.x, top: p.y, transformOrigin: '0 0', transform: `scale(${lerp(0.94, 1, Math.min(1, u))})`,
            opacity: Math.min(1, u) * dim}}>
            <SectionLabel x={0} y={-52} text={c.title} />
            <MiniTree variant={c.variant} />
          </div>
        );
      })}
    </AbsoluteFill>
  );
};

/** S8's last picture, for the scene after it to open on. */
const END_EV = {go: 0, older: 1, laptop: 2, Remote: 3, page: 4};
export const PatternsEnd = () => <Patterns t={999} ev={END_EV} scene={{id: 'S8', title: ''}} />;
