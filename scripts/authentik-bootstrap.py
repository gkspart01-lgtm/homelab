#!/usr/bin/env python3
"""Erstkonfiguration von authentik für Traefik-Forward-Auth (IaC-Ebene 3).

Legt pro App an (idempotent):
  * Proxy-Provider im Modus forward_single (external_host = https://<host>)
  * Application mit passendem Slug
ordnet alle Provider dem "Embedded Outpost" zu und setzt dessen
`config.authentik_host` (sonst zeigt der Login-Redirect auf http://localhost/).

Aufruf (auf docker01, Token aus stacks/komodo/secrets.env):
  AUTHENTIK_URL=http://127.0.0.1:9000 AUTHENTIK_TOKEN=... DOMAIN=hl.mehrwert.icu \
      python3 scripts/authentik-bootstrap.py

Apps: APPS="name:host,name:host,..." (Default: whoami, komodo, home unter <DOMAIN>).
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
DOMAIN = os.environ.get("DOMAIN", "hl.mehrwert.icu")

CTX = ssl.create_default_context()
CTX.check_hostname = False
CTX.verify_mode = ssl.CERT_NONE


def parse_apps():
    default = f"whoami:whoami.{DOMAIN},komodo:komodo.{DOMAIN},home:home.{DOMAIN}"
    raw = os.environ.get("APPS", default)
    apps = []
    for item in raw.split(","):
        item = item.strip()
        if not item:
            continue
        name, _, host = item.partition(":")
        apps.append((name.strip(), host.strip() or f"{name}.{DOMAIN}"))
    # Reihenfolge erhalten, Duplikate entfernen
    seen, out = set(), []
    for name, host in apps:
        if name not in seen:
            seen.add(name)
            out.append((name, host))
    return out


APPS = parse_apps()


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
            with urllib.request.urlopen(f"{URL}/-/health/ready/", context=CTX, timeout=5) as r:
                if r.status in (200, 204):
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


def ensure_provider(name, host, authz, invalid):
    st, provs = api("GET", "/providers/proxy/?page_size=200")
    existing = next((p for p in (provs or {}).get("results", []) if p["name"] == name), None)
    payload = {
        "name": name,
        "authorization_flow": authz,
        "invalidation_flow": invalid,
        "mode": "forward_single",
        "external_host": f"https://{host}",
        "access_token_validity": "hours=24",
    }
    if existing:
        st, _ = api("PATCH", f"/providers/proxy/{existing['pk']}/", payload)
        return existing["pk"], f"Provider {name}: aktualisiert ({st})"
    st, prov = api("POST", "/providers/proxy/", payload)
    if st not in (200, 201):
        sys.exit(f"Provider {name} anlegen fehlgeschlagen: {st} {prov}")
    return prov["pk"], f"Provider {name}: angelegt (pk={prov['pk']})"


def ensure_application(name, host, provider_pk):
    st, apps = api("GET", "/core/applications/?page_size=200")
    existing = next((a for a in (apps or {}).get("results", []) if a["slug"] == name), None)
    payload = {
        "name": name,
        "slug": name,
        "provider": provider_pk,
        "policy_engine_mode": "any",
        "meta_description": f"Zugriff auf https://{host} (Forward-Auth über Traefik)",
        "meta_launch_url": f"https://{host}/",
    }
    if existing:
        st, _ = api("PATCH", f"/core/applications/{name}/", payload)
        return f"Application {name}: aktualisiert ({st})"
    st, res = api("POST", "/core/applications/", payload)
    if st not in (200, 201):
        sys.exit(f"Application {name} anlegen fehlgeschlagen: {st} {res}")
    return f"Application {name}: angelegt"


def main():
    if not TOKEN:
        sys.exit("AUTHENTIK_TOKEN fehlt")
    if not wait_ready():
        sys.exit("authentik ist nicht ready (300s)")

    authz = find_flow("default-provider-authorization-implicit-consent") or \
        find_flow("default-provider-authorization-explicit-consent")
    invalid = find_flow("default-provider-invalidation-flow")
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

    provider_pks = []
    for name, host in APPS:
        pk, msg = ensure_provider(name, host, authz, invalid)
        print(" ", msg)
        print(" ", ensure_application(name, host, pk))
        provider_pks.append(pk)

    # Alle Provider dem Embedded Outpost zuordnen
    st, outposts = api("GET", "/outposts/instances/?page_size=50")
    embedded = next((o for o in (outposts or {}).get("results", []) if "Embedded" in o["name"]), None)
    if not embedded:
        sys.exit("Embedded Outpost nicht gefunden")
    providers = list(dict.fromkeys((embedded.get("providers") or []) + provider_pks))
    cfg = dict(embedded.get("config") or {})
    # Der EMBEDDED Outpost baut Browser-URLs aus config.authentik_host; der DB-Wert
    # gewinnt gegen die Env-Variable. Ohne ihn zeigt der Login auf http://localhost/.
    cfg["authentik_host"] = f"https://auth.{DOMAIN}"
    cfg["authentik_host_browser"] = f"https://auth.{DOMAIN}"
    st, _ = api("PATCH", f"/outposts/instances/{embedded['pk']}/",
                {"providers": providers, "config": cfg})
    print(f"Outpost '{embedded['name']}' -> providers={providers} "
          f"authentik_host=https://auth.{DOMAIN}: {st}")

    # Brand-Domain: Basis für Redirects/Cookies
    st, brands = api("GET", "/core/brands/")
    for b in (brands or {}).get("results", []):
        if b.get("default") and b.get("domain") != DOMAIN:
            st, _ = api("PATCH", f"/core/brands/{b['brand_uuid']}/", {"domain": DOMAIN})
            print(f"Brand-Domain -> {DOMAIN}: {st}")

    print("\nGeschützt:")
    for name, host in APPS:
        print(f"  https://{host}/  (Provider/Application '{name}')")
    print("Hinweis: den authentik-server danach einmal neu starten (neue Outpost-Config).")


if __name__ == "__main__":
    main()
