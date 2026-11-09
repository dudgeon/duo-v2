#!/bin/sh
# Sourced by the duty cases' scaffolds (s25 to s33) after setup.sh, in the same sandboxed folder. Plain sh,
# and dates are epoch arithmetic, so the fixtures stay relative to now with BSD or GNU date.

# ago <seconds> <format>: now minus <seconds> in local time, as `date +<format>` writes it.
ago() { _t=$(( $(date +%s) - $1 )); date -r "$_t" "+$2" 2>/dev/null || date -d "@$_t" "+$2"; }
# agoz <seconds> <format>: the same in UTC.
agoz() { _t=$(( $(date +%s) - $1 )); date -u -r "$_t" "+$2" 2>/dev/null || date -u -d "@$_t" "+$2"; }
# agoms <seconds>: now minus <seconds> as milliseconds since 1970 (the Claude app's own records).
agoms() { echo $(( ($(date +%s) - $1) * 1000 )); }

# Seconds in an hour and a day, for the calls above.
H=3600
D=86400

# wrap_duo2 NAME=folder ...: after setup.sh, makes `duo2` export each NAME as <this folder>/<folder> and then
# run the real one. For a case that needs a private location: DUO_CLAUDE_APP_DIR (the Claude app's scheduled
# runs), CLAUDE_CONFIG_DIR (the installed director skill). The folder is found from the wrapper's own place,
# so it works with run-evals' relative `.director-bin` on PATH, and the sandbox only needs to read the folder.
wrap_duo2() {
  mv .director-bin/duo2 .director-bin/duo2.real
  {
    echo '#!/bin/sh'
    echo 'here=$(cd "$(dirname "$0")/.." && pwd)'
    for _kv in "$@"; do
      echo "export ${_kv%%=*}=\"\$here/${_kv#*=}\""
    done
    echo 'exec "$here/.director-bin/duo2.real" "$@"'
  } > .director-bin/duo2
  chmod +x .director-bin/duo2
}

# task_note <slug> <title> <status> <extra frontmatter lines or ""> <request> <progress lines…>
# Writes tasks/<slug>.md as director-cwd's own note (what the eval's director is called: the folder is `cwd`).
# Progress lines are given without the leading "- ".
task_note() {
  _slug=$1; _title=$2; _status=$3; _extra=$4; _request=$5; shift 5
  {
    echo '---'
    echo "title: $_title"
    echo "status: $_status"
    echo 'directed_by: director-cwd'
    [ -n "$_extra" ] && printf '%s\n' "$_extra"
    echo '---'
    echo "# $_title"
    echo
    echo '## Request'
    echo
    echo "$_request"
    echo
    echo '## Progress'
    echo
    for _l in "$@"; do echo "- $_l"; done
  } > "tasks/$_slug.md"
}

# registry_worker <task path> <session id> <hours ago it started> [<task path> <session id> <hours> ...]
# Writes .duo/director.json with these workers and no `current` entry: a `current` entry for another session id
# would make the caller read as a different director, and status would print no red lines.
registry_worker() {
  mkdir -p .duo
  {
    printf '{"schema":1,"workers":['
    _sep=''
    while [ $# -ge 3 ]; do
      printf '%s{"task":"%s","session":"%s","since":"%s","adopted":false,"name":"w-%s"}' "$_sep" "$1" "$2" "$(agoz $(( $3 * H )) '%Y-%m-%dT%H:%M:%SZ')" "$(echo "$2" | cut -c1-6)"
      _sep=','
      shift 3
    done
    printf ']}\n'
  } > .duo/director.json
}

# log_event <seconds ago> <event> <task> [routine]: one line in .duo/director-log.jsonl.
log_event() {
  mkdir -p .duo
  printf '{"at":"%s","director":"director-cwd","event":"%s","task":"%s","detail":"x"%s}\n' "$(agoz "$1" '%Y-%m-%dT%H:%M:%SZ')" "$2" "$3" "${4:+,\"routine\":true}" >> .duo/director-log.jsonl
}
