# Explanatory tooltips: research

For the quieter **+ New task** and the explanatory tooltip on it (Geoff, 2026-10-11). The question is how products explain a feature on hover without a wall of text. The answers set Duo's trigger, size, anatomy, dismissal and keyboard rules. The canvas is https://claude.ai/artifact/6KHUj9hbPQLwqarUdWpcAc.

Gathered 2026-10-11. **[F]** means the page was opened and read. **[S]** means the claim rests on a search snippet only, so treat it as weaker. Several first-party pages couldn't be read (Apple's HIG and Material 3 render in script; Autodesk's help and forums returned 403 or 404), and those gaps are marked.

## What each product does

| Product | Trigger and delay | Size | Anatomy | Dismissal | Keyboard, settings |
|---|---|---|---|---|---|
| **Fusion 360** | Two stages. A short tooltip, then the description and an animated "tool clip" appear progressively "as the cursor rests on the control" [S, Fusion API `tooltip` pages]. No delay values found. | Not found | Command name; then the description and the clip | Pointer leaves. Holding the mouse button keeps it up [S, Autodesk support] | Preferences › General › Show Tooltips [S]. No keyboard access found. |
| **Office Enhanced ScreenTips** | Rest the pointer on a ribbon control [F] | Larger window than a plain ScreenTip; no px given | Command name, shortcut, art, description, links to Help [F]. Ribbon developer kits add a "Press F1 for Help" footer [S] | Pointer leaves | File › Options › General › ScreenTip style, with three choices: descriptions, names only, none [F] |
| **Photoshop / Illustrator Rich Tooltips** (CC 2018) | Hover a toolbar tool [F, photoshopessentials] | "Much larger" than the plain tip | Tool name, shortcut, one line, a 5–6 s looping video [F] | Pointer leaves. Users report they recur until the tool is used and return after a break [F, Adobe community] | Preferences › Tools › Use Rich Tooltips [F]. Criticised as on by default, a "newbie" feature that "disrupts my workflow"; users asked for a guided-or-expert choice [F] |
| **Figma** | Shortcuts appear in hover text [F, Figma keyboard help] | — | Label and shortcut | — | Richer help is a separate panel (Ctrl⇧?), not a hover [F] |
| **Raycast** | No hover tips [F, Action Panel manual] | — | ⌘K lists every action, each with its shortcut | Esc | Discoverable by a panel, not by hovering |
| **Linear, Notion** | Not verified (docs 404; nothing citable) | | | | |
| **macOS help tags** | About 1 s at rest (`NSInitialToolTipDelay`; Macworld says 1,000 ms) [S]; "appears when a person positions the pointer over a view … for a few seconds" [F, UIKit tooltip article] | One short sentence | Plain text only; SwiftUI `.help()` also sets the accessibility hint | Pointer leaves, or after a few seconds | System-drawn. The old Aqua guide's 60–75 characters is [S] and historical |

## What the guidance says

- **NN/g, Tooltip Guidelines** [F]: user-initiated (hover, or held keyboard focus). Brief, never vital information, never a repeat of the label. Don't cover related content. Tap or click "popup tips" for touch.
- **WCAG 2.1 SC 1.4.13** [F]: extra content shown on hover or focus must be **dismissible** (Esc, without moving the pointer), **hoverable** (the pointer can move onto it without it vanishing) and **persistent** (it stays until hover or focus leaves or the user dismisses it). System `title` tooltips are exempt.
- **W3C APG tooltip** [F]: appears on focus or hover after a small delay. Esc dismisses it and it never takes focus. Content that needs focus (a link) makes it a non-modal dialog, not a tooltip.
- **IBM Carbon** [F]: a tooltip holds text only, with no links, buttons or images. The **toggletip** holds a heading, body and footer link. It opens on click or Enter/Space and closes on Esc, a second click or a click outside. Its maximum width is **288 px**.
- **Primer, Atlassian, Fluent 2** [F]: tooltips are plain text for an icon's label or a shortcut. Anything formatted or interactive belongs in a popover, inline dialog or modal. Screen readers don't announce shortcuts shown only in tooltips (Atlassian).
- **Material 3** (Android docs) [F]: a **plain** tooltip is one line. A **rich** tooltip has an optional title, a multi-line body and an optional action.
- **Delays** [F, Radix]: 700 ms by default, then 300 ms when moving between neighbouring tips. Others cite 500 ms (Visa) and 750 ms (Blockly) [S].
- **Fluent TeachingPopover** [S]: a structured popover for a new feature, with a "Learn more" action. A carousel is used for several steps.

