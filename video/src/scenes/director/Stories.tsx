import React from 'react';
import {AbsoluteFill} from 'remotion';
import type {SceneProps} from '../registry';
import {PaperGround} from '../../lib/Paper';
import {centre, DirectorCard, Glyph, Heading, L, Meter, mixBox, mono, Pulse, ramp, SessionRow, spring, ui, Wire, type Box, type State} from './kit';
import {TREE_DIRECTOR} from './board';
import {Tree} from './Tree';

// S3 to S5: what working with the director looks like, from the transcripts and git (scratch research, Oct 12).
// S3: a one-line ask from the phone becomes a full brief and a landed change. S4: a bigger idea gets a team
// (research and design side by side, Geoff's pick, then a builder). S5: the standup: one question from the phone,
// a Done / Needs you / Next answer, four decisions as buttons, and new sessions starting.

export const PHONE: Box = {x: 144, y: 250, w: 330, h: 620};
export const DIR: Box = {x: 560, y: 470, w: 340, h: 150};

/** A phone with messages: Geoff's going out (right, blue), the director's coming back (left, grey). */
export const PhoneChat = ({box = PHONE, u = 1, children}: {box?: Box; u?: number; children?: React.ReactNode}) => (
  <div style={{position: 'absolute', left: box.x, top: box.y, width: box.w, height: box.h, boxSizing: 'border-box', borderRadius: 44,
    border: `8px solid ${L.text}`, background: L.pane, overflow: 'hidden', opacity: u, transform: `translateY(${(1 - u) * 20}px)`}}>
    <div style={{position: 'absolute', left: '50%', top: 12, width: 90, height: 22, marginLeft: -45, borderRadius: 11, background: L.text}} />
    <div style={{position: 'absolute', left: 18, right: 18, top: 56, bottom: 18, display: 'flex', flexDirection: 'column', gap: 12, fontFamily: ui}}>{children}</div>
  </div>
);

export const Bubble = ({text, typed = 1, mine = true, u = 1, size = 19}: {text: string; typed?: number; mine?: boolean; u?: number; size?: number}) => (
  <div style={{alignSelf: mine ? 'flex-end' : 'flex-start', maxWidth: '88%', padding: '10px 14px', borderRadius: 16, background: mine ? L.chatYou : L.ground,
    fontSize: size, lineHeight: `${Math.round(size * 1.3)}px`, color: L.text, opacity: u, whiteSpace: 'pre-wrap'}}>
    {text.slice(0, Math.round(text.length * typed))}
  </div>
);

/** A card for what landed: the merge, its size, how long it took. */
export const MergeCard = ({box, sha, lines, u}: {box: Box; sha: string; lines: string[]; u: number}) => (
  <div style={{position: 'absolute', left: box.x, top: box.y, width: box.w, boxSizing: 'border-box', padding: '16px 22px', borderRadius: 12, background: L.pane,
    border: `2px solid ${L.text}`, fontFamily: ui, color: L.text, opacity: Math.min(1, u * 1.4), transform: `translateY(${(1 - Math.min(1, u)) * 14}px)`}}>
    <div style={{display: 'flex', alignItems: 'center', gap: 12, fontSize: 24, lineHeight: '32px', fontWeight: 700}}>
      <Glyph state="done" size={22} /> merged <span style={{fontFamily: mono, fontSize: 20, fontWeight: 400, color: L.text2}}>{sha}</span>
    </div>
    {lines.map((l) => <div key={l} style={{fontSize: 21, lineHeight: '30px', color: L.text2}}>{l}</div>)}
  </div>
);

const at = (ev: Record<string, number>, w: string, d = 0) => (ev[w] ?? 1e9) + d;

// ————— S3 · A line becomes a brief —————

const TAB_ASK = 'quick little addition before you cut 0.2.0 -- in the tabbed views (terminal or right pane) we need an on hover close button to close that tab';
const REVIEW_ASK = 'Please start a new extra high effort session to thoroughly review the whole code base. Look for abandoned code, opportunities to refactor, decrease memory’s usage/increase performance, and otherwise improve the maintainability of the repo.';
const BRIEF: Box = {x: 980, y: 210, w: 800, h: 520};
/** The brief's rows: what it adds to the ask, quoted from the brief the director wrote (Oct 6, 472 words). */
const BRIEF_ROWS: [string, string, string][] = [
  ['Your words', '“This is a QUICK, small job; Geoff wants it in before the 0.2.0 release.”', 'quoted'],
  ['Its own branch', 'claude/tab-close, in its own work tree', 'branch'],
  ['Records', 'DL-126 · F-124 · Q-71, reserved for it', 'record'],
  ['The spec', '“the × runs exactly what ⌘W does for that tab … No new semantics.”', 'prove'],
];

