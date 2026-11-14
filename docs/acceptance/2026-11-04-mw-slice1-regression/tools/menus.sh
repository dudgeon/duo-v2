#!/bin/zsh
# menus.sh <old|old23|new> <outfile>: the menu bar as text (every item, key, dim/enabled, check), from a fixture-state launch.
# DUO_MENU_UPDATE=1 asks each menu to validate items first, so enabled/dim match what a person would see.
export MWR=/tmp/mwr-menus-$1
. ${0:A:h}/lib.sh
APPP=$(appfor $1); OUTF=$2
sup_reset; mkdir -p $SUP
png=$MWR/m.png; err=$MWR/m.err; rm -f $png $err
open -g -W -n --env DUO_SUPPORT_DIR=$SUP --env DUO_MENU_UPDATE=1 --stdout /dev/null --stderr $err $APPP --args --state project --then "menus" --capture-window $png &
p=$!; for i in {1..120}; do kill -0 $p 2>/dev/null || break; sleep 0.5; done; kill $p 2>/dev/null
sed -n '/---- menus ----/,/---- end menus ----/p' $err > $OUTF
echo "$1: $(wc -l < $OUTF) lines"
