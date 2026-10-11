import React from 'react';
import {IFrame, staticFile} from 'remotion';
import tokens from '../../style/tokens.json';
import content from '../../fixture/docs/content.json';
import {desk, files} from './deskContent';

// The apps inside S1's windows (Terminal running Claude Code, Finder, a Markdown editor, a browser
// showing the real checkout prototype, PowerPoint, Word). Sample data only: everything here comes from
// fixture/docs/content.json, which S2 also shows as real Duo tabs. Pure functions of `t`.

const ui = tokens.font.ui, mono = tokens.font.mono;
export const caret = (t: number) => (Math.floor(t * 2) % 2 === 0 ? '▍' : ' ');
const typed = (text: string, t: number, at: number, cps: number) => text.slice(0, Math.max(0, Math.floor((t - at) * cps)));

export const Lights = ({dim}: {dim?: boolean}) => (
  <div style={{display: 'flex', gap: 8, position: 'absolute', left: 14, top: 11}}>
    {['#FF5F57', '#FEBC2E', '#28C840'].map((c) => <div key={c} style={{width: 12, height: 12, borderRadius: 6, background: c, opacity: dim ? 0.9 : 1, boxShadow: 'inset 0 0 0 0.5px rgba(0,0,0,0.2)'}} />)}
  </div>
);

// ---- Terminal (dark) running Claude Code -----------------------------------------------------

const T = {bg: '#141416', fg: '#E8E6E3', dim: '#8E8E93', faint: '#5C5C62', orange: '#D97757', rule: '#3A3A40',
  delBg: '#4B1E22', delFg: '#F4CFD2', addBg: '#173A26', addFg: '#CDEFD9'};

type TLine =
  | {k: 'box'; cwd: string}
  | {k: 'user'; text: string}
  | {k: 'tool'; name: string; arg: string}
  | {k: 'out'; text: string}
  | {k: 'say'; text: string}
  | {k: 'diff'; n: number; sign: ' ' | '-' | '+'; text: string}
  | {k: 'gap'};

const tl = (l: TLine, i: number) => {
  switch (l.k) {
    case 'box': return (
      <div key={i} style={{width: 470, border: `1px solid ${T.orange}`, borderRadius: 7, padding: '6px 12px', marginBottom: 12, lineHeight: '20px'}}>
        <div><span style={{color: T.orange}}>✻</span> Welcome to <b>Claude Code</b>!</div>
        <div style={{color: T.dim, fontStyle: 'italic', marginTop: 2}}>/help for help, /status for your current setup</div>
        <div style={{color: T.dim, marginTop: 2}}>cwd: {l.cwd.replace('~', '/Users/geoff')}</div>
      </div>);
    case 'user': return <div key={i} style={{color: T.fg, background: '#26262A', borderRadius: 4, padding: '0 8px', marginBottom: 8, alignSelf: 'flex-start'}}><span style={{color: T.dim}}>{'> '}</span>{l.text}</div>;
    case 'tool': return <div key={i}><span style={{color: '#7FD39A'}}>⏺</span> <b>{l.name}</b>({l.arg})</div>;
    case 'say': return <div key={i} style={{marginTop: 6, marginBottom: 6}}><span>⏺</span> {l.text}</div>;
    case 'out': return <div key={i} style={{color: T.dim, paddingLeft: 8}}>⎿  {l.text}</div>;
    case 'diff': return (
      <div key={i} style={{paddingLeft: 30, whiteSpace: 'pre', overflow: 'hidden', background: l.sign === '-' ? T.delBg : l.sign === '+' ? T.addBg : 'none',
        color: l.sign === '-' ? T.delFg : l.sign === '+' ? T.addFg : T.dim}}>{String(l.n).padStart(3)} {l.sign} {l.text}</div>);
    default: return <div key={i} style={{height: 8}} />;
  }
};

