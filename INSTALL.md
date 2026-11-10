# Installation von 0 auf 100

Jeder Schritt sagt, **auf welchem Rechner** er läuft:

- `[W]` dein Arbeitsrechner (Linux/macOS, `tofu` + `ssh` installiert)
- `[P]` Proxmox-Host `pve2` (192.168.181.99) — per SSH als `root`
- `[D]` `docker01` (192.168.181.100) — per SSH als `debian`
- `[V]` IONOS-VPS — per SSH als `root` (nur für öffentliche Erreichbarkeit)

## Handarbeit vs. Automatik

| # | Schritt | Wer | Handarbeit |
|---|---|---|---|
| 1 | Proxmox VE auf dem Host installieren | du | ISO booten, 1 Assistent |
| 2 | API-Token + Rolle anlegen | `[P]` | 4 Befehle (kopierbar) |
| 3 | `nodes.auto.tfvars` ausfüllen | `[W]` | 3 Werte eintragen |
| 4 | `tofu apply` | `[W]` | 1 Befehl |
| 5 | Tunnel-Daten vom VPS eintragen | `[W]` | 2 Werte (Pubkey, Token) |
| 6 | **alles andere** | `[D]` | 1 Skript, idempotent |

Nach Schritt 6 laufen 8 Stacks, SSO, Gruppen und der Tunnel ohne weiteren Eingriff.
Alles ab Schritt 4 ist wiederholbar: gleiche Befehle, gleiches Ergebnis.

## 1. `[P]` Proxmox-Host

Falls der Host schon läuft: überspringen. Frisch: PVE 9.x installieren (unbeaufsichtigt
per Answer-File, `reboot-mode = "power-off"`), danach:

```bash
[P] hostnamectl set-hostname pve2
[P] sed -i 's/^deb .*enterprise.*/#&/' /etc/apt/sources.list.d/pve-enterprise.list
[P] echo "deb http://download.proxmox.com/debian/pve trixie pve-no-subscription" \
      > /etc/apt/sources.list.d/pve-no-subscription.list
[P] apt update && apt -y full-upgrade
```

Storage: `local` (ISOs/Images) + `local-lvm` (Disks) — beides ist bei PVE-Default vorhanden.

## 2. `[P]` API-Token für OpenTofu

```bash
[P] pveum role add Tofu -privs "VM.Allocate VM.Audit VM.Clone VM.Config.CPU VM.Config.CDROM \
VM.Config.Cloudinit VM.Config.Disk VM.Config.HWType VM.Config.Memory VM.Config.Network \
VM.Config.Options VM.GuestAgent.Audit VM.GuestAgent.Unrestricted VM.PowerMgmt \
Datastore.Allocate Datastore.AllocateSpace Datastore.Audit Pool.Allocate SDN.Use Sys.Audit"
[P] pveum user add tofu@pve
[P] pveum user token add tofu@pve opentofu --privsep 0     # -> "value" notieren
[P] pveum acl modify / --tokens 'tofu@pve!opentofu' --roles Tofu
```

`value` ist das `token_secret` für Schritt 4. Fehlt eins der Rechte, bricht `tofu apply`
mit HTTP 403 ab (typisch: `SDN.Use`, `VM.Config.Cloudinit`, `VM.Config.CDROM`).

## 3. `[P]` VM-Template bauen

```bash
[W] scp tofu/build-template9000.sh root@192.168.181.99:/root/
[P] CIPASSWORD='<Startpasswort für den debian-User>' bash /root/build-template9000.sh
```

Erwartete Ausgabe am Ende: `Task OK` und `VM 9000 -> template`. Das Skript lädt das
Debian-13-Genericcloud-Image, prüft die SHA512, installiert cloud-init und
qemu-guest-agent und generalisiert den Gast (machine-id, Hostkeys, Logs).

Kontrolle:

```bash
[P] qm list | grep 9000          # 9000 debian13-cloud-template  stopped
```

## 4. `[W]` Gäste erzeugen (OpenTofu)

