// The director film's one world: you, the director and the sessions, at their places in each layout. Scenes start
// where the scene before ended (no cuts), so every layout a scene hands on is defined here once, and both scenes use it.
import type {Box, State} from './kit';

/** The ten sessions, named for real work on Duo from the director's first week (decisions.md, findings.md). */
export const SESSIONS = ['Chat mode', 'Word viewer', 'Task board', 'PowerPoint viewer', 'Search', 'Freeze fix', 'Intro film',
  'Remote Control', 'Tasks', 'Codebase review'];

/** S1: you in the middle, the sessions on a ring around you. */
export const RING_YOU: Box = {x: 810, y: 500, w: 300, h: 164};
export const RING_ROW = {w: 300, h: 64};
export const ringRow = (i: number): Box => {
  const a = -Math.PI / 2 + (i + 0.5) * (2 * Math.PI / SESSIONS.length);
  const cx = 960 + 700 * Math.cos(a), cy = 582 + 300 * Math.sin(a);
  return {x: cx - RING_ROW.w / 2, y: cy - RING_ROW.h / 2, ...RING_ROW};
};

/** S2's end, the approved style frame B: you, the director, and the sessions in a panel. */
export const TREE_YOU: Box = {x: 144, y: 420, w: 300, h: 168};
export const TREE_DIRECTOR: Box = {x: 600, y: 404, w: 380, h: 200};
export const PANEL: Box = {x: 1180, y: 188, w: 596, h: 704};
export const PANEL_ROW_H = 60;
export const panelRow = (i: number): Box => ({x: PANEL.x + 2, y: PANEL.y + 72 + i * PANEL_ROW_H, w: PANEL.w - 4, h: PANEL_ROW_H});
export const BUS_X = 1080;

/** What the director's first survey found: the states the tree settles into (attention order, as Duo sorts). */
export const SURVEY: {state: State; right?: string}[] = [
  {state: 'needs', right: '12m'}, {state: 'needs', right: '4m'}, {state: 'review'}, {state: 'review'},
  {state: 'working', right: 'working'}, {state: 'working', right: 'working'}, {state: 'working', right: 'working'},
  {state: 'idle', right: '1h'}, {state: 'idle', right: '3h'}, {state: 'done'},
];
/** The order the sessions sit in the panel once surveyed: SURVEY[k] belongs to SESSIONS[ORDER[k]]. */
export const ORDER = [1, 9, 0, 3, 2, 6, 7, 4, 8, 5];

/** The first prompt, verbatim (Geoff, 2026-10-05 10:08, the first director's transcript). Part A is said in S2's
 *  second line; part B, the survey, in its third. */
export const PROMPT_A = 'There are many sessions in this repo/project all in various states—you are now their director. I am the PM and you are the engineering manager.';
export const PROMPT_B = ' Please do a quick survey of the state of each of these active sessions';

/** Twenty minutes later, the rest of the job (Geoff, 2026-10-05 10:25, the first director's transcript, verbatim). */
export const PROMPT_C = 'I think it would be helpful for you to make and maintain a director reviews artifact; in it you will surface decisions for me and have ui buttons that when I interact with them send you messages\n\nI don\u2019t want to recreate the feature walks (though you should take over that artifact); this is more abstract; it will cover what to do with the various branches and worktrees, when to review, merge, ship, how to resolve conflicts, etc\n\nYou should be periodically watching all other agents in this space and reviewing their work, surfacing decisions to me as needed';
/** An idea sent from the phone (Geoff to the director, 2026-10-12 06:53, verbatim). */
export const IDEA = 'New enhancement: I still think it is not obvious that sessions in the project view left pane are sessions.';
