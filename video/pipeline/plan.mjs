// Turn the script, the voiced lines, the shots and the captures into build/public/timeline.json.
// Voice timing is the beat map: a camera move lands on the word that names its subject.
import {BuildError} from './util.mjs';

const norm = (s) => s.toLowerCase().replace(/[^a-z0-9 ]/g, ' ').split(/\s+/).filter(Boolean);

function wordTime(line, phrase) {
  const want = norm(phrase);
  const words = line.words.map((w) => ({...w, n: norm(w.word).join(' ')}));
  for (let i = 0; i < words.length; i++) {
    if (want.every((w, j) => words[i + j] && words[i + j].n === w)) return words[i].start;
  }
  throw new BuildError(`plan: ${line.id} has no word "${phrase}" to land on (heard: ${line.words.map((w) => w.word).join(' ')})`);
}

function findAnchor(cap, text, state) {
  const els = cap.anchors?.elements ?? [];
  const t = text.toLowerCase();
  const hit = els.find((e) => (e.identifier ?? '').toLowerCase() === t)
    ?? els.find((e) => (e.label ?? '').toLowerCase() === t)
    ?? els.find((e) => [e.label, e.value, e.identifier].some((v) => (v ?? '').toLowerCase().includes(t)));
  if (!hit) throw new BuildError(`anchor: "${text}" is not in ${state}'s anchors (${els.length} elements). Renamed or removed?`);
  return hit.frame;
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
    const lines = [];
    let t = style.voice.leadIn;
    for (const l of scene.lines) {
      const v = byId.get(l.id);
      lines.push({...v, start: +t.toFixed(3)});
      t += v.duration + style.voice.gap;
    }
    let end = Math.max(t + style.voice.tail, style.voice.minScene);
    const s = {id: scene.id, title: scene.title, kind: shot.kind, start: 0, duration: 0, lines};
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
        const f = findAnchor(cap, to.anchor, shot.state);
        const w = Math.max(to.width ?? 600, minW, (f.w + 2 * (to.pad ?? 24)));
        const h = w / aspect;
        let x = to.align === 'left' ? f.x - (to.pad ?? 24) : f.x + f.w / 2 - w / 2;
        let y = f.y + f.h / 2 - h / 2;
        x = Math.min(Math.max(x, 0), desk.winW - w); y = Math.min(Math.max(y, 0), desk.winH - h);
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
      Object.assign(s, {capture: {src: cap.src, scale: style.capture.scale}, desk, camera: keys, appear: !!shot.appear});
    } else throw new BuildError(`shots: ${scene.id} has unknown kind "${shot.kind}"`);
    s.start = +t0.toFixed(3);
    s.duration = +end.toFixed(3);
    t0 += end;
    out.push(s);
  }
  const duration = +t0.toFixed(3);
  return {fps, duration, frames: Math.ceil(duration * fps), fade: style.transition.fade, scenes: out};
}
