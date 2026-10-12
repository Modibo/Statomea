#!/usr/bin/env bash
# Publication de la version web (depuis le Mac) : construit l'application Flutter et met à jour la branche « web »
# (site/ + fichiers de déploiement), puis la pousse. Sur le VPS : cd /opt/statomea && git pull && bash install.sh
# BUILD_APK=1 : construit aussi l'APK Android de la même version (dans /tmp : Gradle échoue dans OneDrive), le publie
# sous site/telecharger/statomea.apk et écrit site/android.json, que l'application Android lit pour signaler la mise
# à jour. Sans BUILD_APK, l'APK et android.json déjà publiés sont conservés.
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
rsync -a --delete --exclude '*.symbols' --exclude 'telecharger/' --exclude 'android.json' "$ROOT/app/statomea/build/web/" "$WT/site/"
if [ "${BUILD_APK:-0}" = "1" ]; then
  B=/tmp/statomea_build
  mkdir -p "$B"
  rsync -a --delete --exclude build --exclude .dart_tool --exclude android/.gradle "$ROOT/app" "$ROOT/packages" "$B/"
  (cd "$B/app/statomea" && flutter build apk --release)
  mkdir -p "$WT/site/telecharger"
  cp "$B/app/statomea/build/app/outputs/flutter-apk/app-release.apk" "$WT/site/telecharger/statomea.apk"
  mkdir -p "$ROOT/dist" && cp "$WT/site/telecharger/statomea.apk" "$ROOT/dist/statomea-$VERSION.apk"
  printf '{"version":"%s","url":"telecharger/statomea.apk"}\n' "$VERSION" > "$WT/site/android.json"
  echo "APK $VERSION publié ($(du -h "$WT/site/telecharger/statomea.apk" | cut -f1))."
fi
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
