# Proxmox VE in einer VM: `hl01` (192.168.181.50)

Ziel war eine **virtuelle** Proxmox-VE-Instanz auf dem Host `pve`, auf der später Dienste als Container/VMs laufen
(u. a. Forgejo und Home Assistant). Bewusst eine VM und **kein** LXC, weil in der VM ein vollständiges
Proxmox mit eigenem Kernel, eigenem Netzwerk-Bridge und eigenen Guests laufen soll.

| | |
|---|---|
| VMID / Name | 101 / `hl01` |
| Host | `pve` (192.168.181.10) |
| Ressourcen | 2 vCPU, 4 GB RAM, 200 GB Disk (LVM-Thin), `virtio-scsi-single` |
| Netz | `net0` virtio auf `vmbr0`, statisch **192.168.181.50/21**, Gateway 192.168.178.1 |
| System | Proxmox VE 9.2.2, Kernel 7.0.2-6-pve, Storage `local` + `local-lvm` |

## Ausgangslage: der erste Versuch war gescheitert

Die VM existierte bereits, und es war schon einmal eine unbeaufsichtigte Installation über die
Proxmox-Auto-Installations-ISO (`proxmox-auto-install-assistant`) versucht worden. Dieser Versuch war
**fehlgeschlagen**: die VM hing seit Stunden in der Root-Shell der Installer-Umgebung
(`Installation aborted - unable to continue`), im Netz war sie nicht erreichbar.

Fehlerbild im Konsolen-Log:

```
INFO: Parsing answer file
INFO: File system selected: ext4
INFO: Setting up network configuration
ERROR: Installation failed: no filter defined
Auto-installation failed (exit-code 1)
Installation aborted - unable to continue (type exit or CTRL-D to reboot)
```

**Ursache:** Im Abschnitt `[network]` stand `source = "from-answer"` zusammen mit einem Netzwerkfilter in
veralteter Syntax (`filter = { "ID_NET_NAME_MAC" = "enx…" }`, zusätzlich mit der MAC-Adresse einer früheren
VM-Instanz). Diese Form wird von Proxmox 9 nicht mehr ausgewertet → der Installer findet kein Netzwerkgerät
und bricht ab, **bevor** er die Platte beschreibt.

## Der Weg, der funktioniert hat

### 1. Konsole ohne GUI auslesen
Auch ohne Bildschirm ließ sich der Zustand ermitteln: über den QEMU-Monitor des Hosts
(`echo "screendump /tmp/x.ppm" | qm monitor 101`) entsteht ein PPM-Screenshot, der sich (mit einem
30-zeiligen reinen Python-Skript) in PNG wandeln und dann auswerten lässt. Damit war die obige Fehlermeldung
sichtbar, ohne die VM jemals anzufassen.

### 2. Answer-File korrigiert
Neues `/root/hl01-answer.toml` auf dem Host ([scripts/hl01-answer.toml](../scripts/hl01-answer.toml)):

```toml
[global]
keyboard = "de"
country = "de"
fqdn = "hl01.fritz.box"
timezone = "Europe/Berlin"
root-password = "«Passwort»"
root-ssh-keys = ["ssh-ed25519 AAAA… hermes"]   # sofortiger SSH-Zugang zum fertigen System
reboot-mode = "power-off"                       # siehe Falle 1

[network]
source = "from-dhcp"                            # Netzwerk vom Installer übernehmen …

[disk-setup]
filesystem = "ext4"
disk-list = ["sda"]
```

Die statische IP wird **nach** der Installation gesetzt (Schritt 7) — das umgeht die Filter-Problematik
komplett. `validate-answer` prüfte die Datei, `inspect-iso` bestätigte sie anschließend im gebauten ISO.

### 3. Auto-Install-ISO bauen

```bash
proxmox-auto-install-assistant prepare-iso /var/lib/vz/template/iso/proxmox-ve_9.2-1.iso \
  --fetch-from iso --answer-file /root/hl01-answer.toml \
  --output /var/lib/vz/template/iso/hl01-auto3.iso
```

### 4. VM für die Installation präparieren

```bash
qm stop 101
dd if=/dev/zero of=/dev/pve/vm-101-disk-0 bs=1M count=64   # alte Bootloader/Partitionstabellen weg
qm set 101 --ide2 local:iso/hl01-auto3.iso,media=cdrom
qm set 101 --boot order=ide2                                 # ISO zuerst
qm start 101
```

