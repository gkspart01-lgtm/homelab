# Zielhost: HP Spectre x360 13-ae043ng ("hl0")

| | |
|---|---|
| CPU | Intel Core i7-8550U (4C/8T, Kaby Lake R, QuickSync) |
| RAM | 16 GB **fest verlötet** – kein Aufrüsten möglich |
| Disk | 1× M.2 2280 (NVMe), **kein** weiterer M.2- und **kein** SATA-Port |
| Netz | **kein RJ45**: 2× USB-C/Thunderbolt 3 + 1× USB 3.1-A → GbE per Adapter |
| Besonderheit | Akku = Mini-USV; Deckel zu muss ignoriert werden |

Dateien:
* `pve-bootstrap.sh` – nach der PVE-Installation ausführen (Repos, Deckel, Thermik, Timer, API-Token)
* `answer-file.toml.example` + `build-autoinstall-iso.sh` – Wiederaufbau per USB-Stick
* `snapraid.conf.example` – Speicher-Pool
* `restic-env.example` + `restic-backup.sh` + `systemd/` – Offsite-Backup
