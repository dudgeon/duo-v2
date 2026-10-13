// The stale-anchor check. plan() notes every rect an app scene reads (a camera, a mark, a click, a menu, a wipe, a drag):
// the anchor it follows, or, for a rect in window points, the video.* anchors inside it. Against the last accepted
// build's notes (.cache/anchors-used.json), a rect that follows an anchor moves with it, and is named so the move can
// be looked at; a rect in window points whose anchors moved, left or arrived is stale: the app changed under it.
// Stale notes keep the last accepted record, so the warning stays until the rect is fixed or --accept-anchors is passed.
import {existsSync, readFileSync, writeFileSync} from 'node:fs';
import {join} from 'node:path';

const keyed = (used) => {
  const out = new Map(), n = new Map();
  for (const u of used) {
    const k = `${u.scene} beat ${u.beat} ${u.role}`;
    const i = (n.get(k) ?? 0) + 1;
    n.set(k, i);
    out.set(i > 1 ? `${k} ${i}` : k, u);
  }
  return out;
};
const same = (a, b) => a && b && ['x', 'y', 'w', 'h'].every((k) => Math.abs(a[k] - b[k]) < 0.5);
const delta = (a, b) => `${b.x - a.x >= 0 ? '+' : ''}${Math.round(b.x - a.x)},${b.y - a.y >= 0 ? '+' : ''}${Math.round(b.y - a.y)}` +
  (Math.abs(a.w - b.w) >= 0.5 || Math.abs(a.h - b.h) >= 0.5 ? ` (${Math.round(a.w)}x${Math.round(a.h)} → ${Math.round(b.w)}x${Math.round(b.h)})` : '');
const frameOf = (cap, id) => {
  const e = (cap?.anchors?.anchors ?? []).find((x) => x.identifier === id);
  return e && {x: e.frame.x, y: e.frame.y, w: e.frame.width, h: e.frame.height};
};

// record: false (the check stage) compares without writing.
export function checkAnchors({used, captures, cache, accept = false, record = true, name = 'anchors-used.json'}) {
  const file = join(cache, name);
  const before = existsSync(file) ? keyed(JSON.parse(readFileSync(file, 'utf8'))) : null;
  const now = keyed(used);
  const moved = [], stale = [], staleKeys = new Set();
  if (before) for (const [k, u] of now) {
    const b = before.get(k);
    if (!b) continue;
    if (u.anchor) {
      // Clicks and menus follow their anchors without comment; the framing is what's worth a look.
      if (b.anchor === u.anchor && !same(b.rect, u.rect) && !['click', 'menu'].includes(u.role)) moved.push(`${k} follows ${u.anchor} in ${u.state}: moved ${delta(b.rect, u.rect)}`);
      continue;
    }
    if (b.anchor || b.state !== u.state) continue;
    // A rect in window points: did what it framed stay put?
    const why = [];
    for (const a of b.inside) {
      const f = frameOf(captures[u.state], a.anchor);
      if (!f) why.push(`${a.anchor} is gone`);
      else if (!same(a.rect, f)) why.push(`${a.anchor} moved ${delta(a.rect, f)}`);
    }
    for (const a of u.inside) if (!b.inside.some((x) => x.anchor === a.anchor)) why.push(`${a.anchor} is now inside it`);
    if (why.length) staleKeys.add(k), stale.push(`${k} is a rect in window points in ${u.state}, and the app moved under it: ${why.slice(0, 4).join('; ')}${why.length > 4 ? ` and ${why.length - 4} more` : ''}. Re-frame it, or make it follow an anchor (rel, fit or on).`);
  }
  const absolute = used.filter((u) => u.absolute && u.role !== 'click').length;
  if (!record) {}
  else if (accept || !stale.length) writeFileSync(file, JSON.stringify(used, null, 1));
  else {
    // Keep the accepted notes for the stale rects; take the rest from this build.
    const keep = [...now].map(([k, u]) => (staleKeys.has(k) && before.get(k)) || u);
    writeFileSync(file, JSON.stringify(keep, null, 1));
  }
  return {moved, stale, absolute, first: !before};
}
