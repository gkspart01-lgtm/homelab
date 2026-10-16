# Backup und Disaster Recovery: 3-2-1 mit Bordmitteln

Regel: **RAID/SnapRAID ist kein Backup.** SnapRAID schuetzt gegen den Ausfall
einer Platte, nicht gegen Loeschen, Verschlüsselungstrojaner oder einen
Blitzschlag, der Host und Platten gleichzeitig erwischt.

## Die drei Ebenen
| Ebene | Was | Wohin | Wie oft |
|---|---|---|---|
| 1 – schnell | `vzdump` aller VMs/LXC (zstd, Snapshot, keep-daily 7/weekly 4) | HDD-Pool `/srv/pool/backup/dump` | taeglich 03:15 (Timer) |
| 2 – offsite | `restic` (verschluesselt, dedupliziert): `/etc`, `/etc/pve`, IaC-Repo, DB-Dumps | IONOS Object Storage (S3) **oder** Hetzner Storage Box | taeglich 02:30 |
| 3 – offline | eine USB-Platte rotierend, ausser Betrieb aufbewahrt | Schrank | monatlich |

* Ebene 1 heilt "ich habe ein `tofu apply` verbockt" in Minuten.
* Ebene 2 heilt "der Laptop ist weg".
* Ebene 3 heilt "der Account/das Netzwerk ist auch weg" (kein Online-Kanal).

## Was in jedes Backup gehoert
1. `/etc/pve` (alle Gastdefinitionen) – im Restore-Fall die halbe Miete.
2. IaC-Repo (`/root/homelab-iac`) – inklusive `tofu/terraform.tfstate`.
3. **age-Private-Key** (`/root/.config/sops/age/keys.txt`) – ohne ihn ist das
   Repo-Restore wertlos. Gehoert ausgedruckt/offline, nicht nur ins restic.
4. Datenbank-Dumps (Vaultwarden, Paperless, Immich, Nextcloud) als Dump, nicht
   als kopierte DB-Datei.
5. `/root/.restic-env` (Klammer: enthaelt das restic-Passwort – siehe Notiz unten).

## Restic-Ziel
* IONOS Object Storage ist S3-kompatibel und damit restic-tauglich; Hetzner
  Storage Box ist meist guenstiger. Beides ist ok – pruefe Preis/Region und
  trage es in `hosts/spectre-x360/restic-env.example` ein.
* Wichtig: **restic-Passwort** getrennt vom Host aufbewahren (Passwortmanager +
  Papier). Ein verschluesseltes Backup ohne Passwort ist Datenverlust mit Extraschritten.

## Restore-Test (gehoert einmal wirklich gemacht)
1. `restic snapshots --last`, `restic restore latest --target /tmp/restore-check`
   – und eine der DB-Dumps wirklich in eine Wegwerf-Datenbank einspielen.
2. `vzdump`-Datei einmal per `qmrestore`/`pct restore` zurueckholen.
3. Ergebnis ins Repo schreiben (`docs/12-rebuild-runbook.md`, Abschnitt Verifikation).
Ohne diesen Test ist es kein Backup, sondern eine Hoffnung.

## Bewusst nicht in Phase 1
**Proxmox Backup Server**: dedupliziert und inkrementell, braucht aber ~2 GB RAM
und eigenen Datastore. Sobald der zweite Rechner steht, wird PBS dorthin
verlagert (dann auch mit S3-Datastore moeglich) und `vzdump` kann entfallen.
