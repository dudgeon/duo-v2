#!/bin/zsh
# Bundles src/duo-editor.js and its CodeMirror dependencies into dist/cm6.js (checked in).
# Versions are pinned in package.json and package-lock.json; `npm ci` restores them exactly.
set -e
cd "${0:A:h}"
[[ -d node_modules ]] || npm ci --no-audit --no-fund
./node_modules/.bin/esbuild src/duo-editor.js --bundle --minify --format=iife --target=safari18 \
  --legal-comments=external --outfile=dist/cm6.js
# Third-party licenses, for the About box and the repo.
node -e '
const fs=require("fs"),p=require("path");const lock=require("./package-lock.json");let out="";
for(const [k,v] of Object.entries(lock.packages)){ if(!k||v.dev) continue;
  const dir=p.join(__dirname,k); const lic=fs.readdirSync(dir).find(f=>/^licen[cs]e/i.test(f));
  out+=`## ${k.replace("node_modules/","")} ${v.version} (${v.license})\n\n`+(lic?fs.readFileSync(p.join(dir,lic),"utf8"):"")+"\n\n";}
fs.writeFileSync("dist/THIRD-PARTY-LICENSES.md","# Third-party licenses in cm6.js\n\n"+out);'
ls -la dist
