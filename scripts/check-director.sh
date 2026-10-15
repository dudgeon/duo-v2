#!/bin/zsh
# Tier 1 of the duo-director test harness: for each profile, run `duo2 director status` from a stand-in
# Claude session and compare what it reports with the profile's expectations. No model, no network,
# no running Duo. See scripts/director-harness/README.md.
#   scripts/check-director.sh [profile-name…]
setopt local_options no_unset 2>/dev/null
root=${0:A:h:h}
h=$root/scripts/director-harness
duo2=$root/.build/debug/duo2
stub=$h/stub-claude

if [[ ! -x $duo2 ]]; then
  print "missing $duo2: run  swift build --product duo2  first"; exit 2
fi

fail=0 pass=0
ok()  { print "  ✔ $1"; pass=$((pass+1)); }
bad() { print "  ✘ $1"; fail=$((fail+1)); }

names=($@)
(( $#names )) || names=(${h}/profiles/*.json(:t:r))

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
  if [[ $g == $'---\nname: duo-director'* ]]; then ok "director guide starts with the skill front matter"; else bad "director guide: ${g[1,60]}"; fi

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
  o=$(cd $proj && $stub --as-session -n director-x --session-id 33333333-3333-4333-8333-333333333333 -- $duo2 director start t --background 2>&1); rc=$?
  if (( rc == 0 )) && [[ $o == *"claude --bg -n 't-"* ]] && python3 -I -c '
import json,sys
r=json.load(open(sys.argv[1]+"/.duo/director.json"))
w=r["workers"][0]
sys.exit(0 if r["current"]["name"]=="director-x" and w["task"]=="tasks/t.md" and w["session"]=="" and w["name"].startswith("t-") else 1)' $proj; then
    ok "Duo closed: start --background records a pending worker by name, and the director"
  else bad "offline start: rc=$rc ${o[1,200]}"; fi
  o=$(cd $proj && $stub --as-session -n director-x --session-id 33333333-3333-4333-8333-333333333333 -- $duo2 director start u --background 2>&1); rc=$?
  if (( rc != 0 )) && [[ $o == *"no directed_by"* ]]; then ok "Duo closed: the user's task (no directed_by:) is refused"; else bad "offline start of the user's task: rc=$rc ${o[1,160]}"; fi
  o=$(cd $proj && $stub --as-session -n director-x --session-id 33333333-3333-4333-8333-333333333333 -- $duo2 director start t 2>&1); rc=$?
  if (( rc != 0 )) && [[ $o == *"only"*"--background"* ]]; then ok "Duo closed: only --background starts"; else bad "offline start without --background: rc=$rc ${o[1,160]}"; fi

  rm -rf $tmp
done

print
print "$pass passed, $fail failed"
(( fail == 0 ))
