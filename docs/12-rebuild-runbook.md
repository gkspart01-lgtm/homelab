# Runbook: Host wieder aufsetzen (Disaster Recovery)

Gilt fuer "Laptop tot / Platte defekt / alles neu". Zeitbedarf ~2 h, davon viel Wartezeit.
Reihenfolge einhalten – jeder Schritt liefert die Grundlage fuer den naechsten.

## 0. Vorher (einmalig, heute)
- [ ] `age`-Private-Key ausgedruckt/offline gesichert
- [ ] restic-Passwort offline gesichert (Passwortmanager + Papier)
- [ ] Answer-File mit echtem SSH-Key gefuellt und Auto-Install-ISO erzeugt
      (`hosts/spectre-x360/build-autoinstall-iso.sh`), ISO auf USB-Stick
- [ ] Repo-Bundle als Kopie: `git clone --mirror` → auf denselben USB-Stick
- [ ] Dieses Runbook ist Teil des Sticks, nicht nur im Git

## 1. Host installieren
1. USB-Stick booten → unbeaufsichtigt (`answer-file.toml`) | alternativ interaktiv installieren.
2. Nach dem automatischen Ausschalten: Stick abziehen, von der Platte booten.
3. SSH mit dem hinterlegten Key pruefen: `ssh root@<ip>`.

## 2. Host-Bootstrap
```bash
# Repo holen (Forgejo laeuft ggf. noch nicht -> Kopie vom Stick nehmen)
git clone <forgejo-url> /root/homelab-iac
bash /root/homelab-iac/hosts/spectre-x360/pve-bootstrap.sh \
     hl0.mehrwert.icu 192.168.178.10/24 192.168.178.1 192.168.178.1
```
Erledigt: Repos, Zeitzone/NTP, Deckel-zu ignorieren, Thermik/Governor,
USB-Autosuspend aus, SnapRAID-/vzdump-Timer, OpenTofu-API-Token.
(Reihenfolge beachten: die statische IP wird **zuletzt** gesetzt und bricht die
SSH-Sitzung ab.)

## 3. Schlüssel wiederherstellen
```bash
# entweder Offline-Kopie zurueckkopieren
install -d -m700 /root/.config/sops/age && cp keys.txt /root/.config/sops/age/keys.txt && chmod 600 /root/.config/sops/age/keys.txt
# oder neu erzeugen (dann .sops.yaml neu schreiben und alle Secrets neu verschluesseln)
bash /root/homelab-iac/scripts/age-init.sh
```
Gegenprobe: `sops -d /root/homelab-iac/secrets/<irgendwas>.sops | head`.

## 4. Speicher
1. Platten anschliessen (Netzteil-Platten zuerst, dann 2,5" am aktiven Hub).
2. `/etc/fstab` aus dem Repo uebernehmen (UUIDs pruefen: `blkid`).
3. `mount -a`, `df -h`, dann `/etc/snapraid.conf` uebernehmen und `snapraid status`.
4. Daten sind auf den Platten schon da (kein Striping!) – SnapRAID-Paritaet nur
   bei Verlust einer Datenplatte neu erzeugen (`snapraid -e` / `snapraid fix`).

## 5. Gäste und Dienste
```bash
cd /root/homelab-iac/tofu
cp nodes.auto.tfvars.example nodes.auto.tfvars   # Token aus /root/tofu-api-token.txt
tofu init && tofu plan && tofu apply            # ram_reserve_mb pruefen!
```
Dann die Zustandsdaten zurueckholen:
```bash
# restic-Env anlegen (Werte aus dem Passwortmanager)
cp /root/homelab-iac/hosts/spectre-x360/restic-env.example /root/.restic-env && chmod 600 /root/.restic-env
restic snapshots
restic restore latest --target /
```
Zuletzt je Stack: `scripts/deploy.sh <stack>`.

## 6. Verifikation (ohne Test ist es kein Rebuild)
- [ ] Proxmox-Web an Port 8006, alle Gaeste gruen
- [ ] `https://vault.hl0.mehrwert.icu` von aussen erreichbar, Zertifikat gueltig
- [ ] Login Vaultwarden mit dem eigenen Passwort (beweist DB-Restore)
- [ ] Immich/Paperless zeigen die alten Daten (Stichprobe, nicht nur "laeuft")
- [ ] `vzdump`-Timer hat gelaufen (`systemctl list-timers`), restic-Snapshot von heute
- [ ] einmal `restic restore` in ein Wegwerf-Verzeichnis, Ergebnis notieren (hier eintragen)
