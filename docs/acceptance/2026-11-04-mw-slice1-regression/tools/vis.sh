#!/bin/zsh
# vis.sh <outdir>: the visible run (Geoff's OK via the director, 2026-11-04): C-160's gaps on main, and the same
# one-shot flows on 0.2.22 for comparison. Windows are shown (DUO_TEST_FOREGROUND=1) and may take focus.
# Isolated: own support folder, scratch Claude config, project names that exist nowhere else (zqv-*), a stand-in
# claude preset in state.json so no real claude starts. Hard stop: everything this script started ends at 18 min.
here=${0:A:h}
REPO=${REPO:-${here:h:h:h:h}}
OLD=${OLD:?set OLD to the v0.2.22 Duo.app}
NEW=$REPO/build/Duo.app
OUT=$1; mkdir -p $OUT
MWV=/tmp/mwv
STUB=$MWV/claude
T0=$SECONDS
mkdir -p $MWV
printf '#!/bin/sh\nexec /usr/bin/python3 -I %s "$@"\n' "$REPO/scripts/scale-tui.py" > $STUB; chmod +x $STUB

( sleep 1080; echo "vis.sh: 18 min hard stop" >&2; pkill -TERM -f -- "--workspace $MWV/" ; pkill -TERM -f "$REPO/scripts/scale-tui.py" ) &
stopper=$!

fresh() {   # fresh <tag>: new fixture + support folder with the stub claude preset
  local r=$MWV/$1
  [[ -d $r ]] && chmod -R u+w $r 2>/dev/null; rm -rf $r; mkdir -p $r/sup/Duo
  python3 -I $here/mkvis.py $r >/dev/null
  printf '{"home": "%s", "root": "%s", "claudePath": "%s"}' "$r/ws/zqvhome" "$r/ws" "$STUB" > $r/sup/Duo/state.json
  R=$r
}