```bash
[W] git clone https://github.com/gkspart01-lgtm/homelab && cd homelab/tofu
[W] cp nodes.auto.tfvars.example nodes.auto.tfvars
[W] $EDITOR nodes.auto.tfvars
```

Drei Werte eintragen, alles andere passt:

```hcl
endpoint        = "https://192.168.181.99:8006/api2/json"
token_id        = "tofu@pve!opentofu"
token_secret    = "<value aus Schritt 2>"
ssh_private_key = "~/.ssh/id_ed25519"     # Pfad zum PRIVATE Key
```

```bash
[W] tofu init
[W] tofu plan        # erwartet: 3 to add (VM 200, VM 201, LXC 220)
[W] tofu apply -auto-approve
```

Erwartete Ausgabe:

```
Apply complete! Resources: 3 added, 0 changed, 0 destroyed.
Outputs:
guests         = { docker01 = { id = 200, ip = "192.168.181.100/21", ... },
                   probe    = { id = 220, ip = "192.168.181.101/21", ... } }
haos           = { id = 201, ram = "2048 MB", url = "http://<dhcp-ip>:8123" }
ram_total_mb   = 8704
ram_reserve_mb = 2560
```

Was hier entsteht: `docker01` (VM 200, 4C/6 GB/64 GB, Docker-Host), `haos` (VM 201,
Home Assistant OS per Image-Import), `probe` (LXC 220, IaC-Beweis).

Optional, wenn `pve2` selbst in einer VM läuft — auf dem **äußeren** PVE:

```bash
[P-aussen] qm set <ID-von-pve2> --memory 12288 --balloon 8192 && qm stop <ID> && qm start <ID>
```

## 5. `[D]` Alles andere: Komodo deployt den Stack

```bash
[D] ssh debian@192.168.181.100
[D] sudo apt-get update && sudo apt-get install -y git
[D] sudo git clone https://github.com/gkspart01-lgtm/homelab /opt/homelab
[D] cd /opt/homelab && sudo bash scripts/bootstrap-komodo.sh
```

Dauer 5–10 Minuten (Images ziehen). Erwartete letzten Zeilen:

```
UpdateStack sparkyfitness: 200
DeployStack sparkyfitness: 200
Komodo-UI:       https://komodo.hl.mehrwert.icu
authentik:       https://auth.hl.mehrwert.icu
```

Das Skript ist ein dünner Wrapper um fertige Software — es startet nur:

1. Docker (Distribution-Pakete)
2. `stacks/komodo` per Compose (Komodo Core + Periphery + MongoDB)
3. `scripts/komodo-bootstrap.py`: legt die Komodo-Variablen an und registriert den
   **Resource Sync** `homelab` auf `komodo/homelab.toml`. Ab hier deployt **Komodo selbst**
   alle Stacks in der Reihenfolge aus `after = [...]`.
4. `scripts/authentik-bootstrap.py`: Provider/Applications/Gruppen per authentik-API
5. `docker restart authentik-server`

Ohne Skripte geht es auch — dann dieselben Schritte von Hand:

- Komodo-UI öffnen (`https://komodo.hl.mehrwert.icu`, `admin` + Passwort aus
  `stacks/komodo/.env`), *Variables* anlegen (`DOMAIN`, `AK_*`, `SPARKY_*`, `RATHOLE_*`)
  und unter *Syncs → New* einen Resource Sync auf Repo `gkspart01-lgtm/homelab`,
  Datei `komodo/homelab.toml` zeigen lassen. Sync ausführen — Komodo legt Server +
  Stacks an und deployt sie.
- authentik-UI: pro App *Applications → Create with Provider* (Proxy Provider,
  Forward auth single application), dann *Policies* → Expression-Policy + Binding an
  die Application (`docs/access-control.md`).

Die Skripte sparen genau diese Klickarbeit — mehr tun sie nicht.

## 6. `[W]` Prüfen

```bash
[W] EDGE_IP=192.168.181.100 DOMAIN=hl.mehrwert.icu python3 scripts/smoke-test-edge.py
```

Erwartet (5/5 OK): HTTP→HTTPS-Redirect, Gate-Redirect zum Login, authentik-Health,
Login-Flow, Login-Maske.

