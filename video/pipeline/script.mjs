// Parse video/script.md, the export of the script Doc (DL-169).
// Scenes are `### S<n> · <title> (about N s)`; each bullet under one is a voiceover line;
// a paragraph starting `Shot:` is the shot note. The table under `## The voice` is the
// pronunciation lexicon (Written | Said): Said is what the voice is given.

export function parseScript(md) {
  const scenes = [];
  const lexicon = [];
  let scene = null, inVoice = false;
  for (const raw of md.split('\n')) {
    const line = raw.trimEnd();
    const h2 = line.match(/^## (.*)/);
    if (h2) { inVoice = /voice/i.test(h2[1]); scene = null; continue; }
    const h3 = line.match(/^### (S\d+)\s*·\s*(.+?)(?:\s*\(about (\d+) s\))?$/);
    if (h3) {
      scene = {id: h3[1], title: h3[2].trim(), targetSeconds: h3[3] ? +h3[3] : null, lines: [], shot: ''};
      scenes.push(scene);
      continue;
    }
    if (inVoice) {
      const row = line.match(/^\|\s*([^|]+?)\s*\|\s*([^|]+?)\s*\|$/);
      if (row && !/^-+$/.test(row[1]) && row[1] !== 'Written') {
        const saidAs = row[2].replace(/\s*\(.*\)\s*$/, ''); // a note in brackets is for people, not the voice
        for (const w of row[1].split(',').map((s) => s.trim()).filter(Boolean)) lexicon.push({written: w, said: saidAs});
      }
      continue;
    }
    if (!scene) continue;
    const bullet = line.match(/^[-*]\s+(.+)/);
    if (bullet) {
      const text = bullet[1].replace(/\*\*|`/g, '').trim();
      scene.lines.push({id: `${scene.id}-${scene.lines.length + 1}`, text});
      continue;
    }
    const shot = line.match(/^Shot:\s*(.+)/);
    if (shot) scene.shot = shot[1].trim();
  }
  return {scenes, lexicon};
}

/** What the voice is given: each Written form replaced by its Said form, longest first, as whole words. */
export function said(text, lexicon) {
  let out = text;
  for (const {written, said: s} of [...lexicon].sort((a, b) => b.written.length - a.written.length)) {
    if (written === s) continue;
    const esc = written.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    out = out.replace(new RegExp(`(^|[^\\w])${esc}(?=$|[^\\w])`, 'g'), (_, pre) => pre + s);
  }
  return out;
}
