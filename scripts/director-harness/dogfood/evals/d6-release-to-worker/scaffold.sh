#!/bin/sh
# D6: "ship it" is a release worker's job, not the director's own (director-regression, S2).
lib=$(dirname "$0")/../_lib; . "$lib/setup.sh"
console_real
release_rules