```bash
[W] AUTHENTIK_TOKEN=$(ssh debian@192.168.181.100 'sudo grep AK_BOOTSTRAP_TOKEN \
      /opt/homelab/stacks/komodo/secrets.env | cut -d= -f2') \
    python3 scripts/authentik-verify-acl.py
```

Erwartet: jede App `True` für `akadmin`, `False` für Benutzer ohne Gruppe.

## 7. `[V]` Tunnel und DNS (nur für Erreichbarkeit von außen)

Auf dem VPS laufen fertige Container: Traefik (Let's Encrypt, Wildcard
`*.hl.mehrwert.icu`) und der rathole-Server. Dort ist nichts zu bauen — nur zwei Werte
abholen:

```bash
[V] grep -E "public_key|token" /pfad/zu/rathole-server.toml   # bzw. docker logs rathole
```

Diese zwei Werte auf `[W]` in den gewünschten Sync übernehmen:

```bash
[W] RATHOLE_REMOTE=hl.mehrwert.icu:8443 \
    RATHOLE_PUBKEY='<Public Key>' \
    RATHOLE_TOKEN='<Service-Token>' \
    SECRETS_FILE=<pfad>/secrets.env \
    KOMODO_PASS='<Komodo-Admin-Passwort>' \
    python3 scripts/komodo-bootstrap.py
```

DNS bei IONOS: A-Records `hl`, `auth`, `home`, `komodo`, `notes`, `fitness`, `whoami`
auf die VPS-IP (oder `*.hl` auf die VPS-IP).

## 8. `[W]` Home Assistant

Die VM 201 entsteht mit `tofu apply` und startet per `onboot=1` mit dem Host. Erststart
im Browser: `http://<dhcp-ip>:8123` → Owner anlegen, Sprache/Zeitzone setzen.

Watchdog scharfschalten (einmalig):

```bash
[P] pveum role add Hawatch -privs "VM.Audit VM.PowerMgmt"
[P] pveum user token add tofu@pve hawatch --privsep 0    # -> "value"
[P] pveum acl modify /vms/201 -t 'tofu@pve!hawatch' -role Hawatch

[W] PVE_TOKEN_SECRET='<value>' SECRETS_FILE=<pfad>/secrets.env \
    KOMODO_PASS='<Komodo-Admin-Passwort>' python3 scripts/komodo-bootstrap.py
```

Kontrolle, dass HA auf 8123 lauscht (nicht auf 80 — siehe `docs/troubleshooting.md`):

```bash
[P] qm guest exec 201 -- /bin/sh -c 'ha core info | grep -E "^(port|version)"'
```

## 9. Ergebnis

| Prüfung | Soll |
|---|---|
| `tofu state list` | 3 Ressourcen: VM 200, VM 201, LXC 220 (Template 9000 baut das Skript) |
| Komodo Stacks | 8 deployt, Status `running` |
| `https://hl.mehrwert.icu/` | 200, ohne Login |
| `https://home.hl.mehrwert.icu/` | 302 → authentik |
| `https://notes.` / `fitness.` / `whoami.` / `komodo.` | 302 → authentik |
| `https://auth.hl.mehrwert.icu/-/health/live/` | 200 |

## 10. Nicht im Git (bewusst)

| Datei | Inhalt | entsteht durch |
|---|---|---|
| `tofu/nodes.auto.tfvars` | API-Token, SSH-Key-Pfad | Schritt 4, von Hand |
| `tofu/terraform.tfstate*` | State | `tofu apply` |
| `stacks/komodo/.env` | Admin-/DB-/JWT-Passwörter | Schritt 5, Zufallswerte |
| `stacks/komodo/secrets.env` | `AK_*`, `SPARKY_*`, `DOMAIN`, `RATHOLE_*`, `PVE_*` | Schritt 5 |
| `stacks/edge/.env`, `stacks/authentik/.env` | ACME-/DB-Zugänge | aus `*.env.example` |

Vor jedem Push:

```bash
[W] git grep -nE 'BEGIN .*PRIVATE KEY|token_secret *= *"[A-Za-z0-9]|PASSWORD=[^<]'
```
