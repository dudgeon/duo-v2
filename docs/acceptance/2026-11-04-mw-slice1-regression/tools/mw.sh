#!/bin/zsh
# mw.sh <outdir>: two and three windows on main (the new app only). Records duo2 output for each step.
export MWR=/tmp/mwr-mw
. ${0:A:h}/lib.sh
OUT=$1; sup_reset; rm -rf $OUT; mkdir -p $OUT; fx_build
app_start $NEW
n=0
r() { n=$((n+1)); local nm=$(printf '%03d-%s' $n $1); shift; d2 $nm "$@"; }
r claude settings claude-path $STUB
r list0 window list
r colour0 window colour
r open-checkout open checkout
r list1 window list
# window 2 on refunds, window 3 on onboarding
r new-refunds window new refunds
r new-onboarding window new onboarding
r list3 window list
r colour-w1 window colour --window 1
r colour-w2 window colour --window 2
r colour-w3 window colour --window 3
# DL-308: opening a project that lives in another window brings that window forward, no duplicate
r again-checkout window new checkout
r again-refunds window new refunds
r list-after-bring window list
r open-in-w3-refunds open refunds --window 3
r list-after-open window list
r status-w1 status --json --window 1
r status-w2 status --json --window 2
r status-w3 status --json --window 3
r status-bysel status --json --window refunds
r status-nowin status --json
# sessions in different windows
r sessions-all sessions --json
r new-session-w2 session new --project refunds --name "W2 session" --window 2
sleep 3
r sessions-w2 sessions --project refunds --json
# route a call from a session in window 2
sid=$($D2 sessions --project refunds --json 2>/dev/null | python3 -I -c "import json,sys;d=json.load(sys.stdin);d=d if isinstance(d,list) else d.get('sessions',[]);print([s['id'] for s in d if s.get('running') and s.get('project')=='refunds'][0])" 2>/dev/null)
[[ -n $sid ]] || { echo "✘ no session id for the routing test" >&2; }
echo "sid=$sid" > $OUT/sid.txt
DUO_SESSION_ID=$sid $D2 status --json > $OUT/from-session-status.out 2> $OUT/from-session-status.err; echo $? > $OUT/from-session-status.rc
DUO_SESSION_ID=$sid $D2 go all > $OUT/from-session-goall.out 2> $OUT/from-session-goall.err; echo $? > $OUT/from-session-goall.rc
# a planted (not running) refunds session and the project's window: does the caller still route to window 2?
sid2=$($D2 sessions --project refunds --json 2>/dev/null | python3 -I -c "import json,sys;d=json.load(sys.stdin);d=d if isinstance(d,list) else d.get('sessions',[]);print([s['id'] for s in d if not s.get('running') and s.get('project')=='refunds'][0])" 2>/dev/null)
echo "sid2=$sid2" >> $OUT/sid.txt
DUO_SESSION_ID=$sid2 $D2 status --json > $OUT/from-planted-status.out 2> $OUT/from-planted-status.err; echo $? > $OUT/from-planted-status.rc
DUO_SESSION_ID=$sid2 $D2 window list > $OUT/from-planted-wlist.out 2>&1; echo $? > $OUT/from-planted-wlist.rc
r after-from-session-w1 status --json --window 1
r after-from-session-w2 status --json --window 2
r after-from-session-w3 status --json --window 3
r open-from-w1 open reading
# Home in another window
r go-home-w2 go home --window 2
r window-home-w3 window home --window 3
r list-home window list
r focus-1 window focus 1
r focus-name window focus onboarding
r focus-missing window focus 9
# colours
r colour-set window colour coral --window 2
r colour-none window colour none --window 3
r colour-bad window colour chartreuse --window 1
r colour-auto-off window colour --auto off
r new-nocolour window new
r list-nocolour window list
r colour-auto-on window colour --auto on
# Classic
r classic settings appearance classic
r colour-classic window colour --window 1
r list-classic window list
r system settings appearance system
r list-system window list
# close
r close-w2 window close 2
r sessions-after-close sessions --json
r list-after-close window list
r close-bysel window close onboarding
r list-after-close2 window list
r reopen-closed-project open refunds
r list-reopen window list
# close all but hide: last window hides, Duo runs
r close-all window close --window 1
r list-c1 window list
for i in 2 3 4 5 6; do $D2 window close --window $i >/dev/null 2>&1; done
r list-c2 window list
r ping-after ping
r status-after status --json
r sessions-after-hide sessions --json
r new-after window new
r list-after-new window list
sleep 2
app_stop
echo done $n
