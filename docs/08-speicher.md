# Speicher: mergerfs + SnapRAID fuer gemischte USB-Platten

## Warum nicht RAID/ZFS
Du hast ~8 USB-Platten von 0,5 bis 8 TB, teils ohne eigenes Netzteil, teils 3,5".
Ein Striped/Pool-Verbund (RAID5/6, ZFS raidz) ueber USB hat drei Nachteile, die
genau dein Problem sind: Platten muessen (praktisch) gleich gross sein, ein
Verbund-Ausfall kostet **alles**, und ein USB-Reset mitten im Schreiben kann den
Pool unbrauchbar machen. SnapRAID+mergerfs dreht das um:

| Eigenschaft | Was sie dir bringt |
|---|---|
| keine Stripes, jede Platte eigenes ext4 | eine Platte allein ist im Notfall lesbar – Restore ohne Verbund |
| SnapRAID-Paritaet | Schutz gegen 1 (spaeter 2) Plattenausfall, nachtraeglich erweiterbar |
| gemischte Groessen | 0,5–8 TB mischen ist der Normalfall |
| Platten duerfen schlafen | leiser, kuehler, laenger haltbar |
| Sync ist ein Zeitplan, kein Dauerzustand | ein Unfall beim Schreiben korrumpiert nicht den ganzen Pool |

**Preis dafuer:** die Paritaetsplatte muss **mindestens so gross sein wie die
groesste Datenplatte** – sie traegt keinen Nutzplatz. Bei dir heisst das: die
groesste Platte (8 TB) wird Paritaet, alle anderen werden Daten.
Willst du sie als Nutzplatz, brauchst du eine zweite 8-TB-Platte als Paritaet.
Das ist die eine Entscheidung, die ich von dir brauche (Liste der Platten).

## Aufbau
```
/srv/parity   <-- groesste Platte,  ext4, enthaelt snapraid.parity
/mnt/disk1..n <-- Datenplatten,    ext4, je ein eigenes Dateisystem
/srv/pool     <-- mergerfs: /mnt/disk1:/mnt/disk2:... -> die Freigabe fuer Dienste
/srv/pool/backup/dump  <-- vzdump-Ziel (Backups liegen NICHT im SnapRAID-Pool)
```
* Platten in `/etc/fstab` **per UUID** mit `nofail,x-systemd.device-timeout=10`
  und eigener Mount-Reihenfolge; bei Ausfall darf der Host ohne die Platte booten.
* SnapRAID-Konfiguration: `hosts/spectre-x360/snapraid.conf.example`.
* Sync/Scrub laufen als systemd-Timer (vom Bootstrap angelegt): Sync taeglich
  04:30, Scrub sonntags 05:30 (`-p 8 -o 20` = 8 % der Daten pruefen).

## USB-Betrieb (der kritische Teil)
* **Aktiver USB-Hub mit Netzteil** ist Pflicht, sobald mehr als zwei Platten
  gleichzeitig laufen. 2,5"-Platten ohne eigenes Netzteil ziehen ihren Strom aus
  dem Port – mehrere davon an einem Hub = Abbrueche und Spannungseinbrueche.
* 3,5"-Platten nur mit eigenem Netzteil; Einschaltstromspitzen entzerren
  (`staggered spin-up`)/Platten nacheinander starten.
* **USB-Autosuspend aus** (macht `pve-bootstrap.sh` per Kernel-Cmdline,
  `usbcore.autosuspend=-1`) – sonst verschwinden Platten im Leerlauf.
* Kabel/Bridges: UASP-faehig (JMS578/ASM1153), keine No-Name-Bridges mischen.
* Der **Netzwerk-Adapter gehoert an USB-C/Thunderbolt**, die Platten an USB-A/Hub –
  so teilen sich NIC und Platten nicht denselben Controller.
* Pruefen: `smartctl -d sat -a /dev/sdX` (SMART kommt bei USB ueber die Bridge),
  `nvme smart-log /dev/nvme0` fuer die Systemplatte.

## Systemplatte (M.2)
* ext4 + LVM-Thin (Standard der PVE-Installation), **kein RAID** – es gibt nur
  einen M.2-Slot.
* Schutz kommt stattdessen von: `vzdump` der Gaeste auf den Pool, restic offsite,
  SnapRAID/`rsync` der Docker-Daten, und dem Rebuild per Auto-Install-ISO.
* Kontingent: 128-GB-SSDs sind zu klein fuer vorhandene Docker-Images + Paperless;
  sinnvoll ist eine 1-TB-NVMe (das Manual erlaubt bis 2 TB im einzelnen Slot).

## Datenklassen (was liegt wo)
| Klasse | Ort | Beispiel |
|---|---|---|
| Konfiguration/IaC | Git + restic | Compose-Stacks, `/etc/pve`, SnapRAID-Config |
| Datenbanken, Passworttresor | SSD (`/srv/ssd/...`) + Dump offsite | Vaultwarden, Immich-DB, Paperless-DB |
| Medien/Dokumente (viel) | mergerfs-Pool | Fotos, PDFs, Nextcloud-Dateien |
| Backup | Pool + Offsite + Offline-Platte | vzdump, restic, rotierende USB-Platte |
