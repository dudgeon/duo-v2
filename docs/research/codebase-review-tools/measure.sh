#!/bin/zsh
# One isolated, background Duo run, measured. Never the user's Duo: its own support folder, a scratch
# CLAUDE_CONFIG_DIR, a stand-in claude (scripts/scale-tui.py, reports 2.1.219), no network, SIGTERM by pid.
#
#   measure.sh <label> <secs> [--docs N] [--html N] [--workspace-copy <dir> --config-copy <dir>] -- <make-scale-fixture args…>
#
# Writes $OUT/<label>/: summary.txt, cpu.txt (t %cpu rss_kb), footprint-*.txt, vmmap.txt, sample.txt, leaks.txt,
# stderr.txt, hangs.jsonl, webkit.txt.  APP (default: the worktree's build/Duo.app).
set -u
zmodload zsh/datetime
W=${W:-${0:A:h:h:h:h}}   # the repo (this script is in docs/research/codebase-review-tools)
OUT=${OUT:-${TMPDIR:-/tmp}/duo-review/runs}
app=${APP:-$W/build/Duo.app}
label=$1 secs=$2; shift 2
docs=0 html=0 wscopy= cfgcopy= events=0 churn=0
while [[ $# -gt 0 && $1 != -- ]]; do
  case $1 in
    --events) events=$2; shift 2;;   # this many sessions get a 256 KB hook-event log (chat mode's MessageDisplay lines)
    --churn) churn=$2; shift 2;;     # KB of a Markdown file in Home that grows by a paragraph every 20 s (a session editing a big doc)
    --docs) docs=$2; shift 2;;
    --html) html=$2; shift 2;;
    --workspace-copy) wscopy=$2; shift 2;;
    --config-copy) cfgcopy=$2; shift 2;;
    *) echo "unknown $1"; exit 2;;
  esac
done
[[ ${1:-} == -- ]] && shift
o=$OUT/$label; rm -rf $o; mkdir -p $o
fx=$(mktemp -d /tmp/d-rv-XXXX); fx=${fx:A}
stub=$fx/claude
printf '#!/bin/sh\nexec /usr/bin/python3 -I %s "$@"\n' "$W/scripts/scale-tui.py" > $stub; chmod +x $stub
if [[ -n $wscopy ]]; then
  mkdir -p $fx/sup/Duo
  cp -Rp $wscopy $fx/ws; cp -Rp $cfgcopy $fx/cfg
else
  python3 $W/scripts/make-scale-fixture.py $fx "$@" --claude $stub > $o/fixture.txt 2>&1 || { echo "fixture failed"; cat $o/fixture.txt; exit 1; }
fi
if (( events > 0 )); then
  python3 -I - $fx $events <<'PY'
import json, os, pathlib, random, sys, time
fx, k = pathlib.Path(sys.argv[1]), int(sys.argv[2])
ids = sorted(p.stem for p in (fx / "cfg" / "projects").glob("*/*.jsonl"))[:k]
ev = fx / "sup" / "Duo" / "events"; ev.mkdir(parents=True, exist_ok=True)
r = random.Random(3); words = "the a session tool edit read file chat claude review plan build check".split()
for sid in ids:
    with open(ev / f"{sid}.jsonl", "w") as f:
        size, t = 0, time.time() - 86400
        while size < 256 * 1024:
            e = {"session_id": sid, "hook_event_name": r.choice(["MessageDisplay", "PreToolUse", "PostToolUse"]),
                 "tool_name": "Read", "message": " ".join(r.choice(words) for _ in range(120))}
            line = json.dumps({"at": round(t, 3), "e": e}) + "\n"; f.write(line); size += len(line); t += 2
print(f"{len(ids)} event logs of 256 KB")
PY
fi
if (( churn > 0 )); then
  python3 -I -c "import sys,random; r=random.Random(5); w='plan review build check finding decision record session'.split(); open(sys.argv[1],'w').write(''.join('## F-%d\n\n%s\n\n' % (i, ' '.join(r.choice(w) for _ in range(150))) for i in range(int(sys.argv[2])*1024//1000)))" $fx/ws/findings.md $(( churn ))
  ( while sleep 20; do [[ -d $fx/ws ]] || break; echo "\n## F-new $RANDOM\n\nAnother finding appended by a session." >> $fx/ws/findings.md; done ) &
  churner=$!
