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
    default = (f"whoami:whoami.{DOMAIN},komodo:komodo.{DOMAIN},"
               f"home:home.{DOMAIN},notes:notes.{DOMAIN},fitness:fitness.{DOMAIN}")
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


def parse_app_groups():
    """Welche Gruppe darf welche App nutzen? "app:gruppe,..."

    Default: Komodo nur fuer Admins, Homepage privat + whoami fuer alle Homelab-Nutzer.
    """
    default = ("komodo:homelab-admins,home:homelab-users,"
               "whoami:homelab-users,notes:homelab-users,fitness:homelab-users")
    raw = os.environ.get("APP_GROUPS", default)
    out = {}
    for item in raw.split(","):
        item = item.strip()
        if not item:
            continue
        app, _, group = item.partition(":")
        out[app.strip()] = group.strip() or "homelab-users"
    return out


APP_GROUPS = parse_app_groups()


def parse_oidc_apps():
    """OIDC-Apps (echtes SSO in der App): "slug|Anzeigename|redirect_uri,..." """
    raw = os.environ.get("OIDC_APPS", "")
    out = []
    for item in raw.split(","):
        item = item.strip()
        if not item:
            continue
        parts = [x.strip() for x in item.split("|")]
        if len(parts) != 3:
            sys.exit(f"OIDC_APPS: erwartet slug|name|redirect_uri, bekam {item!r}")
        out.append(tuple(parts))
    return out


OIDC_APPS = parse_oidc_apps()
REQUIRED_GROUPS = sorted(set(APP_GROUPS.values()) | {"homelab-admins"})


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
    items = provs.get("results", []) if isinstance(provs, dict) else []
    existing = next((p for p in items if p["name"] == name), None)
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
    # Direktabfrage per Slug ist robuster als das Durchblaettern der Liste
    st, existing = api("GET", f"/core/applications/{name}/")
    if st != 200:
        existing = None
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
        # Race/existiert schon -> als Update nachziehen
        st2, _ = api("PATCH", f"/core/applications/{name}/", payload)
        if st2 != 200:
            sys.exit(f"Application {name} anlegen fehlgeschlagen: {st} {res} / {st2}")
        return f"Application {name}: nachgezogen ({st2})"
    return f"Application {name}: angelegt"



def ensure_group(name):
    st, groups = api("GET", "/core/groups/?page_size=200")
    items = groups.get("results", []) if isinstance(groups, dict) else []
    existing = next((g for g in items if g["name"] == name), None)
    if existing:
        return existing["pk"]
    st, res = api("POST", "/core/groups/", {"name": name})
    if st not in (200, 201):
        sys.exit(f"Gruppe {name} anlegen fehlgeschlagen: {st} {res}")
    return res["pk"]


def ensure_group_policy(app, group):
    """Expression-Policy: Zugriff nur fuer Mitglieder der Gruppe."""
    name = f"access-{app}-{group}"
    if group == "homelab-admins":
        expression = 'return ak_is_group_member(request.user, name="homelab-admins")'
    else:
        # Admins duerfen alles, alle anderen nur mit ihrer Gruppe
        expression = (f'return ak_is_group_member(request.user, name="{group}") '
                      'or ak_is_group_member(request.user, name="homelab-admins")')
    st, policies = api("GET", "/policies/expression/?page_size=200")
    items = policies.get("results", []) if isinstance(policies, dict) else []
    existing = next((p for p in items if p["name"] == name), None)
    if existing:
        st, res = api("PATCH", f"/policies/expression/{existing['pk']}/",
                      {"expression": expression, "execution_logging": False})
        return existing["pk"], f"Policy {name}: aktualisiert ({st})"
    st, res = api("POST", "/policies/expression/",
                  {"name": name, "expression": expression, "execution_logging": False})
    if st not in (200, 201):
        sys.exit(f"Policy {name} anlegen fehlgeschlagen: {st} {res}")
    return res["pk"], f"Policy {name}: angelegt"


def ensure_binding(app_uuid, policy_pk, app, group):
    st, bindings = api("GET", "/policies/bindings/?page_size=200")
    for b in (bindings or {}).get("results", []):
        tgt = (b.get("target") or {}).get("pk") if isinstance(b.get("target"), dict) else b.get("target")
        pol = (b.get("policy") or {}).get("pk") if isinstance(b.get("policy"), dict) else b.get("policy")
        if tgt == app_uuid and pol == policy_pk:
            return f"Binding {app}<-{group}: vorhanden"
    st, res = api("POST", "/policies/bindings/", {
        "target": app_uuid, "policy": policy_pk, "order": 0,
        "enabled": True, "negate": False, "timeout": 30, "failure_result": False,
    })
    if st not in (200, 201):
        sys.exit(f"Binding {app} fehlgeschlagen: {st} {res}")
    return f"Binding {app}<-{group}: angelegt"


