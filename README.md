# Duo v2

A native macOS workspace for product managers who work with Claude Code. Projects, sessions and documents stay organized in plain files you can read, every session keeps a live terminal running Claude Code's own TUI, and one screen shows what needs you across all of them.

Status: early build. The UI is being built against approved design screens using fixture data; terminals and live session state come next. See the [build plan](docs/plan/build-plan.md).

## Build and run

Requires macOS 26 or later and the Xcode Command Line Tools (`xcode-select --install`). Xcode is not needed ([ADR-0001](docs/adr/0001-xcode-free-swift-package.md)).

```bash
scripts/bundle.sh
```

```bash
open build/Duo.app
```

The app currently runs on the design fixture (`docs/design/build-handoff/fixture.json`). To open it in one of the design targets' states:

```bash
build/Duo.app/Contents/MacOS/Duo --state project
```

States: `overview`, `flow-zoom-1`, `project`, `flow-zoom-2`, `flow-zoom-3`, `flow-zoom-4`.

To run on real folders instead, point Duo at a workspace. A project is a folder with `PROJECT.md`, Home is the folder with `HOME.md`, and a topic is a project's parent folder. Sessions are real Claude Code sessions:

```bash
scripts/make-demo-workspace.py
```

```bash
open -n build/Duo.app --args --workspace "$PWD/.build/ws"
```

The script builds `.build/ws`, mirroring the fixture's projects. Duo keeps its facts about each project's sessions in `<project>/.duo/sessions.json`.

## Check

Logic checks:

```bash
swift run DuoChecks
```

Visual comparison against the design targets, writing `build/ui/<state>-compare.png` (target, build, difference):

```bash
scripts/check-ui.sh
```

Inside Claude's sandbox, `duo2` must reach the app through one allowed socket. This runs it under macOS Seatbelt the way Claude Code does, with no tokens spent:

```bash
scripts/check-sandbox.sh
```

Design reference PNGs need Google Chrome to re-render ([ADR-0002](docs/adr/0002-visual-target-harness.md)).

## Where things are

| Path | What |
|---|---|
| `Sources/DuoKit/` | Views, model, design tokens, fixture harness |
| `Sources/Duo/` | The app entry point |
| `Sources/DuoControl/` | The app ↔ `duo2` protocol (Foundation only) |
| `Sources/duo2/` | The `duo2` command line, bundled in `Duo.app/Contents/Helpers` |
| `Sources/DuoSearch/` | Cross-project search: index, Core ML embedder, hybrid ranking (shared by the app and `duo2`) |
| `Models/` | The search model, committed in checksummed parts (DL-40) |
| `Vendor/codemirror/` | CodeMirror 6 and Duo's editor module, bundled into a checked-in `dist/cm6.js` |
| `Spikes/` | Throwaway packages from the spike track (`swift run` inside each) |
| `Sources/DuoChecks/` | Logic checks (`swift run DuoChecks`) |
| `scripts/` | Bundle, token generation, UI comparison, pixel sampling |
| `docs/design/build-handoff/` | The design target: screens, tokens, fixture, comparison tools |
| `docs/design/decisions.md` | Owner decisions (DL-n); these win over other docs |
| `docs/design/legacy-requirements.md` | Requirements carried from legacy Duo (LR-n) |
| `docs/design/stack-recommendation.md` | Stack choices and spikes |
| `docs/plan/` | Build plan and roadmap, findings, concerns and open questions |
| `docs/adr/` | Architecture decision records |
| `docs/research/` | Research behind the decisions |

## Licence

MIT (DL-12).
