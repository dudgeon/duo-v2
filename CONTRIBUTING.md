# Contributing to Duo v2

This page is for people building Duo. If you want to use it, start at the [README](README.md) and the [guide](docs/guide/README.md).

Duo v2 is a native macOS app in a Swift package, built without Xcode. Releases are signed and notarized DMGs on [GitHub](https://github.com/dudgeon/duo-v2/releases), cut with the release skill (`.claude/skills/release/`). Claude sessions working on Duo also read [CLAUDE.md](CLAUDE.md), which sets the rules: which docs win, building to the design screens, staying Xcode-free, and how records are numbered.

## Where the decisions and plans are

- [`docs/design/decisions.md`](docs/design/decisions.md): Geoff's decisions (DL-n). They win over every other doc.
- [`docs/design/README.md`](docs/design/README.md): every design doc and handoff, with its status. The approved screens in each handoff's `screens/` are the target for anything visible.
- [`docs/design/system/`](docs/design/system/): the design system as built.
- [`docs/plan/build-plan.md`](docs/plan/build-plan.md): the build plan, v1's scope (§3a) and where v1 stands.
- [`docs/plan/findings.md`](docs/plan/findings.md) (F-n), [`docs/plan/concerns-and-questions.md`](docs/plan/concerns-and-questions.md) (C-n, Q-n), [`docs/plan/enhancements.md`](docs/plan/enhancements.md) (ENH-n).
- [`docs/cli/duo2.md`](docs/cli/duo2.md): the `duo2` reference, generated from the action registry.
- [`docs/acceptance/`](docs/acceptance/README.md): acceptance walks.

## Build and run

Requires macOS 26 or later and the Xcode Command Line Tools (`xcode-select --install`). Xcode is not needed ([ADR-0001](docs/adr/0001-xcode-free-swift-package.md)).

```bash
scripts/bundle.sh
```

```bash
open build/Duo.app
```

Opened plainly, Duo lists every Claude Code session on this Mac, from Claude's logs, grouped by folder; a Home folder (File › Choose Home Folder…, or `duo2 home set <folder>`) holds the projects you track (DL-82 to DL-85). The design fixture (`docs/design/build-handoff/fixture.json`) is for the design targets' states:

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
| `Sources/Duo/` | The app entry point |
| `Sources/DuoKit/` | Views, model, live state, editor host, design tokens, fixture harness |
| `Sources/DuoControl/` | The app ↔ `duo2` protocol and the action registry (Foundation only) |
| `Sources/duo2/` | The `duo2` command line, bundled in `Duo.app/Contents/Helpers` |
| `Sources/DuoSearch/` | Cross-project search: index, Core ML embedder, hybrid ranking (shared by the app and `duo2`) |
| `Sources/DuoChecks/` | Logic checks (`swift run DuoChecks`) |
| `Vendor/codemirror/` | CodeMirror 6 and Duo's editor module (`src/duo-editor.js`), bundled into a checked-in `dist/cm6.js` by `build.sh` |
| `Models/` | The search model, committed in checksummed parts (DL-40) |
| `Spikes/` | Throwaway packages from the spike track (`swift run` inside each) |
| `scripts/` | Bundle, release, token and design-system generation, UI comparison, pixel sampling, acceptance fixtures |
| `docs/design/decisions.md` | Owner decisions (DL-n); these win over other docs |
| `docs/design/README.md` | Index of every design doc and handoff, with its status |
| `docs/design/system/` | The design system: tokens, components, surfaces, as built |
| `docs/design/*-handoff/` | Approved design targets: screens, manifests, READMEs |
| `docs/design/legacy-requirements.md` | Requirements carried from legacy Duo (LR-n) |
| `docs/design/stack-recommendation.md` | Stack choices and spikes |
| `docs/plan/` | Build plan and roadmap, findings (F-n), concerns and questions (C-n, Q-n), enhancements (ENH-n), spikes |
| `docs/prd/` | Product requirements for consolidation (CONS) and cross-project search (SRCH) |
| `docs/cli/duo2.md` | The `duo2` reference, generated from the action registry |
| `docs/features/` | Guides to larger features (`duo2`, Send to Claude) |
| `docs/acceptance/` | Acceptance walks: features, verdict pages, ledgers |
| `docs/adr/` | Architecture decision records |
| `docs/research/` | Research behind the decisions |
| `.claude/skills/` | The acceptance-walk and release skills |
