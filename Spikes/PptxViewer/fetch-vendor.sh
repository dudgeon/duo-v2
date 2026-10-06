#!/bin/zsh
# Fetches the two renderers the proofs of concept use into vendor/ (not committed), pinned:
#   @aiden0z/pptx-renderer 1.3.0 (Apache-2.0), its browser bundle patched by patch-aiden0z.py so
#   every shape's element carries its OOXML id; PPTXjs at 1a9260b (MIT, March 2022).
set -euo pipefail
cd "${0:A:h}"
rm -rf vendor && mkdir -p vendor/aiden0z vendor/pptxjs
tmp=$(mktemp -d)
curl -fsSL https://registry.npmjs.org/@aiden0z/pptx-renderer/-/pptx-renderer-1.3.0.tgz | tar -xz -C $tmp
cp $tmp/package/dist/aiden0z-pptx-renderer.browser.es.js $tmp/package/LICENSE vendor/aiden0z/
python3 patch-aiden0z.py vendor/aiden0z/aiden0z-pptx-renderer.browser.es.js
git clone -q https://github.com/meshesha/PPTXjs.git $tmp/PPTXjs
git -C $tmp/PPTXjs checkout -q 1a9260b2062f89ba822aeb54da792236780af8e7
cp $tmp/PPTXjs/js/{jquery-1.11.3.min.js,jszip.min.js,filereader.js,d3.min.js,nv.d3.min.js,pptxjs.js} $tmp/PPTXjs/css/{pptxjs.css,nv.d3.min.css} $tmp/PPTXjs/LICENSE vendor/pptxjs/
rm -rf $tmp
echo "vendor/ ready: python3 -m http.server 8777 --directory ${0:A:h}, then open /aiden0z.html or /pptxjs.html"
