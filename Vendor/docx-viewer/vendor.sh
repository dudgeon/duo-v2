#!/bin/zsh
# Re-vendors @file-viewer/docx (Apache-2.0) and JSZip (MIT): fetch the two pinned npm tarballs,
# check their hashes, copy the renderer's ES module and the licences here, and wrap JSZip as an ES
# module so the renderer's `import "jszip"` resolves with no import map (the page's policy allows
# no inline script). The result is committed, so a clone builds with nothing fetched (README.md).
set -euo pipefail
cd "${0:A:h}"
fv_version=0.3.33
jz_version=3.10.1
fv_sha=$(awk '/^file-viewer-tarball-sha256:/{print $2}' README.md)
jz_sha=$(awk '/^jszip-tarball-sha256:/{print $2}' README.md)
tmp=$(mktemp -d)
curl -fsSL "https://registry.npmjs.org/@file-viewer/docx/-/docx-$fv_version.tgz" -o $tmp/fv.tgz
curl -fsSL "https://registry.npmjs.org/jszip/-/jszip-$jz_version.tgz" -o $tmp/jz.tgz
for pair in "fv:$fv_sha" "jz:$jz_sha"; do
  have=$(shasum -a 256 $tmp/${pair%%:*}.tgz | awk '{print $1}')
  [[ $have == ${pair#*:} ]] || { echo "${pair%%:*} tarball hash $have isn't ${pair#*:}" >&2; exit 1; }
done
mkdir $tmp/fv $tmp/jz
tar -xzf $tmp/fv.tgz -C $tmp/fv
tar -xzf $tmp/jz.tgz -C $tmp/jz
cp $tmp/fv/package/LICENSE LICENSE
cp $tmp/jz/package/LICENSE.markdown LICENSE-jszip.md
# The renderer's bundled JSZip is the same file as the package's: say so rather than assume.
[[ $(shasum -a 256 < $tmp/fv/package/dist/jszip.min.js) == $(shasum -a 256 < $tmp/jz/package/dist/jszip.min.js) ]] || { echo "the renderer's JSZip isn't JSZip $jz_version" >&2; exit 1; }
# JSZip, as an ES module: its UMD wrapper takes `module.exports`.
{ echo "// JSZip $jz_version (MIT, LICENSE-jszip.md) wrapped as an ES module by vendor.sh."
  echo "var module = { exports: {} }, exports = module.exports;"
  cat $tmp/jz/package/dist/jszip.min.js
  echo
  echo "export default module.exports;"
} > jszip.mjs
# The renderer: its one bare import is pointed at that module (exactly once, or this fails).
sed 's|^\(.*\)import e from"jszip";|\1import e from"./jszip.mjs";|' $tmp/fv/package/dist/docx-preview.mjs > docx-preview.mjs
[[ $(grep -c 'import e from"./jszip.mjs";' docx-preview.mjs) == 1 ]] || { echo "the renderer's import of jszip moved" >&2; exit 1; }
rm -rf $tmp
echo "vendored @file-viewer/docx $fv_version with jszip $jz_version"
