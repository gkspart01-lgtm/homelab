#!/usr/bin/env bash
# Ein Einstiegspunkt nach OpenTofu: bringt auf docker01 Komodo hoch, und Komodo
# deployt daraus den Rest (edge, authentik, whoami) aus komodo/homelab.toml.
#
# Voraussetzungen: Debian-Gast aus dem Template, Repo ausgecheckt, sudo-Rechte.
#   sudo apt-get update && sudo apt-get install -y git
#   sudo git clone https://github.com/gkspart01-lgtm/homelab /opt/homelab
#   sudo bash /opt/homelab/scripts/bootstrap-komodo.sh
#
# Idempotent: mehrfaches Ausführen ist unschädlich (vorhandene .env/Secrets bleiben).
set -euo pipefail

REPO_DIR=${REPO_DIR:-/opt/homelab}
DOMAIN=${DOMAIN:-hl0.mehrwert.icu}
cd "$REPO_DIR"

echo "=== 0. Docker ==="
if ! command -v docker >/dev/null 2>&1; then
  bash "$REPO_DIR/scripts/bootstrap-docker.sh"
fi
docker --version

echo "=== 1. Komodo-.env (Secrets einmalig erzeugen) ==="
ENV_FILE=$REPO_DIR/stacks/komodo/.env
if [ ! -f "$ENV_FILE" ]; then
  DB=$(openssl rand -hex 16)
  ADM=$(openssl rand -base64 18 | tr -d '/+=')
  JWT=$(openssl rand -hex 32)
  WH=$(openssl rand -hex 16)
  sed -e "s|^KOMODO_DATABASE_PASSWORD=.*|KOMODO_DATABASE_PASSWORD=$DB|" \
      -e "s|^KOMODO_INIT_ADMIN_PASSWORD=.*|KOMODO_INIT_ADMIN_PASSWORD=$ADM|" \
      -e "s|^KOMODO_JWT_SECRET=.*|KOMODO_JWT_SECRET=$JWT|" \
      -e "s|^KOMODO_WEBHOOK_SECRET=.*|KOMODO_WEBHOOK_SECRET=$WH|" \
      -e "s|^DOMAIN=.*|DOMAIN=$DOMAIN|" \
      "$REPO_DIR/stacks/komodo/.env.example" > "$ENV_FILE"
  echo "erzeugt: $ENV_FILE (enthält das Admin-Passwort)"
fi
chmod 600 "$ENV_FILE"

echo "=== 2. Komodo starten (Core + Periphery + MongoDB) ==="
docker network create edge >/dev/null 2>&1 || true
( cd "$REPO_DIR/stacks/komodo" && docker compose -p komodo up -d )

echo "=== 3. Auf Core warten ==="
for i in $(seq 1 60); do
  if curl -fsS -m 3 http://127.0.0.1:9120/version >/dev/null 2>&1; then
    echo "Core up nach $((i*3))s ($(curl -fsS http://127.0.0.1:9120/version))"
    break
  fi
  sleep 3
done

echo "=== 4. Variablen, Resource Sync, Deploy ==="
KOMODO_PASS=$(grep '^KOMODO_INIT_ADMIN_PASSWORD=' "$ENV_FILE" | cut -d= -f2-)
KOMODO_PASS="$KOMODO_PASS" DOMAIN="$DOMAIN" \
  python3 "$REPO_DIR/scripts/komodo-bootstrap.py"

echo "=== 5. authentik-Forward-Auth verdrahten (idempotent) ==="
for i in $(seq 1 60); do
  if curl -fsS -m 3 -o /dev/null http://127.0.0.1:9000/-/health/ready/ 2>/dev/null; then
    echo "authentik ready nach $((i*5))s"
    break
  fi
  sleep 5
done
AK_TOKEN=$(grep '^AK_BOOTSTRAP_TOKEN=' "$HOME/.komodo-homelab-secrets.env" 2>/dev/null | cut -d= -f2 || true)
AUTHENTIK_URL=http://127.0.0.1:9000 AUTHENTIK_TOKEN="$AK_TOKEN" DOMAIN="$DOMAIN" \
  python3 "$REPO_DIR/scripts/authentik-bootstrap.py"
# Outpost-Config greift erst nach einem Neustart des Servers
docker restart authentik-server >/dev/null 2>&1 || true
for i in $(seq 1 30); do
  curl -fsS -m 3 -o /dev/null http://127.0.0.1:9000/-/health/ready/ 2>/dev/null && break
  sleep 5
done

echo "=== 6. Status ==="
docker ps --format '{{.Names}}\t{{.Status}}' | sort
echo
echo "Komodo-UI:       https://komodo.$DOMAIN  (hinter authentik, sonst: ssh -L 9120:127.0.0.1:9120)"
echo "authentik:       https://auth.$DOMAIN"
echo "Testdienst:      https://whoami.$DOMAIN"
