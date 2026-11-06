# Entscheidungen

Kurz, eine Entscheidung pro Abschnitt: Kontext → Entscheidung → Folge. Was nicht hier
steht, ist Detail in `stacks/README.md` oder `docs/troubleshooting.md`.

## ADR-1 Komodo als Deployment-Plattform

**Kontext:** Nach OpenTofu bleiben ~8 Compose-Stacks, die irgendwo gestartet und
aktualisiert werden müssen.
**Entscheidung:** Komodo (Core + Periphery + MongoDB) als einziger Einstieg. Die Stacks
stehen in `komodo/homelab.toml`; Reihenfolge über `after`, Secrets als Komodo-Variablen.
**Folge:** Ein `bootstrap-komodo.sh` nach Tofu, danach ist „Datei ändern → Commit → Sync"
der komplette Deployment-Weg. Preis: ein weiterer Dienst mit eigener Datenbank, der
selbst nicht von Komodo verwaltet wird.

## ADR-2 authentik als IdP

**Kontext:** Dienste ohne eigenes Login brauchen ein Gate; Familienmitglieder sollen
nicht für jede App ein Konto bekommen.
**Entscheidung:** authentik mit Proxy-Provider/Forward-Auth, eingebettetem Outpost und
Gruppen-Policies. Tinyauth wäre nur eine Login-Wand ohne Gruppen und ohne OIDC,
Authelia hätte Datei-Policies statt UI und API.
**Folge:** Zwei zusätzliche Container (Server, Worker) plus PostgreSQL/Redis; dafür
Rechteverwaltung komplett per API reproduzierbar (`scripts/authentik-bootstrap.py`).

## ADR-3 rathole statt frp

**Kontext:** Der VPS lief bereits mit `frps` + frps-panel; der Client-Login scheiterte
dauerhaft an der Panel-Anbindung (`send Login request to plugin error`), unabhängig von
Token, Port oder Proxy-Typ.
**Entscheidung:** rathole (Noise-Control-Channel) auf Port 8443, Server auf dem VPS,
Client als Container auf `docker01`.
**Folge:** Öffentliche Erreichbarkeit ohne Panel-Abhängigkeit, dafür ohne
Multi-Tenant-Verwaltung. Der frp-Stack bleibt deklariert (`deploy = false`) und
dokumentiert, falls der VPS später doch auf frp umgestellt wird.

## ADR-4 Home Assistant als VM, nicht als Container

**Kontext:** HAOS-Images sind UEFI-only; im verschachtelten PVE (`hl01`) initialisiert
OVMF nicht (schwarzer Schirm, 0 Disk-I/O, 100 % vCPU).
**Entscheidung:** HAOS als eigene VM 201 auf `pve2` (q35 + OVMF + EFI-Disk), per
Image-Import in `tofu/haos.tf`, nicht als Compose-Container.
**Folge:** HA ist kein Komodo-Stack; Autostart über `onboot=1` plus Watchdog-Container
(ADR-6). Ein Container wäre kein echtes HAOS (kein Supervisor, keine Add-ons).

## ADR-5 Zugriff über Gruppen statt „jeder darf alles"

**Kontext:** Ein SSO-Gate für alle Apps bedeutet, dass jeder Benutzer jede App öffnet.
**Entscheidung:** Zwei Gruppen — `homelab-admins` (alles) und `homelab-users`
(Übersicht, Notizen, whoami). Je App eine Expression-Policy + `PolicyBinding`;
`akadmin` wird automatisch Admin-Mitglied.
**Folge:** Neue Benutzer ohne Gruppe sehen „You do not have access". Verwaltung in
`docs/access-control.md`.

## ADR-6 Watchdog für VMs statt Orchestrator

**Kontext:** Komodo startet Container, keine VMs. Ein hängendes HA soll trotzdem ohne
Handarbeit zurückkommen.
**Entscheidung:** `hawatch` (Alpine-Container) pollt `:8123`, rebootet nach drei
Fehlversuchen per PVE-API und hält eine Stunde Abkühlzeit. Token nur mit
`VM.Audit`/`VM.PowerMgmt` und ACL auf `/vms/201`.
**Folge:** Kein Reboot-Loop, aber auch keine Heilung von Fehlkonfiguration — dann
rebootet er im Stundentakt, bis jemand die Ursache behebt.

## ADR-7 Ein Docker-Host, keine VM pro Dienst

**Kontext:** Zielhardware hat 16 GB RAM; jede VM kostet 2 GB Grundlast.
**Entscheidung:** Ein Debian-VM (`docker01`) für alle Compose-Dienste. Eigene VMs nur,
wenn der Dienst ein eigenes Betriebssystem verlangt (HAOS) — LXC für Dienste wird nicht
verwendet.
**Folge:** Dienste teilen sich Kernel und Docker-Daemon; Ausfälle treffen alle
Container gleichzeitig.

## ADR-8 Komodo hinter authentik, mit Notausgang

**Kontext:** Falko will ein SSO für alles, auch für die Deployment-UI.
**Entscheidung:** Komodo-Router mit `authentik@file`, Gruppe `homelab-admins`.
**Folge:** Wenn authentik ausfällt, ist auch Komodo nicht erreichbar. Deshalb bleibt
`127.0.0.1:9120` als SSH-Tunnel erreichbar:
`ssh -L 9120:127.0.0.1:9120 debian@192.168.181.100`.