export const FromLine = ({t, ev}: SceneProps) => {
  const go = ev.go ?? 0.4;
  const leave = ramp(t, go, go + 0.5);
  const move = spring(t, go, 5.5, 0.95);
  const dir = mixBox(TREE_DIRECTOR, DIR, move);
  const phoneU = spring(t, go + 0.3, 7, 0.9);
  const typed = ramp(t, at(ev, 'asks', -0.3), at(ev, 'asks', 1.6));
  const send = at(ev, 'turns');
  const open = spring(t, send + 0.4, 6, 0.95);
  const row = (k: number) => ramp(t, at(ev, BRIEF_ROWS[k][2]), at(ev, BRIEF_ROWS[k][2], 0.35));
  const review = at(ev, 'review');
  const tabOut = 1 - ramp(t, review - 0.2, review + 0.3);
  const sessionU = spring(t, at(ev, 'briefed'), 8, 0.9);
  const merged = at(ev, 'merged');
  const askU = ramp(t, review, review + 0.4), ask2 = ramp(t, review, review + 1.6);
  const bars = ramp(t, at(ev, 'brief2'), at(ev, 'brief2', 1.0));
  const report = spring(t, at(ev, 'report'), 7, 0.9);
  const briefBox = mixBox(dir, BRIEF, open);

  return (
    <AbsoluteFill>
      <PaperGround />
      <div style={{position: 'absolute', inset: 0, opacity: 1 - leave}}><Tree /></div>
      <Heading title="From a line to a brief" sub="An idea from the phone; a full brief for a new session." u={ramp(t, go + 0.3, go + 0.8)} />

      <PhoneChat u={phoneU}>
        <div style={{fontSize: 16, color: L.text2, textAlign: 'center'}}>to the director</div>
        <div style={{opacity: tabOut, display: 'flex', flexDirection: 'column'}}><Bubble text={TAB_ASK} typed={typed} /></div>
        {askU > 0 && <div style={{display: 'flex', flexDirection: 'column'}}><Bubble text={REVIEW_ASK} typed={ask2} u={askU} size={16} /></div>}
      </PhoneChat>
      <Wire pts={[[PHONE.x + PHONE.w + 4, centre(dir)[1]], [dir.x - 2, centre(dir)[1]]]} draw={ramp(t, go + 0.6, go + 1.1)} head width={2.5} />
      <Pulse a={[PHONE.x + PHONE.w, centre(dir)[1]]} b={[dir.x, centre(dir)[1]]} u={(t - send) / 0.5} color={L.chatYou} r={10} />

      {/* The brief: unfolds out of the director; its rows light as the voice names them. */}
      {open > 0.01 && tabOut > 0.01 && (
        <div style={{position: 'absolute', left: briefBox.x, top: briefBox.y, width: briefBox.w, height: briefBox.h, boxSizing: 'border-box', background: L.pane,
          border: `2px solid ${L.rule}`, borderRadius: 12, overflow: 'hidden', opacity: tabOut}}>
          <div style={{position: 'absolute', left: 36, top: 28, width: BRIEF.w - 72, opacity: ramp(open, 0.7, 1), fontFamily: ui, color: L.text}}>
            <div style={{fontFamily: mono, fontSize: 18, lineHeight: '26px', color: L.text2}}>brief → a new session · 472 words</div>
            <div style={{marginTop: 14, fontSize: 21, lineHeight: '29px', color: L.text2}}>{'“'}{TAB_ASK}{'”'}</div>
            <div style={{marginTop: 18, display: 'flex', flexDirection: 'column', gap: 8}}>
              {BRIEF_ROWS.map(([k, v], i) => (
                <div key={k} style={{display: 'flex', gap: 18, padding: '8px 14px', borderRadius: 8, background: `rgba(233,236,239,${row(i)})`}}>
                  <div style={{flex: 'none', width: 160, fontSize: 18, lineHeight: '28px', fontWeight: 600, letterSpacing: 0.6, color: row(i) > 0.5 ? L.text : L.text2}}>{k}</div>
                  <div style={{fontSize: 21, lineHeight: '28px', color: row(i) > 0.5 ? L.text : L.text2, fontFamily: k === 'Its own branch' || k === 'Records' ? mono : ui}}>{v}</div>
                </div>
              ))}
            </div>
          </div>
        </div>
      )}
      <Wire pts={[[dir.x + dir.w, centre(dir)[1]], [BRIEF.x - 2, centre(dir)[1]]]} draw={ramp(t, send + 0.6, send + 1.0) * tabOut} head width={2.5} />

      {/* The new session, then what landed and when. */}
      <div style={{position: 'absolute', inset: 0, opacity: tabOut}}>
        <div style={{position: 'absolute', inset: 0, opacity: Math.min(1, sessionU)}}>
          <SessionRow box={{x: 980, y: 760, w: 360, h: 64}} name="Tab close" state={t >= merged ? 'done' : 'working'} right={t >= merged ? 'merged' : 'working'} />
        </div>
        <MergeCard box={{x: 1380, y: 744, w: 400, h: 100}} sha="9f1a2f8" lines={['20 files · +443 −12', 'asked 3:01 pm · briefed 25 s later · merged 3:33 pm']}
          u={spring(t, merged, 8, 0.9)} />
      </div>

      {/* The review: a one-sentence ask beside its brief, drawn to scale, and the report. */}
      {bars > 0 && (
        <div style={{position: 'absolute', left: 980, top: 250, width: 800, fontFamily: ui, color: L.text}}>
          <div style={{fontSize: 22, lineHeight: '30px', fontWeight: 600}}>Your ask · 34 words</div>
          <div style={{marginTop: 8, height: 26, width: 800 * (34 / 872) * bars, background: L.chatYou, borderRadius: 6}} />
          <div style={{marginTop: 26, fontSize: 22, lineHeight: '30px', fontWeight: 600}}>The director's brief · 872 words</div>
          <div style={{marginTop: 8, height: 26, width: 800 * bars, background: L.text, borderRadius: 6}} />
          <div style={{marginTop: 18, fontSize: 20, lineHeight: '28px', color: L.text2, opacity: ramp(bars, 0.6, 1)}}>
            {'“Prove each with a search … not a hunch.”  “Measure; don’t guess.”  “Read-only on Duo’s code.”'}
          </div>
        </div>
      )}
      <MergeCard box={{x: 980, y: 560, w: 520, h: 120}} sha="41948ee" lines={['a 776-line report, 74 minutes after the ask', 'then fix sessions, the same afternoon']} u={report} />

      <DirectorCard box={dir} sub="writes the brief"><Meter fill={0.2} /></DirectorCard>
    </AbsoluteFill>
  );
};
const FROMLINE_END = {go: 0, asks: 1, turns: 3, quoted: 4, branch: 4.5, record: 5, prove: 5.5, briefed: 7, merged: 8, review: 9, brief2: 10, report: 11};
export const FromLineEnd = () => <FromLine t={999} ev={FROMLINE_END} scene={{id: 'S3', title: ''}} />;

