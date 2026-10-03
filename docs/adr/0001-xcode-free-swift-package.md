# ADR-0001 · Xcode-free Swift package build

Status: accepted · 2026-10-03 · Decision: DL-30 · Finding: F-2

## Context

The stack recommendation (#2) proposed an Xcode project generated with XcodeGen. The build Mac has only the Command Line Tools. Geoff's company Mac accepted software delivered as files in a `git clone` followed by a local build (cross-project search PRD §4, the mini-meeting-minutes pattern); whether it accepts Xcode or a Developer ID app is unknown (gate zero, DL-31).

## Decision

Duo is a Swift package (`Package.swift`) built with `swift build`. `scripts/bundle.sh` wraps the executable into `build/Duo.app` with an `Info.plist` and an ad-hoc signature. Nothing may require Xcode; Xcode may be installed for optional tools such as Instruments.

## Consequences

- One build path everywhere: `git clone && scripts/bundle.sh`.
- No SwiftUI macro plugins: no `@State`, `@Entry`, `#Preview`. App state lives in `@Observable` classes (Observation's macros ship with the toolchain).
- No XCTest or Swift Testing: logic checks are an executable target, `swift run DuoChecks`, exiting non-zero on failure. UI is checked by the screenshot loop (ADR-0002).
- No asset catalogs: colours and metrics are generated Swift from `docs/design/build-handoff/tokens.json` (`scripts/gen-tokens.py`), with dynamic light/dark providers.
- App icon, if needed, via `iconutil`. Signing and notarization tools (`codesign`, `notarytool`, `stapler`) are in the CLT.
- Revisit if the CLT gain the macro plugins, or if gate zero shows the work Mac can't build Swift at all.
