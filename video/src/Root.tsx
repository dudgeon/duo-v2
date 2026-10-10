import {Composition, staticFile} from 'remotion';
import {M0, type Timeline} from './scenes/M0';

const FPS = 30;

// The timeline is written by build.mjs; the composition's length comes from it.
export const Root = () => (
  <Composition
    id="M0"
    component={M0}
    width={1920}
    height={1080}
    fps={FPS}
    durationInFrames={FPS * 20}
    defaultProps={{timeline: null as Timeline | null}}
    calculateMetadata={async () => {
      const timeline: Timeline = await fetch(staticFile('timeline.json')).then((r) => r.json());
      return {durationInFrames: Math.ceil(timeline.duration * FPS), props: {timeline}};
    }}
  />
);
