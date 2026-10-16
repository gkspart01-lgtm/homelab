# Lab: die Testumgebung wiederholt plattmachen und neu aufsetzen

Ziel dieser Uebung: beweisen, dass der Aufbau reproduzierbar ist – **bevor** er auf
echter Hardware steht. Nicht "es hat einmal funktioniert", sondern "es funktioniert
jede Runde, nach Loeschen des Hosts, ohne Handarbeit".

## Rollen im Lab

| Rolle | Was | Lebensdauer |
|---|---|---|
| **Anker** | Proxmox-Host `pve` (192.168.181.10) mit bare-Repo `/root/git-anchor/homelab.git` + `git daemon` (git://192.168.181.10/homelab.git) | bleibt immer |
| **Git-Host** | Forgejo (Ziel: eigener LXC auf `pve`, damit er Lab-Wipes ueberlebt) | bleibt immer |
| **Ziel** | verschachtelte PVE-VM `lab01` (VMID 101, 2C/4G/200G) – Stellvertreter fuer den Laptop `hl0` | wird pro Runde geloescht |

**Regel:** kein Lab-Wipe, solange das Repo nicht im Anker *und* auf dem Git-Host liegt.
Der Ziel-Host klont in der Runde ausschliesslich aus dem Anker – Forgejo ist Komfort,
der Anker ist die Versicherung.

## Runde fahren

Alles laeuft auf `pve` als root, aus dem Arbeitsverzeichnis `/root/homelab-iac`
(dort klont sich der Host aus dem Anker):

```bash
ssh root@192.168.181.10
git -C /root/homelab-iac pull || git clone git://192.168.181.10/homelab.git /root/homelab-iac
cd /root/homelab-iac/lab
./drill.sh            # provision -> bootstrap -> deploy -> verify, Ergebnis in lab/results/
./drill.sh --keep     # Ziel am Ende NICHT loeschen (zum Debuggen)
```

Einzelschritte (auch einzeln nutzbar):

| Skript | Wirkung |
|---|---|
| `provision-target.sh` | Answer-File aus `hosts/spectre-x360/`, Auto-Install-ISO bauen, VM frisch anlegen, unbeaufsichtigt installieren, bis SSH laeuft |
| `bootstrap-target.sh` | `pve-bootstrap.sh` in den Ziel-Host bringen und ausfuehren (Repos, Deckel, Thermik, Timer, API-Token) |
| `deploy-target.sh` | im Ziel: Repo aus dem Anker klonen, aga-Key erzeugen, `tofu init/validate`, Produktions-`plan` + Labor-`apply` |
| `verify-target.sh` | harte Pruefliste (unten), schreibt `lab/results/<zeitstempel>.md` |
| `destroy-target.sh` | VM stoppen und loeschen |

## Was eine Runde beweist – und was nicht

**Bewiesen:** Host-Installation ohne Handarbeit, Bootstrap-Idempotenz, Klon aus dem
Anker, OpenTofu-Syntax und `plan` in Produktionsgroesse, `apply` in Laborgroesse,
Timers/Deckel/USB-Tuning, API-Token, RAM-Reserve als Output.

**Nicht bewiesen (ehrlich):** die *Groesse* des Zielsystems. Das Lab hat 4 GB RAM,
der Laptop 16. Die Produktionstarife (docker01 8 GB, haos 2 GB) laufen daher nur
durch `plan`, nicht durch `apply`. Der RAM-Flaschenhals wird erst auf dem Laptop
scharf – dort zeigt `tofu output ram_reserve_mb` sofort, was noch reinpasst.

**Noch offen im Lab:** VM-Gaeste (Klon aus dem Debian-Template 9000) brauchen erst
ein gebautes Template im Ziel-Host (Verfahren: `docs/01-proxmox-host.md`, Abschnitt
Cloud-Template). Bis dahin faehrt die Runde LXC-Gaeste.
