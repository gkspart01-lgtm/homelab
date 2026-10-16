# IaC: vier Ebenen, kein Ansible, kein Kubernetes

Ziel: "Server verloren" ist ein Vorgang von ~2 Stunden, nicht ein verlorenes Wochenende.
Deshalb ist jede Ebene zustandsbehaftet, versioniert und einzeln ausfuehrbar.

| Ebene | Werkzeug | Datei/Ort | Was sie leistet |
|---|---|---|---|
| 0 Host | Proxmox-Auto-Install-ISO + Answer-File + Bootstrap | `hosts/spectre-x360/` | nackte Hardware → laufender PVE-Host mit Timern, API-Token, USB-/Thermik-Tuning |
| 1 Infrastruktur | **OpenTofu** (`bpg/proxmox`) | `tofu/` | VMs/LXC deklarativ, `plan` vor `apply`, RAM-Budget als Output |
| 2 Gäste | **cloud-init** + Debian-13-Template | `cloud-init/` | Benutzer, SSH-Key, IP, DNS, Hostname beim ersten Boot |
| 3 Dienste | **Docker Compose** + SOPS/age | `stacks/`, `secrets/` | ein Ordner pro Dienst, Secrets verschluesselt im Git |
| – Daten | `vzdump` + `restic` | `hosts/.../restic-backup.sh` | Backup/Restore, siehe `docs/10-backup.md` |

## Warum so und nicht anders
* **Kein Ansible**: Config-Management ohne eigenen Zustand fuehrt genau zu dem
  Verhalten, das dich an HomelabOS gestoert hat – es fasst Dinge an, die es nicht
  anfassen muesste. OpenTofu hat einen State: es weiss, was existiert, und
  `plan` zeigt jede Aenderung vorher. Der Rest ist cloud-init (einmal beim Boot)
  und Compose (idempotent).
* **Kein Kubernetes**: kein Quorum, kein Ingress-Controller-Zoo, kein CRD-Dschungel.
  Wenn irgendwann doch: `k3s` mit einer Node, nicht Talos.
* **SOPS+age** ist die richtige Wahl fuer ein Repo, das im Git liegt:
  Secrets sind im Diff lesbar-verschluesselt, der Schluessel bleibt offline.
  Aequivalent waere nur ein externer Secret-Store (Vault/OpenBao/Infisical) –
  fuer ein Ein-Personen-Homelab mehr Betrieb als Nutzen.

## Ablauf im Alltag
```bash
# neuer Dienst
mkdir stacks/monitoring && $EDITOR stacks/monitoring/compose.yaml
sops -e -i stacks/monitoring/.env        # verschluesselt speichern
git add -A && git commit -m "monitoring" && git push
scripts/deploy.sh monitoring

# neue VM
$EDITOR tofu/nodes.auto.tfvars           # Eintrag ergaenzen
cd tofu && tofu plan && tofu apply
```
* Vendor-neutral und ohne lokale Besonderheiten: keine Pfade ausserhalb des Repos,
  keine Handarbeit an `/etc` (was der Bootstrap setzt, ist im Skript dokumentiert).
* Der State (`terraform.tfstate`) bleibt auf dem Host und wird per restic
  gesichert. Wer ihn zusaetzlich im Git will: `sops -e terraform.tfstate > state.sops`.

## Migrationspfad (Laptop → neue Hardware)
1. Neuen Host installieren (Answer-File + Bootstrap aus `hosts/`).
2. `git clone` des Repos vom Forgejo, ggf. Forgejo selbst umziehen
   (`git clone --mirror` + `git push --mirror`, Datenverzeichnis per restic).
3. age-Key zurueckkopieren → `sops -d` funktioniert wieder.
4. Platten nach `docs/08-speicher.md` einhaengen, `/etc/snapraid.conf` uebernehmen.
5. `tofu apply` (Gaeste neu), dann `restic restore` der Daten, dann `deploy.sh` je Stack.
Was NICHT reproduzierbar ist, ist nur die Hardware selbst – alles andere ist Text.

## Testen der Reproduzierbarkeit (Anker + Lab)

Die Uebung findet in der Testumgebung statt, nicht auf dem Laptop – und sie wird
**wiederholt**, bis sie ohne Handarbeit durchlaeuft:

1. **Anker** – bare-Repo auf dem Proxmox-Host (`/root/git-anchor/homelab.git`,
   `git daemon` auf 9418). Er ist die Quelle, aus der ein frischer Host klont,
   auch wenn der Git-Host selbst gerade platt ist. Jeder Agent-Commit geht an
   Forgejo *und* in den Anker.
2. **Ziel** – die verschachtelte PVE-VM (`lab01`, VMID 101) ist der Stellvertreter
   des Laptops und wird pro Runde geloescht.
3. **Runde** – `lab/drill.sh` auf dem Anker-Host: Auto-Install-ISO bauen, VM frisch
   installieren, Bootstrap ausfuehren, Repo klonen, `tofu plan` in Produktions-
   groesse + `apply` in Laborgroesse, Pruefliste fahren, Ergebnis committen.

Grenze des Labors: 4 GB RAM im Ziel gegen 16 GB auf dem Laptop. Das Labor beweist
**Verfahren und Idempotenz**, die Produktionstarife laufen dort nur durch `plan`.
