// Turn the script, the voiced lines, the shots and the captures into build/public/timeline.json.
// Voice timing is the beat map: a camera move lands on the word that names its subject.
import {readFileSync} from 'node:fs';
import {spawnSync} from 'node:child_process';
import {BuildError} from './util.mjs';

const norm = (s) => s.toLowerCase().replace(/[^a-z0-9 ]/g, ' ').split(/\s+/).filter(Boolean);

function wordTime(line, phrase, nth = 1) {
  // `nth` picks a later occurrence when a word repeats in the line ("files" twice).
  const want = norm(phrase);
  const words = line.words.map((w) => ({...w, n: norm(w.word).join(' ')}));
  let seen = 0;
  for (let i = 0; i < words.length; i++) {
    if (want.every((w, j) => words[i + j] && words[i + j].n === w) && ++seen === nth) return words[i].start;
  }
  throw new BuildError(`plan: ${line.id} has no word "${phrase}" to land on (heard: ${line.words.map((w) => w.word).join(' ')})`);
}

function findAnchor(cap, text, state) {
  // A rect in window points stands in where the UI has no label to anchor on (the native document view).
  if (typeof text === 'object') return {x: text.x, y: text.y, w: text.w, h: text.h};
  const els = cap.anchors?.anchors ?? [];
  const t = text.toLowerCase();
  const hit = els.find((e) => (e.identifier ?? '').toLowerCase() === t)
    ?? els.find((e) => (e.label ?? '').toLowerCase() === t)
    ?? els.find((e) => [e.label, e.value, e.identifier].some((v) => (v ?? '').toLowerCase().includes(t)));
  if (!hit) throw new BuildError(`anchor: "${text}" is not in ${state}'s anchors (${els.length} elements). Renamed or removed?`);
  const f = hit.frame;
  return {x: f.x, y: f.y, w: f.width, h: f.height};
}

// No shot ever cuts to the next (script rule, Geoff 2026-10-11). Every scene after the first names its
// way in, `transitionIn` in shots.json, from this list; a scene change without one stops the build.
// kind 'app': we get there by using the app (camera pulls back, the cursor clicks, the camera pushes in).
// kind 'graphic': a different idea, so a motion-graphics move. `out` seconds are added to the end of the
// scene before (its exit plays there); `in` seconds open this scene (its entry plays there, before the voice).
// style/shot-grammar.md, "Transitions", describes each one.
export const TRANSITIONS = {
  'logo-to-dock': {kind: 'graphic', from: 'logo', to: 'desk', out: 1.45},
  'dock-launch': {kind: 'app', from: 'desk', to: 'morph', in: 1.5, click: 0.85},
  // Somewhere else in Duo: the camera pulls back to show what to click, the cursor clicks it, the new
  // state comes up and the scene's own beats push in. The scene's `entry` names the click target.
  'click-through': {kind: 'app', from: ['morph', 'app'], to: 'app', in: 1.6, click: 0.95},
  // The next idea happens in the same place: the picture carries straight on (same state, same camera),
  // and the scene's own first click is what moves us. Never a cut: the frames either side are identical.
  'carry-on': {kind: 'app', from: 'app', to: 'app'},
  // Out of Duo for a new idea (S8, Geoff 2026-10-11): the scene opens on the last picture, wide, and fades Duo's window
  // away to the bare desktop on its own `fade` event.
  'duo-fades': {kind: 'graphic', from: 'app', to: 'projects'},
  // Back into Duo: the scene before fades its pile out and Duo's window in, on the next scene's first capture.
  'pile-to-duo': {kind: 'graphic', from: 'projects', to: 'app', out: 1.6},
  // To the closing paper (S11): Duo's window steps away as a thumbnail while the paper ground fills in.
  'duo-steps-away': {kind: 'graphic', from: 'app', to: 'conclusion'},
};
const sceneType = (shot) => (shot.kind === 'drawn' ? shot.scene : shot.kind);
const fromOk = (tr, type) => (Array.isArray(tr.from) ? tr.from.includes(type) : tr.from === type);