fi
# Documents to open after launch: Markdown and HTML files in Home's folder.
for ((i = 1; i <= docs; i++)); do
  { echo "# Note $i"; for ((k = 0; k < 200; k++)); do echo "Line $k of note $i with **bold** and a [link](https://example.com)."; done } > $fx/ws/note-$i.md
done
for ((i = 1; i <= html; i++)); do
  { echo "<html><body><h1>Page $i</h1>"; for ((k = 0; k < 200; k++)); do echo "<p>Paragraph $k</p>"; done; echo "</body></html>"; } > $fx/ws/page-$i.html
done
before_wk=($(pgrep -f 'com.apple.WebKit' | sort -n))
t0=$EPOCHREALTIME
env -u DUO_SUPPORT_DIR -u DUO_SOCKET -u DUO_TOKEN DUO_SUPPORT_DIR=$fx/sup CLAUDE_CONFIG_DIR=$fx/cfg DUO_AUTOCONFIRM=1 \
  $app/Contents/MacOS/Duo --workspace $fx/ws 2>$o/stderr.txt &
pid=$!; sample $pid 8 -mayDie -file $o/early-sample.txt >/dev/null 2>&1 &
t_ep= t_ready= t_restore=
for ((i = 0; i < 600; i++)); do
  [[ -z $t_ep && -f $fx/sup/Duo/endpoint.json ]] && t_ep=$EPOCHREALTIME
  [[ -z $t_restore ]] && grep -q '^restore:' $o/stderr.txt 2>/dev/null && t_restore=$EPOCHREALTIME
  [[ -n $t_ep ]] && break
  sleep 0.05
done
export DUO_SOCKET=$(python3 -c "import json;print(json.load(open('$fx/sup/Duo/endpoint.json'))['socket'])")
export DUO_TOKEN=$(python3 -c "import json;print(json.load(open('$fx/sup/Duo/endpoint.json'))['token'])")
duo2=$app/Contents/Helpers/duo2
for ((i = 0; i < 400; i++)); do
  if $duo2 status > $o/status.txt 2>&1; then t_ready=$EPOCHREALTIME; break; fi
  sleep 0.05
done
printf 'endpoint %.2f s, duo2 status answers %.2f s\n' $(( t_ep - t0 )) $(( ${t_ready:-0} - t0 )) > $o/summary.txt
# Launch work: what runs in the first seconds (the first scan, the archive, the first index pass).
: # early sample moved -mayDie -file $o/early-sample.txt >/dev/null 2>&1 &
early=$!
( sleep 9; mid=($(pgrep -f 'com.apple.WebKit' | sort -n)); n=(${mid:|before_wk}); echo "WebKit processes 9 s after launch, before any document: ${#n}" > $o/webkit-at-launch.txt
  for p in $n; do ps -o pid=,rss=,command= -p $p | sed 's|.*XPCServices/||' | cut -c1-80 >> $o/webkit-at-launch.txt; done ) &
# Open documents through duo2 (Markdown in the editor, HTML as a page), one second apart.
if (( docs + html > 0 )); then
  sleep 10
  footprint -p $pid > $o/footprint-before-docs.txt 2>&1
  for ((i = 1; i <= docs; i++)); do $duo2 doc open $fx/ws/note-$i.md >> $o/docs.txt 2>&1; sleep 1; done
  for ((i = 1; i <= html; i++)); do $duo2 doc open $fx/ws/page-$i.html >> $o/docs.txt 2>&1; sleep 1; done
  $duo2 doc tabs >> $o/docs.txt 2>&1
fi
: > $o/cpu.txt
for ((t = 5; t <= secs; t += 5)); do
  sleep 5
  echo "$t $(ps -o %cpu=,rss=,time= -p $pid)" >> $o/cpu.txt
  [[ -z $t_restore ]] && grep -q '^restore:' $o/stderr.txt 2>/dev/null && t_restore=$EPOCHREALTIME
  if (( t == secs - 15 )); then
    sample $pid 10 -mayDie -file $o/sample.txt >/dev/null 2>&1 &
  fi
