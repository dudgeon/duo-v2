#!/bin/zsh
export DUO_ISOLATED=1   # every duo2 here reaches only the test instance; refuses, never the user's Duo (F-529)
export DUO_TEST_DUO_CLOSED=1   # this script tests the offline verbs, so no instance is the point (F-619)
# Tier 1 of the duo-director test harness: for each profile, run `duo2 director status` from a stand-in
# Claude session and compare what it reports with the profile's expectations. No model, no network,
# no running Duo. See scripts/director-harness/README.md.
#   scripts/check-director.sh [profile-name…]
setopt local_options no_unset 2>/dev/null
zmodload zsh/datetime   # EPOCHREALTIME, for the speed check
root=${0:A:h:h}
h=$root/scripts/director-harness
duo2=$root/.build/debug/duo2
stub=$h/stub-claude

if [[ ! -x $duo2 ]]; then
  print "missing $duo2: run  swift build --product duo2  first"; exit 2
fi

# The stub is `claude` for this whole script. duo2 asks `claude auth status` from PATH, so otherwise the result
# would depend on whether the caller's PATH holds a real CLI, which says "logged out" for a scratch config (F-619).
shim=$(mktemp -d /tmp/dh-XXXX)
trap 'rm -rf $shim' EXIT
ln -s $stub $shim/claude
export PATH=$shim:$PATH

fail=0 pass=0
ok()  { print "  ✔ $1"; pass=$((pass+1)); }
bad() { print "  ✘ $1"; fail=$((fail+1)); }

