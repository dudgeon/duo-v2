#!/bin/sh
# S30 (R5, R6): twelve notes wait at review with nothing checked, and six live notes have had nothing for a
# month. Status opens with one RED R5 line and one RED R6 line, with counts.
lib=$(dirname "$0")/../_lib; . "$lib/setup.sh"; . "$lib/fixtures.sh"
printf -- '---\ntitle: Acme launch\ngoal: launch the new site in November\n---\n# Acme launch\n' > PROJECT.md
mkdir -p tasks
for t in faq press-kit pricing-page onboarding-email changelog logo-refresh help-center release-notes case-study newsletter status-page terms-update; do
  task_note "$t" "$t" review "" "Do the $t work." \
    "$(ago $((9 * D)) '%Y-%m-%d %H:%M') Worker started." \
    "$(ago $((8 * D)) '%Y-%m-%d %H:%M') Worker reported done."
done
for t in blog-redesign partner-list survey-analysis api-docs brand-audit webinar-plan; do
  task_note "$t" "$t" in-progress "" "Do the $t work." \
    "$(ago $((30 * D)) '%Y-%m-%d %H:%M') Worker started."
done