// A rect in window points from a capture's anchors: an id (video.*) or a label.
function anchorRect(cap, key, state, sceneId) {
  if (typeof key === 'object') return key;
  const els = cap.anchors?.anchors ?? [];
  const k = key.toLowerCase();
  const hit = els.find((e) => (e.identifier ?? '').toLowerCase() === k) ?? els.find((e) => (e.label ?? '').toLowerCase() === k)
    ?? els.find((e) => (e.label ?? '').toLowerCase().startsWith(k));
  if (!hit) throw new BuildError(`anchor: ${sceneId} needs "${key}" in ${state}, but it isn't among its ${els.length} anchors. Renamed or removed?`);
  return {x: hit.frame.x, y: hit.frame.y, w: hit.frame.width, h: hit.frame.height};
}
const centre = (r, fx = 0.5, fy = 0.5) => ({x: r.x + r.w * fx, y: r.y + r.h * fy});

// kind drawn/app (S3 on): a run of captures with clicks, menus, drags, camera moves and markers on the
// voice's words. Returns AppScene's data (src/scenes/App.tsx); all rects in window points.
function planApp({scene, shot, lines, tr, prev, prevShot, captures, events, style}) {
  const cap = (st) => { if (!captures[st]) throw new BuildError(`shots: ${scene.id} needs a capture of ${st}`); return captures[st]; };
  const when = (a, last) => {
    if (typeof a === 'number') return a;
    if (a.after !== undefined) return last + a.after;
    const line = lines[a.line - 1];
    if (!line) throw new BuildError(`shots: ${scene.id} names line ${a.line}, but the scene has ${lines.length}`);
    return line.start + (a.word ? wordTime(line, a.word, a.nth) : 0) + (a.offset ?? 0);
  };
  const first = cap(shot.states[0]);
  const data = {window: {w: first.widthPt, h: first.heightPt}, scale: style.capture.scale, src: {}, panes: {}, steps: [], clicks: [], drags: [], cams: [], marks: [], menus: [], ends: []};
  const paneRects = (c) => {
    const out = {};
    for (const id of ['video.pane.left', 'video.pane.middle', 'video.pane.right']) {
      const e = (c.anchors?.anchors ?? []).find((x) => x.identifier === id);
      if (e) out[id.split('.').pop()] = {x: e.frame.x, y: e.frame.y, w: e.frame.width, h: e.frame.height};
    }
    return out;
  };
  data.panes = paneRects(first);
  const use = (st) => { data.src[st] = cap(st).src; return st; };
  let state;
  // The way in: from the scene before's last picture, the click that brings this scene's first state.
  if (tr?.click !== undefined) {
    const en = shot.entry ?? {};
    const prevApp = prev?.app;
    const base = en.base ?? (prevApp ? prevApp.lastState : undefined);
    if (!base) throw new BuildError(`shots: ${scene.id}'s entry needs a base state (the picture ${prev?.id} ends on)`);
    use(base);
    const panes = Object.fromEntries(Object.entries(en.panes ?? {}).map(([p, st]) => [p, use(st)]));
    const target = anchorRect(cap(base), en.click, base, scene.id);
    if (prevApp?.lastCam !== undefined) data.startCam = prevApp.lastCam;
    // Pull back (or across) to show where we'll click, click, then the new state.
    data.cams.push({at: tr.click - 0.15, dur: tr.click - 0.15, rect: en.view ? anchorRect(cap(base), en.view, base, scene.id) : null});
    data.clicks.push({at: tr.click, ...centre(target)});
    const at = tr.click + 0.1;
    // The panes are cut where they stand in the base picture (its layout), not in this scene's first state.
    data.entry = {base, panes, until: at, rects: paneRects(cap(base))};
    state = use(shot.states[0]);
    data.steps.push({at: 0, state});
    events.entry = at;
  } else if (prev?.app) {
    state = use(prev.app.lastState);
    data.steps.push({at: 0, state});
    if (prev.app.lastCam !== undefined) data.startCam = prev.app.lastCam;
  } else {
    state = use(shot.states[0]);
    data.steps.push({at: 0, state});
  }
  let last = tr?.in ?? 0, lastCam = data.startCam ?? null;
  for (const b of shot.beats ?? []) {
    const at = +when(b.at, last).toFixed(3);
    const inSt = b.in ? use(b.in) : state;
    const rect = (k) => anchorRect(cap(inSt), k, inSt, scene.id);
    // cam: an anchor, 'wide', a rect in window points, or {on: anchor, x0, x1, y0, y1}: a part of an anchor (fractions),
    // for panes taller than the frame, where fitting the whole pane would barely zoom.
    const camRect = (c) => {
      if (c === 'wide') return null;
      if (typeof c === 'object' && c.on) { const r = rect(c.on); return {x: r.x + r.w * (c.x0 ?? 0), y: r.y + r.h * (c.y0 ?? 0), w: r.w * ((c.x1 ?? 1) - (c.x0 ?? 0)), h: r.h * ((c.y1 ?? 1) - (c.y0 ?? 0))}; }
      return rect(c);
    };
    if (b.cam !== undefined) { lastCam = camRect(b.cam); data.cams.push({at, dur: b.dur ?? 0.9, rect: lastCam}); }
    if (b.click) data.clicks.push({at, ...centre(rect(b.click), b.fx ?? 0.5, b.fy ?? 0.5), right: !!b.right});
    // drag.reveal: a capture of the selection the drag makes, shown from where the drag began to the cursor as it moves.
    if (b.drag) data.drags.push({at, dur: b.drag.dur ?? 0.7, from: centre(rect(b.drag.from), b.drag.fx0 ?? 0, 0.5), to: centre(rect(b.drag.to ?? b.drag.from), b.drag.fx1 ?? 1, 0.5),
      ...(b.drag.reveal ? {reveal: {state: use(b.drag.reveal), rect: rect(b.drag.from)}} : {})});
    if (b.menu) {
      const r = rect(b.menu.on);
      const p = centre(r, b.fx ?? 0.5, b.fy ?? 0.5);
      data.menus.push({at, until: at + (b.menu.hold ?? 0.9), x: p.x, y: p.y, items: b.menu.items, hi: b.menu.pick ? {at: at + (b.menu.pickAfter ?? 0.55), item: b.menu.pick} : undefined});
      if (b.menu.pick) {
        // The pick is a click on the drawn item: aim at its row (about 22 pt each, below the click).
        // App.tsx's ContextMenu: 5 px padding, 22 px items, 11 px separators, in frame px at 0.855 px a point.
        const idx = b.menu.items.indexOf(b.menu.pick);
        const px = 7 + b.menu.items.slice(0, idx).reduce((y, it) => y + (it === '-' ? 11 : 22), 0) + 11;
        data.clicks.push({at: at + (b.menu.pickAfter ?? 0.55), x: p.x + 70 / 0.855, y: p.y + px / 0.855});
      }
      data.clicks.push({at, ...p, right: true});
    }
    // key: a shortcut's keycaps as it's pressed; wipe: a state revealed left to right inside an anchor (typing).
    if (b.key) (data.keys ??= []).push({at, label: b.key});
    if (b.wipe) (data.wipes ??= []).push({at, dur: b.wipe.dur ?? 1.2, state: use(b.wipe.state), rect: camRect(b.wipe.on)});
    if (b.mark) data.marks.push({at, until: at + (b.hold ?? 2.2), rect: camRect(b.mark), quote: b.quote});
    if (b.state) { state = use(b.state); data.steps.push({at: +(at + (b.stateAfter ?? 0.1)).toFixed(3), state}); }
    data.ends.push(at + (b.hold ?? 0.6));
    last = at;
  }
  data.lastState = state;
  data.lastCam = lastCam;
  return data;
}

