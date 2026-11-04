#!/bin/zsh
# Shared helpers for the multi-window slice 1 regression walk. Source it: . tools/lib.sh
# Everything is isolated: scratch HOME + Claude config under /tmp/mwr/fx, Duo support under /tmp/mwr/sup,
# a stand-in claude (scripts/scale-tui.py), no network. Geoff's Duo and ~/DuoAcceptance are never touched.
REPO=${REPO:-${${(%):-%x}:A:h:h:h:h:h}}   # the checkout this folder lives in (docs/acceptance/<walk>/tools/lib.sh)
# The baselines are extracted by the caller: OLD=<0.2.22 Duo.app> OLD23=<0.2.23 Duo.app> (gh release download, then ditto from the DMG).
MWR=${MWR:-/tmp/mwr}
FX=$MWR/fx
SUP=$MWR/sup
WS=$FX/home/DuoAcceptance/workspace
OLD=${OLD:?set OLD to the v0.2.22 Duo.app}
OLD23=${OLD23:?set OLD23 to the v0.2.23 Duo.app (the base just before slice 0/1)}
appfor() { case $1 in old) echo $OLD;; old23) echo $OLD23;; *) echo $NEW;; esac; }
NEW=$REPO/build/Duo.app                                     # main, release build
STUB=$MWR/claude

sup_reset() { [[ -d $SUP ]] && chmod -R u+w $SUP 2>/dev/null; rm -rf $SUP; }   # Duo's mods folder is read-only
fx_build() {   # fresh identical fixture at the same path for every run (so outputs diff byte for byte)
  rm -rf $FX; mkdir -p $FX/home $FX/cfg $MWR
  ( export HOME=$FX/home CLAUDE_CONFIG_DIR=$FX/cfg; python3 -I $REPO/scripts/acceptance/fixtures.py >/dev/null 2>&1 )
  printf '#!/bin/sh\nexec /usr/bin/python3 -I %s "$@"\n' "$REPO/scripts/scale-tui.py" > $STUB; chmod +x $STUB
}

app_start() {   # app_start <app> [extra Duo args...]  (workspace mode; sets PID, DUO_SOCKET, DUO_TOKEN, D2)
  local app=$1; shift
  fx_build_if_needed
  mkdir -p $SUP
  env -u DUO_SUPPORT_DIR -u DUO_SOCKET -u DUO_TOKEN DUO_SUPPORT_DIR=$SUP CLAUDE_CONFIG_DIR=$FX/cfg DUO_AUTOCONFIRM=1 \
    HOME=$FX/home $app/Contents/MacOS/Duo --workspace $WS "$@" 2>$MWR/stderr.txt >/dev/null &
  PID=$!
  local i; for i in {1..60}; do [[ -f $SUP/Duo/endpoint.json ]] && break; sleep 1; done
  export DUO_SOCKET=$(python3 -I -c "import json;print(json.load(open('$SUP/Duo/endpoint.json'))['socket'])" 2>/dev/null)
  export DUO_TOKEN=$(python3 -I -c "import json;print(json.load(open('$SUP/Duo/endpoint.json'))['token'])" 2>/dev/null)
  # NEVER fall through to Geoff's own Duo (a duo2 with no socket reaches it): both must be set and inside $SUP.
  if [[ -z $DUO_SOCKET || -z $DUO_TOKEN || $DUO_SOCKET != $SUP/* && $DUO_SOCKET != /private$SUP/* ]]; then
    echo "✘ ABORT: no isolated endpoint for this run (socket='$DUO_SOCKET'); not running any duo2" >&2
    kill -TERM $PID 2>/dev/null; exit 99
  fi
  D2=$app/Contents/Helpers/duo2
  sleep 3
}
fx_build_if_needed() { [[ -d $WS ]] || fx_build; }

app_stop() {   # SIGTERM, as ⌘Q
  [[ -n ${PID:-} ]] || return
  kill -TERM $PID 2>/dev/null
  local i; for i in {1..25}; do kill -0 $PID 2>/dev/null || break; sleep 1; done
  kill -0 $PID 2>/dev/null && echo "✘ pid $PID did not quit on SIGTERM" >&2
  pkill -f "$REPO/scripts/scale-tui.py" 2>/dev/null
  unset PID
}

d2() {   # d2 <outfile-stem> <duo2 args...>: run duo2, save stdout, stderr and exit code
  local stem=$1; shift
  [[ -n ${DUO_SOCKET:-} && -n ${DUO_TOKEN:-} ]] || { echo "✘ ABORT: DUO_SOCKET/DUO_TOKEN unset" >&2; exit 99; }
  $D2 "$@" >$OUT/$stem.out 2>$OUT/$stem.err; echo $? >$OUT/$stem.rc
}

launch_capture() {   # launch_capture <app> <png> <then> [Duo args...]: one scripted launch, captured, as check-ui does
  local app=$1 png=$2 then=$3; shift 3
  rm -f $png
  open -g -W -n --env DUO_SUPPORT_DIR=$SUP --env CLAUDE_CONFIG_DIR=$FX/cfg --env DUO_AUTOCONFIRM=1 --env ${DUO_APPEARANCE:+DUO_APPEARANCE=$DUO_APPEARANCE}${DUO_APPEARANCE:-X=1} \
    --stdout /dev/null --stderr ${CAP_ERR:-/dev/null} $app --args "$@" --capture-window $png ${then:+--then "$then"} &
  local p=$! i; for i in {1..160}; do kill -0 $p 2>/dev/null || break; sleep 0.5; done
  kill -0 $p 2>/dev/null && { kill $p; echo "no capture: $png" >&2; }
  wait $p 2>/dev/null
}
