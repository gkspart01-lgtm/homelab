#!/usr/bin/env bash
# Baut das Auto-Install-ISO fuer den Zielhost. Auf einem beliebigen
# Debian/Proxmox-Rechner mit proxmox-auto-install-assistant ausfuehren.
set -euo pipefail
ISO_IN="${1:?Pfad zum offiziellen proxmox-ve_*.iso}"
ANSWER="${2:?Pfad zum answer-file.toml}"
OUT="${3:-hl0-auto.iso}"

command -v proxmox-auto-install-assistant >/dev/null \
  || { echo "proxmox-auto-install-assistant fehlt (apt install proxmox-auto-install-assistant)"; exit 1; }

proxmox-auto-install-assistant validate-answer "$ANSWER"
proxmox-auto-install-assistant prepare-iso "$ISO_IN" --fetch-from iso \
  --answer-file "$ANSWER" --output "$OUT"
proxmox-auto-install-assistant inspect-iso "$OUT" | tail -20
printf '\nISO fertig: %s\nAuf USB schreiben:  dd if=%s of=/dev/sdX bs=4M status=progress oflag=direct\n' "$OUT" "$OUT"