export const ClaudeTerminal = ({lines, t, working, hint = true}: {lines: TLine[]; t: number; working?: string; hint?: boolean}) => (
  <div style={{position: 'absolute', inset: 0, background: T.bg, padding: '10px 16px 10px', fontFamily: mono, fontSize: 13.5, lineHeight: '20px', color: T.fg,
    display: 'flex', flexDirection: 'column', justifyContent: 'flex-end', overflow: 'hidden'}}>
    <div style={{display: 'flex', flexDirection: 'column'}}>{lines.map(tl)}</div>
    {working && <div style={{color: T.orange, marginTop: 6}}>✶ {working}… <span style={{color: T.dim}}>({Math.floor(t) % 60}s · ↑ {(1.1 + (t % 9) * 0.07).toFixed(1)}k tokens · esc to interrupt)</span></div>}
    <div style={{border: `1px solid ${T.rule}`, borderRadius: 7, padding: '3px 10px', marginTop: 8}}>
      <span style={{color: T.fg}}>{'> '}</span>{caret(t)}
    </div>
    {hint && <div style={{color: T.faint, paddingLeft: 10, fontSize: 12}}>? for shortcuts</div>}
  </div>
);

export const TERM1: TLine[] = desk.terms.term1;
export const TERM2: TLine[] = desk.terms.term2;
export const TERM3_LINES: TLine[] = [];

/** A plain zsh Terminal: `ev.path` starts the wrong-then-right cd. `u` is seconds since it began (undefined: finished). */
export const ZshTerminal = ({t, u}: {t: number; u: number | undefined}) => {
  const {user, host, wrongCd: WRONG, rightCd: RIGHT, lastLogin} = desk.zsh;
  const P = `${user}@${host} ~ % `;
  const badPath = WRONG.replace(/^cd\s+~/, `/Users/${user}`);
  const here = RIGHT.split('/').pop();
  const cps = 34;
  const done = u === undefined || u >= 2.25;
  let body: React.ReactNode;
  if (u !== undefined && u < 0) body = <div>{P}{caret(t)}</div>;
  else if (done) body = <><div>{P}{WRONG}</div><div>cd: no such file or directory: {badPath}</div><div>{P}{RIGHT}</div><div>{user}@{host} <b>{here}</b> % {caret(t)}</div></>;
  else if (u! < 0.95) body = <div>{P}{typed(WRONG, u!, 0, cps)}{caret(t)}</div>;
  else if (u! < 1.1) body = <><div>{P}{WRONG}</div><div>cd: no such file or directory: {badPath}</div><div>{P}{caret(t)}</div></>;
  else body = <><div>{P}{WRONG}</div><div>cd: no such file or directory: {badPath}</div><div>{P}{typed(RIGHT, u!, 1.1, cps)}{caret(t)}</div></>;
  return (
    <div style={{position: 'absolute', inset: 0, background: T.bg, padding: '10px 16px', fontFamily: mono, fontSize: 13.5, lineHeight: '20px', color: T.fg, overflow: 'hidden'}}>
      <div style={{color: T.dim}}>Last login: {lastLogin}</div>
      {body}
    </div>
  );
};

// ---- Finder ----------------------------------------------------------------------------------

