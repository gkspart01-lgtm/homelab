#!/usr/bin/env bash
# Deployt einen Stack: Secrets entschluesseln, Compose hochziehen. Kein weiteres Framework.
#   scripts/deploy.sh <stack>          # up -d
#   scripts/deploy.sh <stack> down     # stoppen
set -euo pipefail
STACK="${1:?Stack-Name, z.B. vaultwarden}"
ACTION="${2:-up}"
REPO="${REPO:-/root/homelab-iac}"
DIR="$REPO/stacks/$STACK"
[ -d "$DIR" ] || { echo "kein Stack: $DIR"; exit 1; }
cd "$DIR"

# .env.sops -> temporaere .env (600), nach dem Start wieder loeschen
CLEANUP=""
if [ -f .env.sops ]; then
  umask 077; sops -d .env.sops > .env; CLEANUP=1
fi
if [ "$ACTION" = "down" ]; then
  docker compose down
else
  docker compose pull
  docker compose up -d --remove-orphans
fi
[ -n "$CLEANUP" ] && rm -f .env
docker compose ps
