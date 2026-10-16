#!/usr/bin/env bash
# Harte Pruefliste. Exitcode != 0 heisst: Runde nicht bestanden.
source "$(dirname "$0")/lib.sh"

IP="$(cat "$LAB_DIR/target-ip.txt" 2>/dev/null || echo "$TARGET_IP_ONLY")"
STAMP="$(date +%Y-%m-%d_%H%M)"
RESULT="$LAB_DIR/result-${STAMP}.md"
PASS=0; FAIL=0

check() { # check <name> <erwartet: 0/1> <ausgabe>
  local name="$1" rc="$2" out="${3:-}"
  if [ "$rc" = "0" ]; then PASS=$((PASS+1)); printf '  PASS  %s\n' "$name"
  else FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$name"; fi
  printf -- '- [%s] %s%s\n' "$([ "$rc" = 0 ] && echo x || echo ' ')" "$name" \
    "$([ -n "$out" ] && printf ' — %s' "$out")" >> "$RESULT"
}

{
  echo "# Lab-Runde ${STAMP}"
  echo
  echo "Ziel: VM ${VMID} (${VMNAME}), Anker: ${GIT_URL}"
  echo
  echo "## Pruefungen"
} > "$RESULT"

log "Ziel-VM laeuft?"
check "VM ${VMID} laeuft" "$([ "$(qm status "$VMID" | awk '{print $2}')" = running ] && echo 0 || echo 1)"

log "Gast-Agent antwortet?"
check "Gast-Agent antwortet" "$(qm guest cmd "$VMID" get-osinfo >/dev/null 2>&1 && echo 0 || echo 1)"

log "SSH + Basissystem"
out=$(tssh "$IP" 'pveversion | head -1' 2>/dev/null || true)
check "SSH auf ${IP} + Proxmox laeuft" "$([ -n "$out" ] && echo 0 || echo 1)" "$out"

out=$(tssh "$IP" 'systemctl is-active pveproxy' 2>/dev/null | tr -d '\n' || true)
check "pveproxy aktiv" "$([ "$out" = active ] && echo 0 || echo 1)" "$out"

out=$(tssh "$IP" 'grep -c "HandleLidSwitch=ignore" /etc/systemd/logind.conf.d/10-ignore-lid.conf' 2>/dev/null || echo 0)
check "Deckel-zu wird ignoriert" "$([ "${out:-0}" -ge 1 ] && echo 0 || echo 1)"

out=$(tssh "$IP" 'grep -c usbcore.autosuspend=-1 /etc/default/grub' 2>/dev/null || echo 0)
check "USB-Autosuspend abgeschaltet" "$([ "${out:-0}" -ge 1 ] && echo 0 || echo 1)"

out=$(tssh "$IP" 'command -v mergerfs >/dev/null && command -v snapraid >/dev/null && command -v restic >/dev/null && echo ok' 2>/dev/null || true)
check "mergerfs + snapraid + restic installiert" "$([ "$out" = ok ] && echo 0 || echo 1)"

out=$(tssh "$IP" 'systemctl list-timers --all --no-pager | grep -cE "snapraid-sync|vzdump-all"' 2>/dev/null || echo 0)
check "Timer snapraid-sync + vzdump-all vorhanden" "$([ "${out:-0}" -ge 2 ] && echo 0 || echo 1)" "${out} Treffer"

out=$(tssh "$IP" 'pveum user token list tofu@pve 2>/dev/null | grep -c opentofu' 2>/dev/null || echo 0)
check "OpenTofu-API-Token angelegt" "$([ "${out:-0}" -ge 1 ] && echo 0 || echo 1)"

log "Repo + IaC"
out=$(tssh "$IP" 'git -C /root/homelab-iac log --oneline -1' 2>/dev/null || true)
check "Repo aus dem Anker geklont" "$([ -n "$out" ] && echo 0 || echo 1)" "$out"

out=$(tssh "$IP" 'cd /root/homelab-iac/tofu && tofu validate -no-color 2>&1 | tail -1' 2>/dev/null || true)
check "tofu validate" "$(case "$out" in *valid*) echo 0;; *) echo 1;; esac)" "$out"

out=$(tssh "$IP" 'grep -o "age1[0-9a-z]*" /root/.config/sops/age/keys.txt | head -1' 2>/dev/null || true)
check "age-Key vorhanden" "$([ -n "$out" ] && echo 0 || echo 1)" "Public Key ${out:0:16}..."

if [ "${TOFU_LAB_APPLY:-0}" = "1" ]; then
  out=$(tssh "$IP" 'pct list --no-header 2>/dev/null | wc -l' 2>/dev/null || echo 0)
  check "LXC-Gaeste aus dem Repo angelegt" "$([ "${out:-0}" -ge 1 ] && echo 0 || echo 1)" "${out} Container"
fi

{
  echo
  echo "## Ergebnis: ${PASS} bestanden, ${FAIL} fehlgeschlagen"
  echo
  echo "Nicht geprueft (bewusst): Produktionsgroesse der Gaeste — das Lab hat 4 GB RAM,"
  echo "der Laptop 16 GB. Die Produktionstarife laufen nur durch \`tofu plan\`."
} >> "$RESULT"

log "Ergebnis: ${PASS} bestanden, ${FAIL} fehlgeschlagen -> $RESULT"
publish_result "$RESULT" "Lab-Runde ${STAMP}: ${PASS} bestanden, ${FAIL} fehlgeschlagen"
[ "$FAIL" = "0" ]
