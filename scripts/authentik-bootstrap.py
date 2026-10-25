#!/usr/bin/env python3
"""Erstkonfiguration von authentik für Traefik-Forward-Auth (IaC-Ebene 3).

Legt an (idempotent):
  * Proxy-Provider "whoami" im Modus forward_single
  * Application "whoami" (slug whoami)
  * ordnet den Provider dem "Embedded Outpost" zu

Aufruf (Token aus stacks/authentik/.env):
  AUTHENTIK_TOKEN=... DOMAIN=hl0.mehrwert.icu APP_HOST=whoami.hl0.mehrwert.icu \
      python3 scripts/authentik-bootstrap.py
Optional: AUTHENTIK_URL (default http://127.0.0.1:9000) für den API-Zugang.
"""
import json
import os
import ssl
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

URL = os.environ.get("AUTHENTIK_URL", "http://127.0.0.1:9000").rstrip("/")
TOKEN = os.environ.get("AUTHENTIK_TOKEN", "")
DOMAIN = os.environ.get("DOMAIN", "hl0.mehrwert.icu")
APP_NAME = os.environ.get("APP_NAME", "whoami")
APP_HOST = os.environ.get("APP_HOST", f"{APP_NAME}.{DOMAIN}")

CTX = ssl.create_default_context()
CTX.check_hostname = False
CTX.verify_mode = ssl.CERT_NONE


def api(method, path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(f"{URL}/api/v3{path}", data=data, method=method)
    req.add_header("Authorization", f"Bearer {TOKEN}")
    req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, context=CTX, timeout=30) as r:
            raw = r.read().decode()
            return r.status, (json.loads(raw) if raw.strip() else None)
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()[:400]


def wait_ready(timeout=300):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            req = urllib.request.Request(f"{URL}/-/health/ready/")
            with urllib.request.urlopen(req, context=CTX, timeout=5) as r:
                if r.status in (204, 200):
                    return True
        except Exception:
            pass
        time.sleep(5)
    return False


def find_flow(slug):
    st, flows = api("GET", "/flows/instances/?page_size=200")
    for f in (flows or {}).get("results", []):
        if f["slug"] == slug:
            return f["pk"]
    return None


def main():
    if not TOKEN:
        sys.exit("AUTHENTIK_TOKEN fehlt")
    if not wait_ready():
        sys.exit("authentik ist nicht ready (300s)")

    authz = find_flow("default-provider-authorization-implicit-consent") or \
        find_flow("default-provider-authorization-explicit-consent")
    invalid = find_flow("default-provider-invalidation-flow")
    # Die Default-Blueprints (11 Flows) brauchen nach dem ersten Start 2-3 Minuten.
    deadline = time.time() + 300
    while (not authz or not invalid) and time.time() < deadline:
        print("warte auf Default-Blueprints ...")
        time.sleep(15)
        authz = authz or find_flow("default-provider-authorization-implicit-consent") \
            or find_flow("default-provider-authorization-explicit-consent")
        invalid = invalid or find_flow("default-provider-invalidation-flow")
    if not authz or not invalid:
        sys.exit("Default-Flows nicht gefunden (nach 300 s)")
    print(f"Flows: authorization={authz} invalidation={invalid}")

    # 1. Proxy-Provider (forward_single) — vorhandenen wiederverwenden
    st, provs = api("GET", "/providers/proxy/?page_size=200")
    existing = next((p for p in (provs or {}).get("results", []) if p["name"] == APP_NAME), None)
    payload = {
        "name": APP_NAME,
        "authorization_flow": authz,
        "invalidation_flow": invalid,
        "mode": "forward_single",
        "external_host": f"https://{APP_HOST}",
        "access_token_validity": "hours=24",
    }
    if existing:
        st, prov = api("PATCH", f"/providers/proxy/{existing['pk']}/", payload)
        print(f"Provider aktualisiert: {st} pk={existing['pk']}")
        prov_pk = existing["pk"]
    else:
        st, prov = api("POST", "/providers/proxy/", payload)
        if st not in (200, 201):
            sys.exit(f"Provider anlegen fehlgeschlagen: {st} {prov}")
        prov_pk = prov["pk"]
        print(f"Provider angelegt: pk={prov_pk}")

    # 2. Application
    st, apps = api("GET", "/core/applications/?page_size=200")
    app = next((a for a in (apps or {}).get("results", []) if a["slug"] == APP_NAME), None)
    app_payload = {
        "name": APP_NAME,
        "slug": APP_NAME,
        "provider": prov_pk,
        "policy_engine_mode": "any",
        "meta_description": "Testdienst hinter Traefik + authentik (IaC-Probe)",
        "meta_launch_url": f"https://{APP_HOST}/",
    }
    if app:
        st, _ = api("PATCH", f"/core/applications/{app['slug']}/", app_payload)
        print(f"Application aktualisiert: {st}")
    else:
        st, app = api("POST", "/core/applications/", app_payload)
        if st not in (200, 201):
            sys.exit(f"Application anlegen fehlgeschlagen: {st} {app}")
        print("Application angelegt")

    # 3. Provider dem Embedded Outpost zuordnen
    st, outposts = api("GET", "/outposts/instances/?page_size=50")
    embedded = next((o for o in (outposts or {}).get("results", []) if "Embedded" in o["name"]), None)
    if not embedded:
        sys.exit("Embedded Outpost nicht gefunden")
    providers = list(dict.fromkeys(embedded.get("providers", []) + [prov_pk]))
    # Der EMBEDDED Outpost baut Browser-URLs aus config.authentik_host; der DB-Wert
    # gewinnt gegen die Env-Variable. Ohne ihn zeigt der Login auf http://localhost/.
    cfg = dict(embedded.get("config") or {})
    cfg["authentik_host"] = f"https://auth.{DOMAIN}"
    cfg["authentik_host_browser"] = f"https://auth.{DOMAIN}"
    st, out = api("PATCH", f"/outposts/instances/{embedded['pk']}/",
                  {"providers": providers, "config": cfg})
    print(f"Outpost '{embedded['name']}' -> providers={providers}, "
          f"authentik_host=https://auth.{DOMAIN}: {st}")

    # 4. Kontrolle
    st, app = api("GET", f"/core/applications/{APP_NAME}/")
    print("Kontrolle:", st, {k: app.get(k) for k in ("name", "slug", "provider")} if isinstance(app, dict) else app)
    print(f"Forward-Auth-URL für Traefik: https://auth.{DOMAIN}/outpost.goauthentik.io/auth/traefik")
    print(f"Geschützte App: https://{APP_HOST}/")
    print("Hinweis: den authentik-server danach einmal neu starten (neue Outpost-Config).")


if __name__ == "__main__":
    main()
