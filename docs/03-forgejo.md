# Forgejo 16.0.6 als Container auf `hl01`

| | |
|---|---|
| Gast | LXC **110** `forgejo` auf `hl01` (192.168.181.50) |
| Adresse | **http://192.168.181.51** (nginx :80 → Forgejo :3000) |
| Git-SSH | `ssh://git@192.168.181.51:2222/<owner>/<repo>.git` |
| Ressourcen | 2 vCPU, 2 GB RAM, 24 GB Disk (unprivileged, `nesting=1`, `onboot=1`) |
| Daten | SQLite (`/var/lib/forgejo/forgejo.db`), Repositories unter `/var/lib/forgejo/repositories` |

## Container

```bash
pveam download local debian-13-standard_13.6-1_amd64.tar.zst
pct create 110 local:vztmpl/debian-13-standard_13.6-1_amd64.tar.zst \
  --hostname forgejo --cores 2 --memory 2048 --swap 512 --rootfs local-lvm:24 \
  --net0 name=eth0,bridge=vmbr0,ip=192.168.181.51/21,gw=192.168.178.1 \
  --nameserver 192.168.178.1 --features nesting=1 --unprivileged 1 --onboot 1 --start 1
```

## Installation (alles über `pct exec`, ohne Konsolen-Interaktion)

1. Pakete: `git curl ca-certificates nginx openssh-client xz-utils`
2. Systembenutzer `git` (`--system --shell /bin/bash --group --disabled-password --home /home/git`),
   `ssh-keygen -A` für die Hostschlüssel des eingebauten SSH-Servers.
3. **Release-Binary** `forgejo-16.0.6-linux-amd64` von `code.forgejo.org` inkl. `.sha256` geladen,
   Prüfsumme verifiziert, nach `/usr/local/bin/forgejo` installiert.
4. Verzeichnisse `/etc/forgejo`, `/var/log/forgejo`, `/var/lib/forgejo/{repositories,lfs,avatars,attachments,…}`;
   `app.ini` gehört dem Benutzer `git` und ist für ihn **schreibbar** (Forgejo ergänzt beim ersten Start
   `INTERNAL_TOKEN` selbst).
5. `app.ini` (Auszug): `RUN_USER = git`, `WORK_PATH = /var/lib/forgejo`, `[server] HTTP_ADDR = 127.0.0.1`,
   `HTTP_PORT = 3000`, `ROOT_URL = http://192.168.181.51/`, `START_SSH_SERVER = true`,
   `SSH_LISTEN_PORT = SSH_PORT = 2222`, `LFS_START_SERVER = true`, `[database] DB_TYPE = sqlite3`,
   `[service] DISABLE_REGISTRATION = true`, `[security] INSTALL_LOCK = true`.
6. systemd-Unit `forgejo.service` (`forgejo web --config /etc/forgejo/app.ini`, User `git`,
   `ProtectSystem=strict` + `ReadWritePaths=/etc/forgejo /var/lib/forgejo /var/log/forgejo /home/git`,
   `Restart=always`).
7. nginx-Vhost auf Port 80 als Reverse Proxy auf `127.0.0.1:3000` (`client_max_body_size 512M`,
   `X-Forwarded-*`-Header), Default-Site entfernt.
8. Admin-Konto per CLI:
   `forgejo admin user create --admin --username falko --password «Passwort» --email … --must-change-password=false`.

## Stolpersteine (alle real aufgetreten)

1. **`forgejo generate secret INTERNAL_TOKEN` gibt in v16 nur einen gekürzten Platzhalter aus**
   (`eyJhbG…MvJv`). Wird dieser Wert in `app.ini` geschrieben, startet Forgejo nicht. Lösung:
   `INTERNAL_TOKEN` **weglassen** und von Forgejo selbst erzeugen und speichern lassen — dazu muss die
   `app.ini` dem Benutzer `git` gehören und schreibbar sein.
2. **`ProtectSystem=full`/`strict` ohne `ReadWritePaths` legt `/etc` read-only** → Forgejo bricht mit
   `generateSaveInternalToken() [F] Error saving internal token: open /etc/forgejo/app.ini: read-only file system`
   ab und läuft in eine Restart-Schleife (systemd gibt nach 5 Versuchen auf).
3. **`systemctl enable --now nginx` lädt einen bereits laufenden nginx nicht neu.** Nach dem Anlegen des Vhosts
   antwortete weiterhin die nginx-Default-Seite — mit HTTP **200** und ~615 Byte, was wie Erfolg aussieht.
   Ein `systemctl restart nginx` war nötig.
4. Port 22 im Container ist vom eigenen sshd belegt → der eingebaute Forgejo-SSH-Server nutzt **2222**
   (entsprechend lauten die Clone-URLs).

## Verifikation

* `systemctl is-active forgejo nginx` → `active`/`active`; `ss -tlnp` → `:80`, `127.0.0.1:3000`, `*:2222`
* `GET http://192.168.181.51/user/login` → **200** (12 kB Forgejo-Loginseite), `/api/v1/version` → `16.0.6`
* **HTTP-Git-Roundtrip:** Test-Repo per API angelegt → `git clone http://…/falko/smoke-test.git` →
  Commit → `git push` → Commit serverseitig über `GET /api/v1/repos/…/commits` bestätigt (SHA `988a79b`)
* **Git über SSH:** temporären Key per API registriert, `git clone ssh://git@192.168.181.51:2222/…` →
  Clone erfolgreich, danach Key und Test-Repo wieder gelöscht
* **`pct reboot 110`** → Forgejo und nginx kommen selbstständig wieder hoch, API antwortet
