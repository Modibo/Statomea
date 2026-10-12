#!/usr/bin/env bash
# Publication de la version web (depuis le Mac) : construit l'application Flutter et met à jour la branche « web »
# (site/ + fichiers de déploiement), puis la pousse. Sur le VPS : cd /opt/statomea && git pull && bash install.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="$HOME/development/flutter/bin:$PATH"
if [ "${SKIP_BUILD:-0}" != "1" ]; then
  (cd "$ROOT/app/statomea" && flutter build web --release --no-web-resources-cdn)
fi
VERSION=$(grep -o '"version":"[^"]*"' "$ROOT/app/statomea/build/web/version.json" | cut -d'"' -f4)
WT=$(mktemp -d)
cd "$ROOT"
git fetch -q origin web 2>/dev/null || true
if git rev-parse -q --verify origin/web >/dev/null; then
  git worktree add -q -B web "$WT" origin/web
else
  git worktree add -q --orphan -b web "$WT" 2>/dev/null || { git worktree add -q --detach "$WT"; (cd "$WT" && git checkout -q --orphan web && git rm -rfq .); }
fi
rsync -a --delete --exclude '*.symbols' "$ROOT/app/statomea/build/web/" "$WT/site/"
cp "$ROOT/deploy/docker-compose.yml" "$ROOT/deploy/Caddyfile.static" "$ROOT/deploy/caddy-site.conf" "$ROOT/deploy/install.sh" "$WT/"
cat > "$WT/README.md" <<MD
# Statoméa — version web $VERSION (branche de déploiement)

Branche générée par \`deploy/publish-web.sh\` depuis \`main\` : ne pas modifier à la main.

Installation sur le VPS : \`git clone --branch web --single-branch https://github.com/Modibo/Statomea.git /opt/statomea && bash /opt/statomea/install.sh\`
Mise à jour : \`cd /opt/statomea && git pull && bash install.sh\`
MD
cd "$WT"
git add -A
if git diff --cached --quiet; then echo "Rien de nouveau à publier."; else git commit -q -m "Version web $VERSION"; fi
git push -q -u origin web
cd "$ROOT" && git worktree remove --force "$WT"
echo "Branche web publiée : version $VERSION"
