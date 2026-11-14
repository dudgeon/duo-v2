#!/bin/sh
# S33 (R9): the user complains that a task the director called ready isn't, for the second time. The note sits at
# review and its Progress says the director told the user it was ready. PROJECT.md has no Director section.
lib=$(dirname "$0")/../_lib; . "$lib/setup.sh"; . "$lib/fixtures.sh"
printf -- '---\ntitle: Reports app\ngoal: a reports page people can export\n---\n# Reports app\n' > PROJECT.md
mkdir -p tasks
printf '<!doctype html>\n<html><body>\n<h1>Reports</h1>\n<table id="report"><tr><th>Name</th><th>Total</th></tr><tr><td>Ana</td><td>12</td></tr></table>\n<button id="export">Export</button>\n</body></html>\n' > index.html
task_note export-button "Export button" review 'sessions:
  - "[worker](duo2://session/11111111-1111-4111-8111-111111111111)"
done_when: clicking Export downloads the report as report.csv' \
  'Add an Export button to the reports page that downloads the report as report.csv.' \
  "$(ago $((3 * D)) '%Y-%m-%d %H:%M') Worker started." \
  "$(ago $((2 * D)) '%Y-%m-%d %H:%M') Worker reported done: the export button is in and downloads report.csv." \
  "$(ago $((2 * D)) '%Y-%m-%d %H:%M') Told the user it was ready."
registry_worker tasks/export-button.md 11111111-1111-4111-8111-111111111111 72
