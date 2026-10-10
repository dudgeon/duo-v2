# Shot grammar

The video's visual rules. Its numbers live in `video-tokens.json`. These rules grow with each milestone (M3).

## Wide shots: the window on a Mac desktop

**Every wide shot of the app is Duo's window on a Mac desktop** (Geoff, 2026-10-10: "it makes it feel more real"). The capture is `--capture-window`, frame and toolbar included. The renderer (`src/lib/Desk.tsx`) puts it on a desk:

- **The wallpaper is our own** macOS-style look-alike (`desk.wallpaper`), never Apple's image, which is Apple's copyright (Geoff chose the look-alike, 2026-10-10).
- **The window fills `desk.windowWidthShare`** of the frame's width, centred.
- **It has macOS's corner radius** (`desk.windowRadius`, 16 pt, to be checked against a real window) **and shadow** (`desk.shadow`).
- **The traffic lights are painted in their active colours.** A background capture is never the key window, so it draws them grey. Their size and position are measured from the capture: 14 pt across, centred at 19, 42 and 65 pt from the left and 20 pt from the top.

## The camera

- **It moves over the desk in desk points.** It starts wide, on the whole desk, and pushes into the window.
- **Zoom is eased in log space;** the centre moves on a smootherstep. `src/lib/camera.ts` has the code.
- **It never magnifies a capture past 1:1** at the output size. The build fails if a rect would. A 4x capture lands as tight as a 480 pt-wide region at 1080p, with frames identical to the capture's own pixels (F-276).
- **It holds at least `camera.hold` seconds** on a landed shot.

## Titles

Titles sit on the wallpaper, in white, before the window appears. The window fades in and grows from 96%.