oneshot() {   # oneshot <app-tag> <flow> <then-actions>
  local tag=$1 flow=$2 then=$3 app
  [[ $tag == old ]] && app=$OLD || app=$NEW
  (( SECONDS - T0 > 1000 )) && { echo "skip $tag $flow (time)"; return; }
  fresh $tag-$flow
  local then2=${then//@R/$R}
  open -g -W -n --env DUO_TEST_FOREGROUND=1 --env DUO_SUPPORT_DIR=$R/sup --env CLAUDE_CONFIG_DIR=$R/cfg --env DUO_AUTOCONFIRM=1 \
    --stdout /dev/null --stderr $OUT/$tag-$flow.log $app --args --workspace $R/ws --then "$then2" --capture-window $OUT/$tag-$flow.png &
  local p=$! i; for ((i = 0; i < 90; i++)); do kill -0 $p 2>/dev/null || break; sleep 0.5; done
  kill -0 $p 2>/dev/null && { pkill -TERM -f -- "--workspace $R/ws"; echo "$tag $flow: timed out" >> $OUT/summary.txt; }
  wait $p 2>/dev/null
  # what the flow left on disk
  cp $R/ws/zqvtopic/zqv-alpha/notes.md $OUT/$tag-$flow.notes.md 2>/dev/null
  echo "$tag $flow: png=$([[ -f $OUT/$tag-$flow.png ]] && echo yes || echo no)" >> $OUT/summary.txt
}

A=zqvtopic/zqv-alpha
for tag in new old; do
  # conflict: an unsaved edit in the editor, then the file changed on disk (DL-77); then keep mine
  oneshot $tag conflict "open:zqv-alpha,doc:$A/notes.md,wait:3,user-type:Alpha line=>Alpha MINE,disk-write:beta line=>beta DISK,wait:2,bar-text,pane-state,resolve:mine,wait:1,bar-text"
  # outside edit with no local edit: the editor follows the disk
  oneshot $tag outside "open:zqv-alpha,doc:$A/notes.md,wait:3,disk-write:beta line=>beta OUTSIDE,wait:2,bar-text" #:beta line=>beta OUTSIDE,bar-text"
  # ⇧⌘A search
  oneshot $tag search "search:zqv,search-state"
  # ⌘W closes the tab with the keyboard
  oneshot $tag cmdw "open:zqv-alpha,doc:$A/notes.md,doc:$A/other.md,wait:3,bar-focus,pane-state,cmd-w,wait:1,pane-state"
  # ⌘Q with an unsaved edit: saved on quit
  oneshot $tag cmdq "open:zqv-alpha,doc:$A/notes.md,wait:3,user-type:Alpha line=>Alpha QUIT,quit"
  # chat vs terminal on a planted session (stand-in claude: chat may fall back to the terminal, as it says)
  oneshot $tag chat "open:zqv-alpha,pane-state"
done
echo "one-shots done at $((SECONDS - T0)) s" >> $OUT/summary.txt

# ---- the long multi-window instance on main, driven by duo2 (guarded) ----
fresh mw
env -u DUO_SOCKET -u DUO_TOKEN DUO_TEST_FOREGROUND=1 DUO_SUPPORT_DIR=$R/sup CLAUDE_CONFIG_DIR=$R/cfg DUO_AUTOCONFIRM=1 \
  $NEW/Contents/MacOS/Duo --workspace $R/ws 2>$OUT/mw.log >/dev/null &
PID=$!
for i in {1..40}; do [[ -f $R/sup/Duo/endpoint.json ]] && break; sleep 1; done
export DUO_SOCKET=$(python3 -I -c "import json;print(json.load(open('$R/sup/Duo/endpoint.json'))['socket'])" 2>/dev/null)
export DUO_TOKEN=$(python3 -I -c "import json;print(json.load(open('$R/sup/Duo/endpoint.json'))['token'])" 2>/dev/null)
if [[ -z $DUO_SOCKET || -z $DUO_TOKEN || ( $DUO_SOCKET != $R/sup/* && $DUO_SOCKET != /private$R/sup/* ) ]]; then
  echo "✘ ABORT: no isolated endpoint (socket='$DUO_SOCKET')" | tee -a $OUT/summary.txt; kill -TERM $PID; kill $stopper; exit 99
fi
D2=$NEW/Contents/Helpers/duo2
n=0
r() { n=$((n+1)); local nm=$(printf 'mw-%03d-%s' $n $1); shift; $D2 "$@" >$OUT/$nm.out 2>$OUT/$nm.err; echo $? >$OUT/$nm.rc; }
sleep 3
r settings settings
r open-alpha open zqv-alpha
r new-beta window new zqv-beta
r new-gamma window new zqv-gamma
r list window list
r focus-1 window focus 1          # the Window menu's item for window 1 does this
r status-key status --json --window 1
r list-after-focus window list
r focus-gamma window focus zqv-gamma
r list-after-focus2 window list
r again-beta window new zqv-beta   # DL-308: bring forward, never a second window
r list-after-again window list
r fork-src sessions --project zqv-beta --json
sid=$(python3 -I -c "import json,sys;d=json.load(open('$OUT/mw-$(printf %03d $n)-fork-src.out'));print([s['id'] for s in d if s.get('project')=='zqv-beta'][0])" 2>/dev/null)
r fork session fork $sid --window 2
sleep 3
r sessions-beta sessions --project zqv-beta --json
r list-after-fork window list
fid=$(python3 -I -c "import json;d=json.load(open('$(ls $OUT/mw-*-sessions-beta.out | head -1)'));print([s['id'] for s in d if s.get('running')][0])" 2>/dev/null)
r chat-on session chat $fid on
sleep 2
r chat-status status --json --window 2
r chat-off session chat $fid off
sleep 2
r chat-status2 status --json --window 2
r doc-open doc open notes.md --project zqv-gamma --window 3
printf '\nOutside line.\n' >> $R/ws/zqvtopic/zqv-gamma/notes.md
sleep 3
r doc-read doc read notes.md --window 3
r doc-tabs-w3 doc tabs --window 3
r close-2 window close 2
r sessions-after-close sessions --json
r list-after-close window list
r ping ping
# ⌘Q: SIGTERM quits as ⌘Q does; relaunch shows what survives (slice 2 not built: one window expected)
kill -TERM $PID; for i in {1..20}; do kill -0 $PID 2>/dev/null || break; sleep 1; done
kill -0 $PID 2>/dev/null && echo "✘ main did not quit on SIGTERM" >> $OUT/summary.txt
env -u DUO_SOCKET -u DUO_TOKEN DUO_TEST_FOREGROUND=1 DUO_SUPPORT_DIR=$R/sup CLAUDE_CONFIG_DIR=$R/cfg DUO_AUTOCONFIRM=1 \
  $NEW/Contents/MacOS/Duo --workspace $R/ws 2>$OUT/mw-relaunch.log >/dev/null &
PID=$!
for i in {1..40}; do [[ -f $R/sup/Duo/endpoint.json ]] && break; sleep 1; done
export DUO_SOCKET=$(python3 -I -c "import json;print(json.load(open('$R/sup/Duo/endpoint.json'))['socket'])" 2>/dev/null)
export DUO_TOKEN=$(python3 -I -c "import json;print(json.load(open('$R/sup/Duo/endpoint.json'))['token'])" 2>/dev/null)
if [[ -n $DUO_SOCKET && -n $DUO_TOKEN && ( $DUO_SOCKET == $R/sup/* || $DUO_SOCKET == /private$R/sup/* ) ]]; then
  sleep 3
  r relaunch-list window list
  r relaunch-status status --json
fi
kill -TERM $PID; for i in {1..20}; do kill -0 $PID 2>/dev/null || break; sleep 1; done
pkill -TERM -f "$REPO/scripts/scale-tui.py" 2>/dev/null
kill $stopper 2>/dev/null
echo "vis done at $((SECONDS - T0)) s" >> $OUT/summary.txt
cat $OUT/summary.txt
