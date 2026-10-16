#!/usr/bin/env bash
# Erzeugt einen age-Schluessel fuer SOPS und zeigt, was in secrets/.sops.yaml gehoert.
set -euo pipefail
KEYDIR=/root/.config/sops/age
KEYFILE="$KEYDIR/keys.txt"
mkdir -p "$KEYDIR"; chmod 700 "$KEYDIR"
if [ -f "$KEYFILE" ]; then
  echo "Schluessel vorhanden: $KEYFILE"
else
  age-keygen -o "$KEYFILE"
  chmod 600 "$KEYFILE"
fi
PUB=$(grep -o 'age1[0-9a-z]*' "$KEYFILE" | head -1)
printf '\nPublic Key:  %s\n\n' "$PUB"
printf '1. In secrets/.sops.yaml eintragen:\n   creation_rules:\n     - path_regex: .*\\.(env|sops|yaml|yml|json|ini)$\n       age: %s\n' "$PUB"
printf '2. Private Key AUSDRUCKEN/auf USB kopieren und offline verwahren:\n   %s\n' "$KEYFILE"
printf '3. Ohne diesen Key ist das Git-Repo im Katastrophenfall nicht entschluesselbar.\n'
