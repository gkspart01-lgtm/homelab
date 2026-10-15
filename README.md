# Homelab: Proxmox-VM, Forgejo und Home Assistant

Dokumentation des Aufbaus — geschrieben von Hermes (KI-Agent) beim Einrichten, Stand 15.10.2026.

## Inhalt

| Dokument | Thema |
|---|---|
| [docs/01-proxmox-host.md](docs/01-proxmox-host.md) | Der Proxmox-VE-Host `pve` (192.168.181.10): Zugang, Storage, Gäste |
| [docs/02-proxmox-vm-hl01.md](docs/02-proxmox-vm-hl01.md) | **Die Proxmox-VM `hl01`** — unbeaufsichtigte PVE-Installation in einer VM |
| [docs/03-forgejo.md](docs/03-forgejo.md) | Forgejo 16.0.6 als LXC-Container (`forgejo`, 192.168.181.51) |
| [docs/04-home-assistant.md](docs/04-home-assistant.md) | Home Assistant OS als VM (`homeassistant` auf `hl01`) |
| [docs/05-betrieb.md](docs/05-betrieb.md) | Runbook: neue Gäste, Backups, Updates, Troubleshooting |
| [docs/06-verifikation.md](docs/06-verifikation.md) | Wie jeder Schritt tatsächlich getestet wurde (Befehle + Ergebnisse) |

Skripte und Konfigurationen, die dabei entstanden sind, liegen unter [`scripts/`](scripts/).

## Kurzüberblick der Landschaft

```
Fritz!Box 192.168.178.1 (Gateway, DHCP, DNS)
│   LAN 192.168.176.0/21, Domain fritz.box
│
├── Proxmox-Host "pve"            192.168.181.10   PVE 9.2, Storage: local + local-lvm
│   ├── LXC 100 "hermesagent"     192.168.178.56   Container, in dem dieser Agent läuft
│   ├── VM 9000 "debian13-cloud-template"          cloud-init-Template für Debian-13-VMs
│   └── VM 101 "hl01"             192.168.181.50   Proxmox VE 9.2.2 (verschachtelt!)
│       ├── LXC 110 "forgejo"     192.168.181.51   Forgejo 16.0.6 (dieses Repo)
│       └── VM 100 "homeassistant" (DHCP)          Home Assistant OS 18.3
│
└── bestehende Geräte: Home Assistant (192.168.180.20), OctoPrint, Raspberry Pis …
```

## Wichtige Adressen und Zugänge

| Dienst | Adresse | Login |
|---|---|---|
| Proxmox-Host `pve` | https://192.168.181.10:8006 | `root@pam` |
| Proxmox-VM `hl01` | https://192.168.181.50:8006 | `root@pam` |
| Forgejo | http://192.168.181.51 | Admin-Benutzer `falko` |
| Forgejo Git-SSH | `ssh://git@192.168.181.51:2222/…` | SSH-Key im Web-UI hinterlegen |
| Home Assistant | http://<DHCP-IP>:8123 | beim ersten Aufruf Onboarding-Assistent |

**Passwörter stehen bewusst nicht in diesem Repository** — es ist öffentlich sichtbar. Die Zugangsdaten wurden separat übergeben; alle Stellen, an denen eines gesetzt wurde, sind in den Dokumenten als `«Passwort»` markiert.
