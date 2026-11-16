#!/bin/zsh
# View › Source (DL-346), live: an isolated background Duo on a scratch workspace opens a Markdown file and an HTML file,
# turns Source on and off with `duo2 doc mode` (the verb View › Source's menu item shares its action with), edits the HTML in
# source, goes back to the page (the editor saves first, the page then reads the file) and checks the file on disk. No Claude
# turn runs (a stand-in `claude` idles), no window is shown, nothing reaches the user's Duo (DUO_ISOLATED, own support folder
# and CLAUDE_CONFIG_DIR, duo2 pointed by both DUO_SOCKET and DUO_TOKEN).
#   scripts/check-view-source-live.sh [out-dir]       exit 0 when every step reads as it should
# Captures for the compare (Light, Dark, Classic): scripts/check-view-source-live.sh --captures <out-dir>
set -u
export DUO_ISOLATED=1
cd "${0:A:h:h}"
S=$(cd "$(mktemp -d /tmp/vsl.XXXX)" && pwd -P)   # short: the socket's path must stay under 104
WS=$S/ws CFG=$S/cfg SUP=$S/sup
mkdir -p $WS/Home $WS/garden $CFG/projects $CFG/sessions $SUP/Duo
print -- "# Home" > $WS/Home/HOME.md
printf -- '---\ngoal: "Plan"\n---\n\n# garden\n' > $WS/garden/PROJECT.md
printf -- '---\nstatus: draft\n---\n# Refunds review\nFell **12%%** {++in Q3++}, see [export](q3.csv)\n- `refunds.sql` {>>@geoff #c2: rerun <<}\n' > $WS/garden/review.md
printf -- '<style>\n  .up { color: #2f7d32; }\n</style>\n<h1>Refunds, Q3</h1>\n<p class="lede">Down <span class="up">12%%</span> since July.</p>\n<!-- by reason -->\n<script>\n  const rows = "41,28,17".split(",");\n</script>\n' > $WS/garden/q3.html
printf '#!/bin/sh\nexec sleep 3000\n' > $S/claude; chmod +x $S/claude
print -r -- "{\"claudePath\":\"$S/claude\",\"root\":\"$WS\"}" > $SUP/Duo/state.json
app=${DUO_APP:-build/Duo.app}

if [[ ${1:-} == --captures ]]; then
  out=${2:?out dir}; mkdir -p $out; out=${out:A}
  for scheme in light dark classic; do
    for f in q3.html review.md; do
      png=$out/source-${f%.*}-$scheme.png; rm -f $png
      env -u DUO_SOCKET -u DUO_TOKEN DUO_SUPPORT_DIR=$SUP CLAUDE_CONFIG_DIR=$CFG ANTHROPIC_MODEL=claude-haiku-5-5 DUO_APPEARANCE=$scheme \
        $app/Contents/MacOS/Duo --workspace $WS --window 1440x900 --capture-window $png --then "open:garden,file:$f,source:on,wait:3" 2> $out/$scheme-$f.log &
      pid=$!
      for i in {1..60}; do [[ -f $png ]] && break; sleep 1; done
      sleep 2; kill -TERM $pid 2>/dev/null; for i in {1..10}; do kill -0 $pid 2>/dev/null || break; sleep 1; done
      rm -rf $SUP/Duo/endpoint.json
    done
  done
  ls $out; exit 0
fi

env -u DUO_SOCKET -u DUO_TOKEN DUO_SUPPORT_DIR=$SUP CLAUDE_CONFIG_DIR=$CFG ANTHROPIC_MODEL=claude-haiku-5-5 \
  $app/Contents/MacOS/Duo --workspace $WS 2> $S/duo.err &
duo=$!
trap 'kill -TERM $duo 2>/dev/null' EXIT
for i in {1..40}; do [[ -f $SUP/Duo/endpoint.json ]] && break; sleep 1; done
export DUO_SOCKET=$(python3 -c "import json;print(json.load(open('$SUP/Duo/endpoint.json'))['socket'])")
export DUO_TOKEN=$(python3 -c "import json;print(json.load(open('$SUP/Duo/endpoint.json'))['token'])")
duo2=$app/Contents/Helpers/duo2
fails=0
ok()  { print "  ✔ $1"; }
bad() { print "  ✘ $1"; fails=$((fails+1)); }
has() { [[ $2 == *$3* ]] && ok "$1" || { bad "$1 (got: ${2:0:200})"; } }
sleep 3
$duo2 project open garden >/dev/null 2>&1

print "Markdown"
$duo2 doc open $WS/garden/review.md >/dev/null; sleep 2
has "a Markdown file opens on its page" "$($duo2 doc mode)" "Page."
has "doc mode source" "$($duo2 doc mode source)" "Source."
has "…and says so" "$($duo2 doc mode)" "Source."
has "the text is as typed" "$($duo2 doc read)" '{++in Q3++}'
has "doc mode page" "$($duo2 doc mode page)" "Page."
has "doc mode toggle" "$($duo2 doc mode toggle)" "Source."
$duo2 doc mode page >/dev/null

print "HTML"
$duo2 doc open $WS/garden/q3.html >/dev/null; sleep 3
has "an HTML file opens on its page" "$($duo2 doc mode)" "Page."
has "doc mode source" "$($duo2 doc mode source)" "Source."; sleep 3
has "the editor shows the file's text" "$($duo2 doc read)" 'const rows'
$duo2 doc replace 'Refunds, Q3' 'Refunds, Q4 edited in source' >/dev/null; sleep 1
has "the edit is in the buffer" "$($duo2 doc read)" 'Q4 edited in source'
has "doc mode page (saves first)" "$($duo2 doc mode page)" "Page."; sleep 3
has "the file on disk has the edit" "$(cat $WS/garden/q3.html)" 'Refunds, Q4 edited in source'
has "…and the rest of it" "$(cat $WS/garden/q3.html)" 'const rows = "41,28,17"'
has "toggle again" "$($duo2 doc mode toggle)" "Source."; sleep 2
has "the source reads the saved file" "$($duo2 doc read)" 'Q4 edited in source'
$duo2 doc mode page >/dev/null; sleep 1
has "back on the page" "$($duo2 doc mode)" "Page."

print "$fails failed; Duo's log: $S/duo.err"
exit $((fails > 0))
