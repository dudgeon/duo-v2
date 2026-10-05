# Sparkle (vendored)

Sparkle 2.10.0, from the official release `Sparkle-2.10.0.tar.xz` (github.com/sparkle-project/Sparkle, SHA-256 `c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c`), vendored so a clone builds with nothing fetched (as CodeMirror is). Duo isn't sandboxed, so the framework's XPC services are removed, as Sparkle's docs allow.

- Linked by the `Duo` target only (`Package.swift`); `scripts/bundle.sh` copies it into `Duo.app/Contents/Frameworks`; `scripts/release.sh` signs it inside out with Developer ID.
- The update feed is `appcast.xml`, published with each GitHub release; the app reads `https://github.com/dudgeon/duo-v2/releases/latest/download/appcast.xml`.
- Updates are signed with an Ed25519 key kept in `~/.duo-signing/sparkle-ed25519.key` (never in the repo); its public half is `SUPublicEDKey` in `bundle.sh`. Sparkle's `sign_update` lives in `~/.duo-signing/sparkle-bin/`.
- To upgrade: download the new release's `.tar.xz`, replace `Sparkle.framework` (remove `XPCServices` again), update the version and hash above.
