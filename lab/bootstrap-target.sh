#!/usr/bin/env bash
# Host-Bootstrap im Ziel ausfuehren (Repos, Deckel, Thermik, USB-Tuning, Timer, API-Token).
source "$(dirname "$0")/lib.sh"

IP="$(cat "$LAB_DIR/dhcp-ip.txt" 2>/dev/null || true)"
[ -n "$IP" ] || IP="$(target_ip_dhcp || true)"
[ -n "$IP" ] || die "Ziel-IP unbekannt - erst provision-target.sh ausfuehren"
wait_for_ssh "$IP" 10 || die "kein SSH auf $IP"

log "Bootstrap-Skript uebertragen und ausfuehren"
tscp "$WORK_REPO/hosts/spectre-x360/pve-bootstrap.sh" "root@${IP}:/root/pve-bootstrap.sh"
tssh "$IP" "bash /root/pve-bootstrap.sh '$TARGET_FQDN' '$TARGET_IP' '$TARGET_GW' '$TARGET_DNS'" || \
  warn "Bootstrap meldete Fehler - Ausgabe oben pruefen"

log "Nach dem IP-Wechsel auf ${TARGET_IP_ONLY} warten"
wait_for_ssh "$TARGET_IP_ONLY" 20 || die "Ziel nach IP-Umstellung nicht erreichbar"
cat "$LAB_DIR/dhcp-ip.txt" > /dev/null
printf '%s\n' "$TARGET_IP_ONLY" > "$LAB_DIR/target-ip.txt"
tssh "$TARGET_IP_ONLY" 'hostname -f; ip -4 -o addr show scope global | awk "{print \$2, \$4}"; systemctl is-active pveproxy'
log "BOOTSTRAP OK"
