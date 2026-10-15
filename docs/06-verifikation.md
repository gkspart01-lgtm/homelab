# Verifikation — was wie getestet wurde

Grundsatz: jede Aussage in dieser Doku wurde mit einem Kommando oder einer API-Antwort belegt.
Hier die wichtigsten Nachweise mit den tatsächlichen Ergebnissen.

## Host `pve`

| Prüfung | Kommando / Methode | Ergebnis |
|---|---|---|
| Erreichbarkeit, Version | `POST /api2/json/access/ticket` + `GET /version` | Ticket erhalten, `pve-manager` 9.2.x |
| Storage | `GET /nodes/pve/storage` | `local` (dir) + `local-lvm` (lvmthin), ~208 GB frei |
| Nested-Virtualisierung | `cat /sys/module/kvm_intel/parameters/nested` | `Y` (Voraussetzung für `hl01`) |
| UEFI-Funktion | Test-VM mit `bios ovmf` ohne Disk, Screenshot über QEMU-Monitor | `BdsDxe: No bootable option or device was found …` + Proxmox-OVMF-Splash ⇒ OVMF läuft |

## VM `hl01` (verschachteltes Proxmox VE)

| Prüfung | Methode | Ergebnis |
|---|---|---|
| Installation | Auto-Install-ISO, Konsolen-Screenshot, Thin-Pool-Füllstand | `progress 100.0 % - installation finished`, danach automatisches Power-off |
| Bootet von Platte | `qm set --delete ide2`, `--boot order=scsi0`, `qm start` | System startet, SSH mit hinterlegtem Schlüssel |
| Version/Services | `pveversion`, `systemctl is-active pve-cluster pvedaemon pveproxy pvestatd` | `pve-manager/9.2.2`, Kernel `7.0.2-6-pve`, alle vier `active` |
| API/Web-UI | Ticket-Login gegen `https://192.168.181.50:8006/api2/json/access/ticket` | Login als `root@pam` ok, `version: 9.2.2` |
| Storage | `pvesm status` | `local` aktiv, `local-lvm` (lvmthin) mit ~116 GB frei |
| Container-Betrieb | `pveam download local alpine-…`, `pct create/start/exec/destroy 200` | Container lief, `CT-OK` aus `pct exec`, danach sauber entfernt |
| Statisches Netz | `ip -4 -br addr show vmbr0` | `192.168.181.50/21` |
| Gast-Agent | `GET /nodes/pve/qemu/101/agent/get-osinfo` | `Debian GNU/Linux 13 (trixie)`, Kernel `7.0.2-6-pve` |

## Forgejo (LXC 110 auf `hl01`)

| Prüfung | Methode | Ergebnis |
|---|---|---|
| Dienst | `systemctl is-active forgejo nginx`, `ss -tlnp` | beide `active`; Ports 80, 127.0.0.1:3000, *:2222 |
| Web/API von außen | `curl http://192.168.181.51/user/login`, `/api/v1/version` | HTTP 200 (12 kB Loginseite), `{"version":"16.0.6+gitea-1.22.0"}` |
| Git über HTTP | Test-Repo per API, `git clone`, Commit, `git push`, Serverprüfung | Push-SHA `988a79b` serverseitig in `GET /api/v1/repos/…/commits` sichtbar |
| Git über SSH | temporärer Key per API, `git clone ssh://git@…:2222/…` | Clone erfolgreich; Key und Test-Repo danach gelöscht |
| Neustart | `pct reboot 110` | Forgejo + nginx kommen selbstständig hoch, API antwortet wieder |

## Home Assistant (VM 105 auf `pve`)

| Prüfung | Methode | Ergebnis |
|---|---|---|
| OVMF in `hl01` (Gegenprobe) | Test-VM `bios ovmf` in `hl01`, Screenshot + `/proc/diskstats` | kein Framebuffer, 0 Lese-/Schreibzugriffe auf die Platte über 12 s, ~100 % vCPU ⇒ OVMF unbrauchbar |
| HAOS-Image in `hl01` | `qz -t`, Import, Boot mit q35/OVMF bzw. i440fx | hängt ohne Kernel-Ausgabe; kein DHCP ⇒ kein Boot |
| SeaBIOS-Versuch | `bios seabios` mit dem generischen Image | hängt bei `Booting from Hard Disk...` (Images sind UEFI-only, kein BIOS-Bootloader) |
| HAOS auf `pve` | Import, 32 GB, `sgdisk -e`, Start | Konsole: `Booting 'Slot A (OK=1 TRY=1)'`, DHCP-Lease **192.168.178.71**, Port 8123 offen, Observer: `Supervisor: Connected / Health: Healthy` |
| Core-Installation | HAOS-Konsole (`ha >`) | `OS Version: Home Assistant OS 18.3`, `System is ready! Use browser or app to configure.` — Core wird beim ersten Aufruf der UI eingerichtet |

## Reproduzierbarkeit

Alle Skripte liegen unter [`scripts/`](../scripts/):

| Datei | Zweck |
|---|---|
| `hl01-answer.toml` | Answer-File der unbeaufsichtigten PVE-Installation |
| `pve-auto-install.sh` | ISO bauen, VM präparieren, installieren, bis zum Power-off warten |
| `forgejo-install.sh` | Forgejo-Binary + systemd + nginx im Container |
| `forgejo-fix.sh` | Nacharbeiten (app.ini-Rechte, Unit mit `ReadWritePaths`, nginx-Reload, Admin-Konto) |
| `haos-vm.sh` | HAOS-Image importieren und VM erzeugen (Zielhost: UEFI-fähig!) |
| `pve-api.py` | kleiner Ticket-Auth-API-Client, mit dem der Agent ohne `qm`-Rechte arbeitet |
