import React from 'react';
import {AbsoluteFill} from 'remotion';
import type {SceneProps} from '../registry';
import {PaperGround} from '../../lib/Paper';
import {Heading, L, mono, ramp, spring, ui, Wire, YouCard} from './kit';
import {AXIS_X0, AXIS_X1, dayX} from './Additions';
import {GeneralistsEnd} from './Generalists';

// S7 · What got done. S6's picture gives way to the first week's timeline (the same days as S4's). Every merge into
// main is one cell, stacked over its day as the voice says the count; every release is a tag under its day; a few of
// the things that shipped are named over the days they landed. All real: git log --merges and gh release list,
// counted from the first prompt (Oct 5, 10:08) in local time.

const AXIS = 860;
export const MERGES: [number, number][] = [[5, 6], [6, 46], [7, 58], [8, 13], [9, 20], [10, 8], [11, 16], [12, 20]];
export const RELEASES: Record<number, string[]> = {5: ['0.1.7'], 6: ['0.1.8', '0.1.9', '0.2.0', '0.2.1', '0.2.2'], 7: ['0.2.3', '0.2.4', '0.2.5', '0.2.6', '0.2.7'],
  8: ['0.2.8'], 9: ['0.2.9', '0.2.10'], 10: ['0.2.11']};
/** A few things that shipped, on the day they merged (decisions.md, findings.md). */
const FEATURES: [string, number][] = [['Chat mode', 6], ['Freeze fix', 7.6], ['Word viewer', 8.6], ['Intro film', 11], ['Codebase review', 12]];
const CELL = 18, GAP = 5, PER = 6;

export const Done = ({t, ev}: SceneProps) => {
  const go = ev.go ?? 0.4, merges = ev.merges ?? go + 3, releases = ev.releases ?? merges - 1, feat = ev.feat ?? merges + 1.5;
  const sessions = ev.sessions, decisions = ev.decisions;
  const leave = ramp(t, go, go + 0.5);
  const axis = ramp(t, go + 0.3, go + 1.0);

  return (
    <AbsoluteFill>
      <PaperGround />
      <div style={{position: 'absolute', inset: 0, opacity: 1 - leave}}><GeneralistsEnd /></div>
      <Heading title="What got done" sub="The first week with a director, Oct 5 to Oct 12." u={ramp(t, go + 0.3, go + 0.8)} />

      <Wire pts={[[AXIS_X0, AXIS], [AXIS_X1, AXIS]]} draw={axis} color={L.text} head />
      {MERGES.map(([d, n]) => {
        const x0 = dayX(d) - (PER * CELL + (PER - 1) * GAP) / 2;
        return (
          <React.Fragment key={d}>
            <div style={{position: 'absolute', left: dayX(d) - 40, top: AXIS + 14, width: 80, textAlign: 'center', fontFamily: mono, fontSize: 18,
              lineHeight: '24px', color: L.text2, opacity: axis}}>Oct {d}</div>
            {Array.from({length: n}, (_, k) => {
              const u = ramp(t, merges + (d - 5) * 0.14 + k * 0.012, merges + (d - 5) * 0.14 + k * 0.012 + 0.2);
              if (u <= 0) return null;
              const col = k % PER, row = Math.floor(k / PER);
              return <div key={k} style={{position: 'absolute', left: x0 + col * (CELL + GAP), top: AXIS - 16 - (row + 1) * (CELL + GAP) + (1 - u) * 8,
                width: CELL, height: CELL, borderRadius: 4, background: '#9DB38A', opacity: u}} />;
            })}
            <div style={{position: 'absolute', left: dayX(d) - 70, top: AXIS + 48, width: 140, display: 'flex', flexWrap: 'wrap', justifyContent: 'center', gap: 6}}>
              {(RELEASES[d] ?? []).map((r, j) => (
                <span key={r} style={{padding: '1px 8px', borderRadius: 6, background: L.chatYou, fontFamily: mono, fontSize: 16, lineHeight: '24px', color: L.text,
                  opacity: ramp(t, releases + (d - 5) * 0.1 + j * 0.05, releases + (d - 5) * 0.1 + j * 0.05 + 0.25)}}>{r}</span>
              ))}
            </div>
          </React.Fragment>
        );
      })}
      {FEATURES.map(([name, d], j) => {
        const u = spring(t, feat + 0.3 * j, 9, 0.85);
        const y = j % 2 === 0 ? 470 : 530;
        return (
          <React.Fragment key={name}>
            <div style={{position: 'absolute', left: dayX(d) - 1, top: y + 40, width: 2, height: 560 - y - 40 + 40, background: L.rule, opacity: Math.min(1, u)}} />
            <div style={{position: 'absolute', left: dayX(d), top: y, transform: `translate(-50%, ${(1 - Math.min(1, u)) * -14}px)`, padding: '4px 14px', borderRadius: 10,
              background: L.pane, border: `2px solid ${L.rule}`, fontFamily: ui, fontSize: 20, lineHeight: '28px', fontWeight: 600, color: L.text, whiteSpace: 'nowrap',
              opacity: Math.min(1, u * 1.4)}}>{name}</div>
          </React.Fragment>
        );
      })}

      {/* The counts, set once as the voice says each (never spinning). */}
      <div style={{position: 'absolute', left: 1240, top: 120, fontFamily: ui, color: L.text}}>
        {([['187', 'merges into main', merges], ['15', 'releases', releases], ['about 100', 'sessions did the work', sessions]] as [string, string, number | undefined][]).map(([n, what, at]) => (
          <div key={what} style={{fontSize: 30, lineHeight: '44px', opacity: at === undefined ? 0 : ramp(t, at, at + 0.35)}}>
            <b>{n}</b> <span style={{color: L.text2}}>{what}</span>
          </div>
        ))}
      </div>
      {decisions !== undefined && (
        <YouCard box={{x: 1240, y: 270, w: 340, h: 110}} label="made the decisions" u={ramp(t, decisions, decisions + 0.4)} />
      )}
    </AbsoluteFill>
  );
};

/** S7's last picture, for the scene after it to open on. */
const END_EV = {go: 0, releases: 1, merges: 2, feat: 3, sessions: 5, decisions: 6};
export const DoneEnd = () => <Done t={999} ev={END_EV} scene={{id: 'S7', title: ''}} />;
