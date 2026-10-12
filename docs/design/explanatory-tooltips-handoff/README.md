# Duo: a quieter New task, and the Explainer — design handoff

Status: approved by Geoff, 2026-10-12 (DL-172), by buttons after one round on the canvas https://claude.ai/artifact/6KHUj9hbPQLwqarUdWpcAc. Not built.

The research is in `docs/design/explanatory-tooltips-study/research.md`. The canvas holds every option. The screens here are copies of the chosen boards (HTML, and `png/` at 2x). They are presentation boards: the window drawn inside each is the target. Where a board draws options or notes, build only what the table names.

## Targets

| Screen | Build | Not chosen (canvas only) |
|---|---|---|
| `01-sidebar-fold` | **A3.** The sidebar's footer keeps one button, renamed **+ New Claude Code session** (Duo's one button style). **+ New task** leaves the footer and becomes the Tasks fold's last row: `rowSession` 26, a + (the task rows' hover + glyph, 10 in a 12 column) and "New task" in `control` 12/16 `text2`, lined up with the task names, with the `selected` fill and `text` on hover. While the fold is closed, hovering its header shows a + at its trailing end (`rowActionSize` 18, as task rows show, DL-112), which is New task. Both carry the help tag **Track a new task in this project**. | A1 a borderless text button; A2 an icon button |
| `02-explainer-tasks` | **B3.** The task **Explainer**, opened by a long hover on the New task row or the fold header's +, above it. It holds the title **Tasks**, the line **Track the work in this project.**, and an annotated task (box, title, two lines of detail, a file chip and a session chip) with numbered marks 1–3. Below that are three numbered lines: **A to-do.** Check it off when it’s done. / **Detail and context,** if you want them. Claude reads them. / **Files and Claude Code sessions,** attached, so the work stays together. The footer has **Learn more about tasks** and **Don’t show again**. | B1 icons with three points; B2 a click-opened ? (toggletip) |
| `03-behaviour` | Timing, placement, dismissal, keyboard and VoiceOver, and until-dismissed (below). | — |
| `04-component` | The Explainer's parts, sizes and rules, so it can serve another feature later. | — |

## Behaviour a picture can't show

- **Two tiers.**
  - The help tag is the system's (`.help("Track a new task in this project")`), at the system delay, about 1 s.
  - If the pointer stays still on the trigger for 1.5 s more, the help tag gives way to the Explainer.
  - Any move off the trigger resets the clock.
- **It's a popover Duo draws.**
  - 300 wide, `pane` fill, 1 `rule` border, `radiusPopover` 10, `shadowPopover`.
  - Padding is `popoverPaddingTop` 14, `popoverPaddingHorizontal` 16 and 12 at the bottom, with 10 between parts.
  - A 12 arrow points at the trigger's centre.
  - It opens with the system popover fade (Reduce Motion: instantly) and never takes focus when opened by hover.
- **Placement.**
  - It sits above the trigger, with its left edge on the pane's 16 inset, and may overhang the next pane by up to 16.
  - When there's no room above, it goes below. It never covers its own trigger.
- **Dismissal (WCAG 1.4.13).**
  - It stays while the pointer is on the trigger or on the Explainer.
  - It closes 300 ms after the pointer leaves both, on Esc, on any click, or on typing, scrolling or the window losing focus.
  - A click on the trigger also does its action (a new task).
- **Until dismissed** (Geoff: "until dismissed, like a check or a 'don't show again'").
  - It opens on every long hover until **Don’t show again** is clicked. After that, hover shows only the help tag, and Help › Explain Tasks still opens it.
  - The flag is per Explainer, kept in Duo's preferences, not in any project file.
  - Settings › General gains **Show dismissed explanations again**, a button that clears every flag. This is a stand-in placement (Q-177).
- **Keyboard and VoiceOver.**
  - **Help › Explain Tasks** opens the Explainer at its trigger, with focus on Learn more. Esc closes it and focus returns to where it was. There's no new shortcut (DL-34).
  - The help tag's sentence is the trigger's accessibility hint. A custom action, **Explain**, reads the title, the line and the three lines.
  - The picture is decorative and hidden from VoiceOver.
- **The picture** is drawn from Duo's own parts in the tokens:
  - the task box (`TaskBox`), `body`/`text2` lines and the state glyph;
  - a file chip and a session chip (18 high, `radiusPill`, 1 `rule`, 11 type; the file name in mono);
  - numbered marks (16, filled `text`, white 10 semibold; never the accent).

  No video, no motion.
- **Learn more** opens the user guide's tasks page. Until that exists it isn't shown (Q-177).
- **The Tasks fold always shows in a project.** A3 needs the fold even with no tasks. While there are none, it holds DL-147's explainer and the New task row, open by default. Today the fold appears only when there are tasks.
- **Keep `video.newtask.button`** on the New task row, the intro video's cursor target.
- **The task board's own + New task** (`TaskBoardView.swift`, header row) is unchanged: it's the board's primary action, and the Explainer isn't attached there.

## duo2 (DL-71)

- **New task** is still `duo2 task new`.
- **Help › Explain Tasks** shows help to a person at the screen, so list it in `Parity.uiOnly` with that reason.
- **Show dismissed explanations again** is `duo2 settings set explainers.reset` (or whatever the settings family names it; the build session checks).

## Not in this handoff

The same component on Chat mode's pill and on Home's title (canvas C1 and C2) stays a study for now (Geoff: Tasks only). The component is built so they can be added by decision.
