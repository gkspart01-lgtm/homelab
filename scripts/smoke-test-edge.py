#!/usr/bin/env python3
"""Smoke-Test der Edge-Kette: Traefik -> authentik-Forward-Auth -> geschuetzte App.

Prueft ohne oeffentliches DNS (Hostnamen werden lokal auf die Edge-IP gezeigt) und
mit selbstsigniertem Lab-Zertifikat:
  1. HTTP :80 leitet auf HTTPS
  2. App ohne Sitzung -> Redirect in den authentik-Login (Gate greift)
  3. authentik-Health durch Traefik
  4. authorize leitet in den Login-Flow
  5. Flow-Executor liefert die Login-Maske

Der interaktive Login (Passwort, Callback, Sitzungs-Cookie) wird im Browser
geprueft: https://<app>.<domain>/ -> Login bei https://auth.<domain>/ -> zurueck.

Aufruf:
  EDGE_IP=192.168.181.100 DOMAIN=hl0.mehrwert.icu APP_NAME=whoami \
      python3 scripts/smoke-test-edge.py
"""
import json
import os
import socket
import ssl
import sys
import urllib.error
import urllib.parse
import urllib.request

EDGE_IP = os.environ.get("EDGE_IP", "192.168.181.100")
DOMAIN = os.environ.get("DOMAIN", "hl0.mehrwert.icu")
APP = os.environ.get("APP_NAME", "whoami")
APP_URL = f"https://{APP}.{DOMAIN}"
AUTH_URL = f"https://auth.{DOMAIN}"

CTX = ssl.create_default_context()
CTX.check_hostname = False
CTX.verify_mode = ssl.CERT_NONE

_real_getaddrinfo = socket.getaddrinfo


def fake_dns(host, port, *a, **kw):
    if isinstance(host, str) and host.endswith(DOMAIN):
        host = EDGE_IP
    return _real_getaddrinfo(host, port, *a, **kw)


socket.getaddrinfo = fake_dns


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


opener = urllib.request.build_opener(
    urllib.request.HTTPSHandler(context=CTX), NoRedirect
)


def req(url, headers=None):
    r = urllib.request.Request(url)
    for k, v in (headers or {}).items():
        r.add_header(k, v)
    try:
        with opener.open(r, timeout=25) as resp:
            return resp.status, dict(resp.headers), resp.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as e:
        return e.code, dict(e.headers), e.read().decode("utf-8", "replace")


def abs_url(url):
    return f"{AUTH_URL}{url}" if url.startswith("/") else url


def main():
    ok = True

    def check(nr, name, cond, info=""):
        nonlocal ok
        ok &= bool(cond)
        print(f"{nr:>2}) {'OK  ' if cond else 'FAIL'} {name}{(' — ' + info) if info else ''}")

    print(f"Ziel: {APP_URL} ueber {EDGE_IP} (TLS selbstsigniert, DNS lokal gefaelscht)\n")

    st, h, _ = req(f"http://{EDGE_IP}/", headers={"Host": f"{APP}.{DOMAIN}"})
    check(1, "HTTP :80 leitet auf HTTPS", st in (301, 308), f"{st} -> {h.get('Location', '')}")

    st, h, _ = req(f"{APP_URL}/")
    loc = h.get("Location", "")
    check(2, "App ohne Sitzung -> authentik-Login",
          st in (302, 303) and "application/o/authorize" in loc, f"{st} -> {loc.split('?')[0]}")

    st, _, _ = req(f"{AUTH_URL}/-/health/live/")
    check(3, "authentik-Health durch Traefik", st in (200, 204), str(st))

    st, h, _ = req(loc)
    flow_url = abs_url(h.get("Location", ""))
    check(4, "authorize leitet in den Login-Flow", st in (302, 303) and "/flow" in flow_url,
          flow_url.split("?")[0])

    q = urllib.parse.parse_qs(urllib.parse.urlparse(flow_url).query).get("next", [""])[0]
    if not q:
        q = urllib.parse.parse_qs(urllib.parse.urlparse(loc).query).get("redirect_uri", [""])[0]
    ex = f"{AUTH_URL}/api/v3/flows/executor/default-authentication-flow/?query={urllib.parse.quote(q, safe='')}"
    st, _, body = req(ex)
    comp = json.loads(body).get("component") if st == 200 and body.startswith("{") else None
    check(5, "Flow-Executor liefert Login-Maske", st == 200 and comp == "ak-stage-identification", str(comp))

    print("\nErgebnis:", "Kette steht (Schritte 1-5 gruen)" if ok else "mindestens ein Schritt rot")
    print(f"Interaktiv pruefen: {APP_URL}/ -> Login -> zurueck zur App.")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
