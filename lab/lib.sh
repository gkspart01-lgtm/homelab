#!/usr/bin/env bash
# Gemeinsame Helfer fuer den Lab-Drill. Auf dem Anker-Host (pve) als root sourcen.
set -euo pipefail

LAB_DIR=${LAB_DIR:-/root/lab}
WORK_REPO=${WORK_REPO:-/root/homelab-iac}

VMID=${VMID:-101}
VMNAME=${VMNAME:-lab01}
VM_MEM=${VM_MEM:-4096}
VM_CORES=${VM_CORES:-2}
VM_DISK=${VM_DISK:-200}
VM_STORAGE=${VM_STORAGE:-local-lvm}
VM_BRIDGE=${VM_BRIDGE:-vmbr0}
PVE_ISO=${PVE_ISO:-/var/lib/vz/template/iso/proxmox-ve_9.2-1.iso}

# Endgueltige Adresse des Ziel-Hosts (setzt der Bootstrap), Adressplan wie beim Laptop
TARGET_FQDN=${TARGET_FQDN:-${VMNAME}.fritz.box}
TARGET_IP=${TARGET_IP:-192.168.181.50/21}
TARGET_IP_ONLY=${TARGET_IP_ONLY:-${TARGET_IP%%/*}}
TARGET_GW=${TARGET_GW:-192.168.178.1}
TARGET_DNS=${TARGET_DNS:-192.168.178.1}

# Anker (persistenter Klon-Ursprung)
ANCHOR_DIR=${ANCHOR_DIR:-/root/git-anchor}
ANCHOR_REPO=${ANCHOR_REPO:-homelab.git}
PVE_IP=${PVE_IP:-192.168.181.10}
GIT_URL=${GIT_URL:-git://${PVE_IP}/${ANCHOR_REPO}}

LAB_KEY=${LAB_KEY:-$LAB_DIR/id_ed25519}   # Schluessel, mit dem pve den Ziel-Host steuert

log()  { printf '\n[%s] == %s\n' "$(date +%H:%M:%S)" "$*"; }
warn() { printf '[%s] !! %s\n'  "$(date +%H:%M:%S)" "$*" >&2; }
die()  { printf '[%s] FEHLER: %s\n' "$(date +%H:%M:%S)" "$*" >&2; exit 1; }

# --- SSH zum Ziel ------------------------------------------------------------
ssh_opts=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10
          -o LogLevel=ERROR -i "$LAB_KEY")

tssh() { ssh "${ssh_opts[@]}" "root@${1}" "${@:2}"; }          # tssh <ip> <befehl>
tscp() { scp "${ssh_opts[@]}" "$@"; }                          # tscp <quelle> root@<ip>:<ziel>

# --- Zustand des Ziels ------------------------------------------------------
target_ip_dhcp() {
  qm guest cmd "$VMID" network-get-interfaces 2>/dev/null | python3 -c '
import json,sys
try: d=json.load(sys.stdin)
except Exception: raise SystemExit(1)
for iface in d:
    for a in iface.get("ip-addresses", []):
        ip=a.get("ip-address","")
        if a.get("ip-address-type")=="ipv4" and not ip.startswith("127.") and not ip.startswith("169.254."):
            print(ip); raise SystemExit(0)
raise SystemExit(1)'
}

wait_for_ssh() {  # wait_for_ssh <ip> [versuche]
  local ip="$1" tries="${2:-40}" n=0
  while [ "$n" -lt "$tries" ]; do
    if tssh "$ip" true 2>/dev/null; then return 0; fi
    n=$((n+1)); sleep 15
  done
  return 1
}

vm_exists() { qm status "$VMID" >/dev/null 2>&1; }

ensure_lab_key() {
  mkdir -p "$LAB_DIR"; chmod 700 "$LAB_DIR"
  if [ ! -f "$LAB_KEY" ]; then
    ssh-keygen -t ed25519 -N "" -C "lab@pve" -f "$LAB_KEY" >/dev/null
    chmod 600 "$LAB_KEY"
  fi
}

ensure_work_repo() {
  if [ ! -d "$WORK_REPO/.git" ]; then
    git clone "$GIT_URL" "$WORK_REPO"
  else
    git -C "$WORK_REPO" pull --ff-only || warn "pull fehlgeschlagen - arbeite mit lokalem Stand"
  fi
}

publish_result() {  # publish_result <datei> <nachricht>
  local f="$1" msg="$2"
  cp "$f" "$WORK_REPO/lab/results/"
  git -C "$WORK_REPO" add -A
  git -C "$WORK_REPO" -c user.name=lab -c user.email=lab@pve \
      commit -q -m "$msg" || true
  git -C "$WORK_REPO" push -q origin main || warn "push in den Anker fehlgeschlagen"
}
