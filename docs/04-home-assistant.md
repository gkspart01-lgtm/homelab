# Home Assistant OS als VM

| | |
|---|---|
| Gast | VM **105** `homeassistant` auf dem **Host `pve`** (192.168.181.10) |
| System | Home Assistant OS **18.3** (offizielles `haos_ova-18.3.qcow2`) |
| Ressourcen | 2 vCPU, 2 GB RAM, 32 GB Disk, UEFI (OVMF) + q35, `onboot=1` |
| Adresse | **http://192.168.178.71:8123** (DHCP-Lease der Fritz!Box) |
| Zugang | Onboarding-Assistent beim ersten Aufruf (Eigentümer-Konto selbst anlegen) |

## Warum auf `pve` und nicht in `hl01`

Der erste Versuch war, HAOS **in der verschachtelten Proxmox-VM `hl01`** zu betreiben (zusammen mit Forgejo).
Das schlug fehl — und zwar nicht an HAOS, sondern am UEFI-Firmware-Stack der verschachtelten VM:

* `hl01` ist selbst ein Gast (PVE in einer VM). In diesem Gast läuft **OVMF nicht nutzbar**:
  eine VM mit `bios: ovmf` initialisiert dort nicht einmal den Grafikspeicher
  (Proxmox-Konsole zeigt dauerhaft „Guest has not initialized the display (yet)“, auch ohne Disk),
  verursacht **keinen einzigen Disk-Zugriff** (`/proc/diskstats` der VM-Platte blieb über 12 s unverändert)
  und hängt mit ~100 % vCPU in einer Endlosschleife.
* HAOS-Images (`haos_ova-*.qcow2` **und** `haos_generic-x86-64-*.img`) sind **UEFI-only** — im
  MBR-Bereich liegt kein BIOS-Bootloader (`sgdisk -p` zeigt eine EFI-Systempartition, keinen `EF02`-Eintrag;
  im ersten MB finden sich nur FAT-Bootsektor-Meldungen). SeaBIOS kann sie also nicht starten.
* Auf dem Host `pve` (nicht verschachtelt) funktioniert OVMF: eine Test-VM zeigt dort das
  `BdsDxe`-Firmware-Bild, und die HAOS-VM bootet bis `Booting 'Slot A (OK=1 TRY=1)'` →
  Kernel startet, DHCP-Lease, Dienst kommt hoch.

Kurz: **HAOS braucht funktionierendes UEFI; in der verschachtelten PVE-VM ist das nicht gegeben.**
Deshalb läuft Home Assistant auf dem Host `pve`; `hl01` bleibt der Platz für BIOS-bootbare Gäste (z. B. Forgejo).

## Aufbau (Host `pve`)

```bash
cd /var/lib/vz/template/iso
curl -fsSLO https://github.com/home-assistant/operating-system/releases/download/18.3/haos_ova-18.3.qcow2.xz
xz -t haos_ova-18.3.qcow2.xz && unxz -k haos_ova-18.3.qcow2.xz
qemu-img info haos_ova-18.3.qcow2        # qcow2, virtuelle Größe 32 GiB

qm create 105 --name homeassistant --ostype l26 --machine q35 --bios ovmf \
  --memory 2048 --cores 2 --cpu host --scsihw virtio-scsi-single \
  --efidisk0 local-lvm:0,efitype=4m,pre-enrolled-keys=0 \
  --net0 virtio,bridge=vmbr0 --agent enabled=1 --onboot 1 --serial0 socket \
  --scsi0 local-lvm:0,import-from=/var/lib/vz/template/iso/haos_ova-18.3.qcow2 \
  --boot order=scsi0

qm resize 105 scsi0 32G
sgdisk -e /dev/pve/vm-105-disk-1      # Backup-GPT ans Diskende (GPT passt sonst nicht zur Größe)
qm start 105
```

Wichtig bei HAOS: das Image bringt seine Partitionen (hassos-boot, kernel0/1, system0/1, bootstate,
overlay, data) mit einer **kleinen** GPT mit; die Datenpartition wird von HAOS beim ersten Start auf die
Diskgröße erweitert. Deshalb vor dem ersten Start auf 32 GB vergrößern und die GPT konsistent ziehen.

## Inbetriebnahme

1. VM starten, ~2–5 Minuten warten. HAOS zieht beim ersten Start den Home-Assistant-Core-Container
   aus dem Internet (dauert eine Weile), erst danach öffnet Port 8123.
2. IP ermitteln: DHCP-Lease am Router **oder** MAC aus `qm config 105 | grep net0`
   (`BC:24:11:94:77:EB`) im ARP-Cache suchen.
3. `http://<ip>:8123` aufrufen → Onboarding: Name, Benutzer, Passwort, Standort festlegen.

## Raum für Verbesserungen

* **Feste IP** statt DHCP: im HA-Web-UI unter *Einstellungen → System → Netzwerk* setzbar, oder über die
  HA-CLI `ha network update`. Alternativ eine DHCP-Reservierung in der Fritz!Box für die VM-MAC.
* **RAM** ist auf dem Host knapp (8 GB gesamt, `hl01` belegt 4 GB). Bei Bedarf HA auf 4 GB erhöhen und
  `hl01` dafür auf 3 GB reduzieren (`qm set 101 --memory 3072`).
* Die bestehende Home-Assistant-Instanz im Netz (192.168.180.20) bleibt unangetastet — bei Bedarf lässt sich
  in der neuen Instanz ein **Backup** der alten einspielen (Einstellungen → System → Backups).
