import React from 'react';
import {AbsoluteFill, Img, staticFile} from 'remotion';
import type {SceneProps} from '../registry';
import {PaperGround} from '../../lib/Paper';
import {DuoIcon} from '../../lib/DuoIcon';
import {C, centre, Glyph, Heading, L, mixBox, mono, Pulse, ramp, SessionRow, spring, ui, Wire, YouCard, type Box, type State} from './kit';
import {RING_YOU, ringRow, SESSIONS} from './board';

// S1 · The problem (script v2, Geoff's rewrite, Oct 12). Line 1: the title card builds (canvas option T1, "user" for
// "You"); its finished frame is the film's frame 0. Line 2: a Duo card, the intro's logo build beside a small capture
// of the app. Line 3: a new Claude Code session on the phone for each idea as it's named. Line 4: each session grows a
// worktree branch and lands around you on a ring; the chores pile on as they're named, each a needs-you tag, until
// you're the switchboard. Line 5: your time splits in two. The last picture is S2's first: the ring, all orange.

const at = (ev: Record<string, number>, w: string, d = 0) => (ev[w] ?? 1e9) + d;

// ————— The title card (T1) —————
const T_USER: Box = {x: 1020, y: 470, w: 188, h: 140};
const T_DIR: Box = {x: 1305, y: 470, w: 280, h: 140};
const T_ROWS: [string, State][] = [['Word viewer', 'needs'], ['Chat mode', 'review'], ['Task board', 'working'], ['Intro film', 'working'], ['Freeze fix', 'done']];
const tRow = (k: number): Box => ({x: 1676, y: 352 + k * 80, w: 220, h: 56});

/** The title card: what this film is about, with the pattern drawn small. `u` builds it; the finished card is frame 0. */
export const TitleCard = ({t, t0 = 0.2, out = 0}: {t: number; t0?: number; out?: number}) => {
  const kick = ramp(t, t0, t0 + 0.4), title = ramp(t, t0 + 0.25, t0 + 0.75), sub = ramp(t, t0 + 0.6, t0 + 1.1);
  const user = spring(t, t0 + 0.9, 9, 0.85), dir = spring(t, t0 + 1.2, 9, 0.85);
  const up = ramp(t, t0 + 1.35, t0 + 1.6), bus = ramp(t, t0 + 1.55, t0 + 1.85);
  const row = (k: number) => spring(t, t0 + 1.75 + 0.12 * k, 10, 0.85);
  const dc = centre(T_DIR);
  return (
    <div style={{position: 'absolute', inset: 0, opacity: 1 - out, transform: `translateY(${-out * 30}px)`}}>
      <div style={{position: 'absolute', left: 144, top: 330, width: 860, fontFamily: ui, color: L.text}}>
        <div style={{fontFamily: mono, fontSize: 22, lineHeight: '30px', color: L.text2, letterSpacing: 0.4, opacity: kick}}>A pattern for Claude Code</div>
        <div style={{marginTop: 18, fontSize: 96, lineHeight: '104px', fontWeight: 700, letterSpacing: -2, clipPath: `inset(0 ${100 - 100 * title}% 0 0)`}}>The director agent</div>
        <div style={{marginTop: 26, fontSize: 32, lineHeight: '44px', color: L.text2, opacity: sub, transform: `translateY(${(1 - sub) * 10}px)`}}>
          One Claude Code session briefs, checks and merges the work of the others. You give it high-level instructions, and step into the details when you want to.
        </div>
      </div>
      <Wire pts={[[T_DIR.x, dc[1]], [T_USER.x + T_USER.w + 1, dc[1]]]} draw={up} head />
      <Wire pts={[[T_DIR.x + T_DIR.w, dc[1]], [1645, dc[1]]]} draw={bus} />
      <Wire pts={[[1645, centre(tRow(0))[1]], [1645, centre(tRow(4))[1]]]} draw={bus} />
      {T_ROWS.map((_, k) => <Wire key={k} pts={[[1645, centre(tRow(k))[1]], [1675, centre(tRow(k))[1]]]} draw={row(k)} />)}
      <div style={{position: 'absolute', left: T_USER.x, top: T_USER.y, width: T_USER.w, height: T_USER.h, boxSizing: 'border-box', background: L.pane, border: `2px solid ${L.rule}`,
        borderRadius: 12, padding: '0 22px', display: 'flex', flexDirection: 'column', justifyContent: 'center', fontFamily: ui, opacity: Math.min(1, user), transform: `scale(${0.92 + 0.08 * Math.min(1, user)})`}}>
        <b style={{fontSize: 28, lineHeight: '34px'}}>user</b><span style={{fontSize: 20, lineHeight: '28px', color: L.text2}}>the PM</span>
      </div>
      <div style={{position: 'absolute', left: T_DIR.x, top: T_DIR.y, width: T_DIR.w, height: T_DIR.h, boxSizing: 'border-box', background: C.console, borderRadius: 12,
        padding: '0 26px', display: 'flex', flexDirection: 'column', justifyContent: 'center', fontFamily: mono, color: C.consoleText, opacity: Math.min(1, dir), transform: `scale(${0.92 + 0.08 * Math.min(1, dir)})`}}>
        <span style={{fontSize: 28, lineHeight: '36px'}}>director</span><span style={{fontSize: 18, lineHeight: '26px', color: C.needsYouOnConsole}}>● 2 need you</span>
      </div>
      {T_ROWS.map(([name, state], k) => (
        <div key={name} style={{position: 'absolute', inset: 0, opacity: Math.min(1, row(k))}}>
          <SessionRow box={tRow(k)} name={name} state={state} />
        </div>
      ))}
    </div>
  );
};