### 5. Installation abwarten
Läuft unbeaufsichtigt durch (0 → 100 %, „installation finished") und **schaltet die VM am Ende selbst aus**
(`reboot-mode = "power-off"`). Beobachtet wurde der Fortschritt über den QEMU-Monitor (Screenshot) und den
Füllstand des Thin-Pools (`lvs pve/vm-101-disk-0`). Dauer: ca. 6–7 Minuten.

### 6. Von der Platte booten

```bash
qm set 101 --delete ide2          # ISO abhängen
qm set 101 --boot order=scsi0
qm start 101
```

### 7. Nacharbeiten im installierten System

| Schritt | Befehl / Änderung |
|---|---|
| Enterprise-Repos abschalten | `Enabled: false` in `/etc/apt/sources.list.d/pve-enterprise.sources` und `ceph.sources` |
| Freies Repo aktivieren | `pve-no-subscription.sources` (`download.proxmox.com/debian/pve`, trixie) und `ceph-no-subscription.sources` (`…/ceph-squid`, `no-subscription`) |
| Statische IP | in `/etc/network/interfaces` den `vmbr0`-Block auf `address 192.168.181.50/21` + `dns-nameservers 192.168.178.1`; `/etc/hosts` entsprechend; anwenden mit `nohup sh -c 'sleep 3; ifreload -a' &` (die SSH-Sitzung bricht dabei ab) |
| Gast-Agent | `apt-get install -y qemu-guest-agent`, danach am Host `qm set 101 --agent enabled=1,fstrim_cloned_disks=1` und VM neu starten |
| SSH-Zugang | `root-ssh-keys` aus dem Answer-File liegt bereits in `/root/.ssh/authorized_keys` |

## Fallen, die dokumentiert bleiben sollten

1. **`reboot-mode = "reboot"` zerstört die fertige Installation.** Nach dem Install bootet der Gast neu, SeaBIOS
   nutzt in *derselben* QEMU-Instanz weiter die alte Boot-Reihenfolge — das noch angehängte ISO gewinnt gegen
   die frische Platte und die Installation startet **erneut**, löscht die Platte und beginnt von vorn.
   Beobachtet wurden so mehrere Durchläufe in Folge, bis die Platte wieder halb installiert war.
   `power-off` + ISO abhängen + `boot order=scsi0` ist der zuverlässige Weg.
2. **`qm set --boot order=…` wirkt nicht auf ein laufendes QEMU.** Boot-Order/Bootindex werden nur beim
   Start (neu) gesetzt; man kann den Reboot nach der Installation damit **nicht** umlenken.
3. **Der alte Netzwerk-Filter (`filter = { … }` / `ID_NET_NAME_MAC`) ist in PVE 9.2 wirkungslos** und führt zu
   „no filter defined". Entweder `source = "from-dhcp"` verwenden oder die dokumentierte Punktschreibweise
   `filter.ID_NET_NAME_MAC = "enx…"` — und dann mit der **aktuellen** MAC der VM.
4. **`agent: enabled=1` in der Config heißt nicht, dass der Agent läuft.** Nur ein Aufruf wie
   `GET …/agent/get-osinfo` beweist es (`HTTP 500 QEMU guest agent is not running` als Gegenprobe).
   Nachträgliches Setzen auf einer laufenden VM wird **nicht** hotplugged — VM neu starten.
5. **Nachinstallieren des Agenten ist Pflicht**: das Debian-*genericcloud*-Image enthält `qemu-guest-agent` nicht
   (nachprüfbar über die Paketliste im `…-genericcloud-amd64.json` des Image-Releases).
6. **Enterprise-Repo ab Werk aktiv:** `apt update` scheitert auf einem frisch installierten PVE ohne
   Subscription mit `401 Unauthorized` — ohne Umstellung der Repos lässt sich danach kein Dienst installieren.

## Betrieb

```bash
# Ressourcen ändern (Neustart der VM nötig)
qm set 101 --memory 8192 --cores 4

# Konsole/Status vom Host aus
qm status 101 ; qm terminal 101        # bzw. im Web-UI: https://192.168.181.50:8006
qm monitor 101                         # QEMU-Monitor, u. a. "screendump /tmp/x.ppm"

# Installation reproduzieren
/root/hl01-answer.toml        # Answer-File
/root/hl01-auto3.iso  … bzw.  /var/lib/vz/template/iso/hl01-auto3.iso
```

Belegung: 2 von 200 GB belegt am Anfang — `local-lvm` in der VM hatte danach ~116 GB frei für Container und VMs.