const Folder = ({s = 15}: {s?: number}) => (
  <svg width={s + 4} height={s} viewBox="0 0 20 16" style={{flex: 'none'}}>
    <path d="M1 3a2 2 0 0 1 2-2h4.2l1.8 2H17a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H3a2 2 0 0 1-2-2z" fill="#5BB3F2" />
    <path d="M1 6h18v7a2 2 0 0 1-2 2H3a2 2 0 0 1-2-2z" fill="#7CC6FA" />
  </svg>
);
const FOLDERS = desk.finder.folders;
export const Finder = ({t, huntAt}: {t: number; huntAt?: number}) => {
  // The selection walks down the list, overshoots and comes back: a hunt, landing on checkout-redesign.
  const heroIdx = Math.max(0, FOLDERS.findIndex(([f]) => f === desk.finder.hero));
  const path = [0, 2, 4, 3, heroIdx].map((i) => Math.min(i, FOLDERS.length - 1));
  const step = huntAt === undefined || t < huntAt ? -1 : Math.min(path.length - 1, Math.floor((t - huntAt) / 0.32));
  const sel = huntAt === undefined ? heroIdx : step < 0 ? -1 : path[step];
  const side = (h: string, items: string[], on?: string) => (
    <div style={{marginBottom: 12}}>
      <div style={{fontSize: 10.5, fontWeight: 600, color: '#8A8B90', margin: '0 6px 3px'}}>{h}</div>
      {items.map((f) => <div key={f} style={{display: 'flex', gap: 7, alignItems: 'center', padding: '3px 6px', borderRadius: 5, fontSize: 13, color: '#2B2C30', background: f === on ? '#D9D9DE' : 'none'}}><Folder s={12} />{f}</div>)}
    </div>);
  return (
    <div style={{display: 'flex', height: '100%', fontSize: 13, fontFamily: ui}}>
      <div style={{width: 160, background: '#F1F1F4', padding: '12px 8px', borderRight: '1px solid #DDDDE0'}}>
        {side('Favourites', ['Desktop', 'Documents', 'Downloads', 'work'], 'work')}
        {side('Locations', ['Macintosh HD', 'iCloud Drive'])}
      </div>
      <div style={{flex: 1, background: '#fff'}}>
        <div style={{display: 'flex', padding: '5px 14px', fontSize: 11, color: '#8A8B90', borderBottom: '1px solid #ECECEE'}}><span style={{flex: 1}}>Name</span><span style={{width: 90}}>Date Modified</span></div>
        {FOLDERS.map(([f, d], i) => (
          <div key={f} style={{display: 'flex', alignItems: 'center', gap: 8, margin: '0 6px', padding: '4px 8px', borderRadius: 5, background: i === sel ? '#2F6FEB' : i % 2 ? '#F6F6F8' : '#fff', color: i === sel ? '#fff' : '#2B2C30'}}>
            <Folder /><span style={{flex: 1}}>{f}</span><span style={{width: 90, fontSize: 12, opacity: 0.7}}>{d}</span>
          </div>
        ))}
        <div style={{position: 'absolute', bottom: 0, left: 160, right: 0, padding: '5px 14px', fontSize: 11, color: '#8A8B90', borderTop: '1px solid #ECECEE', background: '#F7F7F9'}}>{FOLDERS.length} items · work › {desk.finder.parent}</div>
      </div>
    </div>
  );
};

// ---- Markdown editor (the real PRD) ----------------------------------------------------------