// ————— Line 3 and 4: the phones, then the ring —————
/** The ideas the voice names, each a new session on the phone: [session, kind, the ask]. Session names are SESSIONS'. */
const IDEAS: [number, string, string, string][] = [
  [0, 'features', 'prototype', 'Chat mode: a more readable overlay on the terminal'],
  [3, 'patterns', 'research', 'PowerPoint viewer: which renderer?'],
  [5, 'bugs', 'bug', 'Freeze on load, on the work laptop'],
];
const MORE = [1, 2, 4, 6, 7, 8, 9];
const phoneBox = (k: number): Box => ({x: 150 + k * 340, y: 260, w: 300, h: 520});
const CHORES: [string, number[], string][] = [['prompts', [0, 5], 'starting prompt'], ['rebasing', [3, 8], 'rebase'], ['review', [1, 6], 'review'], ['merging', [2, 7, 4, 9], 'merge']];

const MiniPhone = ({box, kind, ask, u}: {box: Box; kind: string; ask: string; u: number}) => (
  <div style={{position: 'absolute', left: box.x, top: box.y, width: box.w, height: box.h, boxSizing: 'border-box', borderRadius: 38, border: `7px solid ${L.text}`, background: L.pane,
    overflow: 'hidden', opacity: Math.min(1, u * 1.4), transform: `translateY(${(1 - Math.min(1, u)) * 30}px)`, fontFamily: ui}}>
    <div style={{position: 'absolute', left: '50%', top: 10, width: 76, height: 20, marginLeft: -38, borderRadius: 10, background: L.text}} />
    <div style={{position: 'absolute', left: 16, right: 16, top: 44, display: 'flex', flexDirection: 'column', gap: 10}}>
      <div style={{fontFamily: mono, fontSize: 15, color: L.text2}}>Claude Code · new session</div>
      <div style={{alignSelf: 'flex-start', padding: '2px 10px', borderRadius: 8, background: L.selected, fontSize: 15, fontWeight: 600, color: L.text}}>{kind}</div>
      <div style={{alignSelf: 'flex-end', maxWidth: '92%', padding: '10px 12px', borderRadius: 14, background: L.chatYou, fontSize: 18, lineHeight: '24px', color: L.text}}>{ask}</div>
      <div style={{display: 'flex', alignItems: 'center', gap: 8, fontSize: 15, color: L.text2}}><Glyph state="working" size={14} /> working</div>
    </div>
  </div>
);

