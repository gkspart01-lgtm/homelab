#!/usr/bin/env bash
# Nachtbackup: Konfiguration + IaC-Repo + Datenbankdumps verschluesselt offsite.
set -euo pipefail
export HOME=/root
[ -f /root/.restic-env ] || { echo "fehlt: /root/.restic-env"; exit 1; }
set -a; . /root/.restic-env; set +a

DUMP=/srv/pool/backup/db-dumps
BK=/srv/pool/backup
mkdir -p "$DUMP"

# Proxmox-Konfiguration (pmxcfs) als Tar
tar czf "$BK/etc-pve.tar.gz" -C / etc/pve 2>/dev/null || true

# Datenbanken der Dienste (schreibt die Compose-Stacks nach /srv/pool/backup/db-dumps)
# z.B.  docker exec <pg> pg_dumpall | zstd > "$DUMP/pg-$(date +%F).sql.zst"

restic backup "/etc" "/root" "/etc/pve" "$DUMP" "$BK/etc-pve.tar.gz" \
  --exclude=/root/.cache --exclude=/root/.ssh/known_hosts --tag host-hl0
restic forget --keep-daily 7 --keep-weekly 4 --keep-monthly 6 --prune
restic check --read-data-subset=5%
