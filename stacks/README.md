# Stacks auf `docker01` (192.168.181.100)

Docker-Compose-Stacks für den Edge. Jeder Stack ist eigenständig, Secrets liegen in
einer lokalen `.env` (gitignored), die Konfiguration selbst ist im Git.

| Stack | Zweck | Ports / Adresse | Abhängig von |
|---|---|---|---|
| `edge/` | Traefik v3: HTTP→HTTPS, TLS, Routing über Docker-Labels, Dashboard | `:80`, `:443` | – |
| `authentik/` | Identity Provider (SSO, Proxy-Provider/Forward-Auth) + PostgreSQL + Redis | `https://auth.<DOMAIN>`; `127.0.0.1:9000` nur für Bootstrap | `edge` |
| `whoami/` | Testdienst, beweist Routing + SSO-Gate | `https://whoami.<DOMAIN>` | `edge`, `authentik` |
| `frp/` | Client-Seite des Tunnels zum öffentlichen VPS (frps dort) | ausgehend zu `<VPS>:7000` | `edge` |

## Reihenfolge

```bash
docker network create edge            # einmalig, von allen Stacks geteilt
cd edge      && cp .env.example .env  # DOMAIN setzen
             docker compose up -d
cd authentik && cp .env.example .env  # Secrets: openssl rand -base64 42
             docker compose up -d
cd whoami    && cp .env.example .env
             docker compose up -d
```

Danach die SSO-Erstkonfiguration (Provider + Application + Embedded Outpost):

```bash
# authentik-API über den localhost-Port (SSH-Tunnel vom Admin-Rechner aus):
ssh -f -N -L 19000:127.0.0.1:9000 debian@192.168.181.100
AUTHENTIK_URL=http://127.0.0.1:19000 \
AUTHENTIK_TOKEN=$(grep AUTHENTIK_BOOTSTRAP_TOKEN authentik/.env | cut -d= -f2) \
DOMAIN=hl0.mehrwert.icu APP_NAME=whoami python3 scripts/authentik-bootstrap.py
```

## Wie die Kette funktioniert

1. Anfrage an `https://whoami.<DOMAIN>` → Traefik-Router `whoami` mit Middleware
   `authentik@file`.
2. Traefik fragt den Embedded Outpost:
   `http://authentik-server:9000/outpost.goauthentik.io/auth/traefik`.
3. Ohne Sitzung antwortet der Outpost mit einem Redirect auf
   `https://auth.<DOMAIN>/application/o/authorize/...`; der Browser durchläuft den
   Login-Flow und kommt über
   `https://whoami.<DOMAIN>/outpost.goauthentik.io/callback` zurück.
4. Mit gültiger Sitzung liefert Traefik die Anfrage an `whoami` weiter und setzt die
   `X-authentik-*`-Header (Benutzer, Gruppen, E-Mail).

Deshalb braucht **jede** geschützte App zwei Router: den normalen Router und einen
zweiten für `PathPrefix(/outpost.goauthentik.io/)`, der auf den Outpost zeigt
(`authentik@file`, Priorität höher). Fehlt der zweite, schlägt der Callback fehl.

## Zwei Fallstricke, die Zeit gekostet haben

- **`AUTHENTIK_HOST` (nicht `AUTHENTIK_HOST_BROWSER`)**: Der *embedded* Outpost baut
  Browser-URLs gegen `AUTHENTIK_HOST`. Ohne die Variable (bzw. den Wert im
  Outpost-`config`) läuft der Login-Redirect auf `http://localhost/`.
  `AUTHENTIK_HOST_BROWSER` gilt nur für Standalone-Outposts.
- **`authentik_host` steht auch in der Outpost-Konfiguration in der Datenbank** und
  hat Vorrang. `scripts/authentik-bootstrap.py` setzt beide Stellen.

## Verifikation

```bash
# Kette: Redirect, Gate, Health, Login-Flow (braucht kein öffentliches DNS)
EDGE_IP=192.168.181.100 DOMAIN=hl0.mehrwert.icu python3 scripts/smoke-test-edge.py

# frp-Tunnel: frps als Testserver lokal, echte Traefik-Ports bleiben unberührt
bash scripts/test-frp-tunnel.sh          # auf docker01 ausführen
```

TLS ist im Lab selbstsigniert (Traefik-Default). Let's Encrypt per DNS-01 (IONOS)
ist in `stacks/edge/traefik.yml` vorbereitet und wird aktiviert, sobald
`IONOS_API_KEY`/`IONOS_API_SECRET`/`ACME_EMAIL` in `edge/.env` stehen.
