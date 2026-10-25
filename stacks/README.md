# Stacks auf `docker01` (192.168.181.100)

Docker-Compose-Stacks für den Edge. Jeder Stack ist eigenständig, Secrets liegen in
einer lokalen `.env` (gitignored), die Konfiguration selbst ist im Git.

| Stack | Zweck | Ports / Adresse | Abhängig von |
|---|---|---|---|
| `edge/` | Traefik v3: HTTP→HTTPS, TLS, Routing über Docker-Labels, Dashboard | `:80`, `:443` | – |
| `authentik/` | Identity Provider (SSO, Proxy-Provider/Forward-Auth) + PostgreSQL + Redis | `https://auth.<DOMAIN>`; `127.0.0.1:9000` nur für Bootstrap | `edge` |
| `whoami/` | Testdienst, beweist Routing + SSO-Gate | `https://whoami.<DOMAIN>` | `edge`, `authentik` |
| `frp/` | Client-Seite des Tunnels zum öffentlichen VPS (frps dort) | ausgehend zu `<VPS>:7000` | `edge` |
| `komodo/` | Deployment-Plattform: Core + Periphery + MongoDB. Deployt `edge`, `authentik`, `whoami` aus `komodo/homelab.toml` | `https://komodo.<DOMAIN>` (eigener Login) | – (wird per `bootstrap-komodo.sh` gestartet) |

## Komodo als Einstiegspunkt (empfohlen)

Nach dem OpenTofu-Lauf ist `scripts/bootstrap-komodo.sh` der einzige verbleibende Schritt:

```bash
sudo git clone https://github.com/gkspart01-lgtm/homelab /opt/homelab
sudo bash /opt/homelab/scripts/bootstrap-komodo.sh
```

Der Ablauf steckt in `scripts/`:

1. `bootstrap-docker.sh` — Docker Engine + Compose
2. `stacks/komodo` hochfahren (Core, Periphery, MongoDB), UI auf `https://komodo.<DOMAIN>`
3. `komodo-bootstrap.py` — Secret-Variablen anlegen, Resource Sync `homelab` registrieren,
   Sync ausführen: Komodo legt Server `docker01` an und deployt `edge` → `authentik` → `whoami`
4. `authentik-bootstrap.py` — Proxy-Provider, Application, Embedded Outpost und
   `config.authentik_host` setzen, danach `docker restart authentik-server`

Ab dann gilt: **`komodo/homelab.toml` ist die Quelle der Wahrheit** für Server und Stacks.
Änderung = Commit + Sync (UI, `km x sync homelab` oder Git-Webhook). Die Secrets stehen als
Komodo-Variablen (`is_secret`) in der Datenbank, nicht im Repo; erzeugt und abgelegt in
`/root/.komodo-homelab-secrets.env` (chmod 600).

Zwei bewusste Entscheidungen:

- **Komodo-UI hängt nicht hinter authentik.** Komodo deployt authentik selbst — ein
  IdP-Ausfall darf den Zugang zum Reparaturwerkzeug nicht blockieren. Komodo hat eine
  eigene Anmeldung (`admin` + Passwort aus `stacks/komodo/.env`), die UI ist nur per TLS
  erreichbar.
- **`frp` ist deklariert, aber `deploy = false`.** Der Stack steht in `komodo/homelab.toml`,
  `bootstrap-komodo.py` überspringt ihn. Aktivieren, sobald die VPS-Seite geklärt ist:

  ```bash
  FRP_SERVER_ADDR=<vps> FRP_USER=hl FRP_TOKEN=<server-token> \
    python3 scripts/komodo-bootstrap.py     # legt die Variablen an
  # dann in komodo/homelab.toml bei [[stack]] name="frp" -> deploy = true, Sync ausführen
  ```

  Stand der VPS-Prüfung (212.227.139.254): `:7000` nimmt Verbindungen an, `:80` antwortet
  als frp-vhost (`404 page not found` ohne passenden Proxy), `:443` hat ein
  Let's-Encrypt-Zertifikat für `hl.mehrwert.icu` und liefert `502` (TLS-Terminator ohne
  erreichbares Backend). Ein Login mit dem User-Token aus `frps-tokens.toml`
  (`user = "hl"`, `ports = [8082]`, `domains = ["hl.mehrwert.icu"]`) wird mit
  *"token in login doesn't match token from configuration"* abgelehnt — der Server
  verlangt offenbar seinen globalen `auth.token`; die Port-/Domain-Zuordnung
  (`ports = [8082]`) muss ebenfalls geklärt werden.

## Reihenfolge (manuell, ohne Komodo)

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
DOMAIN=hl.mehrwert.icu APP_NAME=whoami python3 scripts/authentik-bootstrap.py
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

## Fallstricke, die Zeit gekostet haben

- **`AUTHENTIK_HOST` (nicht `AUTHENTIK_HOST_BROWSER`)**: Der *embedded* Outpost baut
  Browser-URLs gegen `AUTHENTIK_HOST`. Ohne die Variable (bzw. den Wert im
  Outpost-`config`) läuft der Login-Redirect auf `http://localhost/`.
  `AUTHENTIK_HOST_BROWSER` gilt nur für Standalone-Outposts.
- **`authentik_host` steht auch in der Outpost-Konfiguration in der Datenbank** und
  hat Vorrang. `scripts/authentik-bootstrap.py` setzt beide Stellen.

## Verifikation

```bash
# Kette: Redirect, Gate, Health, Login-Flow (braucht kein öffentliches DNS)
EDGE_IP=192.168.181.100 DOMAIN=hl.mehrwert.icu python3 scripts/smoke-test-edge.py

# frp-Tunnel: frps als Testserver lokal, echte Traefik-Ports bleiben unberührt
bash scripts/test-frp-tunnel.sh          # auf docker01 ausführen
```

TLS ist im Lab selbstsigniert (Traefik-Default). Let's Encrypt per DNS-01 (IONOS)
ist in `stacks/edge/traefik.yml` vorbereitet und wird aktiviert, sobald
`IONOS_API_KEY`/`IONOS_API_SECRET`/`ACME_EMAIL` in `edge/.env` stehen.

### Komodo

- **Periphery spricht TLS** (`ssl_enabled = true` per Default). Ein Server mit
  `http://periphery:8120` bleibt dauerhaft `NotOk`; richtig ist
  `https://periphery:8120` **plus** `insecure_tls = true` (Selbstsignat).
- **API-Form**: `POST /auth/login` mit `{"type":"LoginLocalUser","params":{...}}` liefert
  ein JWT; danach `Authorization: Bearer <jwt>` gegen `/read/*`, `/write/*`, `/execute/*`.
  Read-Endpunkte erwarten trotzdem einen JSON-Body (notfalls `{}`).
- **Variablen aktualisieren**: `CreateVariable` schlägt bei vorhandenem Namen fehl; der
  Update-Operation heißt `UpdateVariableValue` (nicht `UpdateVariable`).
- **Stack-Status kommt klein** (`running`), nicht `Running` — Statusvergleiche
  case-insensitiv schreiben.
- **Reihenfolge** über `after = [...]` in der Stack-Deklaration, Env pro Stack über
  `stack.config.environment` (wird als `.env` im `run_directory` geschrieben), Secrets per
  `[[VARIABLE]]` interpoliert.
- **Jede geschützte Domain braucht einen eigenen authentik-Provider** (hier `whoami`).
  Eine Domain ohne Provider bekommt vom Outpost keine Freigabe — beim Test der
  Komodo-UI sah das wie ein kaputter Reverse-Proxy aus (Antwort war die authentik-Seite).