## What Duo takes from this

1. **Two tiers, like Fusion and Office.**
   - The plain tier is the system help tag, `.help("Track a new task in this project")`: one sentence, no title, at the system's delay.
   - The explanation is the second tier. It opens only if the pointer keeps resting on the button after the help tag has shown.
2. **The explanation is a popover, not a tooltip.** It has a "Learn more" and must be hoverable and dismissible (WCAG 1.4.13, APG), so it's a non-modal popover drawn with Duo's popover tokens.
   - It never takes focus.
   - It stays open while the pointer is on the button or on the popover.
   - It closes when the pointer leaves both (after a short grace), or on Esc, or on a click anywhere.
3. **Never in the way (the Adobe lesson).** The explanation shows until you've used the feature, then only the plain tier remains: after your first task in any project, + New task goes quiet.
   - Settings › General gets **Explain features on hover**, on by default, like Office's ScreenTip style.
   - This is a proposal ([P]). Geoff decides.
4. **No video, no motion.** Adobe's clips run too short to teach, and Duo's motion rules allow motion only to show where something went. Use one still illustration, drawn from Duo's own parts (a task line, a file chip, a session row), in the tokens.
5. **Short, scannable anatomy.**
   - A title and a one-line lede.
   - The illustration.
   - Three short points, each one line or two.
   - A footer with "Learn more".
   - Width about 300 (Carbon's cap is 288; Duo's sidebar is 300).
6. **Keyboard and VoiceOver.**
   - The help tag's sentence is the button's accessibility hint.
   - The explanation is reachable without a pointer: Help › Explain Tasks, and a VoiceOver custom action "Explain" on the button.
   - Duo's shortcut map is locked (DL-34), so there's no new key.
7. **Don't repeat the label.** "Track a new task in this project" says what the button does and where; "+ New task" alone doesn't.

## Sources

Opened:
- https://www.nngroup.com/articles/tooltip-guidelines/
- https://www.w3.org/WAI/WCAG21/Understanding/content-on-hover-or-focus.html
- https://www.w3.org/WAI/ARIA/apg/patterns/tooltip
- https://carbondesignsystem.com/components/tooltip/usage/
- https://carbondesignsystem.com/components/toggletip/usage/
- https://primer.style/product/components/tooltip/guidelines/
- https://atlassian.design/components/tooltip/usage
- https://fluent2.microsoft.design/components/web/react/core/tooltip/usage
- https://developer.android.com/develop/ui/compose/components/tooltip
- https://www.radix-ui.com/primitives/docs/components/tooltip
- https://developer.apple.com/documentation/uikit/showing-help-tags-for-views-and-controls-using-tooltip-interactions
- https://support.microsoft.com/en-us/office/show-or-hide-screentips-72d92d6a-6d2a-40fd-9ac2-fb9413ffce18
- https://www.photoshopessentials.com/?p=20827
- https://community.adobe.com/t5/photoshop/how-do-i-disable-the-annoying-but-quot-helpful-quot-video-windows-that-pop-up-when-hovering-over-a/td-p/9476785
- https://help.figma.com/hc/en-us/articles/360040328653-Use-Figma-products-with-a-keyboard
- https://manual.raycast.com/action-panel

Tried and unreadable: Apple HIG help tags, popovers and offering help; m3.material.io tooltips; linear.app keyboard docs; Autodesk Fusion help, API and forum pages (403/404). Search snippets used, and marked [S]: the Fusion API tooltip pages, Autodesk support's "Tooltips disappear when hovering", Macworld on `NSInitialToolTipDelay`, WPF ribbon ScreenTip docs, the Fluent TeachingPopover README, and Visa's and Blockly's delays.
