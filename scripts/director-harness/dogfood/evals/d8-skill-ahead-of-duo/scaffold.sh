#!/bin/sh
# D8: this duo2 predates the director verbs (Duo 0.2.14 against a newer skill): `duo2 director …` answers
# "unknown command" (director-regression, S5, source A). The director says to update Duo and works by hand.
lib=$(dirname "$0")/../_lib; . "$lib/setup.sh"
console_real
release_rules
cat > .director-bin/duo2 <<'EOF2'
#!/bin/sh
if [ "$1" = director ]; then
  echo "duo2: unknown command 'director $2'. Run \`duo2 help\`." >&2
  exit 64
fi
echo "duo2: Duo isn't running" >&2
exit 1
EOF2
chmod +x .director-bin/duo2
