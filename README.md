# Homelab

Deklarativ aufgebautes Homelab: **OpenTofu** erzeugt die Gast-VMs, **Komodo** deployt
die Docker-Stacks aus diesem Repo, **authentik** stellt SSO und Gruppen davor, ein
**rathole**-Tunnel holt ausgewählte Dienste über einen IONOS-VPS ins Internet.

```
Internet ─► VPS (Traefik, Let's Encrypt) ─► rathole ─► docker01: Traefik :8081
                                                        │  authentik forward-auth
                                                        └─► Dienst-Container
```

## Dienste

| Dienst | Adresse | Zugriff |
|---|---|---|
| Dienstübersicht (öffentlich) | https://hl.mehrwert.icu/ | offen |
| Dienstübersicht (intern) | https://home.hl.mehrwert.icu/ | SSO · `homelab-users` |
| Komodo | https://komodo.hl.mehrwert.icu/ | SSO · `homelab-admins` |
| authentik | https://auth.hl.mehrwert.icu/ | Login |
| SilverBullet (Notizen) | https://notes.hl.mehrwert.icu/ | SSO · `homelab-users` |
| SparkyFitness | https://fitness.hl.mehrwert.icu/ | SSO · `homelab-users` |
| PancakeSlicer | https://slicer.hl.mehrwert.icu/ | SSO · `homelab-users` |
| whoami (Testdienst) | https://whoami.hl.mehrwert.icu/ | SSO |
| Home Assistant | http://192.168.178.74:8123 | nur LAN, eigenes Login |

## Gäste auf `pve2` (192.168.181.99)

| ID | Name | Typ | Größe | Adresse |
|---|---|---|---|---|
| 9000 | `debian13-cloud-template` | VM-Template | 2C / 2 GB / 10 GB | – |
| 200 | `docker01` | VM (Clone) | 4C / 6 GB / 64 GB | 192.168.181.100/21 |
| 201 | `haos` | VM (Image-Import) | 2C / 2 GB / 32 GB | DHCP 192.168.178.74 |
| 220 | `probe` | LXC | 1C / 512 MB / 4 GB | 192.168.181.101/21 |

## Repo

| Pfad | Inhalt |
|---|---|
| `tofu/` | VMs, Template, HAOS — `tofu/README.md` |
| `komodo/homelab.toml` | Quelle der Wahrheit: welche Stacks auf welchem Server |
| `stacks/` | Compose je Dienst — `stacks/README.md` |
| `scripts/` | Bootstrap und Verifikation |
| `docs/decisions.md` | warum es so gebaut ist |
| `docs/access-control.md` | Benutzer, Gruppen, Rechte |
| `docs/troubleshooting.md` | Fallstricke, die Zeit gekostet haben |

## Installation

[INSTALL.md](INSTALL.md). Auf einem frischen `docker01` sind es zwei Befehle:

```bash
sudo git clone https://github.com/gkspart01-lgtm/homelab /opt/homelab
sudo bash /opt/homelab/scripts/bootstrap-komodo.sh
```

## Betrieb

Änderung = Datei ändern → Commit → Sync in Komodo (UI, `km x sync homelab` oder
Git-Webhook). Neue App: `stacks/README.md`, Abschnitt *Neue App*.
