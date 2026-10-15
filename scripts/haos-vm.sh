#!/bin/sh
# Home Assistant OS 18.3 als VM auf dem HOST pve (nicht in hl01: dort funktioniert OVMF nicht).
set -e

ISO=/var/lib/vz/template/iso/haos_ova-18.3.qcow2.xz
IMG=/var/lib/vz/template/iso/haos_ova-18.3.qcow2

echo "=== 1. auf Download warten / prüfen / entpacken ==="
i=0
while [ ! -f /tmp/haos-pve.log ] && [ $i -lt 90 ]; do sleep 10; i=$((i+1)); done
cat /tmp/haos-pve.log 2>/dev/null || echo "(kein Log)"
ls -la "$ISO"
xz -t "$ISO" && echo "xz ok"
[ -f "$IMG" ] || unxz -k "$ISO"
qemu-img info "$IMG" | grep -E "file format|virtual size"

echo "=== 2. VM 105 (OVMF/UEFI + q35, 2 GB RAM) ==="
qm destroy 105 --purge >/dev/null 2>&1 || true
qm create 105 \
  --name homeassistant \
  --description "Home Assistant OS 18.3 (haos_ova-18.3.qcow2), UEFI/OVMF - VM auf dem Proxmox-Host pve" \
  --memory 2048 --cores 2 --cpu host --ostype l26 \
  --machine q35 --bios ovmf \
  --scsihw virtio-scsi-single \
  --efidisk0 local-lvm:0,efitype=4m,pre-enrolled-keys=0 \
  --net0 virtio,bridge=vmbr0 \
  --agent enabled=1 \
  --onboot 1 \
  --serial0 socket \
  --scsi0 local-lvm:0,import-from=$IMG \
  --boot order=scsi0

echo "=== 3. Disk auf 32 GB + GPT anpassen ==="
qm resize 105 scsi0 32G
sgdisk -e /dev/pve/vm-105-disk-1 2>&1 | tail -1 || true
sgdisk -v /dev/pve/vm-105-disk-1 2>&1 | tail -2

echo "=== 4. Start ==="
qm start 105
sleep 10
qm config 105 | grep -E "^(name|bios|machine|memory|cores|scsi0|net0|efidisk0|onboot|boot)"
qm status 105
