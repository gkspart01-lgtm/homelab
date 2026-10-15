# Betriebs-Runbook

Alles hier läuft mit **root-Zugang** auf dem jeweiligen Proxmox-Host (SSH oder Web-UI-Shell).
Die Gäste-IDs: `hl01` = VM 101 auf `pve`, darauf LXC 110 (`forgejo`) und VM 100 (`homeassistant` — verworfen,
siehe unten), auf `pve` selbst VM 105 (`homeassistant`).

## 1. Neuen Container auf `hl01` anlegen

```bash
ssh root@192.168.181.50
pveam available --section system | grep debian-13          # Template-Name prüfen
pveam download local debian-13-standard_13.6-1_amd64.tar.zst
pct create 111 local:vztmpl/debian-13-standard_13.6-1_amd64.tar.zst \
  --hostname dienst --cores 2 --memory 1024 --swap 512 --rootfs local-lvm:8 \
  --net0 name=eth0,bridge=vmbr0,ip=192.168.181.5x/21,gw=192.168.178.1 \
  --nameserver 192.168.178.1 --features nesting=1 --unprivileged 1 --onboot 1 --start 1
pct exec 111 -- bash          # Shell im Container, ohne SSH/Passwort
```

Freie statische IP vorher prüfen (`ping -c1 <ip>`), Bereich oberhalb des DHCP-Pools nutzen
(bei uns 192.168.181.50–192.168.181.59).

## 2. Bestehende Gäste

```bash
# hl01 (verschachteltes Proxmox VE)
pct list ; pct exec 110 -- systemctl status forgejo nginx   # Forgejo
# Host pve
qm list ; qm config 105 | grep -E "net0|memory"             # Home Assistant
```

## 3. Backup

```bash
# Container im laufenden Betrieb sichern (Snapshot-Modus)
vzdump 110 --mode snapshot --compress zstd --storage local
# HA-VM auf pve
vzdump 105 --mode snapshot --compress zstd --storage local
ls -la /var/lib/vz/dump/
```

Wiederherstellen: `pct restore <id> /var/lib/vz/dump/vzdump-lxc-110-*.tar.zst --storage local-lvm`
bzw. `qmrestore /var/lib/vz/dump/vzdump-qemu-105-*.vma.zst <id> --storage local-lvm`.
Für Home Assistant zusätzlich die **HA-eigenen Backups** nutzen (Einstellungen → System → Backups).

## 4. Updates

| Was | Befehl |
|---|---|
| Proxmox-Host `pve`, nested `hl01` | `apt update && apt full-upgrade` (Repos: `pve-no-subscription`) |
| Forgejo-Container | `pct exec 110 -- apt update && pct exec 110 -- apt upgrade`; Forgejo-Binary: neue Version nach `/usr/local/bin/forgejo` kopieren, `systemctl restart forgejo` |
| Home Assistant OS | im HA-UI unter *Einstellungen → System → Updates*, oder Konsole: `ha os update` / `ha core update` |

## 5. Logs und Diagnose

```bash
qm status 101 ; qm terminal 101        # Konsole der VM (bzw. noVNC im Web-UI)
qm monitor 101                         # QEMU-Monitor; "screendump /tmp/x.ppm" = Bildschirmfoto
pct exec 110 -- journalctl -u forgejo -n 50
journalctl -u pvedaemon -n 50          # auf dem jeweiligen PVE-Host
lvs ; pvesm status                     # Speicherplatz / Thin-Pool
```

## 6. Bekannte Eigenheiten dieser Umgebung

1. **Nested UEFI funktioniert nicht.** In `hl01` (PVE in einer VM) lässt sich kein UEFI-Gast booten —
   OVMF initialisiert dort weder die Konsole noch liest es von der Platte. Auf dem Host `pve` funktioniert
   UEFI normal (verifiziert). Deshalb: BIOS-Gäste in `hl01`, UEFI-Gäste (wie Home Assistant OS) auf `pve`.
2. **Automatik-Installation der PVE-ISO:** `reboot-mode = "power-off"` verwenden, sonst startet der
   Installer nach dem Reboot wieder vom ISO und überschreibt die fertige Installation.
3. **Enterprise-Repos** sind nach einer PVE-Installation aktiv und liefern ohne Subscription `401` —
   `pve-no-subscription` + `ceph-no-subscription` eintragen, sonst läuft kein `apt update`.
4. Passwörter und Schlüssel stehen **nicht** in diesem Repository (es ist öffentlich sichtbar).
