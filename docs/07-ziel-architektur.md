# Zielarchitektur: Proxmox auf dem Laptop ("hl0")

Stand: Planung, aufbauend auf dem Testaufbau (`docs/01`–`06`, wegwerfbar).
Ziel: ein Homelab, das nach einem Hardwareverlust aus diesem Repo in ~2 Stunden
wiederherstellbar ist.

## Hardware-Realität (verifiziert am HP-Service-Manual, 13-ae000–13-ae099)

| Fakt | Konsequenz |
|---|---|
| Intel Core i7-8550U, 4C/8T, UHD 620 (QuickSync) | gut fuer Immich/Transcoding; dauerhaft ~15 W, im duennen Gehaeuse thermisch begrenzt |
| **16 GB LPDDR3 fest verloetet** – "non-customer-accessible/non-upgradable" | 16 GB ist die harte Obergrenze. Kein RAM-Upgrade moeglich. |
| **1× M.2 2280** NVMe, kein SATA-Port | Kein echtes RAID fuer System/Pool. Zweite SSD spaeter nur extern (Thunderbolt). |
| **kein RJ45**: 1× USB-A 3.1, 2× USB-C/Thunderbolt 3 | GbE nur per Adapter (USB-C bevorzugt, weil eigener Controller/Bandbreite) |
| Akku (60 Wh) | wirkt als Mini-USV; Deckel-zu muss per logind ignoriert werden |

Der Laptop ist damit eine ehrliche Einstiegsbasis – aber **nicht die Endstufe**.
Perspektive: gebrauchter SFF-Rechner (2–4 SATA + 2× M.2) als zweiter Node; der
Laptop wird dann Test-/AusweichNode oder PBS-Ziel. Netz-/Portempfehlungen der
Hardware-Runde sind in `hosts/spectre-x360/README.md` zusammengefasst.

## RAM-Budget (16 GB = 16384 MB)
| Rolle | RAM | Phase |
|---|---|---|
| Proxmox-Host (ohne ZFS-ARC) | ~1200 MB | 1 |
| docker01 (VM): Traefik, AdGuard, Vaultwarden, Forgejo-Alternative, SilverBullet, Paperless | 8192 MB | 1 |
| haos (VM, Home Assistant OS) | 2048 MB | 1 |
| forgejo (LXC) | 1024 MB | 1 |
| Reserve fuer Spitzen/Updates | ~1900 MB | – |
| immich (ohne ML-Container) | 4096 MB | 2 |
| nextcloud (schlank, kein AIO) | 2048 MB | 3 |
| sparkyfitness / hermes / monitoring | 512–2048 MB | 4 |

**Regel:** `tofu plan` zeigt `ram_total_mb` und `ram_reserve_mb`. Ist die Reserve
kleiner als ~1,5 GB, wird der naechste Dienst per `enabled = false` geparkt –
das ist der Hebel, den dir 16 GB lassen.

## Dienst-Aufteilung
* **Proxmox als Basis** (VM/LXC) – so bleibt HA OS native und jeder Dienst isoliert.
* **Container gebuendelt**: alle Docker-Dienste in **einer** VM (`docker01`),
  organisiert als Compose-Stacks im Repo. Kein Kubernetes.
* **Home Assistant OS** bleibt eigene VM (eigenes Kernel-Image, eigene Update-Logik).
* **Forgejo** als eigener LXC – er ist der Ursprung aller IaC-Artefakte und soll
  auch dann laufen, wenn der Docker-Host neu gebaut wird.

## Namens- und Adressplan
* Host: `hl0.mehrwert.icu` (FQDN), statisch **192.168.178.10/24**
* Gaeste: `.11` docker01, `.12` haos, `.13` forgejo (alle **unter** dem
  DHCP-Pool der FRITZ!Box, der typischerweise bei `.20` beginnt)
* Dienste: `https://<dienst>.hl0.mehrwert.icu` (Wildcard-Zertifikat, siehe `docs/09-netz.md`)

## Warum nicht anders
* **Kein Kubernetes**: deine Dienste sind zustandsbehaftet und passen auf einen
  Node. Compose im Git ist reproduzierbar ohne Cluster-Betriebsrisiko.
* **Kein ZFS** auf dem Laptop: ARC frisst den knappen RAM, und die USB-Platten
  vertragen kein Pool-Striping (`docs/08-speicher.md`).
* **Kein PBS** in Phase 1: 2 GB RAM, die erst mit dem zweiten Node frei sind.
  Bis dahin: `vzdump` + restic offsite.