// ————— S4 · Teams for bigger ideas —————

const CHAT_ASK = 'New project — will need a research agent and Claude design session: I want to explore a more readable terminal overlay … we should not in any way circumvent human review …';
const RESEARCH: Box = {x: 980, y: 250, w: 360, h: 64}, DESIGN: Box = {x: 1420, y: 250, w: 360, h: 64};
const CANVAS: Box = {x: 1420, y: 360, w: 360, h: 170};
const BUILD: Box = {x: 980, y: 590, w: 360, h: 64};

export const Team = ({t, ev}: SceneProps) => {
  const go = ev.go ?? 0.4;
  const leave = ramp(t, go, go + 0.4);
  const askT = ramp(t, at(ev, 'chat', -0.4), at(ev, 'chat', 1.4));
  const split = spring(t, at(ev, 'research'), 8, 0.9);
  const designU = spring(t, at(ev, 'design'), 8, 0.9);
  const told = at(ev, 'told');
  const canvasU = spring(t, at(ev, 'canvas'), 8, 0.9);
  const picked = ramp(t, at(ev, 'picked'), at(ev, 'picked', 0.3));
  const builder = spring(t, at(ev, 'builder'), 8, 0.9);
  const mergedU = spring(t, at(ev, 'hundred'), 8, 0.9);
  const word = at(ev, 'Word');
  const chatOut = 1 - ramp(t, word - 0.2, word + 0.3);
  const commentU = spring(t, at(ev, 'looks'), 8, 0.9);
  const slices = (k: number) => spring(t, at(ev, 'ship', 0.4 + 0.5 * k), 8, 0.9);
  const dc = centre(DIR);
  const state = (s: State) => s;

  return (
    <AbsoluteFill>
      <PaperGround />
      <div style={{position: 'absolute', inset: 0, opacity: 1 - leave}}><FromLineEnd /></div>
      <Heading title="Teams for bigger ideas" sub="Research and design side by side, then a builder." u={ramp(t, go + 0.3, go + 0.8)} />
      <PhoneChat>
        <div style={{fontSize: 16, color: L.text2, textAlign: 'center'}}>to the director</div>
        <div style={{opacity: chatOut, display: 'flex', flexDirection: 'column'}}><Bubble text={CHAT_ASK} typed={askT} size={17} /></div>
        {chatOut < 1 && <div style={{display: 'flex', flexDirection: 'column'}}><Bubble text="ship 0.2.8 when the docx viewer is done" u={1 - chatOut} /></div>}
      </PhoneChat>
      <Wire pts={[[PHONE.x + PHONE.w + 4, dc[1]], [DIR.x - 2, dc[1]]]} head width={2.5} />

      <div style={{position: 'absolute', inset: 0, opacity: chatOut}}>
        {/* The team: research and design, side by side; research tells design what's possible. */}
        <Wire pts={[[DIR.x + DIR.w, dc[1]], [940, dc[1]], [940, centre(RESEARCH)[1]], [RESEARCH.x - 2, centre(RESEARCH)[1]]]} draw={split} head width={2.5} />
        <div style={{position: 'absolute', inset: 0, opacity: Math.min(1, split)}}><SessionRow box={RESEARCH} name="Research · chat mode" state={state(t >= told + 0.6 ? 'done' : 'working')} /></div>
        <div style={{position: 'absolute', inset: 0, opacity: Math.min(1, designU)}}><SessionRow box={DESIGN} name="Design · chat mode" state={t >= at(ev, 'picked') ? 'done' : 'working'} /></div>
        <Wire pts={[[RESEARCH.x + RESEARCH.w + 2, centre(RESEARCH)[1]], [DESIGN.x - 2, centre(DESIGN)[1]]]} draw={ramp(t, told - 0.2, told + 0.3)} head width={2.5} />
        <Pulse a={[RESEARCH.x + RESEARCH.w, centre(RESEARCH)[1]]} b={[DESIGN.x, centre(DESIGN)[1]]} u={(t - told) / 0.6} color={L.text} r={7} />
        <div style={{position: 'absolute', left: RESEARCH.x + RESEARCH.w + 6, top: RESEARCH.y - 30, fontFamily: mono, fontSize: 16, color: L.text2, opacity: ramp(t, told, told + 0.4)}}>what's possible</div>
        {/* The canvas: three looks; Geoff's pick. */}
        <div style={{position: 'absolute', left: CANVAS.x, top: CANVAS.y, width: CANVAS.w, height: CANVAS.h, boxSizing: 'border-box', borderRadius: 12, border: `2px solid ${L.rule}`,
          background: L.pane, padding: 16, display: 'flex', gap: 12, opacity: Math.min(1, canvasU)}}>
          {['A', 'B', 'C'].map((k) => (
            <div key={k} style={{flex: 1, borderRadius: 8, background: L.ground, border: k === 'B' && picked > 0.5 ? `3px solid ${L.text}` : `2px solid ${L.rule}`, position: 'relative',
              fontFamily: ui, fontSize: 20, fontWeight: 600, color: L.text2, display: 'flex', alignItems: 'flex-end', padding: 10}}>
              {k}{k === 'B' && <span style={{position: 'absolute', right: 10, top: 8, opacity: picked}}><Glyph state="done" size={24} /></span>}
            </div>
          ))}
        </div>
        <div style={{position: 'absolute', left: CANVAS.x, top: CANVAS.y + CANVAS.h + 8, fontFamily: ui, fontSize: 18, color: L.text2, opacity: picked}}>your pick: B, light and readable</div>
        {/* The builder, briefed by the director; then the merge. */}
        <Wire pts={[[940, dc[1]], [940, centre(BUILD)[1]], [BUILD.x - 2, centre(BUILD)[1]]]} draw={ramp(t, at(ev, 'builder'), at(ev, 'builder', 0.4))} head width={2.5} />
        <div style={{position: 'absolute', inset: 0, opacity: Math.min(1, builder)}}><SessionRow box={BUILD} name="Build · chat mode" state={t >= at(ev, 'hundred') ? 'done' : 'working'} right={t >= at(ev, 'hundred') ? 'merged' : 'working'} /></div>
        <MergeCard box={{x: 1380, y: 600, w: 400, h: 100}} sha="911bb27" lines={['108 files · +6,876', '5 h 11 min after the ask']} u={mergedU} />
      </div>

      {/* The Word viewer: four words of review. */}
      <div style={{position: 'absolute', left: 980, top: 280, width: 560, height: 280, boxSizing: 'border-box', borderRadius: 12, border: `2px solid ${L.rule}`, background: L.pane,
        opacity: Math.min(1, spring(t, word, 8, 0.9)), padding: 20, display: 'flex', gap: 14}}>
        {[0, 1, 2].map((k) => <div key={k} style={{flex: 1, borderRadius: 8, background: L.ground, border: `2px solid ${L.rule}`}} />)}
        <div style={{position: 'absolute', left: 300, top: 150, padding: '12px 18px', borderRadius: 14, background: L.commentHighlight, fontFamily: ui, fontSize: 24,
          lineHeight: '32px', fontWeight: 600, color: L.text, opacity: Math.min(1, commentU), transform: `scale(${0.9 + 0.1 * Math.min(1, commentU)})`, whiteSpace: 'nowrap'}}>looks good -- build, test, ship</div>
      </div>
      <div style={{position: 'absolute', left: 980, top: 248, fontFamily: ui, fontSize: 20, fontWeight: 600, letterSpacing: 1.2, color: L.text2, opacity: ramp(t, word, word + 0.4)}}>THE WORD VIEWER · DESIGN CANVAS</div>
      <MergeCard box={{x: 980, y: 600, w: 380, h: 100}} sha="e1a6ace" lines={['85 files · the viewer']} u={slices(0)} />
      <MergeCard box={{x: 1400, y: 600, w: 380, h: 100}} sha="566fc13" lines={['38 files · select and send']} u={slices(1)} />

      <DirectorCard box={DIR} sub="briefs a team"><Meter fill={0.2} /></DirectorCard>
    </AbsoluteFill>
  );
};
const TEAM_END = {go: 0, chat: 1, research: 2, design: 2.2, told: 3, canvas: 4, picked: 4.5, builder: 5, hundred: 6, Word: 7, looks: 8, ship: 8.5};
export const TeamEnd = () => <Team t={999} ev={TEAM_END} scene={{id: 'S4', title: ''}} />;

