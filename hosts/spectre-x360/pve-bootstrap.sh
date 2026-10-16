#!/usr/bin/env bash
# pve-bootstrap.sh - macht aus einem frisch installierten Proxmox VE auf dem
# HP Spectre x360 13-ae (Zielhost "hl0") einen Server. Idempotent, keine GUI.
#
# Aufruf (als root auf dem frischen PVE-Host):
#   bash pve-bootstrap.sh [FQDN] [IP/CIDR] [GATEWAY] [DNS]
# Beispiel:
#   bash pve-bootstrap.sh hl0.mehrwert.icu 192.168.178.10/21 192.168.178.1 192.168.178.1
#
# Ohne IP-Argument bleibt die per DHCP bezogene Adresse erhalten.
set -euo pipefail

FQDN="${1:-hl0.mehrwert.icu}"
SHORT="${FQDN%%.*}"
IP_CIDR="${2:-}"
GW="${3:-192.168.178.1}"
DNS_IP="${4:-192.168.178.1}"

log() { printf '\n== %s\n' "$*"; }
die() { printf 'FEHLER: %s\n' "$*" >&2; exit 1; }
[ "$(id -u)" -eq 0 ] || die "als root ausfuehren"

log "1/12 Zeit + Hostname"
timedatectl set-timezone Europe/Berlin
timedatectl set-ntp true
hostnamectl set-hostname "$SHORT"
if grep -qE '^127\.0\.1\.1' /etc/hosts; then
  sed -i "s|^127\.0\.1\.1.*|127.0.1.1 $FQDN $SHORT|" /etc/hosts
else
  sed -i "1a 127.0.1.1 $FQDN $SHORT" /etc/hosts
fi

log "2/12 Enterprise-Repos abschalten, no-subscription aktivieren"
for f in /etc/apt/sources.list.d/pve-enterprise.sources /etc/apt/sources.list.d/ceph.sources; do
  [ -f "$f" ] && sed -i 's/^Enabled:.*/Enabled: false/' "$f" || true
done
if [ -f /etc/apt/sources.list.d/pve-no-subscription.sources ]; then
  sed -i 's/^Enabled:.*/Enabled: true/' /etc/apt/sources.list.d/pve-no-subscription.sources
fi
grep -q download.proxmox.com /etc/apt/sources.list /etc/apt/sources.list.d/*.sources 2>/dev/null \
  || printf 'deb http://download.proxmox.com/debian/pve trixie pve-no-subscription\n' > /etc/apt/sources.list.d/pve-no-subscription.list

log "3/12 Pakete"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get -y -qq full-upgrade
apt-get -y -qq install smartmontools lm-sensors usbutils nvme-cli ethtool hdparm \
  mergerfs snapraid restic age wireguard-tools git jq zstd sqlite3 rsync thermald

log "4/12 Kernel-Cmdline: USB-Autosuspend aus, Konsole blanken"
if ! grep -q 'usbcore.autosuspend=-1' /etc/default/grub; then
  sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"/GRUB_CMDLINE_LINUX_DEFAULT="\1 usbcore.autosuspend=-1 consoleblank=300"/' /etc/default/grub
  update-grub
fi

log "5/12 Deckel zu = weiterlaufen, kein Suspend/Hibernate (Laptop als Server)"
mkdir -p /etc/systemd/logind.conf.d
cat > /etc/systemd/logind.conf.d/10-ignore-lid.conf <<'EOF'
[Login]
HandleLidSwitch=ignore
HandleLidSwitchExternalPower=ignore
HandleLidSwitchDocked=ignore
IdleAction=ignore
EOF
systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target >/dev/null
systemctl restart systemd-logind || true

log "6/12 Thermik + CPU-Governor (Dauerbetrieb im duennen Gehaeuse)"
systemctl enable --now thermald || true
cat > /etc/systemd/system/cpu-governor.service <<'EOF'
[Unit]
Description=CPU-Governor auf powersave setzen
[Service]
Type=oneshot
ExecStart=/bin/sh -c 'for g in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do echo powersave > "$g"; done'
RemainAfterExit=yes
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --now cpu-governor.service

log "7/12 Bildschirm/BLUETOOTH/WLAN entschaerfen"
[ -d /sys/class/backlight ] && for b in /sys/class/backlight/*/brightness; do echo 0 > "$b" 2>/dev/null || true; done
systemctl disable --now bluetooth.service >/dev/null 2>&1 || true
[ -d /sys/module/hp_wmi ] && true || true

log "8/12 SnapRAID + mergerfs vorbereiten"
cat > /etc/systemd/system/snapraid-sync.service <<'EOF'
[Unit]
Description=SnapRAID Sync (Paritaet aktualisieren)
After=local-fs.target
[Service]
Type=oneshot
ExecStart=/usr/bin/snapraid sync
ExecStartPost=/usr/bin/snapraid status
EOF
cat > /etc/systemd/system/snapraid-sync.timer <<'EOF'
[Unit]
Description=taeglicher SnapRAID-Sync
[Timer]
OnCalendar=*-*-* 04:30:00
RandomizedDelaySec=30m
Persistent=true
[Install]
WantedBy=timers.target
EOF
cat > /etc/systemd/system/snapraid-scrub.service <<'EOF'
[Unit]
Description=SnapRAID Scrub (Datenintegritaet pruefen)
[Service]
Type=oneshot
ExecStart=/bin/sh -c 'snapraid scrub -p 8 -o 20 -l /var/log/snapraid-scrub.log'
EOF
cat > /etc/systemd/system/snapraid-scrub.timer <<'EOF'
[Unit]
Description=woechentlicher SnapRAID-Scrub
[Timer]
OnCalendar=Sun *-*-* 05:30:00
Persistent=true
[Install]
WantedBy=timers.target
EOF
systemctl daemon-reload

