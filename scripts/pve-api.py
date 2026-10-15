#!/usr/bin/env python3
"""Minimal Proxmox VE API client (ticket auth) for the pve node."""
import json
import ssl
import urllib.parse
import urllib.request

HOST = "192.168.181.10"
PORT = 8006
USER = "root@pam"
PASSWORD = os.environ.get("PVE_PASSWORD", "<PASSWORT>")
BASE = f"https://{HOST}:{PORT}/api2/json"

_CTX = ssl.create_default_context()
_CTX.check_hostname = False
_CTX.verify_mode = ssl.CERT_NONE

_ticket = None
_csrf = None


def _auth():
    global _ticket, _csrf
    data = urllib.parse.urlencode({"username": USER, "password": PASSWORD}).encode()
    req = urllib.request.Request(f"{BASE}/access/ticket", data=data)
    with urllib.request.urlopen(req, context=_CTX, timeout=20) as r:
        d = json.load(r)["data"]
    _ticket, _csrf = d["ticket"], d["CSRFPreventionToken"]


def api(method, path, data=None, retry_auth=True):
    if _ticket is None:
        _auth()
    if method in ("GET", "DELETE") and data:
        path = f"{path}?{urllib.parse.urlencode(data, doseq=True)}"
        body = None
    else:
        body = urllib.parse.urlencode(data, doseq=True).encode() if data else None
    req = urllib.request.Request(f"{BASE}{path}", data=body, method=method)
    req.add_header("Cookie", f"PVEAuthCookie={_ticket}")
    if method != "GET" and _csrf:
        req.add_header("CSRFPreventionToken", _csrf)
    try:
        with urllib.request.urlopen(req, context=_CTX, timeout=120) as r:
            raw = r.read().decode()
    except urllib.error.HTTPError as e:
        raw = e.read().decode()
        try:
            err = json.loads(raw)
        except Exception:
            err = {"raw": raw}
        if retry_auth and e.code == 401:
            _auth()
            return api(method, path, data, retry_auth=False)
        raise RuntimeError(f"{method} {path} -> HTTP {e.code}: {err}")
    try:
        return json.loads(raw).get("data")
    except Exception:
        return raw


def wait_task(upid, timeout=1800, poll=5):
    import time
    deadline = time.time() + timeout
    while time.time() < deadline:
        st = api("GET", f"/nodes/pve/tasks/{urllib.parse.quote(upid, safe='')}/status")
        if st.get("status") == "stopped":
            return st
        time.sleep(poll)
    raise TimeoutError(f"task {upid} not done within {timeout}s")


if __name__ == "__main__":
    print("auth:", api("GET", "/version"))
    print("nextid:", api("GET", "/cluster/nextid"))
