#!/bin/sh
# Rebuild the auto-install ISO with reboot-mode=power-off and run the unattended
# Hinweis: Zugangsdaten/Passwoerter sind hier durch <PLATZHALTER> ersetzt. Duplikat-Skript mit echten Werten liegt auf dem jeweiligen Host.
# PVE install in VM 101, waiting until the installer powers the VM off.
set -e

PUB="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAkzuxmmTBvU+UP6hHYyrEa5Zi1lc1qhsoKHidrEFoRV hermes@pve-vm-template"
cat > /root/hl01-answer.toml <<EOF
# Answer file for the nested Proxmox VE VM "hl01" on pve (PVE 9.2 ISO).
[global]
keyboard = "de"
country = "de"
fqdn = "hl01.fritz.box"
mailto = "mail@no.invalid"
timezone = "Europe/Berlin"
root-password = "<ROOT-PASSWORT>"
root-ssh-keys = [
    "$PUB",
]
reboot-mode = "power-off"

[network]
source = "from-dhcp"

[disk-setup]
filesystem = "ext4"
disk-list = ["sda"]
EOF

proxmox-auto-install-assistant validate-answer /root/hl01-answer.toml
rm -f /var/lib/vz/template/iso/hl01-auto3.iso
proxmox-auto-install-assistant prepare-iso /var/lib/vz/template/iso/proxmox-ve_9.2-1.iso \
    --fetch-from iso --answer-file /root/hl01-answer.toml \
    --output /var/lib/vz/template/iso/hl01-auto3.iso

qm stop 101 2>/dev/null || true
sleep 2
# clear GPT/GRUB leftovers from the previous attempts
dd if=/dev/zero of=/dev/pve/vm-101-disk-0 bs=1M count=64 conv=fsync status=none
qm set 101 --ide2 local:iso/hl01-auto3.iso,media=cdrom
qm set 101 --boot order=ide2
qm start 101
echo "install started at $(date +%T)"

# wait for the installer to finish (it powers the VM off)
i=0
while [ $i -lt 60 ]; do
  sleep 15
  i=$((i+1))
  st=$(qm status 101 | awk '{print $2}')
  printf "%s status=%s pool=%s\n" "$(date +%T)" "$st" "$(lvs pve/vm-101-disk-0 --noheadings -o data_percent | tr -d ' ')"
  if [ "$st" = "stopped" ]; then
    echo "INSTALL-FINISHED (VM powered off by installer)"
    exit 0
  fi
done
echo "TIMEOUT waiting for install"
exit 1
