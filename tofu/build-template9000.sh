#!/bin/sh
# Baut auf pve2 das Debian-13-cloud-init-Template (VMID 9000), aus dem OpenTofu klont.
set -eu

VMID=9000
IMG=debian-13-genericcloud-amd64.qcow2
URL_BASE=https://cloud.debian.org/images/cloud/trixie/latest
IMPORT_DIR=/var/lib/vz/import

echo "=== 0. alte Reste weg ==="
qm stop $VMID >/dev/null 2>&1 || true
qm destroy $VMID --purge >/dev/null 2>&1 || true
mkdir -p "$IMPORT_DIR"

echo "=== 1. Image laden + SHA512 prüfen ==="
[ -f "$IMPORT_DIR/$IMG" ] || curl -fsSL -o "$IMPORT_DIR/$IMG" "$URL_BASE/$IMG"
WANT=$(curl -fsSL "$URL_BASE/SHA512SUMS" | awk -v f="$IMG" '$2==f {print $1}')
GOT=$(sha512sum "$IMPORT_DIR/$IMG" | awk '{print $1}')
[ "$WANT" = "$GOT" ] && echo "sha512 ok" || { echo "SHA512 MISMATCH"; exit 1; }

echo "=== 2. VM anlegen (Import + cloud-init) ==="
KEY=${KEY:?KEY muss als Umgebungsvariable uebergeben werden}
# Passwort des cloud-init-Users: aus der Umgebung, niemals im Repo
CIPASSWORD=${CIPASSWORD:?CIPASSWORD muss als Umgebungsvariable uebergeben werden}
printf '%s\n' "$KEY" > /tmp/tpl-sshkeys.pub
qm create $VMID --name debian13-cloud-template --memory 2048 --cores 2 --cpu host --ostype l26 \
  --scsihw virtio-scsi-single --agent enabled=1,fstrim_cloned_disks=1 \
  --scsi0 "local-lvm:0,import-from=$IMPORT_DIR/$IMG" \
  --ide2 local-lvm:cloudinit --net0 virtio,bridge=vmbr0 --ipconfig0 ip=dhcp \
  --ciuser debian --cipassword "$CIPASSWORD" --sshkeys /tmp/tpl-sshkeys.pub --ciupgrade 0 \
  --serial0 socket --vga serial0 --boot order=scsi0 --bootdisk scsi0 --onboot 0 \
  --description "Debian 13 (trixie) genericcloud + cloud-init + qemu-guest-agent. Template fuer OpenTofu (VM-Klone)."
qm resize $VMID scsi0 10G

echo "=== 3. Start + warten auf Gast-Agent ==="
qm start $VMID
i=0
while [ $i -lt 40 ]; do
  sleep 6; i=$((i+1))
  if qm agent $VMID get-osinfo >/tmp/osinfo.json 2>/dev/null; then echo "Agent up nach $((i*6))s"; break; fi
done
qm agent $VMID get-osinfo || { echo "Agent antwortet nicht"; exit 1; }

IP=$(qm agent $VMID network-get-interfaces 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)
for i in d.get('result',[]):
    if i.get('name')!='lo':
        for a in i.get('ip-addresses',[]):
            if a.get('ip-address-type')=='ipv4' and not a['ip-address'].startswith('127.'):
                print(a['ip-address']); raise SystemExit
")
echo "IP im Gast: $IP"

echo "=== 4. Image für Klone aufräumen (Agent, machine-id, Hostkeys, cloud-init) ==="
ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "debian@$IP" '
set -e
sudo -n apt-get update -qq
sudo -n DEBIAN_FRONTEND=noninteractive apt-get install -y -qq qemu-guest-agent 2>&1 | tail -2
sudo -n systemctl enable --now qemu-guest-agent || true
printenv | grep -q . && true
sudo -n truncate -s 0 /etc/machine-id
sudo -n rm -f /var/lib/dbus/machine-id /etc/ssh/ssh_host_*
sudo -n apt-get clean
sudo -n rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*.deb
sudo -n sh -c "rm -f /root/.bash_history /home/debian/.bash_history; : > /var/log/wtmp; : > /var/log/lastlog; rm -f /var/log/cloud-init*.log /var/log/apt/*.log*"
sudo -n cloud-init clean --logs --seed
echo gast-fertig
' 2>&1 | tail -4

echo "=== 5. Herunterfahren + Template ==="
qm shutdown $VMID --timeout 60 || qm stop $VMID
sleep 3
qm template $VMID
qm config $VMID | grep -E "^(name|template|scsi0|ide2|net0|agent|memory|cores)"
echo "TEMPLATE-FERTIG"
