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
boards=("$@"); [ ${#boards[@]} -gt 0 ] || boards=(viewer markup fallback-question fallback picked-hover picked picked-session)
# The paragraph ids the board's picked state hovers (the first body paragraph with a comment) and picks (Casey's).
ids=$(python3 - "$out/fixture/board/Garden plan.docx" <<'PY'
import re, sys, zipfile
d = zipfile.ZipFile(sys.argv[1]).read("word/document.xml").decode()
ps = re.findall(r'<w:p w14:paraId="([0-9A-F]+)"[^>]*>(.*?)</w:p>', d, re.S)
text = lambda x: re.sub(r"<[^>]+>", "", re.sub(r"<w:delText[^>]*>[^<]*</w:delText>", "", x))
print([i for i, x in ps if "volunteers" in text(x)][0], [i for i, x in ps if text(x).startswith("Casey")][0])
PY
)
hoverid=${ids% *}; pickid=${ids#* }
export DUO_EXTRA_ENV="DUO_SUPPORT_DIR=/tmp/d-dx CLAUDE_CONFIG_DIR=/tmp/d-dx-cc"
for b in "${boards[@]}"; do
  watch=""
  case "$b" in
    viewer) file="Garden plan.docx"; acts="docx-hover:(a third author),freeze:3"; target=viewer ;;
    markup) file="Garden full.docx"; acts="docx-menu:open,freeze:3"; target=markup ;;
    fallback-question) file="Garden full.docx"; acts="docx-ask-convert,freeze:3"; target=fallback ;;
    fallback) file="Contract draft.docx"; acts="freeze:3"; target=fallback ;;
    picked-hover) file="Garden plan.docx"; acts="docx-picking,docx-pick-hover:$hoverid,freeze:3"; target=picked ;;
    picked) file="Garden plan.docx"; acts="docx-pick:$pickid,freeze:3"; target=picked ;;
    # With a Claude session showing, as the board draws it: Duo starts one (it asks for no turn), and a watcher
    # writes the beacon Claude itself would (idle) for each, so Send to Claude is the default button.
    picked-session) file="Garden plan.docx"; acts="new,freeze:14,open-file:$ws/work/garden/Garden plan.docx,docx-pick:$pickid,freeze:3"; target=picked; watch=1 ;;
    *) echo "no board $b" >&2; exit 1 ;;
  esac
  if [ -n "${watch:-}" ]; then
    ( set +e +o pipefail; for _ in $(seq 1 40); do
        d=$(pgrep -f -- "MacOS/Duo .*--capture-window $out/$b.png" | head -1)
        for c in $(pgrep -P "${d:-0}" 2>/dev/null); do
          ps -o command= -p "$c" | grep -q -- "claude --session-id" && \
            printf '{"pid":%s,"sessionId":"00000000-0000-4000-8000-%012d","cwd":"%s","status":"idle","kind":"interactive","entrypoint":"cli"}' "$c" "$c" "$ws/work/garden" > /tmp/d-dx-cc/sessions/$c.json
        done; sleep 1; done ) &
  fi
  env -u DUO_SUPPORT_DIR DUO_TIMEOUT=60 scripts/run-live.sh $ws "$out/$b.png" "open:garden,open-file:$ws/work/garden/$file,right-width:460,$acts" "$out/$b.log" >/dev/null
  python3 scripts/chat-crop.py "$out/$b.png" "$out/$b-pane.png" 980 40 460 800
  bash docs/design/build-handoff/tools/compare.sh docx-viewer-handoff/$target "$out/$b-pane.png" "$out/$b-compare.png" >/dev/null
  # The picker bar sits at the bottom of the pane, which is taller than the board's 800: compare it bottom-aligned too.
  case "$b" in picked*)
    python3 scripts/chat-crop.py "$out/$b.png" "$out/$b-bottom.png" 980 101 460 800 >/dev/null
    bash docs/design/build-handoff/tools/compare.sh docx-viewer-handoff/picked "$out/$b-bottom.png" "$out/$b-bottom-compare.png" >/dev/null ;;
  esac
  echo "$b  →  build/docx/$b-compare.png"
done
