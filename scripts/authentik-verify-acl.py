#!/usr/bin/env python3
"""Prüft die Gruppen-ACLs in authentik (Policy-Test ohne Login).

Für jede App wird die zugeordnete Expression-Policy gegen zwei Benutzer getestet:
  * akadmin (Mitglied von homelab-admins)  -> muss überall passen
  * ein temporärer Benutzer ohne Gruppe      -> darf nirgends passen (wird gelöscht)

Aufruf (auf docker01):
  AUTHENTIK_TOKEN=$(grep AK_BOOTSTRAP_TOKEN /opt/homelab/stacks/komodo/secrets.env | cut -d= -f2)
  AUTHENTIK_TOKEN=$AUTHENTIK_TOKEN python3 scripts/authentik-verify-acl.py
"""
import json
import os
import sys
import urllib.error
import urllib.request

BASE = os.environ.get("AUTHENTIK_URL", "http://127.0.0.1:9000").rstrip("/") + "/api/v3"
TOKEN = os.environ.get("AUTHENTIK_TOKEN", "")
APPS = [a for a in os.environ.get("APPS", "komodo,home,whoami").split(",") if a]
TEST_USER = "acl-probe"


def api(method, path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(f"{BASE}{path}", data=data, method=method)
    req.add_header("Authorization", f"Bearer {TOKEN}")
    req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            raw = resp.read()
            return resp.status, (json.loads(raw) if raw.strip().startswith((b"{", b"[")) else None)
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()[:200]


def user_pk(username):
    st, res = api("GET", f"/core/users/?username={username}")
    if isinstance(res, dict):
        for u in res.get("results", []):
            if u["username"] == username:
                return u["pk"]
    return None


def policy_for(app):
    st, res = api("GET", "/policies/expression/?page_size=200")
    items = res.get("results", []) if isinstance(res, dict) else []
    for p in items:
        if p["name"].startswith(f"access-{app}-"):
            return p
    return None


def main():
    if not TOKEN:
        sys.exit("AUTHENTIK_TOKEN fehlt")

    admin = user_pk("akadmin")
    probe = user_pk(TEST_USER)
    created = False
    if not probe:
        st, res = api("POST", "/core/users/", {
            "username": TEST_USER, "name": "ACL Probe",
            "is_active": True, "type": "internal"})
        if st not in (200, 201):
            sys.exit(f"Testbenutzer anlegen fehlgeschlagen: {st} {res}")
        probe = res["pk"]
        created = True

    print(f"{'App':<10}{'akadmin (admin)':<18}{'ohne Gruppe':<12}Ergebnis")
    ok_all = True
    for app in APPS:
        pol = policy_for(app)
        if not pol:
            print(f"{app:<10}{'-':<18}{'-':<12}KEINE POLICY")
            ok_all = False
            continue
        _, r1 = api("POST", f"/policies/all/{pol['pk']}/test/", {"user": admin})
        _, r2 = api("POST", f"/policies/all/{pol['pk']}/test/", {"user": probe})
        a = r1.get("passing") if isinstance(r1, dict) else None
        b = r2.get("passing") if isinstance(r2, dict) else None
        good = (a is True and b is False)
        ok_all &= good
        print(f"{app:<10}{str(a):<18}{str(b):<12}{'OK' if good else 'PRUEFEN'}")

    if created:
        api("DELETE", f"/core/users/{probe}/")
        print(f"\nTestbenutzer {TEST_USER} wieder gelöscht")
    print("\nErgebnis:", "ACLs greifen" if ok_all else "mindestens eine Policy verhält sich falsch")
    return 0 if ok_all else 1


if __name__ == "__main__":
    sys.exit(main())
