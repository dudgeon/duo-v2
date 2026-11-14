#!/bin/sh
# S26 (R2): the director told the user a build would start today; two days on, no worker exists and the note's
# check_by has passed. Status opens with RED R2 for it.
lib=$(dirname "$0")/../_lib; . "$lib/setup.sh"; . "$lib/fixtures.sh"
printf -- '---\ntitle: Export\ngoal: ship CSV export in the next release\n---\n# Export\n' > PROJECT.md
mkdir -p tasks
printf 'def rows():\n    return [("id", "name"), (1, "Ana"), (2, "Ben")]\n' > export.py
task_note build-csv-export "Build the CSV export" in-progress "check_by: $(ago $((2 * D)) '%Y-%m-%dT%H:%M:%S')
done_when: export.py writes rows() to out.csv" \
  'Add a CSV export to export.py: write rows() to out.csv.' \
  "$(ago $((3 * D)) '%Y-%m-%d %H:%M') Filed." \
  "$(ago $((2 * D)) '%Y-%m-%d %H:%M') Told the user the build would start today."
