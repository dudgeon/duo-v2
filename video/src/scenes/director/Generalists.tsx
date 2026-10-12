import React from 'react';
import {AbsoluteFill} from 'remotion';
import type {SceneProps} from '../registry';
import {PaperGround} from '../../lib/Paper';
import {centre, DirectorCard, Heading, L, lerp, Meter, mono, Pulse, ramp, SectionLabel, SessionRow, spring, ui, YouCard, type Box} from './kit';
import {slotNames} from './Tree';
import {WhyEnd, WHY_DIR, WHY_WORKERS, whyWorker, WHY_YOU} from './WhyItWorks';

// S6 · Generalists. It opens on S5's last picture and keeps the director and its four workers. On "persona", each
// worker gets a specialist's badge; on "didn't" the badges fall away. Then briefs go out, one per task the voice names
// (a design study, a bug hunt, a release check, a research question), and each lands on a different worker in turn.
// The workers never change shape or name: the brief is what changes.

const TASKS: [string, string][] = [['design', 'design study'], ['bug', 'bug hunt'], ['release', 'release check'], ['research', 'research question']];
const BADGES = ['designer', 'tester', 'release engineer', 'researcher'];
/** Each task goes to a worker other than the one its badge would have picked. */
const TAKER = [2, 0, 3, 1];

export const Generalists = ({t, ev}: SceneProps) => {
  const go = ev.go ?? 0.4, persona = ev.persona ?? go + 2, didnt = ev.didnt ?? persona + 1;
  const leave = ramp(t, go, go + 0.5);
  const badgeOn = (i: number) => spring(t, persona + 0.12 * i, 10, 0.8);
  const badgeOff = (i: number) => ramp(t, didnt + 0.08 * i, didnt + 0.4 + 0.08 * i);
  const at = (w: string) => ev[w] ?? 1e9;

  return (
    <AbsoluteFill>
      <PaperGround />
      <div style={{position: 'absolute', inset: 0, opacity: 1 - leave}}><WhyEnd /></div>
      <Heading title="Generalists" sub="The brief changes, not the worker." u={ramp(t, go + 0.3, go + 0.8)} />
      <div style={{position: 'absolute', inset: 0, opacity: leave}}>
        <SectionLabel x={WHY_DIR.x} y={250} text="A DIRECTOR" />
        <DirectorCard box={WHY_DIR} sub="writes the brief"><Meter fill={0.2} /></DirectorCard>
        <YouCard box={WHY_YOU} chip={0} />
        {WHY_WORKERS.map((k, i) => {
          const b = whyWorker(i);
          return <SessionRow key={k} box={b} name={slotNames[k]} state="working" />;
        })}
      </div>

      {/* The badges a specialist setup would give them, falling away. */}
      {WHY_WORKERS.map((_, i) => {
        const b = whyWorker(i), on = badgeOn(i), off = badgeOff(i);
        if (on <= 0.01 || off >= 0.99) return null;
        return (
          <div key={`b${i}`} style={{position: 'absolute', left: b.x - 168, top: b.y + 14 + off * 40, width: 150, textAlign: 'right', fontFamily: mono,
            fontSize: 18, lineHeight: '36px', color: L.text2, opacity: Math.min(1, on) * (1 - off), transform: `rotate(${off * -8}deg)`}}>
            <span style={{padding: '4px 10px', borderRadius: 8, border: `1.5px dashed ${L.controlEdge}`, textDecoration: off > 0.2 ? 'line-through' : 'none'}}>{BADGES[i]}</span>
          </div>
        );
      })}

      {/* The briefs: each flies from the director to a worker and stays on it. */}
      {TASKS.map(([word, label], j) => {
        const w = TAKER[j], b = whyWorker(w), from = centre(WHY_DIR), to: [number, number] = [b.x + b.w - 90, b.y + b.h / 2];
        const fly = spring(t, at(word), 6, 0.92);
        if (fly <= 0.001) return null;
        const x = lerp(from[0], to[0], fly), y = lerp(from[1], to[1], fly);
        return (
          <React.Fragment key={word}>
            <Pulse a={[WHY_DIR.x + WHY_DIR.w, from[1]]} b={[b.x, b.y + b.h / 2]} u={(t - at(word)) / 0.5} color={L.text} r={6} />
            <div style={{position: 'absolute', left: x, top: y, transform: 'translate(-50%, -50%)', padding: '4px 12px', borderRadius: 8, background: L.selected,
              fontFamily: ui, fontSize: 20, lineHeight: '28px', fontWeight: 600, color: L.text, whiteSpace: 'nowrap', opacity: Math.min(1, fly * 2)}}>{label}</div>
          </React.Fragment>
        );
      })}
    </AbsoluteFill>
  );
};

/** S6's last picture, for the scene after it to open on. */
const END_EV = {go: 0, persona: 1, didnt: 2, design: 3, bug: 3.5, release: 4, research: 4.5};
export const GeneralistsEnd = () => <Generalists t={999} ev={END_EV} scene={{id: 'S6', title: ''}} />;
