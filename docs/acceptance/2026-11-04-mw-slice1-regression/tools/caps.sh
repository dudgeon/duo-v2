#!/bin/zsh
# caps.sh <old|new> <outdir>: the same scripted launches on either app, each captured to a PNG (--capture-window,
# background, never shown). Fixture states first (light, dark, classic), then live-workspace flows.
export MWR=/tmp/mwr-cap-$1
. ${0:A:h}/lib.sh
which=$1; OUT=$2
APPP=$(appfor $which)
mkdir -p $OUT; rm -f $OUT/*.png(N)
CAP_ERR=/dev/null

# fixture states x appearance
for look in light dark classic; do
  for s in overview flow-zoom-1 project flow-zoom-2 flow-zoom-3 flow-zoom-4; do
    sup_reset; DUO_APPEARANCE=$look launch_capture $APPP $OUT/state-$s-$look.png "" --state $s
  done
done

# live workspace flows: <name> <then-actions comma list> [look]
wsrun() {
  local name=$1 then=$2 look=${3:-light}
  sup_reset; fx_build
  CAP_ERR=$OUT/$name.log DUO_APPEARANCE=$look launch_capture $APPP $OUT/ws-$name-$look.png "$then" --workspace $WS
  CAP_ERR=/dev/null
}
for look in light dark; do
  wsrun launch "" $look
  wsrun allprojects "zoom-out" $look
  wsrun project "open:checkout" $look
  wsrun project-doc "open:checkout,doc:docs/prd.md" $look
  wsrun project-two-docs "open:checkout,doc:docs/prd.md,doc:docs/research.md" $look
  wsrun project-html "open:checkout,doc:prototypes/checkout.html" $look
  wsrun project-deck "open:checkout,doc:decks/field-trial-review.md" $look
  wsrun split "open:checkout,split:decks/field-trial-review.md" $look
  wsrun peek "peek" $look
  wsrun newsession "open:checkout,new" $look
  wsrun home "home" $look
  wsrun refunds "open:refunds" $look
  wsrun onboarding "open:onboarding" $look
done
wsrun project-doc-classic "open:checkout,doc:docs/prd.md" classic
wsrun allprojects-classic "zoom-out" classic
wsrun settings "render-settings:$OUT/settings-render.png"
wsrun menus "menus"
cp $OUT/menus.log $OUT/menus.txt 2>/dev/null
echo captured $(ls $OUT/*.png | wc -l)