log "9/12 vzdump-Zeitplan (Backup aller Gaeste)"
cat > /etc/systemd/system/vzdump-all.service <<'EOF'
[Unit]
Description=Backup aller VMs/LXC auf den HDD-Pool
[Service]
Type=oneshot
ExecStart=/usr/bin/vzdump --all --mode snapshot --compress zstd --notes-template '{{guestname}}' \
  --mailnotification never --dumpdir /srv/pool/backup/dump --prune-backups keep-daily=7,keep-weekly=4
EOF
cat > /etc/systemd/system/vzdump-all.timer <<'EOF'
[Unit]
Description=naechtliches vzdump
[Timer]
OnCalendar=*-*-* 03:15:00
RandomizedDelaySec=20m
Persistent=true
[Install]
WantedBy=timers.target
EOF
systemctl daemon-reload

log "10/12 OpenTofu-API-Token anlegen (fuer die IaC-Ebene)"
pveum role add TofuProvisioner -privs "Datastore.AllocateSpace Datastore.Audit Pool.Allocate Sys.Audit Sys.Console Sys.Modify VM.Allocate VM.Audit VM.Clone VM.Config.CDROM VM.Config.CPU VM.Config.Cloudinit VM.Config.Disk VM.Config.HWType VM.Config.Memory VM.Config.Network VM.Config.Options VM.Migrate VM.PowerMgmt SDN.Use" 2>/dev/null || true
pveum user add tofu@pve --comment "OpenTofu" 2>/dev/null || true
pveum acl modify / --users tofu@pve --roles TofuProvisioner
TOKEN_FILE=/root/tofu-api-token.txt
umask 077
pveum user token add tofu@pve opentofu --privsep 0 2>&1 | tee "$TOKEN_FILE"
printf '\n(Pfad: %s - Wert in tofu/nodes.auto.tfvars eintragen, Datei danach loeschen)\n' "$TOKEN_FILE"

log "11/12 Statische IP (optional)"
if [ -n "$IP_CIDR" ]; then
  cp -n /etc/network/interfaces "/etc/network/interfaces.bak.$(date +%F-%H%M)"
  python3 - "$IP_CIDR" "$GW" "$DNS_IP" <<'PY'
import re, sys
ip, gw, dns = sys.argv[1:4]
p = "/etc/network/interfaces"
s = open(p).read()
def setkv(block, key, val):
    if re.search(rf'^\s*{key}\s+', block, re.M):
        return re.sub(rf'^\s*{key}\s+.*$', f'\t{key} {val}', block, count=1, flags=re.M)
    return block.rstrip() + f'\n\t{key} {val}\n'
m = re.search(r'^auto vmbr0.*?(?=^\S|\Z)', s, re.M | re.S)
if not m:
    raise SystemExit("vmbr0-Block nicht gefunden - IP bitte manuell setzen")
b = m.group(0)
b = re.sub(r'^\s*(address|netmask|gateway|dns-nameservers)\s+.*$', '', b, flags=re.M)
b = re.sub(r'\n{2,}', '\n', b)
b = setkv(b, 'address', ip)
b = setkv(b, 'gateway', gw)
b = setkv(b, 'dns-nameservers', dns)
open(p, 'w').write(s[:m.start()] + b.rstrip() + '\n' + s[m.end():])
print("interfaces angepasst:", ip, gw, dns)
PY
  printf '%s %s\n' "$(printf '%s' "$IP_CIDR" | cut -d/ -f1)" "$FQDN" >> /etc/hosts
  nohup sh -c 'sleep 3; ifreload -a' >/dev/null 2>&1 &
  printf 'IP wird gleich aktiv: %s - die SSH-Sitzung bricht dabei ab.\n' "$IP_CIDR"
fi

log "12/12 Zusammenfassung"
{
  echo "Host:      $(hostname -f)"
  echo "PVE:       $(pveversion | head -1)"
  echo "Kernel:    $(uname -r)"
  echo "CPU:       $(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2)"
  echo "RAM:       $(free -h | awk '/Mem:/{print $2}')"
  echo "NICs:      $(ls /sys/class/net | tr '\n' ' ')"
  echo "IP:        $(ip -4 -o addr show scope global | awk '{print $2" "$4}' | tr '\n' ' ')"
} | tee /root/bootstrap-summary.txt
printf '\nFertig. Naechste Schritte:\n'
printf '  1. Disks anschliessen, /etc/fstab + /etc/snapraid.conf aus dem Repo uebernehmen\n'
printf '  2. Repo auf den Host klonen (git clone <forgejo-url> /root/homelab-iac)\n'
printf '  3. scripts/age-init.sh ausfuehren (SOPS/age-Key) und den Key OFFLINE sichern\n'
printf '  4. tofu init && tofu apply (Ordner tofu/)\n'
