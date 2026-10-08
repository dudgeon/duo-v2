#!/bin/bash
# Builds an isolated GitHub test setup for DL-149/DL-157 under <dir> (default /tmp/d-gh), touching
# nothing real: no network, no GitHub account, no token.
#   scripts/github-fixture.sh [dir] [READ|WRITE] [signed-in|signed-out|no-gh]
# Makes:
#   <dir>/upstream.git, <dir>/fork.git   bare repos standing in for github.com/acme/website and tester/website
#   <dir>/gitconfig                      git's global config: a user, and url.insteadOf mapping those URLs to the bare repos
#   <dir>/gh                             a stub gh (logs to <dir>/gh.log), signed in as "tester" with the given access
#   <dir>/ws                             a workspace: HOME.md, website/pricing-copy (a copy on a new branch, with changes)
#                                        and docs-in-repo/notes (a project inside a bigger repo Duo didn't copy, DL-157)
#   <dir>/env                            KEY=value lines for DUO_EXTRA_ENV (scripts/run-live.sh)
# The main branch of upstream refuses pushes (GH006) once the seed is in, like a protected branch.
set -euo pipefail
dir=${1:-/tmp/d-gh}
perm=${2:-WRITE}
auth=${3:-signed-in}
rm -rf "$dir"; mkdir -p "$dir/sup" "$dir/claude" "$dir/ws"
export GIT_CONFIG_GLOBAL="$dir/gitconfig" GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0
cat > "$GIT_CONFIG_GLOBAL" <<EOF
[user]
	name = Tester
	email = tester@example.com
[init]
	defaultBranch = main
[url "$dir/upstream.git"]
	insteadOf = https://github.com/acme/website.git
[url "$dir/fork.git"]
	insteadOf = https://github.com/tester/website.git
EOF
git init -q --bare "$dir/upstream.git"; git init -q --bare "$dir/fork.git"
git clone -q "$dir/upstream.git" "$dir/seed" 2>/dev/null
cd "$dir/seed"
mkdir -p content; printf '# Pricing\n\nPay for what you use.\n' > content/pricing.md; printf 'Q: Annual?\nA: Yes.\n' > content/faq.md
printf '# website\n' > README.md
git add . && git commit -qm "Initial site" && git push -q origin main
cat > "$dir/upstream.git/hooks/pre-receive" <<'EOF'
#!/bin/sh
while read o n r; do
  if [ "$r" = refs/heads/main ]; then
    echo "error: GH006: Protected branch update failed for refs/heads/main." >&2
    echo "error: Changes must be made through a pull request." >&2
    exit 1
  fi
done
EOF
chmod +x "$dir/upstream.git/hooks/pre-receive"

# Home and a project that is a copy of acme/website on its own branch, with changes.
printf -- '---\ntype: home\ntitle: Home\n---\n# Home\n' > "$dir/ws/HOME.md"
git clone -q https://github.com/acme/website.git "$dir/ws/website/pricing-copy"
cd "$dir/ws/website/pricing-copy"
git switch -q -c tester/pricing-copy
printf -- '---\ntype: project\ntitle: Pricing copy\ngoal: New pricing page copy, approved by marketing\n---\n# Pricing copy\n' > PROJECT.md
printf '/PROJECT.md\n.duo/\n' >> .git/info/exclude
printf '# Pricing\n\nPay for what you ship.\n' > content/pricing.md
printf 'Q: Annual?\nA: Yes, with two months free.\n' > content/faq.md
printf '{"plans": ["Free", "Team"]}\n' > content/plans.json

# A project inside a bigger repo that Duo didn't copy (DL-157), with an untracked PROJECT.md.
mkdir -p "$dir/ws/docs-in-repo/notes"
cd "$dir/ws/docs-in-repo"; git init -q; printf 'x\n' > top.txt; git add . && git commit -qm init
printf -- '---\ntype: project\ntitle: Notes\n---\n# Notes\n' > notes/PROJECT.md
printf 'a\n' > notes/a.md

# A stub gh.
login='"tester"'; [ "$auth" = signed-out ] && login=''
cat > "$dir/gh" <<EOF
#!/bin/sh
echo "\$*" >> "$dir/gh.log"
case "\$1 \$2" in
  "auth status") if [ -n '$login' ]; then echo '{"hosts":{"github.com":[{"state":"success","active":true,"host":"github.com","login":$login}]}}'; else echo '{"hosts":{}}'; fi ;;
  "repo view") echo '{"viewerPermission":"$perm","visibility":"PRIVATE","defaultBranchRef":{"name":"main"},"isFork":false,"parent":null}' ;;
  "api repos/acme/website/branches/main") echo 'true' ;;
  "api repos/acme/website/rules/branches/main") echo '' ;;
  "repo fork") git remote add fork https://github.com/tester/website.git ;;
  "pr list") echo '[]' ;;
  "pr create") echo 'https://github.com/acme/website/pull/482' ;;
  "auth login") echo 'stub: would open the browser' ;;
  *) echo "stub gh: \$*" >&2; exit 1 ;;
esac
EOF
chmod +x "$dir/gh"
ghpath="$dir/gh"; [ "$auth" = no-gh ] && ghpath=none
cat > "$dir/env" <<EOF
DUO_SUPPORT_DIR=$dir/sup CLAUDE_CONFIG_DIR=$dir/claude GIT_CONFIG_GLOBAL=$dir/gitconfig GIT_CONFIG_NOSYSTEM=1 DUO_GH_PATH=$ghpath DUO_REPO_FETCH=1
EOF
echo "made $dir (access $perm, gh $auth)"