const PRD = desk.prd;
export const MarkdownEditor = () => {
  // Hard-wrap the long paragraph the way an editor with soft wrap shows it.
  const rows: {n: number; text: string; cont: boolean}[] = [];
  PRD.split('\n').forEach((l, i) => {
    const words = l.split(' '); let cur = '', first = true;
    for (const w of words) { if ((cur + ' ' + w).trim().length > 54) { rows.push({n: i + 1, text: cur, cont: !first}); cur = w; first = false; } else cur = (cur + ' ' + w).trim(); }
    rows.push({n: i + 1, text: cur, cont: !first});
  });
  return (
    <div style={{height: '100%', background: '#FFFFFF', display: 'flex', flexDirection: 'column', fontFamily: mono, fontSize: 13, lineHeight: '21px'}}>
      <div style={{display: 'flex', background: '#F0F0F2', borderBottom: '1px solid #DADADD', fontFamily: ui, fontSize: 12}}>
        <div style={{padding: '6px 14px', background: '#fff', borderRight: '1px solid #DADADD', color: '#2B2C30'}}>prd-v2.md</div>
        <div style={{padding: '6px 14px', color: '#8A8B90'}}>outline.md</div>
      </div>
      <div style={{flex: 1, overflow: 'hidden', padding: '8px 0'}}>
        {rows.map((r, i) => {
          const h = r.text.startsWith('#');
          return (
            <div key={i} style={{display: 'flex', whiteSpace: 'pre'}}>
              <span style={{width: 40, textAlign: 'right', paddingRight: 14, color: '#B5B7BD', flex: 'none'}}>{r.cont ? '' : r.n}</span>
              <span style={{color: h ? '#0550AE' : '#24292F', fontWeight: h ? 700 : 400, fontSize: r.text.startsWith('# ') ? 15 : 13}}>{h ? <><span style={{color: '#9AA3AE', fontWeight: 400}}>{r.text.match(/^#+ /)![0]}</span>{r.text.replace(/^#+ /, '')}</> : r.text || ' '}</span>
            </div>);
        })}
      </div>
      <div style={{padding: '4px 14px', fontFamily: ui, fontSize: 11, color: '#8A8B90', background: '#F7F7F9', borderTop: '1px solid #E4E4E7', display: 'flex', justifyContent: 'space-between'}}><span>Markdown</span><span>Ln 9, Col 41</span></div>
    </div>
  );
};

// ---- Browser (Safari-like) showing the real checkout.html -----------------------------------

export const BROWSER_BAR_H = 54;
const Chev = ({d}: {d: 'l' | 'r'}) => <div style={{width: 8, height: 8, borderLeft: '2px solid #85868B', borderBottom: '2px solid #85868B', transform: `rotate(${d === 'l' ? 45 : -135}deg)`}} />;
export const BrowserBar = () => (
  <>
    <div style={{position: 'absolute', left: 84, top: 18, display: 'flex', gap: 18}}><Chev d="l" /><Chev d="r" /></div>
    <div style={{position: 'absolute', left: 150, right: 90, top: 12, height: 28, borderRadius: 7, background: '#E4E4E8', fontSize: 13, color: '#3A3B40', textAlign: 'center', lineHeight: '28px', fontFamily: ui}}>
      <span style={{display: 'inline-block', width: 8, height: 7, background: '#8A8B90', borderRadius: 1.5, marginRight: 7}} />{desk.url}
    </div>
  </>
);
export const BrowserPage = ({w, h}: {w: number; h: number}) => {
  const vw = 960, s = w / vw;
  return (
    <div style={{position: 'absolute', inset: 0, overflow: 'hidden', background: '#F7F6F3'}}>
      <IFrame src={staticFile(files.prototype)} style={{width: vw, height: h / s, border: 0, transform: `scale(${s})`, transformOrigin: '0 0', display: 'block'}} />
    </div>
  );
};

// ---- Slides (PowerPoint) -----------------------------------------------------------------------

const SL = {ink: '#1B2A3A', grey: '#9AA7B5', mid: '#5B6B7C', accent: '#C43E1C'};
type SlideData = (typeof content.deck.slides)[number];
/** One slide drawn at 960x540; callers scale it. */
export const Slide = ({s, index}: {s: SlideData; index: number}) => {
  const base: React.CSSProperties = {width: 960, height: 540, background: '#fff', position: 'relative', fontFamily: ui, color: SL.ink, overflow: 'hidden'};
  if (s.kind === 'title') return (
    <div style={base}>
      <div style={{position: 'absolute', left: 0, top: 0, bottom: 0, width: 22, background: SL.accent}} />
      <div style={{position: 'absolute', left: 90, top: 190, width: 700, fontSize: 64, fontWeight: 700, lineHeight: 1.08, letterSpacing: -1.5}}>{s.title}</div>
      <div style={{position: 'absolute', left: 92, top: 380, fontSize: 26, color: SL.mid}}>{s.subtitle}</div>
    </div>);
  if (s.kind === 'chart' && s.chart) {
    const bars = s.chart.bars as [string, number][], max = 40, ch = 290, cw = 560;
    return (
      <div style={base}>
        <div style={{position: 'absolute', left: 60, top: 46, width: 840, fontSize: 40, fontWeight: 700, lineHeight: 1.12, letterSpacing: -0.8}}>{s.title}</div>
        <div style={{position: 'absolute', left: 60, top: 168, fontSize: 18, color: SL.mid}}>{s.chart.label}</div>
        <div style={{position: 'absolute', left: 60, top: 200, width: cw, height: ch + 40}}>
          {[0, 10, 20, 30, 40].map((g) => <div key={g} style={{position: 'absolute', left: 36, right: 0, top: ch - (g / max) * ch, borderTop: '1px solid #E4E8EC'}}><span style={{position: 'absolute', left: -36, top: -10, fontSize: 14, color: SL.grey}}>{g}</span></div>)}
          {bars.map(([n, v], i) => {
            const bw = 78, gap = (cw - 36 - bars.length * bw) / bars.length, x = 36 + gap / 2 + i * (bw + gap), hot = v === 38;
            return (
              <React.Fragment key={n}>
                <div style={{position: 'absolute', left: x, width: bw, bottom: 40, height: (v / max) * ch, background: hot ? SL.accent : '#B7C2CE', borderRadius: '4px 4px 0 0'}} />
                <div style={{position: 'absolute', left: x, width: bw, bottom: 40 + (v / max) * ch + 6, textAlign: 'center', fontSize: 20, fontWeight: 700, color: hot ? SL.accent : SL.mid}}>{v}</div>
                <div style={{position: 'absolute', left: x - 12, width: bw + 24, bottom: 8, textAlign: 'center', fontSize: 17, color: SL.mid}}>{n}</div>
              </React.Fragment>);
          })}
        </div>
        <div style={{position: 'absolute', left: 680, top: 230, width: 220}}>
          <div style={{fontSize: 96, fontWeight: 800, color: SL.accent, letterSpacing: -3, lineHeight: 1}}>38%</div>
          <div style={{fontSize: 22, color: SL.ink, marginTop: 14, lineHeight: 1.3}}>{(s as {note?: string}).note?.replace('38% of ', 'of ')}</div>
        </div>
        <div style={{position: 'absolute', right: 40, bottom: 22, fontSize: 14, color: SL.grey}}>{index + 1}</div>
      </div>);
  }
  return (
    <div style={base}>
      <div style={{position: 'absolute', left: 60, top: 46, width: 840, fontSize: 40, fontWeight: 700, lineHeight: 1.12, letterSpacing: -0.8}}>{s.title}</div>
      <div style={{position: 'absolute', left: 64, top: 190, width: 800}}>
        {(s.bullets ?? []).map((b) => <div key={b} style={{fontSize: 32, margin: '0 0 26px', paddingLeft: 36, position: 'relative'}}><span style={{position: 'absolute', left: 0, top: 14, width: 12, height: 12, borderRadius: 6, background: SL.accent}} />{b}</div>)}
      </div>
      <div style={{position: 'absolute', right: 40, bottom: 22, fontSize: 14, color: SL.grey}}>{index + 1}</div>
    </div>);
};

const Ico = ({w = 26, c = '#C8CACF'}: {w?: number; c?: string}) => <div style={{width: w, height: 22, borderRadius: 4, background: c}} />;
const RibbonGroup = ({label, icons, last}: {label: string; icons: number[]; last?: boolean}) => (
  <div style={{display: 'flex', flexDirection: 'column', alignItems: 'center', padding: '0 12px', borderRight: last ? 'none' : '1px solid #D9DADE', height: 50, justifyContent: 'space-between'}}>
    <div style={{display: 'flex', gap: 6, alignItems: 'center', flex: 1}}>{icons.map((w, i) => <Ico key={i} w={w} c={i === 0 ? '#BFC3CA' : '#D3D5DA'} />)}</div>
    <div style={{fontSize: 9.5, color: '#7C7E85'}}>{label}</div>
  </div>
);
const Tabs = ({tabs, on, accent}: {tabs: string[]; on: string; accent: string}) => (
  <div style={{display: 'flex', gap: 16, padding: '0 14px', height: 28, alignItems: 'flex-end', fontSize: 12.5, color: '#3A3B40', borderBottom: '1px solid #D6D6DA', background: '#F3F3F5'}}>
    {tabs.map((tb) => <div key={tb} style={{padding: '0 2px 5px', borderBottom: tb === on ? `2.5px solid ${accent}` : '2.5px solid transparent', color: tb === on ? accent : '#3A3B40', fontWeight: tb === on ? 600 : 400}}>{tb}</div>)}
  </div>
);
const OfficeTitle = ({file, accent, glyph, auto = true}: {file: string; accent: string; glyph: string; auto?: boolean}) => (
  <div style={{height: 34, background: '#F3F3F5', position: 'relative', fontFamily: ui}}>
    <Lights />
    <div style={{position: 'absolute', left: 78, top: 9, display: 'flex', alignItems: 'center', gap: 7, fontSize: 11, color: '#5A5B60'}}>
      <div style={{width: 18, height: 18, borderRadius: 4, background: accent, color: '#fff', fontWeight: 800, fontSize: 11.5, textAlign: 'center', lineHeight: '18px'}}>{glyph}</div>{auto && <>AutoSave
      <div style={{width: 26, height: 14, borderRadius: 7, background: '#C9CACE', position: 'relative'}}><div style={{position: 'absolute', left: 2, top: 2, width: 10, height: 10, borderRadius: 5, background: '#fff'}} /></div></>}
    </div>
    <div style={{position: 'absolute', left: 0, right: 0, top: 9, textAlign: 'center', fontSize: 13, fontWeight: 600, color: '#3A3B40'}}>{file}</div>
  </div>
);

export const DeckApp = () => {
  const slides = content.deck.slides, cur = 1;
  const mainW = 500, ms = mainW / 960;
  return (
    <div style={{position: 'absolute', inset: 0, background: '#fff', fontFamily: ui, display: 'flex', flexDirection: 'column'}}>
      <OfficeTitle file={files.deck} accent="#C43E1C" glyph="P" />
      <Tabs tabs={['Home', 'Insert', 'Draw', 'Design', 'Transitions', 'Animations', 'Slide Show', 'Review', 'View']} on="Home" accent="#C43E1C" />
      <div style={{height: 62, background: '#F8F8FA', borderBottom: '1px solid #D6D6DA', display: 'flex', alignItems: 'center', padding: '4px 6px'}}>
        <RibbonGroup label="Paste" icons={[30, 18]} /><RibbonGroup label="Slides" icons={[30, 22]} /><RibbonGroup label="Font" icons={[60, 22, 22]} /><RibbonGroup label="Paragraph" icons={[22, 22, 22, 22]} />
        <RibbonGroup label="Drawing" icons={[26, 26, 26]} /><RibbonGroup label="Editing" icons={[26, 26]} last />
      </div>
      <div style={{flex: 1, display: 'flex', minHeight: 0}}>
        <div style={{width: 128, background: '#EDEDF0', borderRight: '1px solid #D6D6DA', padding: '10px 0 0', overflow: 'hidden'}}>
          {slides.map((s, i) => (
            <div key={i} style={{display: 'flex', gap: 6, padding: '0 8px 0 6px', marginBottom: 8, alignItems: 'flex-start'}}>
              <span style={{width: 12, fontSize: 10.5, color: '#7C7E85', textAlign: 'right', marginTop: 2}}>{i + 1}</span>
              <div style={{width: 96, height: 54, position: 'relative', outline: i === cur ? '2px solid #C43E1C' : '1px solid #C9CACE', outlineOffset: i === cur ? 1 : 0, overflow: 'hidden', background: '#fff'}}>
                <div style={{transform: `scale(${96 / 960})`, transformOrigin: '0 0', position: 'absolute', left: 0, top: 0}}><Slide s={s} index={i} /></div>
              </div>
            </div>))}
        </div>
        <div style={{flex: 1, background: '#D4D5D9', position: 'relative', overflow: 'hidden'}}>
          <div style={{position: 'absolute', left: (800 - 128 - mainW) / 2, top: 14, width: mainW, height: 540 * ms, boxShadow: '0 2px 10px rgba(0,0,0,0.25)', overflow: 'hidden', background: '#fff'}}>
            <div style={{transform: `scale(${ms})`, transformOrigin: '0 0'}}><Slide s={slides[cur]} index={cur} /></div>
          </div>
        </div>
      </div>
      <div style={{height: 22, background: '#F3F3F5', borderTop: '1px solid #D6D6DA', fontSize: 10.5, color: '#6A6B70', display: 'flex', alignItems: 'center', padding: '0 12px', justifyContent: 'space-between'}}><span>Slide 2 of 4</span><span>Notes  ·  Comments  ·  Fit 100%</span></div>
    </div>
  );
};

// ---- Word -------------------------------------------------------------------------------------

export const DocApp = () => {
  const d = content.doc, blue = '#185ABD';
  return (
    <div style={{position: 'absolute', inset: 0, background: '#fff', fontFamily: ui, display: 'flex', flexDirection: 'column'}}>
      <OfficeTitle file={files.doc} accent={blue} glyph="W" auto={false} />
      <Tabs tabs={['Home', 'Insert', 'Draw', 'Design', 'Layout', 'References', 'Review', 'View']} on="Home" accent={blue} />
      <div style={{height: 62, background: '#F8F8FA', borderBottom: '1px solid #D6D6DA', display: 'flex', alignItems: 'center', padding: '4px 6px'}}>
        <RibbonGroup label="Paste" icons={[30, 18]} /><RibbonGroup label="Font" icons={[70, 22, 22]} /><RibbonGroup label="Paragraph" icons={[22, 22, 22]} /><RibbonGroup label="Styles" icons={[40, 40]} last />
      </div>
      <div style={{flex: 1, background: '#D4D5D9', position: 'relative', overflow: 'hidden'}}>
        <div style={{height: 18, background: '#EDEDF0', borderBottom: '1px solid #D6D6DA', position: 'relative'}}>
          <div style={{position: 'absolute', left: 44, right: 44, top: 5, height: 9, background: '#fff', borderLeft: '36px solid #D9DADE', borderRight: '36px solid #D9DADE', backgroundImage: 'repeating-linear-gradient(90deg, #9A9BA0 0 1px, transparent 1px 12px)', backgroundSize: '12px 4px', backgroundRepeat: 'repeat-x', backgroundPosition: '0 5px'}} />
        </div>
        <div style={{position: 'absolute', left: 36, right: 36, top: 30, bottom: -40, background: '#fff', boxShadow: '0 1px 8px rgba(0,0,0,0.25)', padding: '34px 42px', color: '#222'}}>
          <div style={{fontFamily: 'Georgia, "Times New Roman", serif', fontSize: 25, fontWeight: 700, lineHeight: 1.18, color: '#1F2A44'}}>{d.title}</div>
          <div style={{fontSize: 11.5, color: '#7A7C82', margin: '6px 0 14px', paddingBottom: 10, borderBottom: '1px solid #E1E2E6'}}>{d.byline}</div>
          {d.sections.map((sec) => (
            <div key={sec.heading} style={{marginBottom: 10}}>
              <div style={{fontSize: 14.5, fontWeight: 700, color: blue, marginBottom: 3}}>{sec.heading}</div>
              {'body' in sec && sec.body && <div style={{fontSize: 12, lineHeight: 1.5}}>{sec.body}</div>}
              {'quotes' in sec && sec.quotes?.map((q) => <div key={q} style={{fontSize: 12, fontStyle: 'italic', lineHeight: 1.45, borderLeft: `3px solid ${blue}`, padding: '1px 0 1px 10px', margin: '4px 0', color: '#3A3F4A'}}>{q}</div>)}
              {'bullets' in sec && sec.bullets?.map((b) => <div key={b} style={{fontSize: 12, lineHeight: 1.5, paddingLeft: 18, position: 'relative'}}><span style={{position: 'absolute', left: 5}}>•</span>{b}</div>)}
            </div>))}
        </div>
      </div>
    </div>
  );
};