export const Opening = ({t, ev}: SceneProps) => {
  const duo = at(ev, 'duo'), typ = at(ev, 'typically'), wt = at(ev, 'worktrees'), time = at(ev, 'time');
  const titleOut = ramp(t, duo - 0.3, duo + 0.2);
  const duoIn = ramp(t, duo - 0.1, duo + 0.4), duoOut = ramp(t, typ - 0.3, typ + 0.2);
  const phoneU = (k: number) => spring(t, k < IDEAS.length ? at(ev, IDEAS[k][1], -0.2) : typ, 8, 0.9);
  // Line 4: the phones become sessions on a ring around you, each with its own worktree branch.
  const toRing = spring(t, wt, 5, 0.95);
  const ringU = ramp(t, wt + 0.2, wt + 0.8);
  const moreU = (j: number) => spring(t, wt + 0.4 + 0.1 * j, 9, 0.85);
  const askAt = SESSIONS.map(() => Infinity);
  for (const [w, rows] of CHORES) for (const r of rows) askAt[r] = Math.min(askAt[r], at(ev, w));
  const chore = (i: number) => CHORES.find(([, rows]) => rows.includes(i));
  const state = (i: number): State => (t >= askAt[i] ? 'needs' : 'working');
  const orange = (i: number) => ramp(t, askAt[i] + 0.5, askAt[i] + 0.8);
  const chip = askAt.filter((a) => t >= a + 0.6).length;
  const split = ramp(t, time, time + 0.5), half = ramp(t, at(ev, 'direction', -0.2), at(ev, 'direction', 0.4));
  const you = RING_YOU, yc = centre(you);
  const row = (i: number) => {
    const p = IDEAS.findIndex(([s]) => s === i);
    if (p < 0) return ringRow(i);
    const ph = phoneBox(p), small: Box = {x: ph.x + 20, y: ph.y + 220, w: 260, h: 64};
    return mixBox(small, ringRow(i), toRing);
  };

  return (
    <AbsoluteFill>
      <PaperGround />
      <TitleCard t={t} out={titleOut} />

      {/* Line 2: Duo, with the intro's logo build and a small capture of the app. */}
      {duoIn > 0 && duoOut < 1 && (
        <div style={{position: 'absolute', inset: 0, opacity: duoIn * (1 - duoOut)}}>
          <div style={{position: 'absolute', left: 220, top: 380}}><DuoIcon t={(t - duo) * 1.0 + 0.0} size={260} /></div>
          <div style={{position: 'absolute', left: 520, top: 400, fontFamily: ui, color: L.text}}>
            <div style={{fontSize: 120, lineHeight: '120px', fontWeight: 650, letterSpacing: -4, clipPath: `inset(0 ${100 - 100 * ramp(t, duo + 0.8, duo + 1.2)}% 0 0)`}}>Duo</div>
            <div style={{marginTop: 18, fontSize: 30, lineHeight: '40px', color: L.text2, opacity: ramp(t, duo + 1.1, duo + 1.5)}}>A personal project, built after hours</div>
          </div>
          <div style={{position: 'absolute', left: 1080, top: 300, width: 680, height: 416, borderRadius: 12, overflow: 'hidden', boxShadow: `0 0 0 1.5px ${L.rule}, 0 18px 40px rgba(31,35,40,0.12)`,
            opacity: ramp(t, duo + 0.9, duo + 1.4), transform: `translateY(${(1 - ramp(t, duo + 0.9, duo + 1.4)) * 20}px)`}}>
            <Img src={staticFile('capture/video-s2-right-4.png')} style={{width: 680, height: 416, objectFit: 'cover', objectPosition: 'left top'}} />
          </div>
        </div>
      )}

      {/* Line 3: a new session on the phone for each idea. */}
      {IDEAS.map(([, , kind, ask], k) => {
        const u = phoneU(k);
        if (u <= 0.001) return null;
        return <div key={k} style={{position: 'absolute', inset: 0, opacity: 1 - toRing}}><MiniPhone box={phoneBox(k)} kind={kind} ask={ask} u={u} /></div>;
      })}
      {[3, 4].map((k) => (
        <div key={k} style={{position: 'absolute', inset: 0, opacity: (1 - toRing) * ramp(t, at(ev, 'bugs', 0.5 + 0.3 * (k - 3)), at(ev, 'bugs', 0.9 + 0.3 * (k - 3)))}}>
          <MiniPhone box={phoneBox(k)} kind={k === 3 ? 'prototype' : 'research'} ask={k === 3 ? 'Search across every project' : 'How do other apps explain tasks?'} u={1} />
        </div>
      ))}
      <Heading title="The problem" sub="A session for every idea, and you in the middle." u={ramp(t, wt, wt + 0.5)} />

      {/* Line 4 and 5: the ring, the chores, the switchboard. */}
      <div style={{position: 'absolute', inset: 0, opacity: ringU}}>
        {SESSIONS.map((_, i) => <Wire key={`w${i}`} pts={[yc, centre(ringRow(i))]} draw={ramp(t, wt + 0.6, wt + 1.1)} />)}
        {SESSIONS.map((_, i) => <Wire key={`o${i}`} pts={[yc, centre(ringRow(i))]} color={L.needsYou} opacity={orange(i)} />)}
        {SESSIONS.map((_, i) => <Pulse key={`p${i}`} a={centre(ringRow(i))} b={yc} u={(t - askAt[i]) / 0.6} />)}
      </div>
      {SESSIONS.map((name, i) => {
        const isPhone = IDEAS.some(([s]) => s === i);
        const u = isPhone ? Math.min(1, toRing * 2) : Math.min(1, moreU(MORE.indexOf(i)));
        const b = row(i), c = chore(i);
        return (
          <div key={name} style={{position: 'absolute', inset: 0, opacity: u}}>
            <SessionRow box={b} name={name} state={state(i)} />
            <div style={{position: 'absolute', left: b.x + 14, top: b.y + b.h + 4, fontFamily: mono, fontSize: 14, color: '#4E6A3F', opacity: ramp(t, wt + 1.0, wt + 1.4)}}>worktree</div>
            {c && t >= askAt[i] && (
              <div style={{position: 'absolute', left: b.x + b.w - 8, top: b.y - 14, transform: 'translateX(-100%)', padding: '1px 9px', borderRadius: 8, background: L.needsYou,
                color: L.onNeedsYou, fontFamily: ui, fontSize: 15, lineHeight: '22px', fontWeight: 600, whiteSpace: 'nowrap', opacity: ramp(t, askAt[i], askAt[i] + 0.25)}}>{c[2]}</div>
            )}
          </div>
        );
      })}
      <div style={{position: 'absolute', inset: 0, opacity: ringU}}>
        <YouCard box={you} chip={chip} />
        {/* Line 5: your time, half on merges and renumbering, half on direction. */}
        <div style={{position: 'absolute', left: you.x - 60, top: you.y + you.h + 18, width: you.w + 120, opacity: split, fontFamily: ui}}>
          <div style={{display: 'flex', height: 18, borderRadius: 9, overflow: 'hidden', border: `1.5px solid ${L.rule}`, background: L.pane}}>
            <div style={{width: `${50 * split}%`, background: L.needsYou}} />
            <div style={{width: `${50 * half}%`, background: L.text}} />
          </div>
          <div style={{display: 'flex', justifyContent: 'space-between', marginTop: 6, fontSize: 16, lineHeight: '22px', color: L.text2}}>
            <span>merges, renumbering</span><span style={{opacity: half}}>direction</span>
          </div>
        </div>
      </div>
    </AbsoluteFill>
  );
};

/** S1's last picture: S2 opens on it. */
const END_EV = {share: 0, duo: 1, typically: 2, features: 2.2, patterns: 2.4, bugs: 2.6, worktrees: 3, prompts: 3.5, rebasing: 3.7, review: 3.9, merging: 4.1, time: 5, direction: 5.5};
export const OpeningEnd = () => <Opening t={999} ev={END_EV} scene={{id: 'S1', title: ''}} />;
