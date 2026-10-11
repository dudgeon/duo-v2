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

Titles sit on the wallpaper, in white, before the window appears. The window grows in from 96%; a scene never fades in from another (see Transitions).

## Transitions

**No shot ever cuts or dissolves to the next** (Geoff, 2026-10-11). Every scene after the first names its way in (`transitionIn` in `shots.json`), from the list in `pipeline/plan.mjs` (`TRANSITIONS`). A scene change without one stops the build.

- **Somewhere else in the app: navigate.** The camera pulls back enough to show where we'll click, the cursor travels there and clicks (with a press), and the camera pushes in on what opens. Every frame is still a capture of the real app.
- **A different idea: a motion graphic.** Something already on screen carries across, rather than wiping the frame. The outgoing scene's last frame and the incoming scene's first frame must be the same picture.
- **Where the time goes:** a transition's `out` seconds are added to the end of the scene before (its exit), and its `in` seconds open the scene after (its entry), before the voice starts. The build stops if a scene's voice starts during its entry.

The transitions so far:

| Name | Kind | From → to | What happens |
|---|---|---|---|
| `logo-to-dock` | graphic | S0 logo → S1 desk | The title and line wipe back toward the icon, the menu bar and Dock slide in, and the icon arcs down into its Dock slot with a small pop. That frame is S1's empty desktop. |
| `dock-launch` | app | S1 desk → S2 morph | The camera pushes toward the Dock, the cursor clicks Duo's tile, and the tile bounces and gets its running dot. The camera pulls back as the pile starts to morph into the Duo window. |
