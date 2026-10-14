#!/bin/sh
# A documents project with no git: three notes and a thin PROJECT.md.
lib=$(dirname "$0")/../_lib; . "$lib/setup.sh"
mkdir -p notes tasks
printf -- '---\ntitle: Pricing review\ngoal: a pricing recommendation for Q4\n---\n# Pricing review\n' > PROJECT.md
printf '# Call with Sam\n\n- Sam thinks per-seat pricing scares small teams.\n- Wants a free tier capped at 3 seats.\n' > notes/sam-call.md
printf '# Competitor scan\n\n- Two competitors moved to usage pricing this year.\n- One kept per-seat and lost share.\n' > notes/competitors.md
printf '# Finance constraints\n\n- Gross margin must stay above 70%%.\n- No price change before 1 November.\n' > notes/finance.md
