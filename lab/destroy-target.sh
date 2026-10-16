#!/usr/bin/env bash
# Ziel-VM stoppen und loeschen. Der Anker und Forgejo bleiben unberuehrt.
source "$(dirname "$0")/lib.sh"
log "Ziel-VM ${VMID} entfernen"
if vm_exists; then
  qm stop "$VMID" --skiplock 1 >/dev/null 2>&1 || true
  sleep 3
  qm destroy "$VMID" --purge 1 --skiplock 1 || die "VM $VMID liess sich nicht loeschen"
  log "VM ${VMID} geloescht (Disks mit --purge)"
else
  log "VM ${VMID} existiert nicht - nichts zu tun"
fi
rm -f "$LAB_DIR/dhcp-ip.txt" "$LAB_DIR/target-ip.txt"
