#!/usr/bin/env bash
# Installation et mise à jour de Statoméa sur le VPS (à lancer dans /opt/statomea, clone de la branche « web »).
# Idempotent : (re)crée le conteneur statique, ajoute une seule fois le bloc du site au Caddyfile de la façade
# (après sauvegarde), valide puis recharge Caddy, et vérifie la version servie.
set -euo pipefail
cd "$(dirname "$0")"
CADDY=nexolab-api-caddy-1
MAIN=/home/ubuntu/nexolab-api/Caddyfile
HOST=statomea.komodi-labo.org

if [ -z "${PROXY_NETWORK:-}" ]; then
  PROXY_NETWORK=$(docker inspect "$CADDY" --format '{{range $k, $v := .NetworkSettings.Networks}}{{println $k}}{{end}}' | head -n 1)
fi
export PROXY_NETWORK
echo "Réseau de la façade : $PROXY_NETWORK"

docker compose -p statomea up -d --force-recreate
sleep 2
# Le serveur statique doit répondre avant de toucher à la façade.
docker exec statomea-web wget -qO- http://localhost/version.json >/dev/null || { echo "Le conteneur statomea-web ne répond pas : docker logs statomea-web"; exit 1; }
echo "Conteneur statomea-web : OK"

if ! grep -q "^$HOST" "$MAIN"; then
  BACKUP="$MAIN.bak-$(date +%Y%m%d-%H%M%S)"
  cp "$MAIN" "$BACKUP"
  cat caddy-site.conf >> "$MAIN"     # ajout en place : même inode, le montage du conteneur voit le changement
  if ! docker exec "$CADDY" caddy validate --config /etc/caddy/Caddyfile >/dev/null 2>&1; then
    cat "$BACKUP" > "$MAIN"          # restauration en place, Caddy n'a pas été rechargé
    echo "Configuration invalide : Caddyfile restauré, rien n'a été rechargé."
    docker exec "$CADDY" caddy validate --config /etc/caddy/Caddyfile || true
    exit 1
  fi
  echo "Bloc $HOST ajouté au Caddyfile (sauvegarde : $BACKUP)."
fi
docker exec "$CADDY" caddy validate --config /etc/caddy/Caddyfile >/dev/null
docker exec "$CADDY" caddy reload --config /etc/caddy/Caddyfile
echo "Caddy rechargé."

sleep 3
echo "Version locale : $(grep -o '"version":"[^"]*"' site/version.json)"
echo "Version servie : $(curl -s --max-time 20 "https://$HOST/version.json" | grep -o '"version":"[^"]*"' || echo 'pas encore accessible (DNS ou certificat en cours ?)')"
