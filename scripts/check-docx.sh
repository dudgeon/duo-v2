#!/bin/bash
# The Word viewer's comparison loop (docx-viewer-handoff): live captures of an isolated Duo on a scratch
# workspace holding docs/design/docx-viewer-handoff/fixture's documents, the right pane cropped to the
# board and compared with it. No Claude turn; background (F-227); never the real support folder.
#
#   scripts/check-docx.sh                    build, then viewer, markup, fallback-question, fallback
#   NO_BUILD=1 scripts/check-docx.sh viewer  reuse build/Duo.app, only these
#
# Writes build/docx/<name>.png (the window), <name>-pane.png and <name>-compare.png (TARGET | BUILD | DIFFERENCE).
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
[ -n "${NO_BUILD:-}" ] || scripts/bundle.sh >/dev/null
fx=docs/design/docx-viewer-handoff/fixture
ws=/tmp/d-dx-ws; out="$root/build/docx"
mkdir -p "$out" $ws/Home $ws/work/garden /tmp/d-dx /tmp/d-dx-cc
printf -- '---\ngoal: "Home"\n---\n\n# Home\n' > $ws/Home/HOME.md
printf -- '---\ngoal: "Plan the garden"\n---\n\n# garden\n' > $ws/work/garden/PROJECT.md
python3 $fx/make_garden.py "$out/fixture" >/dev/null
cp "$out/fixture/board/Garden plan.docx" "$out/fixture/locked/Contract draft.docx" $ws/work/garden/
cp "$out/fixture/full/Garden plan.docx" "$ws/work/garden/Garden full.docx"
boards=("$@"); [ ${#boards[@]} -gt 0 ] || boards=(viewer markup fallback-question fallback)
export DUO_EXTRA_ENV="DUO_SUPPORT_DIR=/tmp/d-dx CLAUDE_CONFIG_DIR=/tmp/d-dx-cc"
for b in "${boards[@]}"; do
  case "$b" in
    viewer) file="Garden plan.docx"; acts="docx-hover:(a third author),freeze:3"; target=viewer ;;
    markup) file="Garden full.docx"; acts="docx-menu:open,freeze:3"; target=markup ;;
    fallback-question) file="Garden full.docx"; acts="docx-ask-convert,freeze:3"; target=fallback ;;
    fallback) file="Contract draft.docx"; acts="freeze:3"; target=fallback ;;
    *) echo "no board $b" >&2; exit 1 ;;
  esac
  env -u DUO_SUPPORT_DIR DUO_TIMEOUT=60 scripts/run-live.sh $ws "$out/$b.png" "open:garden,open-file:$ws/work/garden/$file,right-width:460,$acts" "$out/$b.log" >/dev/null
  python3 scripts/chat-crop.py "$out/$b.png" "$out/$b-pane.png" 980 40 460 800
  bash docs/design/build-handoff/tools/compare.sh docx-viewer-handoff/$target "$out/$b-pane.png" "$out/$b-compare.png" >/dev/null
  echo "$b  →  build/docx/$b-compare.png"
done
