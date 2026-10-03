# ADR-0003 · AppKit split view for the three panes

Status: accepted · 2026-10-03 · Handoff: §3, §7 · Findings: F-5

## Context

Both altitudes are three panes with fixed design widths (340 · flex · 340 and 300 · flex · 460), 1 pt dividers in token colours (`consoleRule` beside the Home terminal, `rule` elsewhere), collapsible side panes, and minimum widths. Collapsing must never tear down a pane's view, because the panes will host live terminals (LR-13). SwiftUI's `HSplitView` and `NavigationSplitView` can't colour dividers per edge and impose their own sidebar styling.

## Decision

`PaneSplit` wraps an `NSSplitView` subclass (`DuoSplitView`) in `NSViewRepresentable`. Each pane is an `NSHostingView` with `sizingOptions = []`. The subclass draws each divider in its own colour, places dividers at the design widths on first layout (a pane's border counts inside its width, as in the targets), and collapses side panes with `setPosition` so their views stay alive. Both altitudes are kept mounted in a `ZStack`; only the active one is visible and hit-testable, so zooming doesn't destroy panes either.

## Consequences

- Pane edges and divider colours match the targets exactly (F-5).
- Hosted SwiftUI panes don't inherit the parent environment, so the model is injected into each pane explicitly.
- Terminal views (Phase D) can live in these panes without being recreated on collapse or zoom.
