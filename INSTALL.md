# Installation

Von einem frischen Proxmox-Host zu laufenden Diensten — ohne Klicks. Alles nach
Schritt 1 ist deklarativ: OpenTofu für die Gäste, Komodo für die Container.

## 0. Voraussetzungen

- Proxmox VE 9.x mit root-SSH und API-Zugang (Referenz: `pve2`, 192.168.181.99)
- Arbeitsrechner mit OpenTofu ≥ 1.8 und einem SSH-Key, der auf den Gästen liegt
- Für öffentliche URLs: IONOS-VPS mit Traefik (Let's Encrypt) und rathole-Server,
  DNS-Zeigen auf den VPS. Ohne VPS funktioniert alles außer der Erreichbarkeit von außen.

## 1. VM-Template bauen (auf dem PVE-Host)

```bash
scp tofu/build-template9000.sh root@192.168.181.99:/root/
ssh root@192.168.181.99 'CIPASSWORD=<Startpasswort> bash /root/build-template9000.sh'
```

Ergebnis: VM **9000** `debian13-cloud-template`, 10 GB, cloud-init + qemu-guest-agent,
generalisierbar (machine-id/Hostkeys entfernt). Das Skript lädt das Debian-13-Genericcloud-
Image selbst und prüft es gegen die veröffentlichte SHA512.

## 2. API-Token für OpenTofu

```bash
ssh root@192.168.181.99
pveum role add Tofu -privs "VM.Allocate VM.Audit VM.Clone VM.Config.CPU VM.Config.CDROM \
VM.Config.Cloudinit VM.Config.Disk VM.Config.HWType VM.Config.Memory VM.Config.Network \
VM.Config.Options VM.GuestAgent.Audit VM.GuestAgent.Unrestricted VM.PowerMgmt \
Datastore.Allocate Datastore.AllocateSpace Datastore.Audit Pool.Allocate SDN.Use Sys.Audit"
pveum user add tofu@pve
pveum user token add tofu@pve opentofu --privsep 0   # -> "value" ist das token_secret
pveum acl modify / --tokens 'tofu@pve!opentofu' --roles Tofu
```

Fehlt eines der Rechte (`SDN.Use`, `VM.Config.Cloudinit`, `VM.Config.CDROM`,
`VM.GuestAgent.*`), bricht `tofu apply` mit HTTP 403 ab.

## 3. Gäste erzeugen

```bash
cd tofu
cp nodes.auto.tfvars.example nodes.auto.tfvars
# nodes.auto.tfvars: endpoint, token_id, token_secret, ssh_private_key (Pfad!)
tofu init
tofu plan
tofu apply
```

Erzeugt `docker01` (VM 200), `haos` (VM 201, Image-Import mit EFI-Disk) und `probe`
(LXC 220). Outputs: `ipv4`, `ram_total_mb`, `ram_reserve_mb`.

## 4. Ballooning am äußeren PVE (empfohlen)

`pve2` ist selbst eine VM. Der äußere Host darf Speicher zurückholen, das Gast-Budget
bleibt trotzdem gedeckt (Minimum = Budget − 4 GB):

```bash
qm set <ID-von-pve2> --memory 12288 --balloon 8192
qm stop <ID> && qm start <ID>
```

## 5. docker01: ein Skript macht den Rest

```bash
ssh debian@192.168.181.100
sudo apt-get update && sudo apt-get install -y git
sudo git clone https://github.com/gkspart01-lgtm/homelab /opt/homelab
cd /opt/homelab && sudo bash scripts/bootstrap-komodo.sh
```

Idempotent, mehrfach ausführbar. Reihenfolge:

1. `scripts/bootstrap-docker.sh` — Docker Engine + Compose-Plugin
2. `stacks/komodo` — Core 2 + Periphery + MongoDB; erzeugt `stacks/komodo/.env` mit
   Zufallspasswörtern (nur beim ersten Lauf, enthält das Admin-Passwort)
3. `scripts/komodo-bootstrap.py` — Variablen anlegen, Resource-Sync `homelab` aus
   `komodo/homelab.toml`, Stacks in `after`-Reihenfolge deployen
4. `scripts/authentik-bootstrap.py` — Provider, Applications, Outpost, Gruppen + Policies
5. `docker restart authentik-server` (Outpost liest seine Config beim Start)

Danach erreichbar: `https://komodo.<DOMAIN>` (Admin `admin`, Passwort aus
`stacks/komodo/.env`), `https://home.<DOMAIN>`, `https://whoami.<DOMAIN>`.

## 6. Verifizieren

```bash
# Kette ohne öffentliches DNS: Redirect, Gate, Health, Login-Flow
EDGE_IP=192.168.181.100 DOMAIN=hl.mehrwert.icu python3 scripts/smoke-test-edge.py

# Gruppen-ACL: Admin darf alles, Benutzer ohne Gruppe nichts
AUTHENTIK_TOKEN=$(grep AK_BOOTSTRAP_TOKEN stacks/komodo/secrets.env | cut -d= -f2) \
  python3 scripts/authentik-verify-acl.py

# Öffentlich (nur mit VPS + rathole)
for u in https://hl.mehrwert.icu/ https://home.hl.mehrwert.icu/ \
         https://komodo.hl.mehrwert.icu/ https://notes.hl.mehrwert.icu/ \
         https://auth.hl.mehrwert.icu/-/health/live/; do
  printf '%-42s %s\n' "$u" "$(curl -s -o /dev/null -m 20 -w '%{http_code}' "$u")"
done
# erwartet: 200 (apex, health), sonst 302 auf auth.<DOMAIN>
```

## 7. Tunnel zum VPS aktivieren

```bash
RATHOLE_REMOTE=hl.mehrwert.icu:8443 \
RATHOLE_PUBKEY=<Public Key des VPS> \
RATHOLE_TOKEN=<Service-Token> \
SECRETS_FILE=stacks/komodo/secrets.env python3 scripts/komodo-bootstrap.py
```

Der Client reicht Klartext an Traefik `webplain :8081`; TLS terminiert der VPS.
`frp` ist deklariert, aber `deploy = false` (siehe `docs/decisions.md`, ADR-3).

## 8. Home Assistant

Die VM 201 entsteht mit `tofu apply`; beim ersten Start Onboarding im Browser
(`http://<ip>:8123`) abschließen. Danach den Watchdog scharfschalten:

```bash
ssh root@192.168.181.99
pveum role add Hawatch -privs "VM.Audit VM.PowerMgmt"
pveum user token add tofu@pve hawatch --privsep 0    # -> "value"
pveum acl modify /vms/201 -t 'tofu@pve!hawatch' -role Hawatch
```

Auf `docker01` die Variablen setzen und den Sync anstoßen:

```bash
PVE_TOKEN_SECRET=<value aus dem Token-Output> \
  SECRETS_FILE=stacks/komodo/secrets.env python3 scripts/komodo-bootstrap.py
```

`hawatch` pollt `HA_URL` (Default `http://192.168.178.74:8123`), rebootet nach drei
Fehlversuchen die VM über die PVE-API und hält danach eine Stunde Ruhe.

Kontrolle, dass HA wirklich auf 8123 lauscht (nicht auf 80 — siehe
`docs/troubleshooting.md`):

```bash
qm guest exec 201 -- /bin/sh -c 'ha core info | grep -E "^(port|version)"'
```

## 9. Was bewusst nicht im Git liegt

| Datei | Inhalt | entsteht durch |
|---|---|---|
| `tofu/nodes.auto.tfvars` | API-Token, SSH-Key-Pfad | Schritt 3 (manuell) |
| `tofu/terraform.tfstate*` | State | `tofu apply` |
| `stacks/komodo/.env` | Admin-/DB-/JWT-Passwörter | Schritt 5 (Zufallswerte) |
| `stacks/komodo/secrets.env` | generierte Stack-Secrets (`AK_*`, `DOMAIN`, `RATHOLE_*`, `PVE_*`) | Schritt 5 |
| `stacks/edge/.env`, `stacks/authentik/.env` | ACME-/DB-Zugänge | `*.env.example` kopieren |

Vor jedem Push: `git grep -nE 'BEGIN .*PRIVATE KEY|token_secret|PASSWORD='` gegen den
Arbeitsstand laufen lassen.
