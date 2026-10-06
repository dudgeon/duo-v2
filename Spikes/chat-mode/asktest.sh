#!/bin/zsh
# Runs asktest.mjs against the mock at several terminal sizes (F-106). Each size is a fresh session.
here=${0:A:h}; cd $here
for size in "100 34" "60 34" "80 20"; do
  set -- ${=size}
  rm -rf scratch
  SERVER_ARGS="--cols $1 --rows $2" ./start.sh > /tmp/duo-asktest-server.log 2>&1 &
  sleep 4
  echo "== ${1}x${2}"
  node asktest.mjs | tail -14
  pkill -TERM -f "server.mjs --cwd $here/scratch"; pkill -f "node mock.mjs"; sleep 1.5
done
