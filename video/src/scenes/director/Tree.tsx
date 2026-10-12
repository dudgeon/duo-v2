import React from 'react';
import {centre, DirectorCard, L, SectionLabel, SessionRow, Wire, YouCard, type Box, type State} from './kit';
import {BUS_X, ORDER, PANEL, panelRow, SESSIONS, SURVEY, TREE_DIRECTOR, TREE_YOU} from './board';

// The settled tree, as S2 ends and later scenes begin (style frame B): you, the director, the sessions in a panel,
// with one line between you and the director and a bus to every session. Parts can be dimmed, moved or restated by the
// scene drawing it; with the defaults it is exactly S2's last picture.

export type TreeProps = {
  you?: Box; director?: Box; panel?: Box; row?: (k: number) => Box; busX?: number;
  youU?: number; panelU?: number; wiresU?: number; directorU?: number;
  chip?: number; sub?: string; subU?: number; needs?: number; label?: string;
  states?: {state: State; right?: string}[]; names?: string[];
  directorChildren?: React.ReactNode; rowRight?: (k: number) => React.ReactNode;
};

/** Panel slot k holds SESSIONS[ORDER[k]], in the state the survey found. */
export const slotNames = ORDER.map((i) => SESSIONS[i]);

export const Tree = ({you = TREE_YOU, director = TREE_DIRECTOR, panel = PANEL, row = panelRow, busX = BUS_X, youU = 1, panelU = 1, wiresU = 1,
  directorU = 1, chip = 2, sub = 'engineering manager', subU = 1, needs = 2, label, states = SURVEY, names = slotNames, directorChildren, rowRight}: TreeProps) => {
  const yc = centre(you), dc = centre(director);
  const first = centre(row(0))[1], last = centre(row(names.length - 1))[1];
  return (
    <>
      <div style={{position: 'absolute', left: panel.x, top: panel.y, width: panel.w, height: panel.h, boxSizing: 'border-box', background: L.pane,
        border: `2px solid ${L.rule}`, borderRadius: 12, opacity: panelU}} />
      <SectionLabel x={panel.x + 32} y={panel.y + 24} text={label ?? `SESSIONS · ${names.length}`} u={panelU} />
      <div style={{position: 'absolute', inset: 0, opacity: wiresU}}>
        <Wire pts={[[director.x, dc[1]], [you.x + you.w + 1, yc[1]]]} head />
        <Wire pts={[[director.x + director.w, dc[1]], [busX, dc[1]]]} />
        <Wire pts={[[busX, Math.min(first, dc[1])], [busX, Math.max(last, dc[1])]]} />
        {names.map((_, k) => <Wire key={k} pts={[[busX, centre(row(k))[1]], [panel.x - 2, centre(row(k))[1]]]} head width={2.5} />)}
      </div>
      {names.map((name, k) => (
        <div key={name} style={{position: 'absolute', inset: 0, opacity: panelU}}>
          <SessionRow box={row(k)} name={name} state={states[k].state} right={rowRight ? undefined : states[k].right} flush />
          {rowRight?.(k)}
        </div>
      ))}
      <YouCard box={you} chip={chip} u={youU} />
      <div style={{position: 'absolute', inset: 0, opacity: directorU}}>
        <DirectorCard box={director} sub={sub} subU={subU} needs={needs}>{directorChildren}</DirectorCard>
      </div>
    </>
  );
};
