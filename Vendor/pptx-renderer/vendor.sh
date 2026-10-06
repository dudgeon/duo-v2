#!/bin/zsh
# Re-vendors @aiden0z/pptx-renderer (Apache-2.0): fetch the pinned npm tarball, check its hash,
# copy the standalone browser bundle and its notices here, and apply patch.py. The result is
# committed, so a clone builds with nothing fetched (README.md).
set -euo pipefail
cd "${0:A:h}"
version=1.3.0
sha=$(awk '/^tarball-sha256:/{print $2}' README.md)
tmp=$(mktemp -d)
curl -fsSL "https://registry.npmjs.org/@aiden0z/pptx-renderer/-/pptx-renderer-$version.tgz" -o $tmp/p.tgz
have=$(shasum -a 256 $tmp/p.tgz | awk '{print $1}')
[[ $have == $sha ]] || { echo "tarball hash $have isn't $sha" >&2; exit 1; }
tar -xzf $tmp/p.tgz -C $tmp
cp $tmp/package/dist/aiden0z-pptx-renderer.browser.es.js pptx-renderer.js
cp $tmp/package/LICENSE LICENSE
cp $tmp/package/THIRD_PARTY_NOTICES.md THIRD_PARTY_NOTICES.md
rm -rf licenses && cp -R $tmp/package/licenses licenses
python3 patch.py pptx-renderer.js
rm -rf $tmp
echo "vendored @aiden0z/pptx-renderer $version"
