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

---

## Ziel-Setup (ab 15.10.2026): Proxmox auf dem Laptop `hl0`

Der Testaufbau oben (Host `pve`, VM `hl01`) ist **wegwerfbar** und diente nur als
Uebungsplatz. Der produktive Aufbau entsteht auf einem HP Spectre x360 13-ae043ng
(i7-8550U, 16 GB, 1× M.2) und ist vollstaendig aus diesem Repo reproduzierbar.

| Dokument | Thema |
|---|---|
| [docs/07-ziel-architektur.md](docs/07-ziel-architektur.md) | Zielbild, Hardware-Realitaet, RAM-Budget, Dienst-Aufteilung |
| [docs/08-speicher.md](docs/08-speicher.md) | mergerfs + SnapRAID fuer gemischte USB-Platten |
| [docs/09-netz.md](docs/09-netz.md) | Public Edge am IONOS-VPS per WireGuard, DNS-01/Wildcard, Split-DNS |
| [docs/10-backup.md](docs/10-backup.md) | 3-2-1 (vzdump, restic offsite, Offline-Platte) |
| [docs/11-iac.md](docs/11-iac.md) | Vier IaC-Ebenen: Host, OpenTofu, cloud-init, Compose + SOPS/age |
| [docs/12-rebuild-runbook.md](docs/12-rebuild-runbook.md) | **Disaster Recovery**: Host in ~2 h wieder aufsetzen |

```
hosts/spectre-x360/   Answer-File, Bootstrap, SnapRAID-/restic-/systemd-Vorlagen
tofu/                 OpenTofu + bpg/proxmox: alle VMs/LXC deklarativ
cloud-init/           Muster fuer Gast-Initialisierung
stacks/               Docker-Compose-Stacks, ein Ordner pro Dienst
secrets/              SOPS-Konfiguration (age) + Regeln
scripts/              age-init.sh, deploy.sh
```

## Anker und Lab: wie die Reproduzierbarkeit bewiesen wird

* **Anker** (persistenter Klon-Ursprung, ueberlebt jeden Test-Wipe):
  bare-Repo auf dem Proxmox-Host `pve` unter `/root/git-anchor/homelab.git`,
  erreichbar als `git://192.168.181.10/homelab.git`. Der Agent pusht bei jedem
  Commit an Forgejo **und** in den Anker (zwei push-URLs an einem Remote).
* **Lab** (`lab/`): Skripte, die den Ziel-Host wiederholt komplett plattmachen und
  aus diesem Repo neu aufbauen — Provision (Auto-Install-ISO) → Bootstrap →
  Repo klonen → OpenTofu plan/apply → Pruefliste → Ergebnis als Markdown im Repo.
  Einzelschritte und Grenzen des Labors: [lab/README.md](lab/README.md)
