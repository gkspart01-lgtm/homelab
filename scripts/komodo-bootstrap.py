#!/usr/bin/env python3
"""Komodo-Erstkonfiguration: Variablen, Resource Sync, Deploy — alles per API.

Nach `stacks/komodo` up ist das der einzige Schritt, damit Komodo den Rest
(edge, authentik, whoami) aus `komodo/homelab.toml` aufbaut.

Idempotent: vorhandene Variablen/Syncs werden aktualisiert.

Aufruf (auf docker01 oder per SSH):
  KOMODO_PASS=$(grep KOMODO_INIT_ADMIN_PASSWORD stacks/komodo/.env | cut -d= -f2) \
  DOMAIN=hl.mehrwert.icu python3 scripts/komodo-bootstrap.py

Optionen (Umgebung):
  KOMODO_URL      default http://127.0.0.1:9120
  KOMODO_USER     default admin
  KOMODO_PASS     Pflicht
  SECRETS_FILE    default ~/.komodo-homelab-secrets.env (wird angelegt, chmod 600)
  PANE            default homelab (Name des Resource Sync)
  REPO            default gkspart01-lgtm/homelab
  SYNC_FILE       default komodo/homelab.toml
  WAIT            default 900 (Sekunden auf laufende Stacks warten)
"""
import json
import os
import pathlib
import secrets
import sys
import time
import tomllib
import urllib.error
import urllib.request

URL = os.environ.get("KOMODO_URL", "http://127.0.0.1:9120").rstrip("/")
USER = os.environ.get("KOMODO_USER", "admin")
PASS = os.environ.get("KOMODO_PASS", "")
DOMAIN = os.environ.get("DOMAIN", "hl.mehrwert.icu")
SECRETS_FILE = pathlib.Path(
    os.environ.get("SECRETS_FILE", os.path.expanduser("~/.komodo-homelab-secrets.env"))
)
SYNC_NAME = os.environ.get("SYNC_NAME", "homelab")
REPO = os.environ.get("REPO", "gkspart01-lgtm/homelab")
SYNC_FILE = os.environ.get("SYNC_FILE", "komodo/homelab.toml")
WAIT = int(os.environ.get("WAIT", "900"))

JWT = ""


def api(path, body=None, method="POST"):
    # Komodo-Read-Endpunkte erwarten einen (ggf. leeren) JSON-Body
    data = json.dumps(body if body is not None else {}).encode()
    req = urllib.request.Request(f"{URL}{path}", data=data, method=method)
    req.add_header("Content-Type", "application/json")
    if JWT:
        req.add_header("Authorization", f"Bearer {JWT}")
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            raw = resp.read().decode()
            return resp.status, (json.loads(raw) if raw.strip() else None)
    except urllib.error.HTTPError as e:
        raw = e.read().decode()
        try:
            return e.code, json.loads(raw)
        except Exception:
            return e.code, raw[:400]


def login():
    global JWT
    for _ in range(30):
        st, res = api("/auth/login", {"type": "LoginLocalUser",
                                      "params": {"username": USER, "password": PASS}})
        if st == 200 and isinstance(res, dict):
            JWT = res["data"]["jwt"]
            print("Login ok")
            return
        time.sleep(5)
    sys.exit(f"Login fehlgeschlagen (letzte Antwort: {st} {res})")


def load_secrets():
    """Secrets aus Datei lesen oder erzeugen und ablegen."""
    values = {}
    if SECRETS_FILE.exists():
        for line in SECRETS_FILE.read_text().splitlines():
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                values[k.strip()] = v.strip()
    wanted = {
        "DOMAIN": DOMAIN,
        "AK_ADMIN_EMAIL": f"admin@{DOMAIN}",
        "AK_DB_PASS": secrets.token_hex(24),
        "AK_SECRET_KEY": secrets.token_urlsafe(48),
        "AK_ADMIN_PASS": secrets.token_urlsafe(18),
        "AK_BOOTSTRAP_TOKEN": secrets.token_hex(32),
    }
    # Explizit gesetztes DOMAIN gewinnt gegen den Wert aus der Secrets-Datei
    if os.environ.get("DOMAIN") and values.get("DOMAIN") != os.environ["DOMAIN"]:
        values["DOMAIN"] = os.environ["DOMAIN"]
        wanted["DOMAIN"] = os.environ["DOMAIN"]
        wanted["AK_ADMIN_EMAIL"] = f"admin@{os.environ['DOMAIN']}"
    changed = False
    for k, default in wanted.items():
        if not values.get(k) or k in ("DOMAIN", "AK_ADMIN_EMAIL"):
            values[k] = default
            changed = True
    if changed:
        SECRETS_FILE.parent.mkdir(parents=True, exist_ok=True)
        SECRETS_FILE.write_text(
            "# von scripts/komodo-bootstrap.py erzeugt — NICHT committen\n"
            + "\n".join(f"{k}={v}" for k, v in values.items())
            + "\n"
        )
        SECRETS_FILE.chmod(0o600)
        print(f"Secrets geschrieben: {SECRETS_FILE}")
    return values


def set_variable(name, value, secret):
    """Variable anlegen; existiert sie schon, Wert setzen (Komodo-API: UpdateVariableValue)."""
    st, res = api("/write/CreateVariable", {"name": name, "value": value, "is_secret": secret})
    if st == 200:
        return "angelegt"
    st2, res2 = api("/write/UpdateVariableValue", {"name": name, "value": value})
    if st2 in (200, 304):
        return "aktualisiert" if st2 == 200 else "unveraendert"
    print(f"  WARNUNG Variable {name}: create={st} update={st2} {str(res2)[:160]}")
    return "fehler"


