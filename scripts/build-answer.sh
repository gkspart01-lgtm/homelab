#!/bin/sh
# Build the corrected answer file on the pve host, validate it and prepare the ISO.
# Hinweis: Zugangsdaten/Passwoerter sind hier durch <PLATZHALTER> ersetzt. Duplikat-Skript mit echten Werten liegt auf dem jeweiligen Host.
set -e

# --- 1. answer file -----------------------------------------------------------
PUB="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAkzuxmmTBvU+UP6hHYyrEa5Zi1lc1qhsoKHidrEFoRV hermes@pve-vm-template"
cat > /root/hl01-answer.toml <<EOF
# Answer file for the Proxmox VE VM "hl01" (nested PVE on pve), PVE 9.2 ISO.
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
reboot-mode = "reboot"

[network]
source = "from-dhcp"

[disk-setup]
filesystem = "ext4"
disk-list = ["sda"]
EOF

echo "=== new answer file ==="
cat /root/hl01-answer.toml
echo "=== validate NEW ==="
proxmox-auto-install-assistant validate-answer /root/hl01-answer.toml || true