// ————— S5 · A standup —————

const DIGEST: Box = {x: 980, y: 230, w: 800, h: 430};
const BUTTONS = ['Yes, cut 0.2.1 (Recommended)', 'Design narrow windows (Recommended)', 'Commit it', 'Yes, by default'];

export const Standup = ({t, ev}: SceneProps) => {
  const go = ev.go ?? 0.4;
  const leave = ramp(t, go, go + 0.4);
  const askT = ramp(t, at(ev, 'ask', -0.2), at(ev, 'ask', 0.8));
  const digest = spring(t, at(ev, 'standup'), 7, 0.92);
  const part = (w: string) => ramp(t, at(ev, w), at(ev, w, 0.35));
  const buttonsU = spring(t, at(ev, 'buttons'), 8, 0.9);
  const tap = (k: number) => ramp(t, at(ev, 'tapped', 0.25 * k), at(ev, 'tapped', 0.25 * k + 0.2));
  const started = (k: number) => spring(t, at(ev, 'started', 0.3 * k), 8, 0.9);
  const dc = centre(DIR);
  const SECTION = (title: string, w: string, lines: string[]) => (
    <div style={{opacity: part(w), transform: `translateY(${(1 - part(w)) * 8}px)`}}>
      <div style={{fontSize: 18, lineHeight: '26px', fontWeight: 700, letterSpacing: 1.2, color: title === 'NEEDS YOU' ? L.needsYou : L.text2}}>{title}</div>
      {lines.map((l) => <div key={l} style={{fontSize: 21, lineHeight: '30px', color: L.text}}>{l}</div>)}
    </div>
  );
  return (
    <AbsoluteFill>
      <PaperGround />
      <div style={{position: 'absolute', inset: 0, opacity: 1 - leave}}><TeamEnd /></div>
      <Heading title="Catching up" sub="One question, one answer for the whole fleet." u={ramp(t, go + 0.3, go + 0.8)} />
      <PhoneChat>
        <div style={{fontSize: 16, color: L.text2, textAlign: 'center'}}>to the director</div>
        <div style={{display: 'flex', flexDirection: 'column'}}><Bubble text="please do a scan -- where are you blocked?" typed={askT} /></div>
        <div style={{display: 'flex', flexDirection: 'column', gap: 8, opacity: Math.min(1, buttonsU)}}>
          {BUTTONS.map((b, k) => (
            <div key={b} style={{padding: '9px 12px', borderRadius: 10, fontSize: 16, lineHeight: '21px', border: `1.5px solid ${tap(k) > 0.5 ? L.text : L.controlEdge}`,
              background: tap(k) > 0.5 ? L.text : L.pane, color: tap(k) > 0.5 ? L.pane : L.text}}>{b}</div>
          ))}
        </div>
      </PhoneChat>
      <Wire pts={[[PHONE.x + PHONE.w + 4, dc[1]], [DIR.x - 2, dc[1]]]} head width={2.5} />
      <Pulse a={[PHONE.x + PHONE.w, dc[1]]} b={[DIR.x, dc[1]]} u={(t - at(ev, 'ask', 0.8)) / 0.5} color={L.chatYou} r={10} />

      <Wire pts={[[DIR.x + DIR.w, dc[1]], [DIGEST.x - 2, dc[1]]]} draw={ramp(t, at(ev, 'standup', -0.3), at(ev, 'standup'))} head width={2.5} />
      <div style={{position: 'absolute', left: DIGEST.x, top: DIGEST.y, width: DIGEST.w, height: DIGEST.h, boxSizing: 'border-box', padding: '26px 34px', borderRadius: 12,
        background: L.pane, border: `2px solid ${L.rule}`, fontFamily: ui, display: 'flex', flexDirection: 'column', gap: 16, opacity: Math.min(1, digest),
        transform: `translateX(${(1 - Math.min(1, digest)) * 20}px)`}}>
        <div style={{fontFamily: mono, fontSize: 18, color: L.text2}}>from the director · Oct 6, 5:02 pm</div>
        {SECTION('DONE', 'done', ['main is clean, 3 commits since v0.2.0', 'only the director is busy'])}
        {SECTION('NEEDS YOU', 'needs', ['4 decisions, as buttons on your phone'])}
        {SECTION('NEXT', 'next', ['cut 0.2.1 · start the next designs'])}
      </div>
      {['Remote Control option', 'Narrow windows · design'].map((name, k) => (
        <div key={name} style={{position: 'absolute', inset: 0, opacity: Math.min(1, started(k))}}>
          <SessionRow box={{x: 980 + k * 420, y: 700, w: 380, h: 64}} name={name} state="working" right="new" />
        </div>
      ))}
      <div style={{position: 'absolute', left: 980, top: 778, fontFamily: ui, fontSize: 20, color: L.text2, opacity: ramp(t, at(ev, 'started', 0.6), at(ev, 'started', 1))}}>
        started 47 seconds after the last tap
      </div>
      <DirectorCard box={DIR} sub="the standup" needs={t >= at(ev, 'standup') && t < at(ev, 'tapped', 1.2) ? 4 : 0}><Meter fill={0.2} /></DirectorCard>
    </AbsoluteFill>
  );
};
const STANDUP_END = {go: 0, ask: 1, standup: 2, done: 2.5, needs: 3, next: 3.5, buttons: 4, tapped: 5, started: 6};
export const StandupEnd = () => <Standup t={999} ev={STANDUP_END} scene={{id: 'S5', title: ''}} />;
