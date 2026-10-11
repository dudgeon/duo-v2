// S1's pile at its last frame: where every window sits, in 1920x1080 frame px, front to back by z.
// Clutter.tsx draws S1 from this same object, so S2's morph can start from exactly these rects
// (each window's `id` is the key of its open event in shots.json S1.events).

export type ClutterKind = 'terminal' | 'finder' | 'markdown' | 'browser' | 'deck' | 'doc';
export type ClutterWin = {id: string; kind: ClutterKind; x: number; y: number; w: number; h: number; z: number};

// Listed in the order they open (the order of the narration), so z rises with it: the window opened last is in front.
export const CLUTTER_LAYOUT: ClutterWin[] = [
  {id: 'term1', kind: 'terminal', x: 50, y: 70, w: 640, h: 390, z: 11},
  {id: 'term2', kind: 'terminal', x: 250, y: 300, w: 640, h: 390, z: 12},
  {id: 'finder', kind: 'finder', x: 30, y: 560, w: 560, h: 360, z: 13},
  {id: 'markdown', kind: 'markdown', x: 720, y: 55, w: 500, h: 390, z: 14},
  {id: 'browser', kind: 'browser', x: 1090, y: 70, w: 800, h: 540, z: 15},
  {id: 'deck', kind: 'deck', x: 1070, y: 490, w: 800, h: 470, z: 16},
  {id: 'doc', kind: 'doc', x: 590, y: 430, w: 470, h: 520, z: 17},
  {id: 'term3', kind: 'terminal', x: 330, y: 690, w: 540, h: 260, z: 18},
];

export const clutterWin = (id: string): ClutterWin => {
  const w = CLUTTER_LAYOUT.find((x) => x.id === id);
  if (!w) throw new Error(`clutterLayout: no window ${id}`);
  return w;
};
