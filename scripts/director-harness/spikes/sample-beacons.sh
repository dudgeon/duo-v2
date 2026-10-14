#!/bin/zsh
# Samples a scratch config's session beacons (sessions/*.json) every 0.25 s, printing each change:
#   sample-beacons.sh <config dir> <seconds>
cfg=$1 secs=$2 last=
end=$((SECONDS + secs))
while (( SECONDS < end )); do
  now=$(cat $cfg/sessions/*.json 2>/dev/null | python3 -c 'import sys,json
for l in sys.stdin.read().replace("}{","}\n{").splitlines():
  try: b=json.loads(l)
  except Exception: continue
  print(b.get("status"), b.get("waitingFor",""))' 2>/dev/null)
  [[ $now != $last ]] && print -r -- "$(date +%T) ${now:-<no beacon>}" && last=$now
  sleep 0.25
done
