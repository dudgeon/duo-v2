---
name: release
description: Cut a Duo version release — build HEAD from a clean worktree, sign with Developer ID, notarize, staple a DMG, launch-check it, tag vX.Y.Z and publish a GitHub release with the DMG attached. Use when Geoff says "release", "cut a version", "ship v0.x", "publish a build", or asks for a signed or notarized DMG.
---

# Release

`scripts/release.sh` does the whole cut; this skill is the judgment around it: which version, what ships, the notes, and what to do when Apple says no.

What the script does, in order, stopping at the first failure:
1. Preflight: tag free locally, on origin and on GitHub; signing keychain unlocks; Developer ID identity valid; notary profile answers.
2. Builds the **committed** `HEAD` in a temporary worktree (`scripts/bundle.sh release`), so uncommitted work never ships and `build/Duo.app` is untouched. Sets `CFBundleShortVersionString` from the version and `CFBundleVersion` from the commit count (the tag is the single version source, LR-61).
3. Signs every nested Mach-O (`Contents/Helpers/duo2`), then the app: Developer ID, Hardened Runtime, secure timestamp. No entitlements.
4. Launch check (LR-61): opens the signed app and requires a captured frame.
5. Notarizes and staples the app, builds `Duo-<v>.dmg` (app + Applications link), signs it, notarizes and staples the DMG.
6. Mounts the DMG: Gatekeeper must say `Notarized Developer ID` for the DMG and the app, and the app inside must launch.
7. Tags `v<version>` on the commit, pushes the tag, and runs `gh release create` with the DMG and its `.sha256`. A version with a suffix (`0.2.0-rc.1`) is published as a pre-release.

Output stays in `build/release/<version>/`: the app, DMG, checksum, notary JSON, launch captures and logs.

Signing material is in `~/.duo-signing/` (outside the repo; its `README.md` lists every file): the dedicated keychain with the identity `Developer ID Application: Geoffrey Dudgeon (R39EF29X3Y)`, which expires 2031-09-17, and the notarytool profile `duo-notary` (App Store Connect key ZYTKPDMQ37).

## 1. Version

If Geoff named one, use it. Otherwise read the last tag (`git describe --tags --abbrev=0`; there may be none yet) and the commits since, then ask with AskUserQuestion: next patch for fixes only, next minor for anything user-visible (pre-1.0 the scheme is `0.MINOR.PATCH`), with your pick first. Never reuse, move or delete a tag that has been pushed.

## 2. What ships

The script ships `git rev-parse HEAD` of the current checkout, committed files only.
- Run `git status` and `git log -1`. If the work Geoff expects in this release isn't committed, say so and ask; don't release a different commit silently.
- Another agent may be working in this checkout. Never commit, stash, reset or check out over its changes to cut a release. If the release needs a different commit, run the script from a worktree of that commit instead.
- The commit should be on origin. The script warns if it isn't, and pushing the tag uploads it anyway.

## 3. Release notes

Write `build/release/<version>-notes.md` (beside the output folder, not inside it: the script empties that folder). Read `git log <last-tag>..HEAD` (or the whole history for the first release) and the DL-n, F-n and ENH-n entries added in that range. Write it for someone installing Duo:
- **What's new**: user-visible changes in plain words, grouped (workspace, sessions, editor, search, `duo2`), a line each. Skip internals unless they change behaviour someone would notice.
- **Requirements**: macOS 26 or later, Apple Silicon (until Universal builds are decided), Claude Code installed.
- **Install**: open the DMG and drag Duo to Applications. The `duo2` command is at `Duo.app/Contents/Helpers/duo2`.
- Known gaps worth a warning (open C-n rows that bite users).

## 4. Run it

Run it in the background; it takes 10–20 minutes, most of it Apple's notary service:

```bash
scripts/release.sh <version> --notes build/release/<version>-notes.md
```

- The repo is public, so publishing is visible to everyone. Geoff asking for a release is the go-ahead. Add `--draft` if he asks for a draft or something looks off, and `--no-publish` to rehearse (everything except the tag and upload).
- When it finishes, report the release URL, the DMG's size and its SHA-256. Send the notes file with SendUserFile only if Geoff wasn't watching.

## 5. When it fails

The script prints the failing step and where its evidence is.

| Failure | What to do |
|---|---|
| `no signing keychain` / `no valid Developer ID Application identity` | Check `~/.duo-signing/` against its README. If the cert expired or was revoked, make a new one: CSR at developer.apple.com → Certificates → Developer ID Application (**G2 Sub-CA**), then import it into the dedicated keychain as the README describes. |
| A keychain dialog appears, or codesign hangs | Something signed from the login keychain. The script always passes `--keychain`; check that a hand-run command does too. Never type a password. |
| `notary profile 'duo-notary' doesn't work` | Usually Apple wants an updated Program License Agreement accepted (developer.apple.com/account shows a banner). That's a legal agreement, so ask Geoff before accepting it. Otherwise the key was revoked: make a new team key (Developer access) and run `notarytool store-credentials` as in the README. |
| Notarization `Invalid` | Read `issues` in `build/release/<v>/notary-log.json`. Typical causes: a nested binary the signing loop missed, a missing timestamp, or Hardened Runtime off. New nested code (a framework, dylib or Sparkle) has to be signed inside out before the app; frameworks are signed as bundles. Log what you learn as an F-n. |
| Launch check fails | Read `build/release/<v>/launch-*.log`. If the signed copy fails but `build/Duo.app` runs, Hardened Runtime is blocking something: work out which entitlement it needs, add an entitlements file and pass it with `--entitlements` when signing the app, then record a finding. Don't ship without the check. |
| `tag … already exists` | Pick the next version. If a run died after pushing the tag but before `gh release create`, finish by hand with `gh release create v<v> build/release/<v>/Duo-<v>.dmg build/release/<v>/Duo-<v>.dmg.sha256 --verify-tag --title "Duo <v>" --notes-file …`. |
| `the release build failed` | The committed tree doesn't build in a clean checkout (an uncommitted file it depends on, say). Fix it on the branch first. |

## Not yet

Sparkle updates, Universal (Intel) builds and an app icon are open Phase L work (build plan, G1). Don't add them as part of a release cut.
