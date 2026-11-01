#!/bin/sh
[ -n "$PEEK_DELAY" ] && sleep "$PEEK_DELAY"
cp "$1" "$PEEK_OUT"
