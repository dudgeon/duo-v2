#!/bin/sh
# D1: a worker's report holds a choice only Geoff can make; PROJECT.md routes decisions to the console
# (the real wording), which this case can't reach.
lib=$(dirname "$0")/../_lib; . "$lib/setup.sh"
console_real
task_with_choice
