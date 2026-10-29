import {createElement, Fragment, type ComponentType} from 'react';
import {Captions} from './director/kit';
import {PaperCard} from './director/PaperCard';
import {Switchboard} from './director/Switchboard';
import {Opening} from './director/Opening';
import {Levels} from './director/Levels';
import {FirstPrompt} from './director/FirstPrompt';
import {Skill} from './director/Skill';
import {Additions} from './director/Additions';
import {WhyItWorks} from './director/WhyItWorks';
import {Generalists} from './director/Generalists';
import {Done} from './director/Done';
import {Patterns} from './director/Patterns';
import {NextUp, Projects, StartHere} from './director/Ending';
import {FromLine, Standup, Team} from './director/Stories';
import {ReleaseApp, captioned as releaseCaptioned} from './release-0-2-21/ReleaseApp';
import {ReleaseEnd, ReleaseTitle} from './release-0-2-21/Title';

/** What a registered scene draws: the time in the scene, its events (seconds), and the scene's timeline entry. */
export type SceneProps = {t: number; ev: Record<string, number>; scene: {id: string; title: string; topic?: string | null; lines?: {text: string; start: number; duration: number}[]}};

/** The director film's scenes carry captions of their voice lines (DL-180). */
const captioned = (C: ComponentType<SceneProps>): ComponentType<SceneProps> => (p: SceneProps) =>
  createElement(Fragment, null, createElement(C, p), createElement(Captions, {t: p.t, lines: p.scene.lines ?? []}));

/**
 * Scene kinds other films add: a drawn scene whose shot says `scene: "<kind>"` is drawn by the component listed here,
 * which Film.tsx consults before its own branches. A new film registers its scenes here (they live in src/scenes/<film>/,
 * which only that film's render keys hash). The intro's scenes stay Film.tsx's branches.
 */
export const SCENE_KINDS: Record<string, ComponentType<SceneProps>> = {
  'paper-card': PaperCard,
  'dir-switchboard': captioned(Switchboard),
  'dir-opening': captioned(Opening),
  'dir-levels': captioned(Levels),
  'dir-prompt': captioned(FirstPrompt),
  'dir-skill': captioned(Skill),
  'dir-additions': captioned(Additions),
  'dir-why': captioned(WhyItWorks),
  'dir-generalists': captioned(Generalists),
  'dir-done': captioned(Done),
  'dir-patterns': captioned(Patterns),
  'dir-projects': captioned(Projects),
  'dir-next': captioned(NextUp),
  'dir-start': captioned(StartHere),
  'dir-brief': captioned(FromLine),
  'dir-team': captioned(Team),
  'dir-standup': captioned(Standup),
  // The 0.2.21 release film (films/release-0-2-21): the title card and its ending, and app scenes with captions.
  'rel-title': releaseCaptioned(ReleaseTitle),
  'rel-app': releaseCaptioned(ReleaseApp),
  'rel-end': releaseCaptioned(ReleaseEnd),
};