# Arguments name profiles (and `duties`, the section after them). No argument runs all of it.
args=($@)
run_duties=0
if (( $#args == 0 )); then
  names=(${h}/profiles/*.json(:t:r)); run_duties=1
else
  names=(${args:#duties}); (( ${args[(Ie)duties]} )) && run_duties=1
fi

for name in $names; do
  prof=$h/profiles/$name.json
  print "== $name"
  tmp=$(mktemp -d /tmp/dh-XXXX)
  cfg=$tmp/c proj=$tmp/p sup=$tmp/s
  mkdir -p $proj $sup
  print "# $name" > $proj/PROJECT.md
  python3 -I $h/profile.py setup $prof $cfg

  # Isolation: a scratch support folder, no endpoint, so duo2 can never reach a running Duo.
  unset DUO_SOCKET DUO_TOKEN DUO_SESSION_ID CLAUDE_CODE_MESSAGING_SOCKET CLAUDE_CODE_DISABLE_AGENT_VIEW CLAUDE_CODE_PROJECTS_SESSION
  export DUO_SUPPORT_DIR=$sup CLAUDE_CONFIG_DIR=$cfg STUB_PROFILE=$prof
  if [[ $DUO_SUPPORT_DIR != $tmp/s ]]; then print "  ✘ isolation: DUO_SUPPORT_DIR is not the scratch folder"; exit 2; fi

  out=$(cd $proj && $stub --as-session -n director-x -- $duo2 director status 2>&1)
  if [[ $out != *"Duo isn't running"* ]]; then
    print "  ✘ isolation: output lacks \"Duo isn't running\" (is a Duo reachable?); stopping"
    print -r -- $out; exit 2
  fi

  # The login probe reached the stub, and status says what the profile says.
  if [[ -s $cfg/stub-auth-status && $(command -v claude) == $shim/claude ]]; then ok "the login probe reached the stub, not a real CLI"
  else bad "the login probe didn't reach the stub: claude is $(command -v claude)"; fi
  logged_in=$(python3 -I $h/profile.py get $prof stub.loggedIn)
  if [[ $logged_in == false ]]; then
    if [[ $out == *"RED R8 the CLI: Claude's CLI is logged out"* ]]; then ok "logged out: R8 says so"; else bad "logged out: no R8 line in ${out[1,300]}"; fi
  elif [[ $out == *"RED R8 the CLI"* ]]; then bad "logged in, but R8 says logged out"
  else ok "logged in: no R8 line about the CLI"; fi

  typeset -A got
  got=()
  [[ $out =~ 'Claude Code ([^ ,]+)' ]] && got[version]=$match[1]
  [[ $out =~ 'Messaging \(SendMessage, idle notices\): ([a-z]+)' ]] && got[messaging]=$match[1]
  [[ $out =~ 'Background sessions: ([a-z]+)' ]] && got[background]=$match[1]
  [[ $out =~ 'resuming one with a message: ([a-z]+)' ]] && got[backgroundResume]=$match[1]
  [[ $out =~ 'Remote Control: ([a-z]+)' ]] && got[remoteControl]=$match[1]
  [[ $out =~ 'Hooks: ([a-z]+)' ]] && got[hooks]=$match[1]
  [[ $out =~ 'Monitor: ([a-z]+)' ]] && got[monitor]=$match[1]

  for k in version messaging background backgroundResume remoteControl hooks monitor; do
    want=$(python3 -I $h/profile.py get $prof expect.$k)
    if [[ ${got[$k]:-} == $want ]]; then ok "$k = $want"; else bad "$k: want $want, got '${got[$k]:-?}'"; fi
  done

  # Stub behaviour: flags the profile lacks fail, and --bg --resume mints a new id and keeps the name.
  flags=$(python3 -I $h/profile.py get $prof stub.flags)
  if [[ $flags != *'"--bg"'* ]]; then
    e=$($stub --bg -n w1 2>&1); rc=$?
    if (( rc == 1 )) && [[ $e == *"unknown option '--bg'"* ]]; then ok "stub rejects --bg (unknown option)"; else bad "stub accepted --bg: rc=$rc $e"; fi
  else
    $stub --bg -n w1 --session-id 11111111-1111-4111-8111-111111111111 > /dev/null
    $stub --bg --resume 11111111-1111-4111-8111-111111111111 > /dev/null
    if python3 -I -c '
import json,sys
s=json.load(open(sys.argv[1]+"/stub-sessions.json"))
sys.exit(0 if len(s)==2 and s[0]["name"]==s[1]["name"]=="w1" and s[0]["id"]!=s[1]["id"] else 1)' $cfg; then
      ok "stub --bg --resume mints a new id and keeps the name"
    else bad "stub --bg --resume: $(cat $cfg/stub-sessions.json)"; fi
  fi
  if [[ $(python3 -I $h/profile.py get $prof stub.flags) != *'"--nope"'* ]]; then
    e=$($stub --nope 2>&1); rc=$?
    if (( rc == 1 )) && [[ $e == *"unknown option '--nope'"* ]]; then ok "stub rejects an unlisted flag"; else bad "unlisted flag not rejected: rc=$rc $e"; fi
  fi

  # The skill text, offline.
  g=$(cd $proj && $duo2 director guide 2>&1)
  if [[ $g == $'---\nname: director\n'* ]]; then ok "director guide starts with the skill front matter"; else bad "director guide: ${g[1,60]}"; fi

  # Duo closed, project outside Home: the Home Duo was given (its state.json) is named, not "No Home".
  mkdir -p $tmp/home $sup/Duo
  print "# Home" > $tmp/home/HOME.md
  print -r -- "{\"home\":\"$tmp/home\"}" > $sup/Duo/state.json
  o=$(cd $proj && $stub --as-session -n director-x -- $duo2 director status 2>&1)
  if [[ $o == *"Home: $tmp/home (Duo's Home"* && $o == *"$tmp/home/HOME.md (## Director) (no ## Director section yet)"* ]]; then ok "Duo closed: Duo's configured Home is used for a project outside it"
  else bad "offline Home: ${o[1,300]}"; fi
  rm $sup/Duo/state.json

  # Duo closed: start --background records a pending worker by name, and refuses the user's task.
  mkdir -p $proj/tasks
  print -r -- $'---\ntitle: T\nstatus: in-progress\ndirected_by: "director-x"\n---\n# T\n' > $proj/tasks/t.md
  print -r -- $'---\ntitle: U\nstatus: open\n---\n# U\n' > $proj/tasks/u.md
  if [[ $logged_in == false ]]; then
    # A logged-out CLI: every start of a worker with Duo closed is refused, and says why (F-365).
    o=$(cd $proj && $stub --as-session -n director-x --session-id 33333333-3333-4333-8333-333333333333 -- $duo2 director start t --background 2>&1); rc=$?
    if (( rc != 0 )) && [[ $o == *"logged out"* ]]; then ok "Duo closed, logged out: start is refused"; else bad "offline start, logged out: rc=$rc ${o[1,160]}"; fi
    rm -rf $tmp
    continue
  fi
  if [[ $(python3 -I $h/profile.py get $prof expect.background) == no ]]; then
    # No background sessions: every start of a worker with Duo closed is refused, and says why.
    o=$(cd $proj && $stub --as-session -n director-x --session-id 33333333-3333-4333-8333-333333333333 -- $duo2 director start t --background 2>&1); rc=$?
    if (( rc != 0 )) && [[ $o == *"Background sessions are off"* ]]; then ok "Duo closed, no background sessions: start is refused"; else bad "offline start with no background: rc=$rc ${o[1,160]}"; fi
    rm -rf $tmp
    continue
  fi
  o=$(cd $proj && $stub --as-session -n director-x --session-id 33333333-3333-4333-8333-333333333333 -- $duo2 director start t --background 2>&1); rc=$?
  if (( rc == 0 )) && [[ $o == *"claude --bg"*"-n 't-"* ]] && python3 -I -c '
import json,sys
r=json.load(open(sys.argv[1]+"/.duo/director.json"))
w=r["workers"][0]
sys.exit(0 if r["current"]["name"]=="director-x" and w["task"]=="tasks/t.md" and w["session"]=="" and w["name"].startswith("t-") else 1)' $proj; then
    ok "Duo closed: start --background records a pending worker by name, and the director"
  else bad "offline start: rc=$rc ${o[1,200]}"; fi
  o=$(cd $proj && $stub --as-session -n director-x --session-id 33333333-3333-4333-8333-333333333333 -- $duo2 director start --title "Quoted \"words\"" --request 'He said "ship it", then:
- two lines' --done-when "a draft exists" --background 2>&1); rc=$?
  n=$(ls $proj/tasks/ | grep -v '^t.md$' | grep -v '^u.md$' | head -1)
  if (( rc == 0 )) && [[ -n $n ]] && python3 -I -c '
import json,sys
t=open(sys.argv[1]+"/tasks/"+sys.argv[2]).read()
r=json.load(open(sys.argv[1]+"/.duo/director.json"))
ok = "directed_by: \"director-x\"" in t and "done_when: \"a draft exists\"" in t and "## Request\n\nHe said \"ship it\", then:\n- two lines\n" in t and "## Progress" in t and "status: in-progress" in t
w=[x for x in r["workers"] if x["task"]=="tasks/"+sys.argv[2]]
sys.exit(0 if ok and w and w[0]["session"]=="" and w[0]["name"] else 1)' $proj $n; then
    ok "Duo closed: start --title … --request … --background writes the note (the request verbatim) and records the pending worker"
  else bad "offline start --title: rc=$rc n=$n ${o[1,200]}"; fi
  o=$(cd $proj && $stub --as-session -n director-x --session-id 33333333-3333-4333-8333-333333333333 -- $duo2 director start u --background 2>&1); rc=$?
  if (( rc != 0 )) && [[ $o == *"no directed_by"* ]]; then ok "Duo closed: the user's task (no directed_by:) is refused"; else bad "offline start of the user's task: rc=$rc ${o[1,160]}"; fi
  o=$(cd $proj && $stub --as-session -n director-x --session-id 33333333-3333-4333-8333-333333333333 -- $duo2 director start t 2>&1); rc=$?
  if (( rc == 0 )) && [[ $o == *"claude --bg"*"-n 't-"* ]]; then ok "Duo closed: no flag starts in the background too (DL-230)"; else bad "offline start without --background: rc=$rc ${o[1,160]}"; fi
  o=$(cd $proj && $stub --as-session -n director-x --session-id 33333333-3333-4333-8333-333333333333 -- $duo2 director start t --in-duo 2>&1); rc=$?
  if (( rc != 0 )) && [[ $o == *"--in-duo needs Duo running"* ]]; then ok "Duo closed: --in-duo is refused"; else bad "offline start --in-duo: rc=$rc ${o[1,160]}"; fi

  rm -rf $tmp
done

# == duties: the red lines `duo2 director status` opens with (DL-319), each proved with the real binary on a
# fixture built by hand: no model, no network, no Duo. R8's Duo lines (a Duo running but unreachable, hot, not
# checking for updates) can't fire in this context (Duo's process and update-check facts are never read in a test
# context), so DuoChecks proves those. Dates come from `date`, so every fixture stays relative to now.
if (( run_duties )); then
  print "== duties"
  prof=$h/profiles/current.json   # messaging: yes
  tmp=$(mktemp -d /tmp/dh-XXXX)
  cfg=$tmp/c proj=$tmp/p sup=$tmp/s app=$tmp/app sid=44444444-4444-4444-8444-444444444444
  mkdir -p $proj/tasks $sup $app
  print "# duties" > $proj/PROJECT.md
  python3 -I $h/profile.py setup $prof $cfg

  # The same isolation as the loop: scratch config and support folders, no endpoint, the Claude app's records
  # in a scratch folder, and a stop if the output isn't Duo-closed.
  unset DUO_SOCKET DUO_TOKEN DUO_SESSION_ID CLAUDE_CODE_MESSAGING_SOCKET CLAUDE_CODE_DISABLE_AGENT_VIEW CLAUDE_CODE_PROJECTS_SESSION
  export DUO_SUPPORT_DIR=$sup CLAUDE_CONFIG_DIR=$cfg STUB_PROFILE=$prof DUO_CLAUDE_APP_DIR=$app
  if [[ $DUO_SUPPORT_DIR != $tmp/s ]]; then print "  ✘ isolation: DUO_SUPPORT_DIR is not the scratch folder"; exit 2; fi

  # `duo2 director <args>` from the project, as the session director-x.
  dd()    { (cd $proj && $stub --as-session -n director-x --session-id $sid -- $duo2 director "$@" 2>&1) }
  # An empty project again, with director-x recorded as its director (what `check` needs).
  fresh() { rm -rf $proj/tasks $proj/.duo $cfg/projects $app/claude-code-sessions; mkdir -p $proj/tasks $cfg/projects/x; dd start --take-over > /dev/null }
  # Times, relative to now: a note's date, its minute, a local ISO time (check_by), UTC (a transcript, the log).
  tday()  { date -v-$1 +%Y-%m-%d }
  tmin()  { date -v-$1 '+%Y-%m-%d %H:%M' }
  tloc()  { date -v$1 +%Y-%m-%dT%H:%M:%S }
  tutc()  { date -u -v-$1 +%Y-%m-%dT%H:%M:%SZ }
  msago() { print $(( ($(date +%s) - $1) * 1000 )) }
  # A note director-x directs: note <slug> <status> <progress line…>; $nx holds extra frontmatter lines.
  note() {
    local slug=$1 st=$2 l; shift 2
    { print -r -- "---"; print -r -- "title: $slug"; print -r -- "status: $st"; print -r -- "directed_by: \"director-x\""
      [[ -n ${nx:-} ]] && print -r -- "$nx"
      print -r -- "---"; print -r -- "# $slug"; print; print "## Request"; print; print "Do the work."; print; print "## Progress"; print
      for l in "$@"; do print -r -- "- $l"; done } > $proj/tasks/$slug.md
  }
  # A registry worker for a task, with a session id no live session has (so it reads as stopped), started $3 hours ago.
  worker() {
    python3 -I - $proj/.duo/director.json $1 $2 $3 <<'PY'
import json, sys, datetime
f, task, sess, hours = sys.argv[1], sys.argv[2], sys.argv[3], float(sys.argv[4])
r = json.load(open(f))
since = (datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(hours=hours)).strftime("%Y-%m-%dT%H:%M:%SZ")
r.setdefault("workers", []).append({"task": task, "session": sess, "since": since, "adopted": False, "name": "w-abc123"})
json.dump(r, open(f, "w"))
PY
  }
  # An event line in the director's log.
  logev() { print -r -- "{\"at\":\"$(tutc $1)\",\"director\":\"director-x\",\"event\":\"$2\",\"task\":\"$3\",\"detail\":\"x\"${4:+,\"routine\":true}}" >> $proj/.duo/director-log.jsonl }
  # Everything a verb might change, as one hash.
  snap()  { cat $proj/tasks/*.md $proj/.duo/director.json $proj/.duo/director-log.jsonl 2>/dev/null | shasum | cut -c1-40 }
  nred()  { print -r -- "$1" | grep -c "^  RED $2 "; }
  has()   { if [[ $2 == *"$3"* ]]; then ok "$1"; else bad "$1: no '$3' in: ${2[1,500]}"; fi }
  lacks() { if [[ $2 != *"$3"* ]]; then ok "$1"; else bad "$1: found '$3' in: ${2[1,500]}"; fi }
  # check_by of a note, as seconds from now (python reads the local ISO time as local, so a DST change doesn't shift it).
  byin()  { python3 -I -c '
import re, sys, datetime
m = re.search(r"^check_by:\s*(\S+)", open(sys.argv[1]).read(), re.M)
print(int((datetime.datetime.fromisoformat(m.group(1)).astimezone() - datetime.datetime.now().astimezone()).total_seconds()) if m else "none")' $proj/tasks/$1.md }
  tasksha() { cat $proj/tasks/*.md | shasum | cut -c1-40 }

  # 1. An empty project.
  fresh
  o=$(dd status)
  if [[ $o != *"Duo isn't running"* ]]; then print "  ✘ isolation: output lacks \"Duo isn't running\" (is a Duo reachable?); stopping"; print -r -- $o; exit 2; fi
  if [[ ${o%%$'\n'*} == "Red lines: none." ]]; then ok "an empty project prints Red lines: none. first"; else bad "empty project: ${o[1,300]}"; fi
  if [[ -s $cfg/stub-auth-status ]]; then ok "the login probe reached the stub, not a real CLI"; else bad "the login probe didn't reach the stub: claude is $(command -v claude)"; fi

  # 2. R1: a worker that stopped with nothing checked since.
  fresh
  note stopped in-progress "$(tmin 4H) Worker started."
  worker tasks/stopped.md 11111111-1111-4111-8111-111111111111 4
  o=$(dd status)
  has "R1: a registry worker with no live session, nothing checked: RED R1 tasks/stopped.md" $o "  RED R1 tasks/stopped.md: Its worker stopped 4 h ago"
  has "R1: it opens status, counted" ${o%%$'\n'*} "Red lines (1)"

  # 3. R2: a check_by in the past, and one in the future.
  fresh
  nx="check_by: $(tloc -50H)" note late in-progress "$(tday 2d) Told the user the build starts today."
  nx="check_by: $(tloc +1d)" note soon in-progress "$(tday 0d) Looking tomorrow."
  o=$(dd status)
  has "R2: a check_by two days past: RED R2" $o "  RED R2 tasks/late.md: Its check_by passed 2 d ago"
  lacks "R2: a check_by tomorrow gives no line for that note" $o "tasks/soon.md"
  # A live note with no worker and no next look, untouched for two hours: with others like it, one line.
  fresh
  for i in 1 2; do note orphan$i in-progress "$(tday 1d) Filed."; touch -t $(date -v-2H +%Y%m%d%H%M) $proj/tasks/orphan$i.md; done
  o=$(dd status)
  has "R2: two live notes with no worker and no check_by: RED R2 live notes, counted" $o "  RED R2 live notes: 2 notes are marked live with no worker and no check_by: tasks/orphan1.md, tasks/orphan2.md."
  n=$(nred $o R2)
  if (( n == 1 )); then ok "R2: and they are one line, not one each"; else bad "R2: $n RED R2 lines for two unowned notes: ${o[1,400]}"; fi

  # 4. R3: a scheduled run for this project that started in Default and never finished a turn.
  fresh
  jobs=$app/claude-code-sessions/a/b; mkdir -p $jobs $tmp/elsewhere
  print -r -- "{\"scheduledTasks\":[{\"id\":\"nightly-audit\",\"displayName\":\"Nightly audit\",\"enabled\":true,\"cwd\":\"$proj\"},{\"id\":\"other-job\",\"displayName\":\"Other\",\"enabled\":true,\"cwd\":\"$tmp/elsewhere\"}]}" > $jobs/scheduled-tasks.json
  print -r -- "{\"sessionId\":\"local_a1\",\"scheduledTaskId\":\"nightly-audit\",\"createdAt\":$(msago 5400),\"lastActivityAt\":$(msago 3600),\"permissionMode\":\"default\",\"isArchived\":false}" > $jobs/local_a1.json
  print -r -- "{\"sessionId\":\"local_b1\",\"scheduledTaskId\":\"other-job\",\"createdAt\":$(msago 5400),\"lastActivityAt\":$(msago 3600),\"permissionMode\":\"default\",\"isArchived\":false}" > $jobs/local_b1.json
  o=$(dd status)
  has "R3: a stuck run of this project's job: RED R3 naming the job" $o "  RED R3 nightly-audit: Its run started"
  has "R3: it says the run started in default" $o "in default, with no activity for 60 min"
  lacks "R3: a job in another folder isn't named" $o "other-job"
  print '{ this is not json' > $jobs/scheduled-tasks.json
  o=$(dd status)
  has "R3: a corrupt scheduled-tasks.json: Can't read scheduled runs" $o "Can't read scheduled runs"
  lacks "R3: and it names the file, never the folder's path" $o "$app"
  rm -rf $app/claude-code-sessions
  o=$(dd status)
  lacks "R3: no folder, no scheduled-run line (no jobs is not blind)" $o "Can't read scheduled runs"
  lacks "R3: and no R3 line" $o "RED R3"

  # 5. R4 and R7: a check recorded after the director's last word, and a turn 40 minutes old with no word.
  fresh
  print -r -- "{\"type\":\"user\",\"timestamp\":\"$(tutc 40M)\",\"message\":{\"role\":\"user\",\"content\":\"A worker went idle.\"}}
{\"type\":\"assistant\",\"timestamp\":\"$(tutc 40M)\",\"message\":{\"role\":\"assistant\",\"content\":[{\"type\":\"text\",\"text\":\"Looking.\"}]}}" > $cfg/projects/x/$sid.jsonl
  logev 10M check tasks/found.md
  o=$(dd status)
  has "R4: a non-routine check newer than the last word to the user: RED R4" $o "  RED R4 tasks/found.md: You recorded a check 10 min ago"
  has "R7: a turn 40 minutes old with no word: RED R7" $o "  RED R7 this turn: You've gone 40 min without a word"
  rm $proj/.duo/director-log.jsonl; logev 10M check tasks/found.md routine
  o=$(dd status)
  lacks "R4: a routine check in its place gives no R4" $o "RED R4"
  has "R7: and R7 stands" $o "RED R7"

  # 6. R5: twelve notes at review are one line, however the rest of their facts look.
  fresh
  for i in {01..12}; do
    if (( i <= 4 )); then nx="check_by: $(tloc -2d)"; else nx=""; fi
    note rv$i review "$(tday 30d) Worker started." "$(tday 30d) Worker reported done."
    if (( i >= 5 && i <= 8 )); then worker tasks/rv$i.md 222222$i-2222-4222-8222-222222222222 40; fi
  done
  nx=""
  o=$(dd status)
  n=$(nred $o R5)
  if (( n == 1 )); then ok "R5: twelve notes at review give exactly one RED R5 line"; else bad "R5: $n RED R5 lines: ${o[1,500]}"; fi
  has "R5: and it counts them: 12" $o "RED R5 review: 12 notes wait at review"
  if print -r -- $o | grep "RED R[126] " | grep -q "rv[0-9]"; then bad "R5: a review note also got an R1, R2 or R6 line: $(print -r -- $o | grep 'RED R[126] ' | head -3)"; else ok "R5: no R1, R2 or R6 line for any of them (check_by, a worker and age notwithstanding)"; fi

  # 7. R6: eight stale live notes are one line, and a status word Duo doesn't know is another.
  fresh
  for i in {1..8}; do note st$i in-progress "$(tday 30d) Worker started."; done
  o=$(dd status)
  n=$(nred $o R6)
  if (( n == 1 )); then ok "R6: eight in-progress notes with Progress 30 days old and no check_by: exactly one RED R6 line"; else bad "R6: $n RED R6 lines: ${o[1,500]}"; fi
  has "R6: it counts them: 8" $o "RED R6 the record: 8 notes marked live"
  has "R6: it names five and the rest as a count" $o "tasks/st5.md and 3 more (--all lists them)"
  lacks "R6: not the sixth" $o "tasks/st6.md"
  has "R6: --all names all eight" "$(dd status --all)" "tasks/st8.md"
  note odd building "$(tday 0d) Started."
  o=$(dd status)
  has "R6: a note with status building gets the status-word line" $o "  RED R6 the record: 1 note uses a status word Duo doesn't know: tasks/odd.md (building)"

  # 8. R8: bypass mode, from the transcript.
  fresh
  print -r -- "{\"type\":\"permission-mode\",\"permissionMode\":\"bypassPermissions\",\"sessionId\":\"$sid\"}" > $cfg/projects/x/$sid.jsonl
  o=$(dd status)
  has "R8: a transcript recording bypassPermissions: RED R8 your mode" $o "  RED R8 your mode: This session runs in bypass"
  print -r -- "{\"type\":\"permission-mode\",\"permissionMode\":\"auto\",\"sessionId\":\"$sid\"}" >> $cfg/projects/x/$sid.jsonl
  lacks "R8: Auto, the last mode recorded, is fine" "$(dd status)" "RED R8"

  # 9. R9: three sends to one task in an hour, and no check after them.
  fresh
  nx="check_by: $(tloc +1d)" note sendy in-progress "$(tday 0d) Worker started."
  logev 50M send tasks/sendy.md; logev 30M send tasks/sendy.md; logev 10M send tasks/sendy.md
  o=$(dd status)
  has "R9: three sends to one task in the last hour: RED R9" $o "  RED R9 tasks/sendy.md: You've sent to this worker 3 times"
  logev 5M check tasks/sendy.md
  lacks "R9: a check after the first send clears it" "$(dd status)" "RED R9"

  # 10. A note whose file name starts with _ is a record, never a task.
  fresh
  note _notes in-progress "$(tday 30d) Kept for reference."
  note twin in-progress "$(tday 30d) Kept for reference."
  o=$(dd status); oa=$(dd status --all)
  has "_ notes: the same note without the underscore is named (the control)" $o "tasks/twin.md"
  lacks "_ notes: tasks/_notes.md (directed, in-progress) never appears" $o "_notes"
  lacks "_ notes: nor with --all" $oa "_notes"

  # 11. The task list shrinks to running and waiting workers; the red lines still name the rest.
  fresh
  note gone in-progress "$(tmin 4H) Worker started."
  worker tasks/gone.md 11111111-1111-4111-8111-111111111111 4
  o=$(dd status); oa=$(dd status --all)
  lacks "list: a stopped worker's note isn't in the list" $o $'\n  tasks/gone.md  '
  has "list: the list says how many it left out" $o "and 1 other task (--all lists them)."
  has "list: --all lists it" $oa $'\n  tasks/gone.md  gone (in-progress)  stopped'
  has "list: the red lines still name it (without --all)" $o "RED R1 tasks/gone.md"
  has "list: and with --all" $oa "RED R1 tasks/gone.md"

  # 12. duo2 director check, with Duo closed.
  fresh
  nx="check_by: $(tloc -1d)" note a in-progress "$(tmin 4H) Worker started."
  worker tasks/a.md 11111111-1111-4111-8111-111111111111 4
  nx="check_by: $(tloc -1d)" note b in-progress "$(tday 0d) Said the draft would be ready."
  nx="check_by: $(tloc +1d)" note c in-progress "$(tday 0d) Waiting."
  o=$(dd status)
  has "check: before it, R1 for the stopped worker's note" $o "RED R1 tasks/a.md"
  has "check: before it, R2 for the note past its check_by" $o "RED R2 tasks/b.md"
  o=$(dd check tasks/a.md "read the report" --next 2d); rc=$?
  if (( rc == 0 )) && [[ $o == "Checked tasks/a.md. Next look by "* ]]; then ok "check: a note, evidence and --next 2d: the verb says when the next look is"; else bad "check a: rc=$rc ${o[1,200]}"; fi
  if awk '/^## Progress/{p=1} p && /^- [0-9-]+ [0-9:]+ Checked: read the report$/{f=1} END{exit !f}' $proj/tasks/a.md; then ok "check: a dated Checked: line is appended under ## Progress"; else bad "check: no Checked: line in $(tail -4 $proj/tasks/a.md)"; fi
  by=$(byin a)
  if [[ $by == <-> ]] && (( by > 2*86400 - 120 && by < 2*86400 + 120 )); then ok "check: check_by is set to two days on"; else bad "check: check_by is $by s from now, want about 172800"; fi
  if python3 -I -c '
import json, sys
ev = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
c = [e for e in ev if e["event"] == "check"]
sys.exit(0 if len(c) == 1 and c[0]["task"] == "tasks/a.md" and c[0]["detail"] == "read the report" and not c[0].get("routine") and c[0]["director"] == "director-x" else 1)' $proj/.duo/director-log.jsonl; then ok "check: one check event is logged, with the task and the evidence"; else bad "check: log is $(tail -2 $proj/.duo/director-log.jsonl)"; fi
  o=$(dd status)
  lacks "check: it clears that note's R1 line" $o "RED R1 tasks/a.md"
  lacks "check: and it left no R2 line for it" $o "RED R2 tasks/a.md"
  has "check: the other note's R2 is still there" $o "RED R2 tasks/b.md"
  dd check tasks/b.md "looked: the draft is half done" --next 3d > /dev/null
  lacks "check: a check clears R2 (check_by moved on)" "$(dd status)" "RED R2 tasks/b.md"
  before=$(snap)
  o=$(dd check tasks/c.md); rc=$?
  if (( rc != 0 )) && [[ $(snap) == $before ]]; then ok "check: no evidence exits non-zero and changes nothing"; else bad "check with no evidence: rc=$rc ${o[1,200]}"; fi
  o=$(dd check tasks/c.md ""); rc=$?
  if (( rc != 0 )) && [[ $(snap) == $before ]]; then ok "check: empty evidence exits non-zero and changes nothing"; else bad "check with empty evidence: rc=$rc ${o[1,200]}"; fi
  o=$(dd check tasks/c.md "looked" --next soon); rc=$?
  if (( rc != 0 )) && [[ $o == *"--next takes"* && $(snap) == $before ]]; then ok "check: a bad --next exits non-zero, says what it takes, and changes nothing"; else bad "check with --next soon: rc=$rc ${o[1,200]}"; fi
  o=$(dd check tasks/none.md "looked"); rc=$?
  if (( rc != 0 )) && [[ $(snap) == $before ]]; then ok "check: a task that doesn't exist exits non-zero and changes nothing"; else bad "check of a missing task: rc=$rc ${o[1,200]}"; fi
  o=$(dd check tasks/c.md "nothing changed" --next none); rc=$?
  if (( rc == 0 )) && [[ $(byin c) == none && $o == *"No next look set."* ]]; then ok "check: --next none clears check_by"; else bad "check --next none: rc=$rc by=$(byin c) ${o[1,200]}"; fi
  # A job: no note, a log line.
  jobs=$app/claude-code-sessions/a/b; mkdir -p $jobs
  print -r -- "{\"scheduledTasks\":[{\"id\":\"daily\",\"displayName\":\"Daily\",\"enabled\":true,\"cwd\":\"$proj\"}]}" > $jobs/scheduled-tasks.json
  print -r -- "{\"sessionId\":\"local_d1\",\"scheduledTaskId\":\"daily\",\"createdAt\":$(msago 10800),\"lastActivityAt\":$(msago 7200),\"permissionMode\":\"auto\",\"completedTurns\":3,\"isArchived\":false}" > $jobs/local_d1.json
  has "check: a finished run nobody read: RED R3 for the job" "$(dd status)" "RED R3 daily: Its run finished 2 h ago"
  notes=$(tasksha)
  o=$(dd check job:daily "nothing new" --routine); rc=$?
  if (( rc == 0 )) && [[ $o == "Checked job:daily. No next look set."* && $(tasksha) == $notes ]]; then ok "check: job:<id> --routine changes no note"; else bad "check job: rc=$rc ${o[1,200]}"; fi
  if python3 -I -c '
import json, sys
ev = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
c = [e for e in ev if e["event"] == "check" and e.get("task") == "job:daily"]
sys.exit(0 if len(c) == 1 and c[0].get("routine") is True and c[0]["detail"] == "nothing new" else 1)' $proj/.duo/director-log.jsonl; then ok "check: and logs it with routine true"; else bad "check job log: $(tail -2 $proj/.duo/director-log.jsonl)"; fi
  lacks "check: and clears the job's finished-run line" "$(dd status)" "RED R3 daily"

  # 13. director start sets a next look, except for a suggestion.
  fresh
  o=$(dd start --no-worker --title "Plan the move" --request "Please plan the move."); rc=$?
  by=$(byin plan-the-move)
  if (( rc == 0 )) && [[ $by == <-> ]] && (( by > 2*3600 - 120 && by < 2*3600 + 120 )); then ok "start: --no-worker writes check_by two hours on"; else bad "start --no-worker: rc=$rc check_by=$by ${o[1,200]}"; fi
  o=$(dd start --suggest --title "Maybe later" --request "Think about it."); rc=$?
  if (( rc == 0 )) && [[ $(byin maybe-later) == none && $(grep -c '^status: suggested' $proj/tasks/maybe-later.md) == 1 ]]; then ok "start: --suggest writes no check_by"; else bad "start --suggest: rc=$rc check_by=$(byin maybe-later) ${o[1,200]}"; fi

  # 14. The nudge: a verb that worked ends by saying how many red lines are open.
  fresh
  note a in-progress "$(tmin 4H) Worker started."
  worker tasks/a.md 11111111-1111-4111-8111-111111111111 4
  nx="check_by: $(tloc +1d)" note b in-progress "$(tday 0d) Waiting."
  o=$(dd check tasks/b.md "looked, still waiting" --next 1d)
  if [[ ${o##*$'\n'} == "1 red line: run duo2 director status." ]]; then ok "nudge: with a red line open, check ends 1 red line: run duo2 director status."; else bad "nudge with a red line: ${o[1,300]}"; fi
  o=$(dd check tasks/a.md "read the worker's report" --next 1d)
  lacks "nudge: with none open, it doesn't" $o "red line"

  # 15. Speed: status over 100 notes, 25 of them with a stopped worker, 25 at review, 25 stale, a job and a transcript.
  fresh
  python3 -I - $proj $cfg $sid <<'PY'
import json, sys, os, datetime
proj, cfg, sid = sys.argv[1:4]
now = datetime.datetime.now()
def day(n): return (now - datetime.timedelta(days=n)).strftime("%Y-%m-%d")
reg = json.load(open(proj + "/.duo/director.json"))
for i in range(100):
    kind = i % 4
    status = ["in-progress", "review", "in-progress", "done"][kind]
    prog = [day(0), day(30), day(30), day(1)][kind]
    with open("%s/tasks/n%03d.md" % (proj, i), "w") as f:
        f.write('---\ntitle: n%03d\nstatus: %s\ndirected_by: "director-x"\n---\n# n%03d\n\n## Request\n\nDo it.\n\n## Progress\n\n- %s Worker started.\n' % (i, status, i, prog))
    if kind == 0:
        since = (datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(hours=5)).strftime("%Y-%m-%dT%H:%M:%SZ")
        reg["workers"].append({"task": "tasks/n%03d.md" % i, "session": "5555%04d-5555-4555-8555-555555555555" % i, "since": since, "adopted": False, "name": "w-%d" % i})
json.dump(reg, open(proj + "/.duo/director.json", "w"))
PY
  t0=$EPOCHREALTIME
  o=$(dd status)
  t1=$EPOCHREALTIME
  took=$(( t1 - t0 ))
  printf '  · status over 100 notes took %.2f s (%s red lines)\n' $took "$(print -r -- $o | grep -c '^  RED ')"
  if (( took > 2 )); then bad "speed: status over 100 notes took $took s, over the 2 s limit"; else ok "speed: status over 100 notes is under 2 s"; fi

  # 16. Claude's shell sandbox denies the system's temporary items folder, where Foundation's .atomic stages a
  # write, so every director write used to fail there (F-621). The same denial, no model needed.
  fresh
  note sandboxed in-progress "$(tmin 4H) Worker started."
  o=$(cd $proj && sandbox-exec -p '(version 1)(allow default)(deny file-write* (subpath "/private/var/folders"))' \
    $stub --as-session -n director-x --session-id $sid -- $duo2 director check tasks/sandboxed.md "read it under the sandbox" --next 2d 2>&1); rc=$?
  if (( rc == 0 )) && grep -q "Checked: read it under the sandbox" $proj/tasks/sandboxed.md && grep -q "^check_by: " $proj/tasks/sandboxed.md; then
    ok "a write under Claude's shell sandbox works (F-621)"
  else bad "write under the sandbox: rc=$rc ${o[1,300]}"; fi
  lacks "and leaves no temporary file behind" "$(ls -A $proj/tasks)" ".tmp"

  unset DUO_CLAUDE_APP_DIR
  rm -rf $tmp
fi

print
print "$pass passed, $fail failed"
(( fail == 0 ))
