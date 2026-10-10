import {Composition, staticFile} from 'remotion';
import {Film, type FilmTimeline} from './scenes/Film';
import tokens from '../style/tokens.json';
import {WallpaperSvg} from './lib/Desk';

// build.mjs writes build/public/timeline.json; the film's length comes from it.
export const Root = () => (
  <>
  {/* Rendered once as a still (at --scale=4) into build/public/wallpaper.png. */}
  <Composition id="Wallpaper" component={() => <WallpaperSvg w={tokens.frame.width} h={tokens.frame.height} />}
    width={tokens.frame.width} height={tokens.frame.height} fps={tokens.frame.fps} durationInFrames={1} />
  <Composition
    id="Intro"
    component={Film}
    width={tokens.frame.width}
    height={tokens.frame.height}
    fps={tokens.frame.fps}
    durationInFrames={tokens.frame.fps * 10}
    defaultProps={{timeline: null as FilmTimeline | null}}
    calculateMetadata={async () => {
      const timeline: FilmTimeline = await fetch(staticFile('timeline.json')).then((r) => r.json());
      return {durationInFrames: timeline.frames, props: {timeline}};
    }}
  />
  </>
);
