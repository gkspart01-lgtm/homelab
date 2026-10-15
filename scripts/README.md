# Skripte

Alle Skripte stammen aus dem tatsächlichen Aufbau und sind **sanitisiert**: Passwörter stehen als
`<ROOT-PASSWORT>` bzw. `<PASSWORT>`. Beim Nachbauen die Platzhalter ersetzen.

| Datei | Zweck | Ausführung |
|---|---|---|
| `build-answer.sh` + `pve-auto-install.sh` | Answer-File schreiben, Auto-Install-ISO bauen, VM 101 präparieren, installieren und bis zum automatischen Power-off warten | auf dem Ziel-Proxmox-Host als root |
| `forgejo-install.sh` | Forgejo 16.x: Binary laden+prüfen, Benutzer `git`, Verzeichnisse, `app.ini`, systemd-Unit, nginx-Vhost, Admin-Konto | im LXC-Container als root (`pct push` + `pct exec`) |
| `forgejo-fix.sh` | Nacharbeiten: `app.ini` dem Benutzer `git` geben, Unit mit `ProtectSystem=strict` + `ReadWritePaths`, nginx neu starten, Admin anlegen, verifizieren | im LXC-Container als root |
| `haos-vm.sh` | Home Assistant OS: Image prüfen/entpacken, VM mit UEFI (OVMF) + q35 anlegen, Disk auf 32 GB, GPT anpassen, starten | auf einem **UEFI-fähigen** Proxmox-Host als root |
| `pve-api.py` | Minimaler Proxmox-API-Client (Ticket-Auth) für Umgebungen, in denen nur die REST-API erreichbar ist | überall, Passwort via `PVE_PASSWORD` |
| `ha-console.sh` | Tastendrücke per QEMU-Monitor (`sendkey`) in die HAOS-Konsole senden und ein Bildschirmfoto zurückholen — nützlich, um in einer VM ohne SSH Kommandos wie `core info` abzusetzen | auf dem Proxmox-Host, der die HA-VM trägt |