def ensure_oauth_app(slug, name, redirect_uri, group, authz, invalid):
    """OAuth2/OIDC-Provider + Application, gibt (client_id, client_secret) zurueck."""
    st, certs = api("GET", "/crypto/certificatekeypairs/?page_size=200")
    items = certs.get("results", []) if isinstance(certs, dict) else []
    cert = next((c for c in items if "self-signed" in c["name"].lower()), items[0] if items else None)
    if not cert:
        sys.exit("kein Signatur-Zertifikat in authentik gefunden")

    # Scope-Mappings und Grant-Typen sind Pflicht: ohne beides liefert der
    # Provider keine Claims (kein email/name im ID-Token) und lehnt
    # authorization_code ab ("Invalid grant_type for provider").
    st, maps = api("GET", "/propertymappings/provider/scope/?page_size=200")
    map_items = maps.get("results", []) if isinstance(maps, dict) else []
    by_scope = {m["scope_name"]: m["pk"] for m in map_items}
    scope_pks = [by_scope[s] for s in ("openid", "email", "profile") if s in by_scope]
    if len(scope_pks) < 3:
        sys.exit(f"authentik-Scope-Mappings unvollstaendig: {sorted(by_scope)}")

    prov_name = f"oauth-{slug}"
    payload = {
        "name": prov_name,
        "authorization_flow": authz,
        "invalidation_flow": invalid,
        "client_type": "confidential",
        # authentik >= 2024.10: Liste von Objekten, nicht Strings
        "redirect_uris": [{"matching_mode": "strict", "url": redirect_uri}],
        "signing_key": cert["pk"],
        "include_claims_in_id_token": True,
        "sub_mode": "hashed_user_id",
        "access_code_validity": "minutes=1",
        "grant_types": ["authorization_code", "refresh_token"],
        "property_mappings": scope_pks,
    }
    st, provs = api("GET", "/providers/oauth2/?page_size=200")
    existing = next((p for p in (provs.get("results", []) if isinstance(provs, dict) else [])
                     if p["name"] == prov_name), None)
    if existing:
        api("PATCH", f"/providers/oauth2/{existing['pk']}/", payload)
        st, prov = api("GET", f"/providers/oauth2/{existing['pk']}/")
        msg = f"OIDC {slug}: Provider aktualisiert ({st})"
    else:
        st, prov = api("POST", "/providers/oauth2/", payload)
        if st not in (200, 201):
            sys.exit(f"OAuth2-Provider {slug} fehlgeschlagen: {st} {prov}")
        msg = f"OIDC {slug}: Provider angelegt"
    print(" ", msg)

    from urllib.parse import urlsplit
    print(" ", ensure_application(slug, urlsplit(redirect_uri).netloc, prov["pk"]))

    # Zugriff wie bei den Proxy-Apps auf die Gruppe beschraenken
    pol_pk, pmsg = ensure_group_policy(slug, group)
    print(" ", pmsg)
    st, app = api("GET", f"/core/applications/{slug}/")
    print(" ", ensure_binding(app["pk"], pol_pk, slug, group))

    return prov.get("client_id"), prov.get("client_secret")

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

    # Gruppen anlegen (ACL-Basis)
    for g in REQUIRED_GROUPS:
        print(f"Gruppe {g}: {ensure_group(g)}")

    provider_pks = []
    for name, host in APPS:
        pk, msg = ensure_provider(name, host, authz, invalid)
        print(" ", msg)
        print(" ", ensure_application(name, host, pk))
        provider_pks.append(pk)

    # Zugriffs-Policies je App (nur Mitglieder der jeweiligen Gruppe)
    app_uuid = {}
    for app_name, _ in APPS:
        st_a, a = api("GET", f"/core/applications/{app_name}/")
        if st_a == 200 and isinstance(a, dict):
            app_uuid[app_name] = a["pk"]
    print("Zugriff:")
    for app, group in APP_GROUPS.items():
        if app not in app_uuid:
            continue
        pol_pk, msg = ensure_group_policy(app, group)
        print(" ", msg)
        print(" ", ensure_binding(app_uuid[app], pol_pk, app, group))

    # OIDC-Apps (echtes SSO in der Anwendung selbst)
    for slug, name, redirect_uri in OIDC_APPS:
        cid, csec = ensure_oauth_app(slug, name, redirect_uri,
                                     APP_GROUPS.get(slug, "homelab-users"), authz, invalid)
        print(f"  client_id={cid}")
        if csec:
            print(f"  client_secret={csec}")
        path = os.environ.get("OIDC_SECRETS_FILE")
        if path and cid and csec:
            with open(path, "a", encoding="utf-8") as fh:
                fh.write(f"SPARKY_OIDC_CLIENT_ID={cid}\nSPARKY_OIDC_CLIENT_SECRET={csec}\n")
            print(f"  -> {path}")

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

    # Der Erst-Admin muss in der Admin-Gruppe sein, sonst sperrt er sich selbst aus
    st, users = api("GET", "/core/users/?page_size=200")
    admin = next((u for u in (users or {}).get("results", []) if u["username"] == "akadmin"), None)
    st, groups = api("GET", "/core/groups/?page_size=200")
    admin_group = next((g for g in (groups or {}).get("results", []) if g["name"] == "homelab-admins"), None)
    if admin and admin_group and admin["pk"] not in [u["pk"] for u in admin_group.get("users_obj", [])]:
        users_list = [u["pk"] for u in admin_group.get("users_obj", [])] + [admin["pk"]]
        api("PATCH", f"/core/groups/{admin_group['pk']}/", {"users": users_list})
        print("akadmin -> Gruppe homelab-admins")

    print("\nGeschützt:")
    for name, host in APPS:
        group = APP_GROUPS.get(name, "—")
        print(f"  https://{host}/  (App '{name}', Zugriff: Gruppe {group})")
    print("Hinweis: den authentik-server danach einmal neu starten (neue Outpost-Config).")


if __name__ == "__main__":
    main()
