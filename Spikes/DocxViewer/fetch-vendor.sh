#!/bin/zsh
# Fetches the renderers the proof pages use into vendor/ (not committed), pinned, from npm tarballs:
#   docx-preview 0.4.1 (Apache-2.0, "docxjs") + jszip 3.10.1 (MIT/GPLv3 dual; we take MIT)
#   @file-viewer/docx 0.3.33 (Apache-2.0, a maintained docxjs fork with read-only review modes)
#   @apollo-design/docx-preview 0.9.0 (Apache-2.0, another docxjs fork; tried for comparison)
#   mammoth 1.13.0 (BSD-2-Clause)
# Then builds the Quick Look column: qlmanage -p -o writes the HTML Quick Look would show.
set -euo pipefail
cd "${0:A:h}"
rm -rf vendor && mkdir -p vendor/{docx-preview,file-viewer,apollo,mammoth,jszip} out/ql
tmp=$(mktemp -d)
get() { mkdir -p $tmp/$2; curl -fsSL "https://registry.npmjs.org/$1" | tar -xz -C $tmp/$2; }
get docx-preview/-/docx-preview-0.4.1.tgz dp
get jszip/-/jszip-3.10.1.tgz jz
get @file-viewer/docx/-/docx-0.3.33.tgz fv
get @apollo-design/docx-preview/-/docx-preview-0.9.0.tgz ap
get mammoth/-/mammoth-1.13.0.tgz mm
cp $tmp/dp/package/dist/docx-preview.mjs $tmp/dp/package/LICENSE vendor/docx-preview/
cp $tmp/jz/package/dist/jszip.min.js $tmp/jz/package/LICENSE.markdown vendor/jszip/
cp $tmp/fv/package/dist/{docx-preview.mjs,docx-preview.worker.js,jszip.min.js} $tmp/fv/package/LICENSE vendor/file-viewer/
cp $tmp/ap/package/dist/docx-preview.mjs $tmp/ap/package/LICENSE vendor/apollo/
cp $tmp/mm/package/mammoth.browser.min.js $tmp/mm/package/LICENSE vendor/mammoth/
rm -rf $tmp
python3 patch-paraids.py vendor/docx-preview/docx-preview.mjs
printf "export default window.JSZip;\n" > vendor/jszip/shim.mjs
for f in docs/*.docx; do qlmanage -p -o out/ql $f >/dev/null 2>&1; done
swiftc -O snap.swift -o out/snap && swiftc -O compose.swift -o out/compose
echo "vendor/ ready: python3 -m http.server 8778 --directory ${0:A:h}, then open /fileviewer.html?doc=review (or docxpreview, mammoth, quicklook, apollo); out/snap <url> <png> [width] [js] snapshots one"
