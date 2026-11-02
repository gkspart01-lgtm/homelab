#!/usr/bin/env bash
# Setzt das Passwort des authentik-Adminusers neu.
#
# Hintergrund: AUTHENTIK_BOOTSTRAP_PASSWORD wirkt nur beim ALLERERSTEN Start.
# Wird der Wert in der .env später geändert, bleibt das alte Passwort in der DB.
# Dieses Skript setzt es idempotent auf den gewünschten Wert.
#
# Aufruf (auf docker01):
#   AK_PASS='<neues passwort>' bash scripts/authentik-set-password.sh
#   # oder ohne AK_PASS: liest AK_ADMIN_PASS aus stacks/komodo/secrets.env
set -euo pipefail

USER_NAME=${AK_USER:-akadmin}
SECRETS_FILE=${SECRETS_FILE:-/opt/homelab/stacks/komodo/secrets.env}

if [ -z "${AK_PASS:-}" ]; then
  if [ -r "$SECRETS_FILE" ]; then
    AK_PASS=$(grep '^AK_ADMIN_PASS=' "$SECRETS_FILE" | cut -d= -f2-)
  fi
fi
[ -n "${AK_PASS:-}" ] || { echo "Kein Passwort: AK_PASS setzen oder $SECRETS_FILE lesbar machen"; exit 1; }

# Passwort per stdin an die Django-Shell geben (keine Argumente in der Prozessliste)
printf '%s\n' \
  "from authentik.core.models import User" \
  "u = User.objects.get(username=\"$USER_NAME\")" \
  "u.set_password(\"$AK_PASS\")" \
  "u.save()" \
  "print(\"PASSWORT-GESETZT:\", u.check_password(\"$AK_PASS\"))" \
  | docker exec -i authentik-server ak shell 2>&1 | grep -E "PASSWORT-GESETZT|Error|Traceback" | tail -3
