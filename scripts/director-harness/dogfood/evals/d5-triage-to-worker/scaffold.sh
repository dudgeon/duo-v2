#!/bin/sh
# D5: "have an agent … triage" must go to a worker Geoff can open, not a subagent (director-regression,
# S1). The fixture's Director section carries the real PROJECT.md's worker line.
lib=$(dirname "$0")/../_lib; . "$lib/setup.sh"
console_real
