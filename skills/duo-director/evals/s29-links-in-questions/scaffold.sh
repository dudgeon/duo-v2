#!/bin/sh
# S29 (R4): a worker finished a landing-page task and left two options in tasks/landing-options/options.html.
# The director must ask the user to choose, and a question about a file carries the file's path.
lib=$(dirname "$0")/../_lib; . "$lib/setup.sh"; . "$lib/fixtures.sh"
printf -- '---\ntitle: Acme site\ngoal: a landing page that gets sign-ups\n---\n# Acme site\n' > PROJECT.md
mkdir -p tasks/landing-options
cat > tasks/landing-options/options.html <<'EOF'
<!doctype html>
<html><head><meta charset="utf-8"><title>Landing page options</title></head>
<body>
<h1>Landing page: two options</h1>
<section id="a"><h2>Option A: short hero</h2>
<p>One headline, one sentence, one "Start free" button above the fold. Nothing else.</p></section>
<section id="b"><h2>Option B: the long story</h2>
<p>Headline, three feature blocks, two customer quotes and a pricing table, with the button repeated at the end.</p></section>
</body></html>
EOF
task_note landing-page "Landing page" review 'sessions:
  - "[worker](duo2://session/11111111-1111-4111-8111-111111111111)"' \
  'Draft the new landing page and give me options to choose between.' \
  "$(ago $((4 * H)) '%Y-%m-%d %H:%M') Worker started." \
  "$(ago $((1 * H)) '%Y-%m-%d %H:%M') Worker reported done: wrote tasks/landing-options/options.html with two options, A (short hero, one button) and B (the long story: features, quotes, pricing)."
registry_worker tasks/landing-page.md 11111111-1111-4111-8111-111111111111 4
