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
| `click-through` | app | S2 → S3, S3 → S4 | The camera pulls back to show what to click, the cursor clicks it (All projects; the Needs you session), the app's next state comes up, and the scene's beats push in. |
| `carry-on` | app | S4 → S5 → S6 → S7, S9 → S10 | The picture carries straight on (the same capture, the same camera); the scene's first beat is the click that changes it (the chat toggle on "chat"). |
| `duo-fades` | graphic | S7 → S8 | The scene opens on S7's last picture, wide, and fades Duo's window away to the bare desktop on its `fade` event (Geoff: "this is the point where duo should fade away"). |
| `pile-to-duo` | graphic | S8 → S9 | The resume picker's pile fades out and Duo's window fades back in on the next scene's first capture, the same picture S7 ended on. |
| `duo-steps-away` | graphic | S10 → S11 | Duo's window shrinks and slides off as a thumbnail while the paper ground fills in. |
| `stand-in`, `stand-in-out` | graphic | any → card → S11 | Only while a scene's captures aren't built: a labelled card, never silent (the report names it). |

## App scenes (S3 on)

`scene: "app"` in `shots.json` plays real captures of Duo (`video-s3-*`, `video-s4-*`, `video-s5-*` in `VideoTargets.swift`) with beats on the voice's words. A beat can carry:
- `cam`: framing that follows the app, so a change to Duo's layout moves the camera with what it frames:
  - an anchor, or `wide`;
  - `{on, x0, x1, y0, y1}`: part of an anchor, in fractions. Use it for panes taller than the frame, where fitting the whole pane barely zooms;
  - `{rel, dx, dy, w, h}`: a rect placed from an anchor's top-left (`x` or `y` instead of `dx` or `dy` pins that edge in window points). Use it to frame a row with what's around it, such as S10's + New task;
  - `{fit: [anchors], pad}`: the anchors' union, padded (`pad` is a number or `{t, r, b, l}`), such as S10's task rows, first to last.
  A bare rect in window points (`{x, y, w, h}`) still works, but it doesn't follow the app. The build names it as stale when the anchors inside it move (`pipeline/anchors.mjs`). `mark` and `wipe.on` take the same forms.
- `click` and `state`: the cursor clicks, and the next capture comes up.
- `menu`: a context menu, drawn with the app's real items, because macOS draws menus outside the window capture.
- `drag`: a selection.
- `mark` and `quote` (the quote is a large caption card, lower left).
- `key`: a shortcut's keycaps as it's pressed (S7's ⌘B, ⌘K).
- `wipe: {state, on, dur}`: a state revealed left to right inside an anchor, for typing that renders as it's typed.
- `drag.reveal`: the selection capture shown from the drag's start to the cursor as it moves.
A shot's `pauses: {"n": seconds}` adds picture after line n, and `tail` holds the end.
Drawn scenes: `projects` (S8, `src/scenes/ProjectsBg.tsx`: drawn Terminal and Finder with Claude Code 2.1.296's own screens, the folder map) and `conclusion` (S11, `src/scenes/Conclusion.tsx`: the release line from `gh release list`, the topic list, Help › Report an Issue…, the opening card).
Anchors come from each capture's accessibility dump (`video.*` ids or labels).

## Topic list (DL-170)

Each scene's `Topic:` line in the script names it in a running list. At every change of topic (`src/lib/Topics.tsx`), the
picture steps right to 80% of the frame and the list stands in the left 20% (`RAIL`, 384 px) on paper: done topics grey with ✓,
upcoming ones faint, the new one large in ink with the accent bar sliding to it from the topic just finished. It starts 0.35 s
before the scene change, slides in over 0.5 s, holds about 1.9 s and slides out over 0.5 s; the scenes' own transitions keep playing
in the smaller picture. A scene whose topic repeats the last adds no change. The rejected options (ribbon, contents page,
carousel) are still in `src/scenes/TopicVariants.tsx` (composition `TopicVariant`).

## Callout words

A marker's words are a `Caption` (`src/lib/Paper.tsx`): a white card, 46 px SF Pro semibold with an accent bar, lower left,
72 px from the bottom (Geoff, 2026-10-11: "larger and easier to see"). `Quote`, the small mono quote, is kept only for the archived style frames.