done
wait %sample 2>/dev/null; sleep 1
footprint -p $pid > $o/footprint.txt 2>&1
vmmap --summary $pid > $o/vmmap.txt 2>&1
leaks $pid > $o/leaks.txt 2>&1
after_wk=($(pgrep -f 'com.apple.WebKit' | sort -n))
new_wk=(${after_wk:|before_wk})
{ echo "new WebKit processes: ${#new_wk}"; for p in $new_wk; do ps -o pid=,rss=,command= -p $p | cut -c1-160; done
  (( ${#new_wk} )) && footprint ${new_wk} 2>&1 | tail -n 4; } > $o/webkit.txt
threads=$(ps -M -p $pid | tail -n +2 | wc -l | tr -d ' ')
fds=$(lsof -p $pid 2>/dev/null | wc -l | tr -d ' ')
kids=$(pgrep -P $pid | wc -l | tr -d ' ')
kidrss=$(for k in $(pgrep -P $pid); do ps -o rss= -p $k; done | awk '{s+=$1} END {print s+0}')
{ [[ -n $t_restore ]] && printf 'restore line %.2f s: %s\n' $(( t_restore - t0 )) "$(grep '^restore:' $o/stderr.txt | head -1)"
  echo "threads $threads, open files $fds, child processes $kids (rss ${kidrss} KB)"
  grep -E 'Physical footprint:|Physical footprint \(peak\)' $o/footprint.txt
  grep -E '^Physical footprint|TOTAL' $o/vmmap.txt | head -3
  grep -E 'leaks for|total leaked' $o/leaks.txt | head -2
  awk '$1 >= 30 {s += $2; n++} END {if (n) printf "mean CPU after 30 s: %.1f%% over %d readings\n", s/n, n}' $o/cpu.txt
  awk 'END {printf "rss at end: %.0f MB\n", $3/1024}' $o/cpu.txt
  awk '$3 > m {m = $3; t = $1} END {printf "rss max (5 s readings): %.0f MB at %d s\n", m/1024, t}' $o/cpu.txt
  awk '$1 >= 15 && $1 <= 60 {s += $2; n++} END {if (n) printf "mean CPU 15-60 s: %.1f%%\n", s/n}' $o/cpu.txt
  awk '$1 > 60 {s += $2; n++} END {if (n) printf "mean CPU after 60 s: %.1f%%\n", s/n}' $o/cpu.txt
  cat $o/webkit-at-launch.txt 2>/dev/null | head -1
  # Exact CPU from cumulative CPU time (ps time= is [h:]m:ss.cc): launch to 30 s, and 60 s to the end.
  awk 'function secs(s,  a, n) { n = split(s, a, ":"); return n == 3 ? a[1]*3600 + a[2]*60 + a[3] : a[1]*60 + a[2] }
       { c[$1] = secs($4); last = $1 }
       END { if (30 in c) printf "CPU time to 30 s: %.1f s (%.0f%% of a core)\n", c[30], c[30]/30*100;
             if ((60 in c) && last > 60) printf "CPU 60 s to %d s: %.1f%% of a core\n", last, (c[last]-c[60])/(last-60)*100 }' $o/cpu.txt
} >> $o/summary.txt
cp $fx/sup/Duo/logs/hangs.jsonl $o/ 2>/dev/null
kill -TERM $pid; for i in {1..20}; do kill -0 $pid 2>/dev/null || break; sleep 1; done
kill -0 $pid 2>/dev/null && echo "Duo didn't quit within 20 s (pid $pid)" >> $o/summary.txt
pkill -f "$fx/claude" 2>/dev/null; pkill -f "$W/scripts/scale-tui.py" 2>/dev/null
[[ -n ${churner:-} ]] && kill $churner 2>/dev/null
cp $fx/sup/Duo/search/*.sqlite* $o/ 2>/dev/null; du -sh $fx/sup/Duo/* > $o/support-sizes.txt 2>/dev/null
rm -rf $fx
cat $o/summary.txt
