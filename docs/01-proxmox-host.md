# Der Proxmox-Host `pve` (192.168.181.10)

Ausgangslage: Der Agent läuft selbst in einem LXC-Container auf diesem Host und hat dort **keinen** `qm`/`pct`-CLI-Zugriff, sondern erreicht Proxmox ausschließlich über die REST-API auf Port 8006. Für Aufräum- und Dateiarbeiten am Host wurde zusätzlich ein SSH-Zugang als `root` hergestellt.

## Systemdaten

| | |
|---|---|
| Hostname / FQDN | `pve` / `pve.fritz.box` |
| IP / Netz | 192.168.181.10, LAN `192.168.176.0/21`, Gateway 192.168.178.1 |
| Proxmox VE | 9.2 (API-Release 9.2, `pve-manager` 9.2.x), Kernel 7.0.x-pve |
| CPU | Intel Core i7-8550U, **nested virtualization aktiv** (`/sys/module/kvm_intel/parameters/nested` = `Y`) |
| Storage | `local` (dir, ISO/Templates/Backup/Import), `local-lvm` (LVM-Thin im VG `pve`) |

Der Host ist selbst ein KVM-Gast — durch das aktivierte Nesting können aber auch die darin laufenden VMs/Container weiter virtualisieren (genau das nutzt `hl01`).

## Zugang, der eingerichtet wurde

1. **API mit Ticket-Auth** (Basis für alle Automatisierung):
   `POST https://192.168.181.10:8006/api2/json/access/ticket` mit `username=root@pam` und Passwort →
   Antwort enthält `ticket` (+ `CSRFPreventionToken`). Folgerequests brauchen `Cookie: PVEAuthCookie=<ticket>`,
   schreibende Zugriffe zusätzlich `CSRFPreventionToken`.
2. **SSH als root** für Dinge, die die API nicht kann (Dateien anlegen, ISOs bauen, ISOs anhängen):
   Der öffentliche Schlüssel `~/.ssh/id_ed25519.pub` des Agenten wurde in `/root/.ssh/authorized_keys` des Hosts eingetragen.
   Passwort-Login für `root` funktioniert ebenfalls — für nicht-interaktive Aufrufe wurde ein
   `SSH_ASKPASS`-Helfer benutzt.

## Gäste (Ausgangs- und Endstand)

| ID | Typ | Name | Zustand |
|---|---|---|---|
| 100 | LXC | `hermesagent` | läuft dauerhaft (192.168.178.56) — hier läuft der Agent |
| 101 | VM | `hl01` | Proxmox VE 9.2.2, siehe [02-proxmox-vm-hl01.md](02-proxmox-vm-hl01.md) |
| 9000 | VM | `debian13-cloud-template` | Template (kein Betrieb), siehe unten |

## Das Debian-13-Cloud-Template (VM 9000)

Weil für neue Debian-VMs ein wiederverwendbares, sauberes Template fehlte, wurde VMID **9000** als cloud-init-Template gebaut:

1. `debian-13-genericcloud-amd64.qcow2` (Debian 13.7 „trixie") über
   `POST /nodes/pve/storage/local/download-url` mit `content=import` samt **SHA512-Prüfsumme** in den
   Import-Ordner geladen.
2. VM erstellt mit `scsi0=local-lvm:0,import-from=local:import/…qcow2`, cloud-init-Laufwerk (`ide2`),
   `ciuser=debian`, `cipassword=«Passwort»`, `sshkeys=<prozentkodierter Public Key>`, `ipconfig0=ip=dhcp`,
   `agent=enabled=1,fstrim_cloned_disks=1`, `serial0=socket`, `vga=serial0`.
3. Disk auf 10 GB vergrößert, gebootet, per SSH `qemu-guest-agent` nachinstalliert
   (im Debian-*genericcloud*-Image **nicht** enthalten) und das Image „generalüberholt":
   `truncate -s 0 /etc/machine-id`, `/etc/ssh/ssh_host_*` gelöscht, `cloud-init clean --logs --seed`,
   apt-Caches/Logs/History geleert, `fstrim`.
4. Sauber über den Gast-Agent heruntergefahren und `POST /nodes/pve/qemu/9000/template` → Template.
5. **Getestet** durch einen vollständigen Full-Clone (VMID 102): Boot, Gast-Agent antwortet,
   Hostname = Klonname, frische machine-id, SSH mit hinterlegtem Key — danach wieder gelöscht.

### Stolpersteine dabei

- **`snippets` lassen sich nicht über die API hochladen** (Upload akzeptiert nur `iso`, `vztmpl`, `import`).
  Damit ist `cicustom=user=local:snippets/…` ohne Shell-Zugriff auf den Host nicht erreichbar.
  Lösung: `sshkeys` schon beim Erstellen mitgeben — die von Proxmox generierte cloud-init-Konfiguration
  legt den Key beim ersten Boot ab — und das Image danach per SSH fertigstellen.
- **`sshkeys` ist ein URL-kodierter String**: der Key muss vorher prozentkodiert werden
  (`urllib.parse.quote(key, safe="")`), sonst antwortet Proxmox mit `invalid urlencoded string`.
- Proxmox schreibt `ssh_pwauth: false` — Passwort-Login per SSH funktioniert in frischen Klonen nur,
  wenn das Image ihn selbst erlaubt (hier über eine Drop-in-Datei bzw. den SSH-Key gelöst).
