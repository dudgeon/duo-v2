# Duo: stand-ins, batch 2 — design handoff

Status: approved by Geoff, 2026-10-07 (DL-132), in three rounds of buttons. Answers Q-46, Q-47, Q-50, Q-51, Q-52, Q-39, Q-57, Q-66, Q-67, Q-68 and DL-127's wording (Q-71). The boards were drawn on the Design canvas https://claude.ai/artifact/3TTPpMG5scibGpopR14afr with the Duo design system (every mark a [P]), beside captures of each stand-in as built. They are exported here as static HTML, with PNGs in `screens/png/`. Only the chosen boards are exported; the canvas keeps the options he didn't choose.

## What the boards settle

| Board | Part | What it draws |
|---|---|---|
| `q46-hover` | (a) Q-46 | A group-style task row under the pointer: the `selected` fill, the status whole, the + after it. A long title gives way first. |
| `q47-writable`, `q47-admin` | (b) Q-47 | The update question shows the release's own notes in a box under "You have …": a `WHAT’S NEW` label, the notes, up to 160 high and then it scrolls. Later sits apart at the left; the default stays rightmost. |
| `q50-highlight` | (c) Q-50 | The drop highlight as built: over a folder, and the whole Files block for the root. |
| `q50-clash` | (c) Q-50 | Several taken names: the title counts them; each row of the box gives the name, `from <folder>` and "the one there: edited 2h ago". Keep Both stays the default. |
| `q51-copy` | (d) Q-51 | From another volume Duo copies, as Finder. The + badge is the system's. |
| `q52-preview`, `q52-none` | (e) Q-52 | A file Duo can't show: a 36-high strip on `ground` (kind and "read only" in `text2`; Open With ⌄, Show in Finder) over Quick Look; with no preview, the name, a line and the buttons, centred. |
| `q39-hover` | (f) Q-39 | A tab for a file outside the project adds its folder in `text2` under the pointer. |
| `q57-home-pill` | (g) Q-57a | The Terminal / Chat pill at the right end of Home's session tab row. |
| `q57-link-status` | (g) Q-57b | A chat file link under the pointer: its target in a status line at the transcript's bottom left. |
| `q66-downloading` | (h) Q-66 | A running download in the download notice's place: "Downloading report.pdf…", the converting bar's progress line, "2.1 of 8.4 MB", Cancel. |
| `q67-popup` | (i) Q-67 | `↳` in `text2` before a popup's title; tooltip "Opened from ‹opener›". |
| `q68-drawing`, `q68-no-session`, `q68-narrow` | (j) Q-68 | A deck while drawing (controls dimmed, empty numbered frames); picked with no session (use Send To, Send to Claude dimmed, Send To default); under 460 (2/5, the picker in two rows). |
| `close-busy` | (k) DL-127 | The busy-tab question's words for a Claude session and for a shell command. |

## Behaviour a picture can't show

- **Later (Q-47)** stays as built: it skips that version for the launch and the scheduled checks (F-69). The notes come from the GitHub release's body, which `release.sh --notes` writes. The question shows the Markdown as plain lines, and bullets stay bullets. With no notes, the box isn't shown.
- **Plain kind names (Q-52):** PDF, ZIP archive, Keynote deck, Numbers sheet, Pages document, image, video, audio, disk image, app; the system's own name for anything else.
- **The link status line (Q-57b)** shows while the pointer is over a file link and goes when it leaves; web links show their address.
- **A running download (Q-66)** with no known size shows the bar moving and no count. Cancel stops it and removes the partial file.
- **Q-68:** Page Up, Page Down, ← and → move between slides, right-click a slide for Select Shape, and `.pptm` and `.ppsx` open as `.pptx`, all as built.
- **DL-134 still applies:** a hovered right-pane tab has its fill behind the × and the name, and Q-39's folder sits inside that fill.

## Exempt from the comparison

Names, notes, files and times are illustrative. Quick Look's preview and a page's own content are drawn by the system or the page. Terminal text is blank in window captures (F-25).
