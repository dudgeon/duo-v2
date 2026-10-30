# Releases

*Part of Duo's director procedures (`README.md`): Duo dev's habits on top of the shared duo-director core. Moved here from the project skill (retired) on 2026-10-17; the rules are in _PROJECT.md's `## Director`.*

## 4. Releases

- **Brief a release worker; don't run `release.sh` yourself** (Geoff, 2026-10-19, DL-222). After Geoff's go, a Sonnet worker cuts it: the brief names the version, the scale gate under the lock, the notes, `release.sh`, the verification below and the GPU lock. You keep the go, the console and the review of its report.
- Only with Geoff's go-ahead (public repo). The release worker uses the `release` skill. Versions are **patch bumps (0.2.x)**; Geoff picks minor milestones himself.
- Apple's notary queue can be slow. Run `DUO_NOTARY_TIMEOUT=55m scripts/release.sh <v> --notes build/release/<v>-notes.md` with `run_in_background` and a 2-hour timeout. Afterwards check `gh release view`, then `build/release/<v>/Duo.app/Contents/Helpers/duo2 update probe`, which must say the feed offers the new version.
- Release notes are for users: what's new and fixed, in plain words.
