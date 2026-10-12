import type {ComponentType} from 'react';
import {PaperCard} from './director/PaperCard';
import {Switchboard} from './director/Switchboard';
import {FirstPrompt} from './director/FirstPrompt';
import {Skill} from './director/Skill';
import {Additions} from './director/Additions';
import {WhyItWorks} from './director/WhyItWorks';
import {Generalists} from './director/Generalists';
import {Done} from './director/Done';
import {Patterns} from './director/Patterns';
import {NextUp, Projects, StartHere} from './director/Ending';

/** What a registered scene draws: the time in the scene, its events (seconds), and the scene's timeline entry. */
export type SceneProps = {t: number; ev: Record<string, number>; scene: {id: string; title: string; topic?: string | null}};

/**
 * Scene kinds other films add: a drawn scene whose shot says `scene: "<kind>"` is drawn by the component listed here,
 * which Film.tsx consults before its own branches. A new film registers its scenes here (they live in src/scenes/<film>/,
 * which only that film's render keys hash). The intro's scenes stay Film.tsx's branches.
 */
export const SCENE_KINDS: Record<string, ComponentType<SceneProps>> = {
  'paper-card': PaperCard,
  'dir-switchboard': Switchboard,
  'dir-prompt': FirstPrompt,
  'dir-skill': Skill,
  'dir-additions': Additions,
  'dir-why': WhyItWorks,
  'dir-generalists': Generalists,
  'dir-done': Done,
  'dir-patterns': Patterns,
  'dir-projects': Projects,
  'dir-next': NextUp,
  'dir-start': StartHere,
};