export function plan({scenes, shots, voiced, captures, style}) {
  const fps = style.frame.fps, aspect = style.frame.width / style.frame.height;
  const minW = style.frame.width / style.capture.scale; // narrower would magnify past 1:1
  const byId = new Map(voiced.map((l) => [l.id, l]));
  const out = [];
  let t0 = 0;
  for (const scene of scenes) {
    const shot = shots[scene.id];
    if (!shot) throw new BuildError(`shots: scene ${scene.id} "${scene.title}" has no shot in shots.json`);
    const prev = out[out.length - 1];
    let tr;
    if (prev) {
      const name = shot.transitionIn;
      tr = TRANSITIONS[name];
      if (!tr) throw new BuildError(`transition: ${scene.id} has no way in from ${prev.id}${name ? ` ("${name}" is not in plan.mjs TRANSITIONS)` : ''}. Shots never cut: give ${scene.id} a transitionIn (app navigation if it's somewhere else in the app, a motion graphic if it's a new idea).`);
      const pt = sceneType(shots[prev.id]);
      if (!fromOk(tr, pt) || tr.to !== sceneType(shot)) throw new BuildError(`transition: "${name}" goes ${tr.from} -> ${tr.to}, but ${prev.id} -> ${scene.id} is ${pt} -> ${sceneType(shot)}`);
      if (tr.out) {
        prev.exit = {name, at: prev.duration};
        if (prev.drawn) prev.drawn.events.exit = prev.duration;
        prev.duration = +(prev.duration + tr.out).toFixed(3);
        t0 += tr.out;
      }
    }
    const lines = [];
    let t = shot.leadIn ?? style.voice.leadIn; // a shot that opens on picture alone (S0's logo build) waits longer
    // `pauses` {"2": 1.8}: extra seconds of picture after a line, for beats the voice doesn't name (a turn arriving).
    scene.lines.forEach((l, i) => {
      const v = byId.get(l.id);
      lines.push({...v, start: +t.toFixed(3)});
      t += v.duration + style.voice.gap + (shot.pauses?.[i + 1] ?? 0);
    });
    let end = Math.max(t + (shot.tail ?? style.voice.tail), style.voice.minScene);
    const s = {id: scene.id, title: scene.title, topic: scene.topic ?? null, kind: shot.kind, start: 0, duration: 0, lines};
    if (shot.kind === 'card') {
      Object.assign(s, {card: {title: shot.title, sub: shot.sub, standIn: !!shot.standIn}});
    } else if (shot.kind === 'desk') {
      const cap = captures[shot.state];
      const deskW = Math.round(cap.widthPt / style.desk.windowWidthShare), deskH = Math.round(deskW / aspect);
      const desk = {deskW, deskH, winX: (deskW - cap.widthPt) / 2, winY: (deskH - cap.heightPt) / 2, winW: cap.widthPt, winH: cap.heightPt};
      const wide = {x: 0, y: 0, w: deskW, h: deskH};
      const rectFor = (to) => {
        if (to === 'wide') return wide;
        if (to === 'window') {
          let w = desk.winW * 1.06, h = w / aspect;
          if (h < desk.winH * 1.06) { h = desk.winH * 1.06; w = h * aspect; }
          return {x: desk.winX + desk.winW / 2 - w / 2, y: desk.winY + desk.winH / 2 - h / 2, w, h};
        }
        const f = findAnchor(cap, to.anchor ?? to.rect, shot.state);
        const paper = (shot.ground ?? 'paper') === 'paper';
        const w = Math.max(to.width ?? 600, minW, (f.w + 2 * (to.pad ?? 24)), paper ? style.camera.paperMinWidth : 0);
        const h = w / aspect;
        let x = to.align === 'left' ? f.x - (to.pad ?? 24) : f.x + f.w / 2 - w / 2;
        // An anchor taller than the frame (a pane) is framed from its top, where its content starts.
        let y = f.h + 2 * (to.pad ?? 24) > h ? f.y - (to.pad ?? 24) / 2 : f.y + f.h / 2 - h / 2;
        if (paper) {
          // On paper the window floats: keep a margin of paper in view, and when the shot is near the top,
          // show the window's top edge with a band above it for the chapter mark.
          const m = style.camera.paperMargin, band = style.camera.chapterBand;
          x = Math.min(Math.max(x, -m), desk.winW + m - w);
          y = Math.min(Math.max(y, -band), desk.winH + m - h);
          if (y < band) y = -band;
        } else { x = Math.min(Math.max(x, 0), desk.winW - w); y = Math.min(Math.max(y, 0), desk.winH - h); }
        return {x: x + desk.winX, y: y + desk.winY, w, h};
      };
      const keys = [{t: 0, rect: wide}];
      for (const m of shot.moves ?? []) {
        const line = lines[m.line - 1];
        if (!line) throw new BuildError(`shots: ${scene.id} move to ${JSON.stringify(m.to)} names line ${m.line}, but the scene has ${lines.length}`);
        const land = line.start + (m.land ? wordTime(line, m.land) : m.dur);
        const prev = keys[keys.length - 1];
        const start = Math.max(prev.t, land - m.dur);
        keys.push({t: +start.toFixed(3), rect: prev.rect}, {t: +land.toFixed(3), rect: rectFor(m.to)});
        end = Math.max(end, land + style.camera.hold);
      }
      for (const k of keys) {
        const mag = style.frame.width / k.rect.w / style.capture.scale;
        if (mag > style.camera.maxMagnification + 1e-9) throw new BuildError(`zoom: ${scene.id} magnifies ${mag.toFixed(2)}x past the capture`);
      }
      // Callouts: an anchor's rect in desk points, shown from a word of a line for `hold` seconds.
      const callouts = (shot.callouts ?? []).map((co) => {
        const line = lines[co.line - 1];
        if (!line) throw new BuildError(`shots: ${scene.id} callout "${co.label}" names line ${co.line}, but the scene has ${lines.length}`);
        const f = findAnchor(cap, co.anchor ?? co.rect, shot.state);
        const start = line.start + (co.word ? wordTime(line, co.word) : 0) + (co.offset ?? 0);
        const endAt = start + (co.hold ?? style.callout.hold);
        end = Math.max(end, endAt + 0.3);
        let crop;
        if (co.crop) {
          const c = typeof co.crop === 'string' ? findAnchor(cap, co.crop, shot.state) : co.crop;
          crop = {x: c.x - (co.cropPad ?? 8), y: c.y - (co.cropPad ?? 8), w: c.w + 2 * (co.cropPad ?? 8), h: c.h + 2 * (co.cropPad ?? 8)};
          if (co.cropHeight) crop.h = co.cropHeight;
        }
        return {rect: {x: f.x + desk.winX, y: f.y + desk.winY, w: f.w, h: f.h}, title: co.title, quote: co.quote, crop,
          start: +start.toFixed(3), end: +endAt.toFixed(3)};
      });
      Object.assign(s, {capture: {src: cap.src, scale: style.capture.scale}, desk, camera: keys, appear: !!shot.appear, callouts,
        ground: shot.ground ?? 'paper', chapter: shot.chapter ?? true});
    } else if (shot.kind === 'drawn') {
      // A drawn scene (src/lib/Clutter.tsx): its events happen on words of its lines.
      const events = {};
      for (const [name, e] of Object.entries(shot.events ?? {})) {
        const line = lines[e.line - 1];
        if (!line) throw new BuildError(`shots: ${scene.id} event ${name} names line ${e.line}, but the scene has ${lines.length}`);
        events[name] = +(line.start + (e.word ? wordTime(line, e.word, e.nth) : 0) + (e.offset ?? 0)).toFixed(3);
        end = Math.max(end, events[name] + 0.5);
      }
      if (tr?.in) {
        // The entry plays before anything else; the scene's own business starts when it ends.
        events.morph = tr.in;
        if (tr.click !== undefined) events.launch = tr.click;
        if (lines[0] && lines[0].start < tr.in + 0.6) throw new BuildError(`transition: ${scene.id}'s voice starts at ${lines[0].start}s, during its ${shot.transitionIn} entry (${tr.in}s). Raise its leadIn.`);
      }
      Object.assign(s, {drawn: {scene: shot.scene, events}});
      if (shot.scene === 'app') s.app = planApp({scene, shot, lines, tr, prev, prevShot: prev && shots[prev.id], captures, events, style});
      if (shot.scene === 'app') for (const b of s.app.ends) end = Math.max(end, b);
      if (shot.scene === 'morph') {
        // S2's morph draws panes from several captures of one layout; anchors come from the first.
        const caps = shot.states.map((st) => { if (!captures[st]) throw new BuildError(`shots: ${scene.id} needs a capture of ${st}`); return [st, captures[st]]; });
        const first = caps[0][1];
        const anchors = {};
        for (const e of first.anchors?.anchors ?? []) if ((e.identifier ?? '').startsWith('video.') && !anchors[e.identifier]) anchors[e.identifier] = {x: e.frame.x, y: e.frame.y, w: e.frame.width, h: e.frame.height};
        for (const id of ['video.pane.left', 'video.pane.middle', 'video.pane.right', 'video.tab.middle.1', 'video.tab.middle.2', 'video.tab.right.2', 'video.tab.right.3', 'video.tab.right.4'])
          if (!anchors[id]) throw new BuildError(`anchor: ${id} is not in ${shot.states[0]}'s anchors. Renamed or removed?`);
        s.morph = {window: {w: first.widthPt, h: first.heightPt}, scale: style.capture.scale, src: Object.fromEntries(caps.map(([st, c]) => [st, c.src])), anchors};
      }
      if (shot.scene === 'projects') {
        // S8: drawn windows on the desk. Duo's window (its first state's capture) fades out and, at the exit, back in
        // as the next scene's first state; the terminal screens are the real 2.1.296 renders from the fixture.
        const cap = (st) => { if (!captures[st]) throw new BuildError(`shots: ${scene.id} needs a capture of ${st}`); return captures[st]; };
        const first = cap(shot.states[0]), back = cap(shot.states[1] ?? shot.states[0]);
        const fx = (f) => readFileSync(new URL(`../fixture/${f}`, import.meta.url), 'utf8');
        s.projects = {window: {w: first.widthPt, h: first.heightPt}, scale: style.capture.scale, src: first.src, back: back.src,
          screens: Object.fromEntries(Object.entries(shot.screens ?? {}).map(([k, f]) => [k, fx(f)]))};
      }
      if (shot.scene === 'conclusion') {
        // S11: the release line is Duo's real releases, read from GitHub at build time (shot.releases is the fallback
        // when gh can't reach it), so the video's own "built from" stamp stays true.
        const cap = captures[shot.states[0]];
        if (!cap) throw new BuildError(`shots: ${scene.id} needs a capture of ${shot.states[0]}`);
        let releases = shot.releases ?? [];
        const gh = spawnSync('gh', ['release', 'list', '--limit', '40', '--json', 'tagName,publishedAt'], {encoding: 'utf8'});
        if (gh.status === 0) try { releases = JSON.parse(gh.stdout).map((r) => ({tag: r.tagName, date: r.publishedAt.slice(0, 10)})).reverse(); } catch {}
        const md = (iso) => new Date(iso + 'T12:00:00Z').toLocaleDateString('en-US', {month: 'short', day: 'numeric', timeZone: 'UTC'});
        const topics = []; for (const sc of scenes) if (sc.topic && sc.topic !== topics[topics.length - 1]) topics.push(sc.topic);
        const today = new Date();
        s.conclusion = {window: {w: cap.widthPt, h: cap.heightPt}, src: cap.src, topics, inProgress: shot.inProgress ?? [],
          releases: releases.map((r) => ({tag: r.tag, date: md(r.date)})), os: shot.os ?? 'macOS',
          built: today.toLocaleDateString('en-US', {month: 'short', day: 'numeric', year: 'numeric'})};
      }
      if (shot.scene === 'turn') {
        s.turn = {headline: shot.headline, projects: shot.projects, shots: shot.states.map((st) => {
          if (!captures[st]) throw new BuildError(`shots: ${scene.id} needs a capture of ${st}`);
          return captures[st].src;
        })};
      }
    } else throw new BuildError(`shots: ${scene.id} has unknown kind "${shot.kind}"`);
    if (tr) s.transitionIn = {name: shot.transitionIn, kind: tr.kind};
    s.start = +t0.toFixed(3);
    s.duration = +end.toFixed(3);
    t0 += end;
    out.push(s);
  }
  const duration = +t0.toFixed(3);
  return {fps, duration, frames: Math.ceil(duration * fps), fade: 0, scenes: out};
}
