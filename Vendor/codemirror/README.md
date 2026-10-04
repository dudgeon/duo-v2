# CodeMirror 6, vendored

Duo's markdown editor runs CodeMirror 6 in one `WKWebView` (stack recommendation #8). Everything it needs at runtime is checked in here, so Duo never fetches code:

- `dist/cm6.js`: CodeMirror plus Duo's editor module (`src/duo-editor.js`), bundled and minified by esbuild.
- `dist/THIRD-PARTY-LICENSES.md`: the licences of everything in the bundle (all MIT).
- `package.json` and `package-lock.json`: exact versions. `node_modules/` isn't committed.

To rebuild after changing `src/` or a version:

```bash
Vendor/codemirror/build.sh
```

It runs `npm ci` from the lockfile when `node_modules/` is missing. Spike S4/S5 (`Spikes/S4Editor`) exercises the bundle in a web view.
