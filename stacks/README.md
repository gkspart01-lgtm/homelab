# Stacks auf `docker01` (192.168.181.100)

Jeder Stack ist eigenständig; Konfiguration im Git, Secrets in `.env` (gitignored) bzw.
als Komodo-Variablen. Quelle der Wahrheit für „was läuft" ist `komodo/homelab.toml`.

| Stack | Zweck | Adresse / Zugriff |
|---|---|---|
| `edge/` | Traefik v3: HTTP→HTTPS, TLS, Routing per Docker-Label, Dashboard | `:80`, `:443` |
| `authentik/` | IdP, Proxy-Provider/Forward-Auth, PostgreSQL, Redis | `https://auth.<DOMAIN>` |
| `whoami/` | Testdienst für Routing + SSO | `https://whoami.<DOMAIN>` |
| `homepage/` | Dienstübersicht, zwei Instanzen (`config-public`, `config-private`) | `https://<DOMAIN>`, `https://home.<DOMAIN>` |
| `silverbullet/` | Notizen (Markdown), Volume `silverbullet_space` | `https://notes.<DOMAIN>` |
| `sparkyfitness/` | Ernährung/Fitness-Tracking (PostgreSQL + Server + Frontend v1.12.0) | `https://fitness.<DOMAIN>` |
| `rathole/` | Tunnel zum VPS (Noise, TCP) | ausgehend `:8443` |
| `hawatch/` | Watchdog für die HA-VM (Poll + PVE-Reboot) | intern |
| `komodo/` | Deployment-Plattform (Core, Periphery, MongoDB) | `https://komodo.<DOMAIN>` |
| `frp/` | frpc-Client — **geparkt** (`deploy = false`) | ausgehend `:7001` |

## Neue App

Vier Stellen, dann ein Sync:

1. `stacks/<name>/compose.yaml` — Router-Satz: `websecure` mit `authentik@file`, dazu
   `*-plain` auf `webplain` mit `tunnel-headers@file,authentik@file` und je ein
   `PathPrefix('/outpost.goauthentik.io/')`-Router mit Priorität 100.
2. `komodo/homelab.toml` — `[[stack]]` mit `deploy = true`, `after = ["edge", "authentik"]`,
   `run_directory`, `environment` (nur `[[VAR]]`, keine Literale).
3. `scripts/authentik-bootstrap.py` — `APPS` (`app:host`) und `APP_GROUPS` (`app:gruppe`)
   ergänzen, sonst hat niemand Zugriff.
4. `stacks/homepage/config-private/services.yaml` — Eintrag in der Übersicht.

```bash
cd /opt/homelab && sudo git pull
SECRETS_FILE=stacks/komodo/secrets.env python3 scripts/komodo-bootstrap.py
sudo docker restart authentik-server     # nur wenn sich authentik-Config geändert hat
curl -s -o /dev/null -w '%{http_code}\n' https://<name>.hl.mehrwert.icu/   # 302 = Gate greift
```

## Betrieb

- **Deploy:** Sync in der Komodo-UI, `km x sync homelab` oder Git-Webhook.
- **Secrets:** eine Datei, `stacks/komodo/secrets.env`; Komodo-Variablen werden daraus
  erzeugt. Nie zwei Quellen parallel pflegen.
- **Homepage-Inhalt:** YAML ändern → Commit → Sync; die Container lesen ihre Config ohne
  Neustart neu.
- **Tunnel:** Client-Config wird aus `[[RATHOLE_*]]` gerendert (`stacks/rathole/client.toml.template`).
- **Backups:** `docker run --rm -v <volume>:/s -v $PWD:/b alpine tar czf /b/<name>.tgz -C /s .`
  für alle Volumes mit Zustand (`silverbullet_space`, `authentik_authentik_pgdata`,
  `komodo_komodo_mongo_data`, `edge_traefik_acme`).

Fallstricke: `docs/troubleshooting.md`. Entscheidungen: `docs/decisions.md`.
