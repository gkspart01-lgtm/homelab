#!/usr/bin/env bash
# Frische PVE-VM als Ziel-Host: VM loeschen, Auto-Install-ISO bauen, unbeaufsichtigt
# installieren, bis SSH laeuft. Idempotent - beliebig oft wiederholbar.
source "$(dirname "$0")/lib.sh"

ensure_lab_key
ensure_work_repo
mkdir -p "$LAB_DIR"

log "Answer-File fuer ${TARGET_FQDN} erzeugen"
PW_FILE="$LAB_DIR/root-password.txt"
[ -f "$PW_FILE" ] || { openssl rand -base64 18 > "$PW_FILE"; chmod 600 "$PW_FILE"; }
PUB="$(cut -d' ' -f1,2 "$LAB_KEY.pub")"
ANS="$LAB_DIR/answer.toml"
sed -e "s|BITTE-AENDERN|$(cat "$PW_FILE")|" \
    -e "s|ssh-ed25519 AAAA\.\.\.bitte-eintragen|${PUB}|" \
    -e "s|^fqdn = .*|fqdn = \"${TARGET_FQDN}\"|" \
    "$WORK_REPO/hosts/spectre-x360/answer-file.toml.example" > "$ANS"
grep -q "$(cut -d' ' -f2 "$LAB_KEY.pub" | cut -c1-24)" "$ANS" || die "SSH-Key nicht im Answer-File gelandet"
chmod 600 "$ANS"

log "Answer-File pruefen und ISO bauen"
proxmox-auto-install-assistant validate-answer "$ANS" | tail -3
LAB_ISO="/var/lib/vz/template/iso/${VMNAME}-auto.iso"
[ -f "$PVE_ISO" ] || die "PVE-ISO fehlt: $PVE_ISO"
proxmox-auto-install-assistant prepare-iso "$PVE_ISO" --fetch-from iso \
    --answer-file "$ANS" --output "$LAB_ISO" | tail -3

log "Ziel-VM ${VMID} frisch anlegen (${VM_CORES}C/${VM_MEM}MB/${VM_DISK}G)"
if vm_exists; then
  qm stop "$VMID" --skiplock 1 >/dev/null 2>&1 || true
  sleep 3
  qm destroy "$VMID" --purge 1 --skiplock 1 || die "konnte VM $VMID nicht loeschen"
fi
qm create "$VMID" \
  --name "$VMNAME" --memory "$VM_MEM" --cores "$VM_CORES" \
  --scsihw virtio-scsi-single --scsi0 "${VM_STORAGE}:${VM_DISK}" \
  --net0 "virtio,bridge=${VM_BRIDGE}" --agent enabled=1 \
  --ide2 "local:iso/$(basename "$LAB_ISO")",media=cdrom --boot order=ide2 \
  --serial0 socket --vga serial0 --onboot 0
qm start "$VMID"
log "Installation laeuft (ca. 7 min, schaltet sich am Ende selbst aus)"

n=0
while [ "$n" -lt 80 ]; do
  sleep 15; n=$((n+1))
  st=$(qm status "$VMID" | awk '{print $2}')
  printf '  %s status=%s\n' "$(date +%H:%M:%S)" "$st"
  [ "$st" = "stopped" ] && break
done
[ "$(qm status "$VMID" | awk '{print $2}')" = "stopped" ] || die "Installation lief nicht zu Ende"

log "ISO abhaengen, von der Platte booten"
qm set "$VMID" --delete ide2
qm set "$VMID" --boot order=scsi0
qm start "$VMID"

log "Auf Gast-Agent und SSH warten"
IP=""
for i in $(seq 1 40); do
  IP="$(target_ip_dhcp || true)"
  [ -n "$IP" ] && break
  sleep 10
done
[ -n "$IP" ] || die "kein Gast-Agent/IP - VM $VMID erreicht das Netz nicht"
printf '%s\n' "$IP" > "$LAB_DIR/dhcp-ip.txt"
log "Ziel-Host erreichbar unter ${IP} - warte auf SSH"
wait_for_ssh "$IP" 20 || die "SSH auf ${IP} kam nicht hoch"
tssh "$IP" 'pveversion; grep -m1 "model name" /proc/cpuinfo; free -h | head -2'
log "PROVISION OK (IP vorerst ${IP}; der Bootstrap setzt spaeter ${TARGET_IP})"