def ensure_sync():
    st, syncs = api("/read/ListResourceSyncs")
    existing = next((s for s in (syncs or []) if s["name"] == SYNC_NAME), None)
    config = {
        "git_provider": "github.com",
        "git_https": True,
        "repo": REPO,
        "branch": "main",
        "git_account": "",
        "resource_path": [SYNC_FILE],
        "managed": False,
        "delete": False,
        "webhook_enabled": False,
        "match_tags": [],
    }
    if existing:
        st, res = api("/write/UpdateResourceSync",
                      {"id": existing["id"], "config": config})
        print(f"Resource Sync '{SYNC_NAME}' aktualisiert: {st}")
        return
    st, res = api("/write/CreateResourceSync", {"name": SYNC_NAME, "config": config})
    if st != 200:
        sys.exit(f"Resource Sync anlegen fehlgeschlagen: {st} {res}")
    print(f"Resource Sync '{SYNC_NAME}' angelegt")


def run_sync():
    st, res = api("/execute/RunSync", {"sync": SYNC_NAME})
    print(f"RunSync: {st}")
    if st not in (200, 204):
        sys.exit(f"RunSync fehlgeschlagen: {st} {res}")
    deadline = time.time() + WAIT
    while time.time() < deadline:
        st, stacks = api("/read/ListStacks")
        states = {}
        for s in stacks or []:
            info = s.get("info") or {}
            states[s["name"]] = (info.get("state") or info.get("status") or "?")
        print("  Stacks:", ", ".join(f"{k}={v}" for k, v in sorted(states.items())))
        if states and all(str(v).lower() == "running" for v in states.values()):
            print("Alle Stacks laufen.")
            return
        time.sleep(15)
    print("WARNUNG: nicht alle Stacks melden Running innerhalb des Timeouts")
    st, stacks = api("/read/ListStacks")
    for s in stacks or []:
        print(" ", s["name"], (s.get("info") or {}))


def sync_stacks_from_toml():
    """Stack-Configs aus komodo/homelab.toml neu schreiben (Variablen werden dabei
    neu interpoliert) und anschliessend deployen.

    Hintergrund: Komodo rendert [[VAR]] beim Schreiben der Stack-Config, nicht bei
    jedem Deploy. Eine geaenderte Variable landet deshalb erst nach einem
    UpdateStack im .env der Stack-Verzeichnisse.
    """
    toml_path = pathlib.Path(os.environ.get("TOML_FILE", "komodo/homelab.toml"))
    if not toml_path.exists():
        print(f"  ({toml_path} nicht gefunden — überspringe Stack-Update)")
        return
    data = tomllib.loads(toml_path.read_text())
    stacks = data.get("stack", [])
    st, current = api("/read/ListStacks")
    by_name = {s["name"]: s for s in (current or [])}
    st, vars_ = api("/read/ListVariables")
    values = {v["name"]: v.get("value", "") for v in (vars_ or [])}

    def render(text):
        """[[VAR]] durch den aktuellen Variablenwert ersetzen.

        Komodo hasht die gespeicherte Config — bleibt dort der Platzhalter stehen,
        merkt es eine Variablenänderung nicht und deployt nicht neu. Deshalb
        schreiben wir die aufgelösten Werte.
        """
        if not isinstance(text, str):
            return text
        for k, v in values.items():
            text = text.replace(f"[[{k}]]", str(v))
        return text

    for decl in stacks:
        name = decl["name"]
        if name not in by_name:
            continue
        cfg = dict(decl.get("config") or {})
        cfg.setdefault("git_provider", "github.com")
        cfg["environment"] = render(cfg.get("environment", ""))
        st, res = api("/write/UpdateStack", {"id": by_name[name]["id"], "config": cfg})
        print(f"  UpdateStack {name}: {st}")
        st, res = api("/execute/DeployStack", {"stack": name})
        print(f"  DeployStack {name}: {st}")


def main():
    if not PASS:
        sys.exit("KOMODO_PASS fehlt (aus stacks/komodo/.env: KOMODO_INIT_ADMIN_PASSWORD)")
    login()

    # Server-Adresse sicherstellen (Periphery spricht TLS)
    st, servers = api("/read/ListServers")
    for srv in servers or []:
        if srv["name"] != "docker01":
            continue
        addr = str((srv.get("config") or {}).get("address") or "").rstrip("/")
        if addr != "https://periphery:8120":
            api("/write/UpdateServer", {"id": srv["id"], "config": {
                "address": "https://periphery:8120", "insecure_tls": True, "enabled": True}})
            print("Server-Adresse auf https://periphery:8120 gesetzt")
        else:
            print("Server-Adresse ok")

    vals = load_secrets()
    print("Variablen:")
    print("  DOMAIN:", set_variable("DOMAIN", vals["DOMAIN"], False))
    for name in ("AK_DB_PASS", "AK_SECRET_KEY", "AK_ADMIN_EMAIL", "AK_ADMIN_PASS",
                 "AK_BOOTSTRAP_TOKEN"):
        print(f"  {name}:", set_variable(name, vals[name], name != "AK_ADMIN_EMAIL"))

    ensure_sync()
    run_sync()
    if os.environ.get("SYNC_STACKS", "1") == "1":
        print("Stacks aus dem TOML neu schreiben und deployen:")
        sync_stacks_from_toml()


if __name__ == "__main__":
    main()
