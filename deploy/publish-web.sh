#!/usr/bin/env bash
# Publication de la version web (depuis le Mac) : construit l'application Flutter et met à jour la branche « web »
# (site/ + fichiers de déploiement), puis la pousse. Sur le VPS : cd /opt/statomea && git fetch -q && git reset -q --hard origin/web && bash install.sh
# BUILD_APK=1 : construit aussi l'APK Android de la même version (dans /tmp : Gradle échoue dans OneDrive), le publie
# sous site/telecharger/statomea.apk et écrit site/android.json, que l'application Android lit pour signaler la mise
# à jour. Sans BUILD_APK, l'APK et android.json déjà publiés sont conservés.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="$HOME/development/flutter/bin:$PATH"
if [ "${SKIP_BUILD:-0}" != "1" ]; then
  (cd "$ROOT/app/statomea" && flutter build web --release --no-web-resources-cdn --base-href /app/)
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
# Page d'accueil à la racine, application sous /app/ (APK et android.json conservés s'ils ne sont pas reconstruits).
mkdir -p "$WT/site/app"
rsync -a --delete --exclude 'app/' --exclude 'telecharger/' --exclude 'android.json' "$ROOT/deploy/landing/" "$WT/site/"
rsync -a --delete --exclude '*.symbols' "$ROOT/app/statomea/build/web/" "$WT/site/app/"
# Copie à la racine : les pages 1.36.x ouvertes à l'ancienne adresse (racine) y lisent la version et proposent
# « Recharger », qui mène à la page d'accueil.
cp "$WT/site/app/version.json" "$WT/site/version.json"
if [ "${BUILD_APK:-0}" = "1" ]; then
  B=/tmp/statomea_build
  mkdir -p "$B"
  rsync -a --delete --exclude build --exclude .dart_tool --exclude android/.gradle "$ROOT/app" "$ROOT/packages" "$B/"
  # Un APK par architecture (arm64 : quasi tous les téléphones récents ; armv7 : anciens 32 bits) : ~30 Mo au lieu
  # de ~75 Mo pour l'APK universel. statomea.apk reste le lien générique (lien symbolique vers arm64).
  (cd "$B/app/statomea" && flutter build apk --release --split-per-abi)
  rm -rf "$WT/site/telecharger" && mkdir -p "$WT/site/telecharger" "$ROOT/dist"
  # Fichiers nommés avec la version (statomea-1.40.0-arm64-v8a.apk) : un téléphone qui a déjà téléchargé une version
  # précédente ne rouvre pas l'ancien fichier homonyme. Les anciens noms restent en liens symboliques.
  for abi in arm64-v8a armeabi-v7a; do
    cp "$B/app/statomea/build/app/outputs/flutter-apk/app-$abi-release.apk" "$WT/site/telecharger/statomea-$VERSION-$abi.apk"
    cp "$WT/site/telecharger/statomea-$VERSION-$abi.apk" "$ROOT/dist/statomea-$VERSION-$abi.apk"
    (cd "$WT/site/telecharger" && ln -s "statomea-$VERSION-$abi.apk" "statomea-$abi.apk")
  done
  (cd "$WT/site/telecharger" && ln -s "statomea-$VERSION-arm64-v8a.apk" statomea.apk)
  printf '{"version":"%s","url":"telecharger/statomea-%s-arm64-v8a.apk","urls":{"arm64-v8a":"telecharger/statomea-%s-arm64-v8a.apk","armeabi-v7a":"telecharger/statomea-%s-armeabi-v7a.apk"}}\n' "$VERSION" "$VERSION" "$VERSION" "$VERSION" > "$WT/site/android.json"
  echo "APK $VERSION publiés : $(cd "$WT/site/telecharger" && du -h statomea-$VERSION-*.apk | tr '\n' ' ')"
fi
cp "$ROOT/deploy/docker-compose.yml" "$ROOT/deploy/Caddyfile.static" "$ROOT/deploy/caddy-site.conf" "$ROOT/deploy/install.sh" "$WT/"
cat > "$WT/README.md" <<MD
# Statoméa — version web $VERSION (branche de déploiement)

Branche générée par \`deploy/publish-web.sh\` depuis \`main\` : ne pas modifier à la main.

Installation sur le VPS : \`git clone --branch web --single-branch https://github.com/Modibo/Statomea.git /opt/statomea && bash /opt/statomea/install.sh\`
Mise à jour : \`cd /opt/statomea && git fetch -q && git reset -q --hard origin/web && bash install.sh\`
MD
cd "$WT"
# Instantané unique (sans historique) : chaque APK pèserait sinon ~75 Mo de plus dans le dépôt et dans chaque mise à
# jour du VPS, qui se fait donc par « git fetch && git reset --hard origin/web » (et non git pull).
git checkout -q --orphan web-publication
git add -A
git commit -q -m "Version web $VERSION"
git branch -M web-publication web
git push -q -f -u origin web
cd "$ROOT" && git worktree remove --force "$WT"
echo "Branche web publiée : version $VERSION"
