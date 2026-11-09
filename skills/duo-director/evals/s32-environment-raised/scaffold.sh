#!/bin/sh
# S32 (R8): the installed director skill is newer than this Duo (revision 99): this Duo lacks verbs the skill
# names. The wrapper points CLAUDE_CONFIG_DIR at .claude-config, where Installer.directorSkillFile
# (<config>/skills/director/SKILL.md) holds a skill whose header says revision 99. Status opens with RED R8.
lib=$(dirname "$0")/../_lib; . "$lib/setup.sh"; . "$lib/fixtures.sh"
wrap_duo2 CLAUDE_CONFIG_DIR=.claude-config
mkdir -p .claude-config/skills/director
cat > .claude-config/skills/director/SKILL.md <<'EOF'
---
name: director
description: Direct work in a Duo project.
---

<!-- Written by the Duo app (director, format 1, revision 99). Duo rewrites this file each release unless you edit it. -->

# Director

(A newer skill than the Duo that is running.)
EOF
printf -- '---\ntitle: Site\ngoal: keep the site current\n---\n# Site\n' > PROJECT.md
mkdir -p tasks
task_note refresh-footer "Refresh the footer" in-progress "check_by: $(ago $((-1 * D)) '%Y-%m-%dT%H:%M:%S')" \
  'Update the footer year and the contact address in footer.html.' \
  "$(ago $((20 * 60)) '%Y-%m-%d %H:%M') Filed by director-cwd."
printf '<footer>(c) 2025 Acme, hello@acme.example</footer>\n' > footer.html
